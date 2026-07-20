#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Dispatcher.psm1
#  Versao  : 1.1.0
#  Camada  : 1 - Infraestrutura (orquestracao)
#
#  Responsabilidade unica:
#    Manter o registro de modulos, descobri-los/registra-los e invocar suas
#    operacoes de forma padronizada, encapsulando cada resultado no envelope
#    universal e registrando-o no log.
#
#  Contrato exposto (consumido pelo Core - Etapa 4):
#    Initialize-WRAModuleRegistry -Config -Root
#    Register-WRAModule -Manifest            (auto-registro pelos modulos de dominio)
#    Register-WRAModules -Path -Config       (descoberta + importacao)
#    Get-WRAModuleRegistry                   (visao publica do registro)
#    Get-WRAModuleManifest -Module           (manifesto completo)
#    Invoke-WRAOperation -Module -Operation -Context
#    Invoke-WRAOperationSet -Selection -Context
# ============================================================================

Set-StrictMode -Version 2.0

# Estado do modulo.
$script:WRAModules = [ordered]@{ }
$script:WRAModuleInfos = @{ }
$script:WRADispatcherConfig = $null
$script:WRADispatcherRoot = $null

# --------------------------------------------------------------- Utilitarios

function Write-WRADispatchLog {
    param(
        [string] $Level = 'Info',
        [string] $Operation = '',
        [string] $Message = '',
        [System.Management.Automation.ErrorRecord] $Exception
    )
    if (Get-Command -Name 'Write-WRALog' -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-WRALog -Level $Level -Module 'Dispatcher' -Operation $Operation -Message $Message -Exception $Exception
        }
        else {
            Write-WRALog -Level $Level -Module 'Dispatcher' -Operation $Operation -Message $Message
        }
    }
}

function New-WRADispatchEnvelope {
    # Constroi um envelope, usando New-WRAResult quando disponivel, com fallback
    # interno para manter o Dispatcher operante mesmo isolado.
    param(
        [bool] $Success,
        [string] $Module,
        [string] $Operation,
        [double] $DurationMs = 0,
        $Data = $null,
        $Warnings = @(),
        $Errors = @(),
        [string] $ComputerName
    )
    if (-not $ComputerName) { $ComputerName = $env:COMPUTERNAME }

    if (Get-Command -Name 'New-WRAResult' -ErrorAction SilentlyContinue) {
        return New-WRAResult -Success $Success -Module $Module -Operation $Operation `
            -DurationMs $DurationMs -Data $Data -Warnings $Warnings -Errors $Errors -ComputerName $ComputerName
    }

    return [PSCustomObject]([ordered]@{
        Success      = $Success
        Module       = $Module
        Operation    = $Operation
        Duration     = $DurationMs
        Timestamp    = (Get-Date).ToString('o')
        ComputerName = $ComputerName
        Data         = $Data
        Warnings     = @($Warnings)
        Errors       = @($Errors)
    })
}

function New-WRAErrorRecordObject {
    param([System.Management.Automation.ErrorRecord] $ErrorRecord, [string] $Message)
    if ($ErrorRecord) {
        return [PSCustomObject]@{
            Message    = $ErrorRecord.Exception.Message
            Category   = $ErrorRecord.CategoryInfo.Category.ToString()
            StackTrace = $ErrorRecord.ScriptStackTrace
        }
    }
    return [PSCustomObject]@{ Message = $Message; Category = 'OperationStopped'; StackTrace = '' }
}

# ------------------------------------------------------------------ Registro

function Initialize-WRAModuleRegistry {
    [CmdletBinding()]
    param(
        [Parameter()] $Config,
        [Parameter()][string] $Root
    )
    $script:WRAModules = [ordered]@{ }
    $script:WRAModuleInfos = @{ }
    $script:WRADispatcherConfig = $Config
    $script:WRADispatcherRoot = $Root
    return $true
}

function Register-WRAModule {
    # Auto-registro: chamado pelo proprio modulo de dominio no momento do import.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Manifest)

    if (Get-Command -Name 'Test-WRAModuleContract' -ErrorAction SilentlyContinue) {
        if (-not (Test-WRAModuleContract -Manifest $Manifest)) {
            Write-WRADispatchLog -Level 'Warn' -Operation 'Register' -Message 'Manifesto invalido; modulo ignorado.'
            return $false
        }
    }

    if ($null -eq $script:WRAModules) { $script:WRAModules = [ordered]@{ } }

    $modName = [string](Get-WRAProp -Object $Manifest -Path 'Module')
    $opsTable = [ordered]@{ }
    foreach ($op in @(Get-WRAProp -Object $Manifest -Path 'Operations' -Default @())) {
        $opName = [string](Get-WRAProp -Object $op -Path 'Name')
        if (-not $opName) { continue }
        $opsTable[$opName] = [PSCustomObject]@{
            Handler           = [string](Get-WRAProp -Object $op -Path 'Handler')
            Description       = [string](Get-WRAProp -Object $op -Path 'Description' -Default '')
            RequiresElevation = [bool](Get-WRAProp -Object $op -Path 'RequiresElevation' -Default $false)
        }
    }

    $script:WRAModules[$modName] = [PSCustomObject]@{
        Manifest    = $Manifest
        Module      = $modName
        Version     = [string](Get-WRAProp -Object $Manifest -Path 'Version' -Default '1.1.0')
        Description = [string](Get-WRAProp -Object $Manifest -Path 'Description' -Default '')
        Enabled     = $true
        Operations  = $opsTable
    }

    Write-WRADispatchLog -Level 'Debug' -Operation 'Register' -Message ('Modulo registrado: {0} ({1} operacoes).' -f $modName, $opsTable.Count)
    return $true
}

function Update-WRAModulesEnabled {
    param([Parameter()] $Config)
    if ($null -eq $Config) { return }
    $enabledList = @(Get-WRAProp -Object $Config -Path 'Modules.Enabled' -Default @())
    foreach ($modName in @($script:WRAModules.Keys)) {
        $entry = $script:WRAModules[$modName]
        if ($enabledList.Count -eq 0) { $inList = $true } else { $inList = ($enabledList -contains $modName) }
        $modFlag = [bool](Get-WRAProp -Object $Config -Path ('Modules.{0}.Enabled' -f $modName) -Default $true)
        $entry.Enabled = ($inList -and $modFlag)
    }
}

function Register-WRAModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter()] $Config
    )

    if ($null -ne $Config) { $script:WRADispatcherConfig = $Config }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-WRADispatchLog -Level 'Warn' -Operation 'Discover' -Message ('Diretorio de modulos ausente: {0}' -f $Path)
        return (Get-WRAModuleRegistry)
    }

    $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.psm1' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($f in $files) {
        try {
            # O import dispara o auto-registro (Register-WRAModule) no topo do modulo.
            # Capturamos o PSModuleInfo para invocar os handlers no escopo correto
            # (necessario no Windows PowerShell 5.1, onde funcoes de modulo nao ficam
            # visiveis ao Get-Command de dentro de outro modulo).
            $mi = Import-Module -Name $f.FullName -Force -Global -DisableNameChecking -PassThru -ErrorAction Stop
            if ($null -ne $mi) { $script:WRAModuleInfos[$mi.Name] = $mi }
        }
        catch {
            Write-WRADispatchLog -Level 'Warn' -Operation 'Discover' `
                -Message ("Falha ao importar modulo de dominio '{0}': {1}" -f $f.Name, $_.Exception.Message) -Exception $_
        }
    }

    Update-WRAModulesEnabled -Config $script:WRADispatcherConfig
    return (Get-WRAModuleRegistry)
}

