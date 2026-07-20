#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : ProcessAnalyzer.psm1
#  Versao  : 1.1.0
#  Camada  : 2 - Dominio
#
#  Responsabilidade unica:
#    Auditar processos: identificacao, relacionamentos pai/filho, consumo de
#    recursos, threads, handles, usuario, empresa/produto/versao, linha de
#    comando, executavel, assinatura digital, certificado, SHA-256, servicos
#    relacionados, correlacao com itens de inicializacao e entre processos.
#
#  Fontes: Win32_Process (CIM), Get-Process (FileVersionInfo), Win32_Service,
#  Win32_StartupCommand, Get-FileHash e Get-AuthenticodeSignature. O calculo de
#  hash/assinatura usa runspaces (fan-out) com cache por arquivo.
#
#  Operacao: Analyze  ->  Invoke-WRAProcessAnalyzerAnalyze -Context
# ============================================================================

Set-StrictMode -Version 2.0

# Estado (por sessao) do resolvedor nativo de caminho de imagem. Inicializado
# aqui para compatibilidade com StrictMode (evita acesso a variavel nao definida).
$script:WRAImagePathApi = $null

# --------------------------------------------------------------- Utilitarios

function Initialize-WRAImagePathApi {
    # Prepara (uma unica vez) o acesso a API oficial QueryFullProcessImageName,
    # que recupera o caminho do executavel de processos PROTEGIDOS (PPL), como
    # componentes do Windows e do antivirus, cujo Win32_Process.ExecutablePath
    # costuma vir vazio. Degradacao graciosa: se a compilacao falhar (ambiente
    # restrito), retorna $false e o comportamento anterior e preservado.
    if ($null -ne $script:WRAImagePathApi) { return $script:WRAImagePathApi }
    $script:WRAImagePathApi = $false
    try {
        if (-not ([System.Management.Automation.PSTypeName]'WRA.ProcImagePath').Type) {
            Add-Type -ErrorAction Stop -Namespace 'WRA' -Name 'ProcImagePath' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
private static extern System.IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
private static extern bool CloseHandle(System.IntPtr hObject);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
private static extern bool QueryFullProcessImageNameW(System.IntPtr hProcess, int dwFlags, System.Text.StringBuilder lpExeName, ref int lpdwSize);
public static string Resolve(int processId) {
    // 0x1000 = PROCESS_QUERY_LIMITED_INFORMATION (funciona para processos protegidos quando elevado)
    System.IntPtr h = OpenProcess(0x1000, false, processId);
    if (h == System.IntPtr.Zero) { return null; }
    try {
        int capacity = 32768;
        System.Text.StringBuilder sb = new System.Text.StringBuilder(capacity);
        if (QueryFullProcessImageNameW(h, 0, sb, ref capacity)) { return sb.ToString(); }
        return null;
    } finally { CloseHandle(h); }
}
'@
        }
        $script:WRAImagePathApi = $true
    }
    catch { $script:WRAImagePathApi = $false }
    return $script:WRAImagePathApi
}

function Get-WRAResolvedExePath {
    # Resolve o caminho do executavel de um processo por vias oficiais, em ordem
    # de custo/robustez, preservando o comportamento atual (o passo 1 cobre a
    # imensa maioria e e identico ao anterior).
    param($CimProc, $ProcInfoMap, [int] $ThePid)
    # 1) Win32_Process.ExecutablePath (fonte primaria; inalterada).
    $exe = [string](Get-WRAProp -Object $CimProc -Path 'ExecutablePath' -Default '')
    if ($exe) { return $exe }
    if ($ThePid -le 0) { return '' }
    # 2) Get-Process -> MainModule.FileName (processos nao protegidos).
    if ($null -ne $ProcInfoMap -and $ProcInfoMap.ContainsKey($ThePid)) {
        try {
            $mp = $ProcInfoMap[$ThePid].Path
            if ($mp) { return [string]$mp }
        }
        catch { }
    }
    # 3) QueryFullProcessImageName (recupera processos protegidos quando elevado).
    if (Initialize-WRAImagePathApi) {
        try {
            $np = [WRA.ProcImagePath]::Resolve($ThePid)
            if ($np) { return [string]$np }
        }
        catch { }
    }
    return ''
}

