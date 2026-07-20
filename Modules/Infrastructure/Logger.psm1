#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Logger.psm1
#  Versao  : 1.1.0
#  Camada  : 1 - Infraestrutura
#
#  Responsabilidade unica:
#    Registro estruturado e thread-safe de eventos da suite, com filtragem por
#    nivel, saida de console opcional, rotacao automatica e UTF-8 sem BOM.
#
#  Contrato exposto (consumido pelo Core - Etapa 4 - e pelo Framework - Etapa 7):
#    Initialize-WRALogger -Config <obj> -Root <string> [-LogLevel <string>] [-Quiet]
#    Write-WRALog -Level -Module -Operation -Message [-Exception] [-DurationMs] [-Result] [-WarningCount] [-ErrorCount]
#    Write-WRAResultLog -Result <envelope>
#    Stop-WRALogger
#    Get-WRALoggerStatus
#
#  Campos obrigatorios registrados: Data, Hora, Tempo de execucao, Modulo,
#  Operacao, Resultado, Avisos, Erros e Stack Trace quando existir.
# ============================================================================

Set-StrictMode -Version 2.0

# Estado do modulo (configurado em Initialize-WRALogger).
$script:WRALogger = $null

# --------------------------------------------------------------- Utilitarios

function Get-WRACfg {
    # Acesso seguro por caminho pontilhado a um PSCustomObject ou hashtable.
    param([Parameter()] $Object, [Parameter(Mandatory = $true)][string] $Path, [Parameter()] $Default = $null)
    if ($null -eq $Object) { return $Default }
    $node = $Object
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $node) { return $Default }
        if ($node -is [System.Collections.IDictionary]) {
            if ($node.Contains($segment)) { $node = $node[$segment]; continue }
            return $Default
        }
        $prop = $node.PSObject.Properties[$segment]
        if ($null -eq $prop) { return $Default }
        $node = $prop.Value
    }
    if ($null -eq $node) { return $Default }
    return $node
}

function Get-WRASeverity {
    param([Parameter()][string] $Level)
    switch ($Level) {
        'Trace' { return 0 }
        'Debug' { return 1 }
        'Info'  { return 2 }
        'Warn'  { return 3 }
        'Error' { return 4 }
        default { return 2 }
    }
}

function Get-WRACurrentFile {
    $pattern = $script:WRALogger.FilePattern
    $name = $pattern -replace '\{date\}', (Get-Date).ToString('yyyyMMdd')
    return (Join-Path $script:WRALogger.Dir $name)
}

function Write-WRAConsole {
    param([Parameter()][string] $Level, [Parameter()][string] $Text)
    if (-not $script:WRALogger.Console) { return }
    try {
        if ($script:WRALogger.UseColor) {
            $color = 'Gray'
            switch ($Level) {
                'Error' { $color = 'Red' }
                'Warn'  { $color = 'Yellow' }
                'Info'  { $color = 'Gray' }
                'Debug' { $color = 'DarkGray' }
                'Trace' { $color = 'DarkGray' }
            }
            Write-Host $Text -ForegroundColor $color
        }
        else {
            Write-Host $Text
        }
    }
    catch {
        Write-Output $Text
    }
}

function Compress-WRAFile {
    # Compacta um arquivo em .gz usando GZipStream nativo (sem dependencias).
    param([Parameter(Mandatory = $true)][string] $Path)
    $gz = $Path + '.gz'
    try {
        $in = [System.IO.File]::OpenRead($Path)
        try {
            $out = [System.IO.File]::Create($gz)
            try {
                $gzStream = New-Object System.IO.Compression.GZipStream($out, [System.IO.Compression.CompressionMode]::Compress)
                try { $in.CopyTo($gzStream) } finally { $gzStream.Dispose() }
            }
            finally { $out.Dispose() }
        }
        finally { $in.Dispose() }
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $gz
    }
    catch {
        if (Test-Path -LiteralPath $gz) { Remove-Item -LiteralPath $gz -Force -ErrorAction SilentlyContinue }
        return $Path
    }
}

function Invoke-WRARotation {
    # Rotaciona o arquivo corrente quando excede o tamanho maximo configurado.
    param([Parameter(Mandatory = $true)][string] $CurrentFile)
    $rot = $script:WRALogger.Rotation
    if (-not $rot.Enabled) { return }
    if (-not (Test-Path -LiteralPath $CurrentFile)) { return }

    $info = New-Object System.IO.FileInfo($CurrentFile)
    $maxBytes = [int64]$rot.MaxSizeMB * 1MB
    if ($info.Length -lt $maxBytes) { return }

    $archiveDir = Join-Path $script:WRALogger.Dir $rot.ArchiveSubdir
    if (-not (Test-Path -LiteralPath $archiveDir)) {
        [void](New-Item -ItemType Directory -Path $archiveDir -Force)
    }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($CurrentFile)
    $stamp = (Get-Date).ToString('HHmmssfff')
    $dest = Join-Path $archiveDir ('{0}.{1}.log' -f $base, $stamp)

    Move-Item -LiteralPath $CurrentFile -Destination $dest -Force -ErrorAction Stop
    if ($rot.Compress) { [void](Compress-WRAFile -Path $dest) }
}