function Get-WRAModuleRegistry {
    [CmdletBinding()]
    param()
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($modName in @($script:WRAModules.Keys)) {
        $entry = $script:WRAModules[$modName]
        [void]$list.Add([PSCustomObject]@{
            Module      = $entry.Module
            Version     = $entry.Version
            Description = $entry.Description
            Enabled     = $entry.Enabled
            Operations  = @($entry.Operations.Keys)
        })
    }
    return , $list.ToArray()
}

function Get-WRAModuleManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Module)
    if ($script:WRAModules.Contains($Module)) {
        return $script:WRAModules[$Module].Manifest
    }
    return $null
}

# ------------------------------------------------------------------ Selecao

function Resolve-WRASelection {
    param([Parameter()][string[]] $Selection)
    $resolved = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Selection) { $Selection = @('All') }
    $all = (($Selection -contains 'All') -or ($Selection -contains '*'))

    foreach ($modName in @($script:WRAModules.Keys)) {
        $entry = $script:WRAModules[$modName]

        if ($all) { $includeModule = [bool]$entry.Enabled }
        elseif ($Selection -contains $modName) { $includeModule = $true }
        else { $includeModule = $false }

        foreach ($opName in @($entry.Operations.Keys)) {
            $include = $includeModule
            if (-not $include -and ($Selection -contains ('{0}.{1}' -f $modName, $opName))) { $include = $true }
            if ($include) {
                [void]$resolved.Add([PSCustomObject]@{ Module = $modName; Operation = $opName })
            }
        }
    }
    return $resolved
}

# ------------------------------------------------------------------ Execucao