function Invoke-WRAProcCim {
    param(
        [Parameter(Mandatory = $true)][string] $ClassName,
        [Parameter()][string] $Filter,
        [Parameter()][string[]] $Property,
        [Parameter()][int] $TimeoutSec = 30,
        [Parameter()] $Warnings
    )
    if (Get-Command -Name 'Invoke-WRACimQuery' -ErrorAction SilentlyContinue) {
        return @(Invoke-WRACimQuery -ClassName $ClassName -Filter $Filter -Property $Property -TimeoutSec $TimeoutSec -Warnings $Warnings)
    }
    try {
        $params = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
        if ($Filter) { $params['Filter'] = $Filter }
        if ($Property) { $params['Property'] = $Property }
        return @(Get-CimInstance @params)
    }
    catch {
        if ($null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar {0}: {1}" -f $ClassName, $_.Exception.Message)) }
        return @()
    }
}

function Get-WRAProcMemberSafe {
    # Acesso a propriedades do objeto Process (Get-Process) que podem lancar
    # AccessDenied em processos protegidos.
    param([Parameter()] $Process, [Parameter(Mandatory = $true)][string] $Name)
    try { return $Process.$Name } catch { return $null }
}

function ConvertTo-WRACimDateString {
    param([Parameter()] $Value)
    if ($null -eq $Value) { return $null }
    try { return ([datetime]$Value).ToString('o') } catch { }
    try { return $Value.ToString() } catch { return $null }
}

# ----------------------------------------------------------- Cache de intel

function Get-WRAExeCacheDir {
    param([string] $Root, $Config)
    $cacheRel = [string](Get-WRAProp -Object $Config -Path 'Cache.Directory' -Default 'Cache')
    if ([System.IO.Path]::IsPathRooted($cacheRel)) { $base = $cacheRel } else { $base = Join-Path $Root $cacheRel }
    $dir = Join-Path $base 'signatures'
    if (-not (Test-Path -LiteralPath $dir)) {
        try { [void](New-Item -ItemType Directory -Path $dir -Force) } catch { }
    }
    return $dir
}

function Get-WRAExeCacheFile {
    param([string] $CacheDir, [string] $Path)
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())
        $hex = ([System.BitConverter]::ToString($md5.ComputeHash($bytes))).Replace('-', '')
        $md5.Dispose()
        return (Join-Path $CacheDir ($hex + '.json'))
    }
    catch { return $null }
}

function Read-WRAExeCache {
    param([string] $CacheFile, $FileInfo, [int] $TtlHours)
    if (-not $CacheFile -or -not (Test-Path -LiteralPath $CacheFile)) { return $null }
    try {
        $obj = (Get-Content -LiteralPath $CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        $cachedSize = [double](Get-WRAProp -Object $obj -Path 'Size' -Default -1)
        $cachedWrite = [string](Get-WRAProp -Object $obj -Path 'LastWriteUtc' -Default '')
        $computed = [string](Get-WRAProp -Object $obj -Path 'ComputedUtc' -Default '')

        if ($cachedSize -ne [double]$FileInfo.Length) { return $null }
        if ($cachedWrite -ne $FileInfo.LastWriteTimeUtc.ToString('o')) { return $null }
        if ($TtlHours -gt 0 -and $computed) {
            try {
                $age = (Get-Date).ToUniversalTime() - ([datetime]$computed).ToUniversalTime()
                if ($age.TotalHours -gt $TtlHours) { return $null }
            }
            catch { }
        }
        return $obj
    }
    catch { return $null }
}

function Write-WRAExeCache {
    param([string] $CacheFile, $Intel)
    if (-not $CacheFile) { return }
    try {
        $json = ($Intel | ConvertTo-Json -Depth 6 -Compress)
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($CacheFile, $json, $enc)
    }
    catch { }
}

# --------------------------------------------- Coleta de intel do executavel

function Get-WRAFileSha256 {
    # Calculo de SHA-256 nativo: tenta Get-FileHash e, em caso de falha, recorre
    # diretamente a System.Security.Cryptography.SHA256 (mecanismo do .NET/Windows).
    # Retorna o hash em maiusculas ou $null se ambos os caminhos falharem.
    param([string] $Path)
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash }
    catch {
        $sha = $null; $stream = $null
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
        }
        catch { return $null }
        finally {
            if ($null -ne $stream) { $stream.Dispose() }
            if ($null -ne $sha) { $sha.Dispose() }
        }
    }
}