function Clear-WRAOldLogs {
    # Limpeza por idade (MaxAgeDays) e por contagem (MaxFiles no Archive).
    $rot = $script:WRALogger.Rotation
    $dir = $script:WRALogger.Dir
    $archiveDir = Join-Path $dir $rot.ArchiveSubdir
    $cutoff = (Get-Date).AddDays(-1 * [int]$rot.MaxAgeDays)

    foreach ($d in @($dir, $archiveDir)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $files = @(Get-ChildItem -LiteralPath $d -Filter 'WRA_*' -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            if ($f.LastWriteTime -lt $cutoff) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (Test-Path -LiteralPath $archiveDir) {
        $arch = @(Get-ChildItem -LiteralPath $archiveDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $max = [int]$rot.MaxFiles
        if ($arch.Count -gt $max) {
            for ($i = $max; $i -lt $arch.Count; $i++) {
                Remove-Item -LiteralPath $arch[$i].FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Write-WRAFile {
    # Escrita atomica e thread-safe (mutex nomeado por diretorio de log).
    param([Parameter(Mandatory = $true)][string] $Text)
    $file = Get-WRACurrentFile
    $mutex = $script:WRALogger.Mutex
    $acquired = $false
    try {
        if ($null -ne $mutex) {
            try { $acquired = $mutex.WaitOne(2000) }
            catch [System.Threading.AbandonedMutexException] { $acquired = $true }
            catch { $acquired = $false }
        }
        try { Invoke-WRARotation -CurrentFile $file } catch { }
        [System.IO.File]::AppendAllText($file, $Text, $script:WRALogger.Encoding)
    }
    catch {
        # Logging nunca pode lancar excecao para o chamador.
    }
    finally {
        if ($acquired -and $null -ne $mutex) {
            try { $mutex.ReleaseMutex() } catch { }
        }
    }
}

# ------------------------------------------------------------------ Publicos

function Initialize-WRALogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Config,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter()][string] $LogLevel,
        [Parameter()][switch] $Quiet
    )

    $dirRel = [string](Get-WRACfg -Object $Config -Path 'Logging.Directory' -Default 'Logs')
    if ([System.IO.Path]::IsPathRooted($dirRel)) { $dir = $dirRel } else { $dir = Join-Path $Root $dirRel }
    if (-not (Test-Path -LiteralPath $dir)) {
        try { [void](New-Item -ItemType Directory -Path $dir -Force) } catch { }
    }

    $pattern = [string](Get-WRACfg -Object $Config -Path 'Logging.FileNamePattern' -Default 'WRA_{date}.log')

    $levelName = $LogLevel
    if (-not $levelName) { $levelName = [string](Get-WRACfg -Object $Config -Path 'Logging.Level' -Default 'Info') }

    $consoleEnabled = [bool](Get-WRACfg -Object $Config -Path 'Logging.Console.Enabled' -Default $true)
    if ($Quiet) { $consoleEnabled = $false }
    $useColor = [bool](Get-WRACfg -Object $Config -Path 'Logging.Console.UseColor' -Default $true)
    $includeStack = [bool](Get-WRACfg -Object $Config -Path 'Logging.IncludeStackTrace' -Default $true)

    $encName = [string](Get-WRACfg -Object $Config -Path 'Logging.Encoding' -Default 'utf8-no-bom')
    if ($encName -eq 'utf8-bom') {
        $encoding = New-Object System.Text.UTF8Encoding($true)
    }
    else {
        $encoding = New-Object System.Text.UTF8Encoding($false)
    }

    $rotation = @{
        Enabled       = [bool](Get-WRACfg -Object $Config -Path 'Logging.Rotation.Enabled' -Default $true)
        MaxSizeMB     = [int](Get-WRACfg -Object $Config -Path 'Logging.Rotation.MaxSizeMB' -Default 10)
        MaxAgeDays    = [int](Get-WRACfg -Object $Config -Path 'Logging.Rotation.MaxAgeDays' -Default 30)
        MaxFiles      = [int](Get-WRACfg -Object $Config -Path 'Logging.Rotation.MaxFiles' -Default 60)
        Compress      = [bool](Get-WRACfg -Object $Config -Path 'Logging.Rotation.Compress' -Default $true)
        ArchiveSubdir = [string](Get-WRACfg -Object $Config -Path 'Logging.Rotation.ArchiveSubdir' -Default 'Archive')
    }

    # Mutex nomeado de forma deterministica (estavel entre processos e versoes).
    $mutex = $null
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($dir.ToLowerInvariant())
        $hashHex = ([System.BitConverter]::ToString($md5.ComputeHash($bytes))).Replace('-', '')
        $md5.Dispose()
        $mutexName = 'Local\WRA_Log_' + $hashHex
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    }
    catch {
        $mutex = $null
    }

    $script:WRALogger = @{
        Initialized      = $true
        Root             = $Root
        Dir              = $dir
        FilePattern      = $pattern
        LevelName        = $levelName
        LevelThreshold   = (Get-WRASeverity -Level $levelName)
        Console          = $consoleEnabled
        UseColor         = $useColor
        IncludeStackTrace = $includeStack
        Encoding         = $encoding
        Rotation         = $rotation
        Mutex            = $mutex
        StartTime        = (Get-Date)
    }

    try { Clear-WRAOldLogs } catch { }

    return $true
}

function Write-WRALog {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error')][string] $Level = 'Info',
        [Parameter()][string] $Module = 'CORE',
        [Parameter()][string] $Operation = '',
        [Parameter()][string] $Message = '',
        [Parameter()][System.Management.Automation.ErrorRecord] $Exception,
        [Parameter()][Nullable[double]] $DurationMs,
        [Parameter()][string] $Result,
        [Parameter()][Nullable[int]] $WarningCount,
        [Parameter()][Nullable[int]] $ErrorCount
    )

    if ($null -eq $script:WRALogger -or -not $script:WRALogger.Initialized) { return }

    if ((Get-WRASeverity -Level $Level) -lt $script:WRALogger.LevelThreshold) { return }

    $ts = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss.fff')
    $line = '{0} [{1}] [{2}] {3}' -f $ts, $Level.ToUpperInvariant(), $Module, $Operation
    if ($Message) { $line += ' - ' + $Message }

    $suffix = ''
    if ($PSBoundParameters.ContainsKey('DurationMs') -and $null -ne $DurationMs) { $suffix += (' dur={0:0.0}ms' -f $DurationMs) }
    if ($PSBoundParameters.ContainsKey('Result') -and $Result) { $suffix += ' result=' + $Result }
    if ($PSBoundParameters.ContainsKey('WarningCount') -and $null -ne $WarningCount) { $suffix += ' warn=' + $WarningCount }
    if ($PSBoundParameters.ContainsKey('ErrorCount') -and $null -ne $ErrorCount) { $suffix += ' err=' + $ErrorCount }
    if ($suffix) { $line += ' |' + $suffix }

    $fileText = $line + [Environment]::NewLine
    if ($PSBoundParameters.ContainsKey('Exception') -and $Exception -and $script:WRALogger.IncludeStackTrace) {
        if ($Exception.Exception) {
            $fileText += ('    Exception: {0}: {1}' -f $Exception.Exception.GetType().FullName, $Exception.Exception.Message) + [Environment]::NewLine
        }
        if ($Exception.ScriptStackTrace) {
            $fileText += ('    StackTrace: ' + $Exception.ScriptStackTrace) + [Environment]::NewLine
        }
    }

    if ($script:WRALogger.Console) { Write-WRAConsole -Level $Level -Text $line }
    Write-WRAFile -Text $fileText
}

function Write-WRAResultLog {
    # Registra um envelope de resultado (contrato da Etapa 1) com os campos
    # obrigatorios: duracao, resultado, contagem de avisos e de erros.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Result)

    $success = [bool](Get-WRACfg -Object $Result -Path 'Success' -Default $false)
    $module = [string](Get-WRACfg -Object $Result -Path 'Module' -Default 'CORE')
    $operation = [string](Get-WRACfg -Object $Result -Path 'Operation' -Default '')
    $duration = [double](Get-WRACfg -Object $Result -Path 'Duration' -Default 0)
    $warnings = @(Get-WRACfg -Object $Result -Path 'Warnings' -Default @())
    $errors = @(Get-WRACfg -Object $Result -Path 'Errors' -Default @())

    $level = 'Info'
    if ((-not $success) -or ($errors.Count -gt 0)) { $level = 'Error' }
    elseif ($warnings.Count -gt 0) { $level = 'Warn' }

    if ($success) { $resultText = 'OK' } else { $resultText = 'FAIL' }

    Write-WRALog -Level $level -Module $module -Operation $operation -Message 'Operacao concluida' `
        -DurationMs $duration -Result $resultText -WarningCount $warnings.Count -ErrorCount $errors.Count
}

function Get-WRALoggerStatus {
    if ($null -eq $script:WRALogger) {
        return [PSCustomObject]@{ Initialized = $false }
    }
    return [PSCustomObject]@{
        Initialized = $script:WRALogger.Initialized
        Directory   = $script:WRALogger.Dir
        Level       = $script:WRALogger.LevelName
        Console     = $script:WRALogger.Console
        CurrentFile = (Get-WRACurrentFile)
    }
}

function Stop-WRALogger {
    if ($null -ne $script:WRALogger) {
        if ($null -ne $script:WRALogger.Mutex) {
            try { $script:WRALogger.Mutex.Dispose() } catch { }
            $script:WRALogger.Mutex = $null
        }
        $script:WRALogger.Initialized = $false
    }
}

Export-ModuleMember -Function @(
    'Initialize-WRALogger',
    'Write-WRALog',
    'Write-WRAResultLog',
    'Get-WRALoggerStatus',
    'Stop-WRALogger'
)