function Invoke-WRAOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Module,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter()] $Context
    )

    $computerName = $env:COMPUTERNAME
    if ($Context) {
        $cn = Get-WRAProp -Object $Context -Path 'ComputerName'
        if ($cn) { $computerName = [string]$cn }
    }

    if (-not $script:WRAModules.Contains($Module)) {
        $err = New-WRAErrorRecordObject -Message ("Modulo nao encontrado: {0}" -f $Module)
        return New-WRADispatchEnvelope -Success $false -Module $Module -Operation $Operation -Errors @($err) -ComputerName $computerName
    }

    $entry = $script:WRAModules[$Module]
    if (-not $entry.Operations.Contains($Operation)) {
        $err = New-WRAErrorRecordObject -Message ("Operacao nao encontrada: {0}.{1}" -f $Module, $Operation)
        return New-WRADispatchEnvelope -Success $false -Module $Module -Operation $Operation -Errors @($err) -ComputerName $computerName
    }

    $opDef = $entry.Operations[$Operation]
    $handler = $opDef.Handler

    $warnings = @()
    if ($opDef.RequiresElevation -and $Context) {
        $elevated = [bool](Get-WRAProp -Object $Context -Path 'Elevated' -Default $false)
        if (-not $elevated) {
            $warnings += 'Operacao requer privilegios elevados; a coleta pode ser parcial.'
        }
    }

    $data = $null
    $payloadWarnings = @()
    $payloadErrors = @()
    $success = $true

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # No Windows PowerShell 5.1, funcoes de um modulo de dominio nao sao
        # visiveis ao Get-Command de dentro deste modulo. Resolvemos o handler
        # diretamente na tabela de comandos exportados do modulo e o invocamos
        # com parametro nomeado (type-safe no 5.1; o FunctionInfo ja carrega o
        # vinculo com seu modulo, entao roda no escopo correto).
        $mi = $null
        if ($script:WRAModuleInfos.ContainsKey($Module)) { $mi = $script:WRAModuleInfos[$Module] }

        $cmd = $null
        if ($null -ne $mi -and $mi.ExportedCommands.ContainsKey($handler)) {
            $cmd = $mi.ExportedCommands[$handler]
        }
        if ($null -eq $cmd) {
            $cmd = Get-Command -Name $handler -ErrorAction Stop
        }
        $ret = & $cmd -Context $Context

        if (Get-Command -Name 'Test-WRAPayload' -ErrorAction SilentlyContinue) { $isPayload = (Test-WRAPayload -Object $ret) }
        else { $isPayload = $false }

        if ($isPayload) {
            $data = Get-WRAProp -Object $ret -Path 'Data'
            $payloadWarnings = @(Get-WRAProp -Object $ret -Path 'Warnings' -Default @())
            $payloadErrors = @(Get-WRAProp -Object $ret -Path 'Errors' -Default @())
        }
        else {
            $data = $ret
        }

        if ($payloadErrors.Count -gt 0) { $success = $false }
    }
    catch {
        $success = $false
        $payloadErrors += (New-WRAErrorRecordObject -ErrorRecord $_)
        Write-WRADispatchLog -Level 'Error' -Operation ('{0}.{1}' -f $Module, $Operation) `
            -Message ('Excecao na operacao: {0} | STACK: {1}' -f $_.Exception.Message, ($_.ScriptStackTrace -replace "`r?`n", ' >> ')) -Exception $_
    }
    finally {
        $sw.Stop()
    }

    $allWarnings = @($warnings) + @($payloadWarnings)

    $envelope = New-WRADispatchEnvelope -Success $success -Module $Module -Operation $Operation `
        -DurationMs $sw.Elapsed.TotalMilliseconds -Data $data -Warnings $allWarnings -Errors $payloadErrors -ComputerName $computerName

    if (Get-Command -Name 'Write-WRAResultLog' -ErrorAction SilentlyContinue) {
        try { Write-WRAResultLog -Result $envelope } catch { }
    }

    return $envelope
}

function Invoke-WRAOperationSet {
    [CmdletBinding()]
    param(
        [Parameter()][string[]] $Selection = @('All'),
        [Parameter()] $Context
    )
    $results = New-Object System.Collections.Generic.List[object]
    $resolvedOps = @(Resolve-WRASelection -Selection $Selection)
    $total = $resolvedOps.Count
    $idx = 0
    $showProgress = -not [bool](Get-WRAProp -Object $Context -Path 'Quiet' -Default $false)

    foreach ($op in $resolvedOps) {
        $opModule = Get-WRAProp -Object $op -Path 'Module'
        $opOperation = Get-WRAProp -Object $op -Path 'Operation'
        if (-not $opModule -or -not $opOperation) { continue }
        $idx++
        if ($showProgress -and $total -gt 0) {
            $pct = [int]((($idx - 1) / $total) * 100)
            Write-Progress -Id 1 -Activity 'Windows Resource Auditor' `
                -Status ('[{0}/{1}] Executando {2}.{3}...' -f $idx, $total, $opModule, $opOperation) `
                -PercentComplete $pct
        }
        $envelope = Invoke-WRAOperation -Module $opModule -Operation $opOperation -Context $Context
        if ($null -ne $envelope) { [void]$results.Add($envelope) }
    }
    if ($showProgress) {
        Write-Progress -Id 1 -Activity 'Windows Resource Auditor' -Status 'Concluido.' -PercentComplete 100 -Completed
    }

    return $results.ToArray()
}

Export-ModuleMember -Function @(
    'Initialize-WRAModuleRegistry',
    'Register-WRAModule',
    'Register-WRAModules',
    'Get-WRAModuleRegistry',
    'Get-WRAModuleManifest',
    'Invoke-WRAOperation',
    'Invoke-WRAOperationSet'
)