function Get-WRAExeIntel {
    # Computo sequencial (fallback) de hash + assinatura de um executavel.
    param([string] $Path, [bool] $ComputeHashes, [bool] $VerifySignatures, [long] $MaxBytes)
    $res = [ordered]@{
        Path = $Path; Sha256 = $null; SignatureStatus = $null; Signer = $null
        Thumbprint = $null; NotAfter = $null; Size = 0; LastWriteUtc = $null; Error = $null
    }
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        $res.Size = $fi.Length
        $res.LastWriteUtc = $fi.LastWriteTimeUtc.ToString('o')
        if ($ComputeHashes) {
            if ($MaxBytes -gt 0 -and $fi.Length -gt $MaxBytes) { $res.Sha256 = 'SKIPPED_TOO_LARGE' }
            else { $res.Sha256 = Get-WRAFileSha256 -Path $Path }
        }
        if ($VerifySignatures) {
            try {
                $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
                $res.SignatureStatus = [string]$sig.Status
                if ($sig.SignerCertificate) {
                    $res.Signer = $sig.SignerCertificate.Subject
                    $res.Thumbprint = $sig.SignerCertificate.Thumbprint
                    $res.NotAfter = $sig.SignerCertificate.NotAfter.ToString('o')
                }
            }
            catch { $res.SignatureStatus = 'UnknownError'; $res.Error = (("{0} | assinatura: {1}" -f $res.Error, $_.Exception.Message)).Trim(' |') }
        }
    }
    catch { $res.Error = $_.Exception.Message }
    return [PSCustomObject]$res
}

function Resolve-WRAExeIntelSet {
    # Resolve intel para um conjunto de caminhos, usando cache e (quando vantajoso)
    # paralelismo via runspaces.
    param(
        [string[]] $Paths, [string] $Root, $Config,
        [bool] $ComputeHashes, [bool] $VerifySignatures, [bool] $Parallel,
        [int] $MaxParallel, [long] $MaxBytes, [int] $TtlHours, [bool] $CacheEnabled, $Warnings
    )

    $map = @{ }
    $cacheDir = $null
    if ($CacheEnabled) { $cacheDir = Get-WRAExeCacheDir -Root $Root -Config $Config }

    $toCompute = New-Object System.Collections.Generic.List[string]

    foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($map.ContainsKey($p)) { continue }
        $fi = $null
        try { $fi = Get-Item -LiteralPath $p -ErrorAction Stop } catch { }
        if ($null -eq $fi) {
            $map[$p] = [PSCustomObject]@{ Path = $p; Sha256 = $null; SignatureStatus = 'FileNotFound'; Signer = $null; Thumbprint = $null; NotAfter = $null; Error = 'Arquivo inacessivel.' }
            continue
        }
        if ($CacheEnabled) {
            $cf = Get-WRAExeCacheFile -CacheDir $cacheDir -Path $p
            $cached = Read-WRAExeCache -CacheFile $cf -FileInfo $fi -TtlHours $TtlHours
            if ($null -ne $cached) {
                # Rejeita entradas de cache "envenenadas" (hash ausente, sem erro
                # registrado) quando o hash e requerido — assim execucoes que
                # gravaram hash nulo no passado sao recalculadas automaticamente.
                $cSh = Get-WRAProp -Object $cached -Path 'Sha256'
                $cEr = [string](Get-WRAProp -Object $cached -Path 'Error' -Default '')
                if ((-not $ComputeHashes) -or ($null -ne $cSh) -or $cEr) {
                    $map[$p] = $cached; continue
                }
            }
        }
        [void]$toCompute.Add($p)
    }

    if ($toCompute.Count -eq 0) { return $map }

    if ($Parallel -and $toCompute.Count -gt 1) {
        $sb = {
            param($Item, $Common)
            $path = $Item
            $r = [ordered]@{ Path = $path; Sha256 = $null; SignatureStatus = $null; Signer = $null; Thumbprint = $null; NotAfter = $null; Size = 0; LastWriteUtc = $null; Error = $null }
            try {
                $fi = Get-Item -LiteralPath $path -ErrorAction Stop
                $r.Size = $fi.Length
                $r.LastWriteUtc = $fi.LastWriteTimeUtc.ToString('o')
            }
            catch {
                $r.Error = $_.Exception.Message
                return [PSCustomObject]$r
            }
            if ($Common.ComputeHashes) {
                if ($Common.MaxBytes -gt 0 -and $fi.Length -gt $Common.MaxBytes) { $r.Sha256 = 'SKIPPED_TOO_LARGE' }
                else {
                    try { $r.Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash }
                    catch {
                        $sha = $null; $stream = $null
                        try {
                            $sha = [System.Security.Cryptography.SHA256]::Create()
                            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                            $r.Sha256 = ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
                        }
                        catch { $r.Error = (("{0} | hash: {1}" -f $r.Error, $_.Exception.Message)).Trim(' |') }
                        finally { if ($null -ne $stream) { $stream.Dispose() }; if ($null -ne $sha) { $sha.Dispose() } }
                    }
                }
            }
            if ($Common.VerifySignatures) {
                try {
                    $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
                    $r.SignatureStatus = [string]$sig.Status
                    if ($sig.SignerCertificate) {
                        $r.Signer = $sig.SignerCertificate.Subject
                        $r.Thumbprint = $sig.SignerCertificate.Thumbprint
                        $r.NotAfter = $sig.SignerCertificate.NotAfter.ToString('o')
                    }
                }
                catch { $r.SignatureStatus = 'UnknownError'; $r.Error = (("{0} | assinatura: {1}" -f $r.Error, $_.Exception.Message)).Trim(' |') }
            }
            [PSCustomObject]$r
        }
        $common = [PSCustomObject]@{ ComputeHashes = $ComputeHashes; VerifySignatures = $VerifySignatures; MaxBytes = $MaxBytes }
        $parResults = @(Invoke-WRAParallel -Items $toCompute.ToArray() -ScriptBlock $sb -Common $common -ThrottleLimit $MaxParallel -TimeoutSeconds 300)
        foreach ($pr in $parResults) {
            $out = @(Get-WRAProp -Object $pr -Path 'Output' -Default @())
            if ($out.Count -gt 0 -and $null -ne $out[0]) {
                $intel = $out[0]
                $key = [string](Get-WRAProp -Object $intel -Path 'Path')
                if ($key) {
                    $map[$key] = $intel
                    if ($CacheEnabled) { Write-WRAExeCache -CacheFile (Get-WRAExeCacheFile -CacheDir $cacheDir -Path $key) -Intel (Add-WRAComputedStamp -Intel $intel) }
                }
            }
        }

        # Rede de seguranca: se o caminho paralelo nao produziu intel para algum
        # arquivo (ex.: falha na criacao do pool de runspaces), recalcula-o de forma
        # sequencial no runspace principal, onde Get-FileHash e o fallback .NET
        # sempre existem. Preserva o caminho paralelo quando ele funciona (nada a
        # recalcular) e garante que o SHA-256 seja computado nos demais casos.
        foreach ($p in $toCompute) {
            $needs = $false
            if (-not $map.ContainsKey($p)) {
                $needs = $true
            }
            elseif ($ComputeHashes) {
                $ex = $map[$p]
                $sh = Get-WRAProp -Object $ex -Path 'Sha256'
                $er = [string](Get-WRAProp -Object $ex -Path 'Error' -Default '')
                if ($null -eq $sh -and -not $er) { $needs = $true }
            }
            if ($needs) {
                $intel = Get-WRAExeIntel -Path $p -ComputeHashes $ComputeHashes -VerifySignatures $VerifySignatures -MaxBytes $MaxBytes
                $map[$p] = $intel
                if ($CacheEnabled) { Write-WRAExeCache -CacheFile (Get-WRAExeCacheFile -CacheDir $cacheDir -Path $p) -Intel (Add-WRAComputedStamp -Intel $intel) }
            }
        }
    }
    else {
        foreach ($p in $toCompute) {
            $intel = Get-WRAExeIntel -Path $p -ComputeHashes $ComputeHashes -VerifySignatures $VerifySignatures -MaxBytes $MaxBytes
            $map[$p] = $intel
            if ($CacheEnabled) { Write-WRAExeCache -CacheFile (Get-WRAExeCacheFile -CacheDir $cacheDir -Path $p) -Intel (Add-WRAComputedStamp -Intel $intel) }
        }
    }

    return $map
}

function Add-WRAComputedStamp {
    param($Intel)
    $copy = [ordered]@{ }
    foreach ($prop in $Intel.PSObject.Properties) { $copy[$prop.Name] = $prop.Value }
    $copy['ComputedUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    return [PSCustomObject]$copy
}

# ----------------------------------------------------------- Operacao

function Invoke-WRAProcessAnalyzerAnalyze {
    [CmdletBinding()]
    param([Parameter()] $Context)

    $warnings = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]

    $config = Get-WRAProp -Object $Context -Path 'Config'
    $root = [string](Get-WRAProp -Object $Context -Path 'Root' -Default '.')

    $includeCmd = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.IncludeCommandLine' -Default $true)
    $computeHashes = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.ComputeHashes' -Default $true)
    $verifySig = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.VerifySignatures' -Default $true)
    $resolveOwner = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.ResolveOwner' -Default $true)
    $corrServices = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.CorrelateServices' -Default $true)
    $corrStartup = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.CorrelateStartup' -Default $true)
    $parallel = [bool](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.ParallelHashing' -Default $true)
    $maxProc = [int](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.MaxProcesses' -Default 0)
    $maxMb = [int](Get-WRAProp -Object $config -Path 'Modules.ProcessAnalyzer.HashMaxFileSizeMB' -Default 512)
    $maxParallel = [int](Get-WRAProp -Object $config -Path 'General.MaxParallelism' -Default 4)
    $cimTimeout = [int](Get-WRAProp -Object $config -Path 'Timeouts.CimSeconds' -Default 30)
    $cacheEnabled = [bool](Get-WRAProp -Object $config -Path 'Cache.Enabled' -Default $true)
    $ttlHours = [int](Get-WRAProp -Object $config -Path 'Cache.SignatureTtlHours' -Default 168)
    $maxBytes = [long]$maxMb * 1MB

    # 1) Processos via CIM.
    $procProps = @('ProcessId', 'ParentProcessId', 'Name', 'ExecutablePath', 'CommandLine', 'CreationDate', 'ThreadCount', 'HandleCount', 'WorkingSetSize')
    $cimProcs = @(Invoke-WRAProcCim -ClassName 'Win32_Process' -Property $procProps -TimeoutSec $cimTimeout -Warnings $warnings)
    $totalProcesses = $cimProcs.Count

    # Mapa PID -> nome (para parentesco) considerando TODOS os processos.
    $pidNameMap = @{ }
    foreach ($cp in $cimProcs) {
        $thePid = [int](Get-WRANum -Object $cp -Name 'ProcessId')
        $pidNameMap[$thePid] = [string](Get-WRAProp -Object $cp -Path 'Name' -Default '')
    }

    # Contagem de filhos por PID.
    $childCount = @{ }
    foreach ($cp in $cimProcs) {
        $ppid = [int](Get-WRANum -Object $cp -Name 'ParentProcessId')
        if ($childCount.ContainsKey($ppid)) { $childCount[$ppid] = $childCount[$ppid] + 1 } else { $childCount[$ppid] = 1 }
    }

    # Limite opcional (mantem os maiores por working set).
    $selected = $cimProcs
    if ($maxProc -gt 0 -and $cimProcs.Count -gt $maxProc) {
        $selected = @($cimProcs | Sort-Object -Property @{ Expression = { [double](Get-WRAProp -Object $_ -Path 'WorkingSetSize' -Default 0) } } -Descending | Select-Object -First $maxProc)
        [void]$warnings.Add(("Analise limitada aos {0} maiores processos por memoria." -f $maxProc))
    }

    # 2) Enriquecimento via Get-Process (FileVersionInfo).
    $procInfoMap = @{ }
    try {
        foreach ($gp in @(Get-Process -ErrorAction Stop)) {
            $procInfoMap[[int]$gp.Id] = $gp
        }
    }
    catch {
        [void]$warnings.Add(("Falha ao enumerar processos via Get-Process: {0}" -f $_.Exception.Message))
    }

    # 2b) Caminho do executavel resolvido por PID (uma unica vez), com fallback
    # para processos protegidos. Usado tanto na coleta de intel quanto na
    # montagem, garantindo consistencia e SHA-256 tambem para binarios protegidos.
    $exeByPid = @{ }
    foreach ($cp in $selected) {
        $rp = [int](Get-WRANum -Object $cp -Name 'ProcessId')
        $exeByPid[$rp] = Get-WRAResolvedExePath -CimProc $cp -ProcInfoMap $procInfoMap -ThePid $rp
    }

    # 3) Servicos por PID.
    $svcByPid = @{ }
    if ($corrServices) {
        foreach ($s in @(Invoke-WRAProcCim -ClassName 'Win32_Service' -Property @('Name', 'DisplayName', 'State', 'ProcessId') -TimeoutSec $cimTimeout -Warnings $warnings)) {
            $sp = [int](Get-WRANum -Object $s -Name 'ProcessId')
            if ($sp -le 0) { continue }
            if (-not $svcByPid.ContainsKey($sp)) { $svcByPid[$sp] = New-Object System.Collections.Generic.List[object] }
            [void]$svcByPid[$sp].Add([PSCustomObject]@{
                Name = [string](Get-WRAProp -Object $s -Path 'Name' -Default '')
                DisplayName = [string](Get-WRAProp -Object $s -Path 'DisplayName' -Default '')
                State = [string](Get-WRAProp -Object $s -Path 'State' -Default '')
            })
        }
    }

    # 4) Itens de inicializacao (para correlacao).
    $startupPaths = @{ }
    if ($corrStartup) {
        foreach ($sc in @(Invoke-WRAProcCim -ClassName 'Win32_StartupCommand' -Property @('Command', 'Name', 'Location') -TimeoutSec $cimTimeout -Warnings $warnings)) {
            $cmd = [string](Get-WRAProp -Object $sc -Path 'Command' -Default '')
            if ($cmd) {
                $m = [System.Text.RegularExpressions.Regex]::Match($cmd, '([A-Za-z]:\\[^"]+?\.exe)')
                if ($m.Success) { $startupPaths[$m.Value.ToLowerInvariant()] = $true }
            }
        }
    }

    # 5) Intel (hash/assinatura) dos executaveis unicos selecionados.
    $uniquePaths = New-Object System.Collections.Generic.List[string]
    $seenPath = @{ }
    foreach ($cp in $selected) {
        $upPid = [int](Get-WRANum -Object $cp -Name 'ProcessId')
        $exe = [string]$exeByPid[$upPid]
        if ($exe -and -not $seenPath.ContainsKey($exe.ToLowerInvariant())) {
            $seenPath[$exe.ToLowerInvariant()] = $true
            [void]$uniquePaths.Add($exe)
        }
    }
    $intelMap = @{ }
    if (($computeHashes -or $verifySig) -and $uniquePaths.Count -gt 0) {
        $intelMap = Resolve-WRAExeIntelSet -Paths $uniquePaths.ToArray() -Root $root -Config $config `
            -ComputeHashes $computeHashes -VerifySignatures $verifySig -Parallel $parallel `
            -MaxParallel $maxParallel -MaxBytes $maxBytes -TtlHours $ttlHours -CacheEnabled $cacheEnabled -Warnings $warnings
    }

    # 6) Montagem por processo + flags.
    $processes = New-Object System.Collections.Generic.List[object]
    $signed = 0; $unsigned = 0; $sigUnknown = 0; $withServices = 0; $startupCount = 0; $orphans = 0

    foreach ($cp in $selected) {
        $thePid = [int](Get-WRANum -Object $cp -Name 'ProcessId')
        $ppid = [int](Get-WRANum -Object $cp -Name 'ParentProcessId')
        $name = [string](Get-WRAProp -Object $cp -Path 'Name' -Default '')
        $exe = [string]$exeByPid[$thePid]

        $parentName = $null
        $parentMissing = $false
        if ($pidNameMap.ContainsKey($ppid)) { $parentName = $pidNameMap[$ppid] }
        elseif ($ppid -gt 0) { $parentMissing = $true; $orphans++ }

        $owner = $null
        if ($resolveOwner) {
            try {
                $ownerResult = Invoke-CimMethod -InputObject $cp -MethodName 'GetOwner' -ErrorAction Stop
                $u = [string](Get-WRAProp -Object $ownerResult -Path 'User' -Default '')
                $dm = [string](Get-WRAProp -Object $ownerResult -Path 'Domain' -Default '')
                if ($u) { if ($dm) { $owner = ('{0}\{1}' -f $dm, $u) } else { $owner = $u } }
            }
            catch { }
        }

        $company = $null; $product = $null; $fileVersion = $null; $description = $null
        if ($procInfoMap.ContainsKey($thePid)) {
            $gp = $procInfoMap[$thePid]
            $company = Get-WRAProcMemberSafe -Process $gp -Name 'Company'
            $product = Get-WRAProcMemberSafe -Process $gp -Name 'Product'
            $fileVersion = Get-WRAProcMemberSafe -Process $gp -Name 'FileVersion'
            $description = Get-WRAProcMemberSafe -Process $gp -Name 'Description'
        }

        $sha = $null; $sigStatus = $null; $signer = $null; $thumb = $null; $certExp = $null
        if ($exe -and $intelMap.ContainsKey($exe)) {
            $intel = $intelMap[$exe]
            $sha = Get-WRAProp -Object $intel -Path 'Sha256'
            $sigStatus = Get-WRAProp -Object $intel -Path 'SignatureStatus'
            $signer = Get-WRAProp -Object $intel -Path 'Signer'
            $thumb = Get-WRAProp -Object $intel -Path 'Thumbprint'
            $certExp = Get-WRAProp -Object $intel -Path 'NotAfter'
        }

        if ($verifySig) {
            if ($sigStatus -eq 'Valid') { $signed++ }
            elseif ($null -eq $sigStatus -or $sigStatus -eq 'FileNotFound' -or $sigStatus -eq 'UnknownError' -or $sigStatus -eq 'NotSupportedFileFormat' -or $sigStatus -eq 'Incompatible') { $sigUnknown++ }
            else { $unsigned++ }
        }

        $services = @()
        if ($svcByPid.ContainsKey($thePid)) { $services = $svcByPid[$thePid].ToArray(); $withServices++ }

        $isStartup = $false
        if ($exe -and $startupPaths.ContainsKey($exe.ToLowerInvariant())) { $isStartup = $true; $startupCount++ }

        $flags = New-Object System.Collections.Generic.List[string]
        if (-not $exe) { [void]$flags.Add('NoExecutablePath') }
        if ($parentMissing) { [void]$flags.Add('ParentMissing') }
        if ($verifySig -and $exe -and $sigStatus -and $sigStatus -ne 'Valid' -and $sigStatus -ne 'FileNotFound' -and $sigStatus -ne 'UnknownError') { [void]$flags.Add('SignatureNotValid') }

        $cmdLine = $null
        if ($includeCmd) {
            $cmdLine = [string](Get-WRAProp -Object $cp -Path 'CommandLine' -Default '')
            if ($cmdLine.Length -gt 1024) { $cmdLine = $cmdLine.Substring(0, 1024) + '...' }
        }

        $children = 0
        if ($childCount.ContainsKey($thePid)) { $children = $childCount[$thePid] }

        [void]$processes.Add([PSCustomObject]@{
            ProcessId       = $thePid
            Name            = $name
            ParentProcessId = $ppid
            ParentName      = $parentName
            ChildCount      = $children
            User            = $owner
            ExecutablePath  = $exe
            CommandLine     = $cmdLine
            CreationDate    = (ConvertTo-WRACimDateString -Value (Get-WRAProp -Object $cp -Path 'CreationDate'))
            ThreadCount     = [int](Get-WRANum -Object $cp -Name 'ThreadCount')
            HandleCount     = [int](Get-WRANum -Object $cp -Name 'HandleCount')
            WorkingSetMB    = [Math]::Round((Get-WRANum -Object $cp -Name 'WorkingSetSize') / 1MB, 1)
            Company         = $company
            Product         = $product
            FileVersion     = $fileVersion
            Description     = $description
            Sha256          = $sha
            SignatureStatus = $sigStatus
            Signer          = $signer
            CertThumbprint  = $thumb
            CertNotAfter    = $certExp
            Services        = $services
            IsStartup       = $isStartup
            Flags           = $flags.ToArray()
        })
    }

    # 7) Correlacao entre processos: instancias por executavel e itens sinalizados.
    $byExe = @{ }
    foreach ($p in $processes) {
        $exe = [string](Get-WRAProp -Object $p -Path 'ExecutablePath' -Default '')
        if (-not $exe) { continue }
        if ($byExe.ContainsKey($exe)) { $byExe[$exe] = $byExe[$exe] + 1 } else { $byExe[$exe] = 1 }
    }
    $byExeList = New-Object System.Collections.Generic.List[object]
    foreach ($k in $byExe.Keys) {
        if ($byExe[$k] -gt 1) { [void]$byExeList.Add([PSCustomObject]@{ ExecutablePath = $k; Instances = $byExe[$k] }) }
    }
    $byExeList = @($byExeList | Sort-Object -Property Instances -Descending)

    $flagged = @($processes | Where-Object { @(Get-WRAProp -Object $_ -Path 'Flags' -Default @()).Count -gt 0 })

    $data = [PSCustomObject]@{
        Summary = [PSCustomObject]@{
            TotalProcesses   = $totalProcesses
            Analyzed         = $processes.Count
            Signed           = $signed
            Unsigned         = $unsigned
            SignatureUnknown = $sigUnknown
            WithServices     = $withServices
            StartupProcesses = $startupCount
            OrphanProcesses  = $orphans
        }
        Processes = $processes.ToArray()
        Correlation = [PSCustomObject]@{
            ByExecutable = $byExeList
            Flagged      = $flagged
        }
    }

    return New-WRAModulePayload -Data $data -Warnings $warnings.ToArray() -Errors $errors.ToArray()
}

# ----------------------------------------------------------- Auto-registro

$WRAProcManifest = $null
if (Get-Command -Name 'New-WRAModuleManifest' -ErrorAction SilentlyContinue) {
    $ops = @(
        (New-WRAOperation -Name 'Analyze' -Handler 'Invoke-WRAProcessAnalyzerAnalyze' `
            -Description 'Auditoria completa de processos com hash, assinatura e correlacao.')
    )
    $WRAProcManifest = New-WRAModuleManifest -Module 'ProcessAnalyzer' -Operations $ops `
        -Version '1.1.0' -Description 'Auditoria detalhada de processos do sistema.'
}
if ($null -ne $WRAProcManifest -and (Get-Command -Name 'Register-WRAModule' -ErrorAction SilentlyContinue)) {
    [void](Register-WRAModule -Manifest $WRAProcManifest)
}

Export-ModuleMember -Function @('Invoke-WRAProcessAnalyzerAnalyze')
