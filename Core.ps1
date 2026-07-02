#Requires -Version 4.0
# Desenvolvido por Edsilas
[CmdletBinding()]
param(
    [Parameter()]
    [string[]] $Run = @('All'),

    [Parameter()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error')]
    [string] $LogLevel,

    [Parameter()]
    [ValidateSet('HTML', 'JSON', 'CSV')]
    [string[]] $Format,

    [Parameter()]
    [switch] $NoReport,

    [Parameter()]
    [switch] $ListModules,

    [Parameter()]
    [switch] $InstallSchedule,

    [Parameter()]
    [switch] $RemoveSchedule,

    [Parameter()]
    [switch] $ListSchedule,

    [Parameter()]
    [switch] $Watch,

    [Parameter()]
    [switch] $Quiet,

    [Parameter()]
    [Alias('Version')]
    [switch] $ShowVersion,

    [Parameter()]
    [Alias('Help', 'h')]
    [switch] $ShowHelp
)

# ============================================================================
#  Windows Resource Auditor
#  Arquivo : Core.ps1
#  Versao  : 4.1.0
#  Camada  : 1 - Orquestracao (composition root)
#
#  Responsabilidades:
#    - Inicializacao do ambiente e resolucao de caminhos (relativos a si mesmo).
#    - Carregamento dinamico dos subsistemas de infraestrutura disponiveis.
#    - Orquestracao do pipeline: Config -> Log -> Modulos -> Execucao ->
#      Relatorios -> Encerramento.
#    - Deteccao de capacidades em runtime e degradacao graciosa (Fail Safe)
#      quando um subsistema ainda nao esta presente.
#
#  CONTRATO DE INFRAESTRUTURA (implementado pelas etapas indicadas):
#    Configuracao (Etapa 5) ...... Initialize-WRAConfiguration -Root -ConfigPath
#    Log          (Etapa 6) ...... Initialize-WRALogger / Write-WRALog / Stop-WRALogger
#    Contratos    (Etapa 7) ...... New-WRAResult / Test-WRAModuleContract
#    Framework    (Etapa 7) ...... Initialize-WRAModuleRegistry / Register-WRAModules /
#                                  Get-WRAModuleRegistry / Invoke-WRAOperation /
#                                  Invoke-WRAOperationSet
#    Relatorios   (Etapa 13) ..... Invoke-WRAReporting -Results -Config -Root -Formats
#
#  Codigos de saida (faixa reservada 30-99):
#    0   Sucesso
#    30  Falha de bootstrap (ambiente/caminhos)
#    31  Subsistema de configuracao falhou ao inicializar
#    33  Framework de modulos indisponivel (nenhuma auditoria executavel)
#    34  Nenhuma operacao foi executada (selecao vazia ou registro vazio)
#    35  Falha na geracao de relatorios
#    36  Execucao concluida com falhas em um ou mais modulos
#    37  Argumentos invalidos
#    38  Outra instancia ja em execucao (PreventMultipleInstances)
#    39  Falha ao instalar/remover tarefa agendada
#    40  Excecao nao tratada
# ============================================================================

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------- Constantes estruturais
$script:CoreVersion = '4.1.0'
$script:CoreProduct = 'Windows Resource Auditor'

$script:ExitCodes = @{
    Success                    = 0
    BootstrapFailure           = 30
    ConfigurationUnavailable   = 31
    ModuleFrameworkUnavailable = 33
    NoModulesExecuted          = 34
    ReportingFailed            = 35
    CompletedWithErrors        = 36
    InvalidArguments           = 37
    AlreadyRunning             = 38
    ScheduleFailed             = 39
    Unhandled                  = 40
}

# Resolucao da raiz no escopo do script (confiavel apenas no nivel de script).
$script:CoreScriptRoot = $PSScriptRoot
if (-not $script:CoreScriptRoot) {
    if ($PSCommandPath) {
        $script:CoreScriptRoot = Split-Path -Parent $PSCommandPath
    }
    elseif ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $script:CoreScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
}

# Contexto de execucao compartilhado (hashtable para chaves dinamicas).
$script:Ctx = @{
    Paths            = $null
    Config           = $null
    Registry         = $null
    Caps             = @{ Config = $false; Logger = $false; Modules = $false; Reporting = $false; Envelope = $false; Scheduler = $false; Triggers = $false }
    Run              = $Run
    ConfigPath       = $ConfigPath
    LogLevelOverride = $LogLevel
    Formats          = $Format
    NoReport         = [bool]$NoReport
    Quiet            = [bool]$Quiet
    ListModules      = [bool]$ListModules
    InstallSchedule  = [bool]$InstallSchedule
    RemoveSchedule   = [bool]$RemoveSchedule
    ListSchedule     = [bool]$ListSchedule
    Watch            = [bool]$Watch
    RunMutex         = $null
    ComputerName     = $env:COMPUTERNAME
    Elevated         = $false
    PSVersion        = $PSVersionTable.PSVersion
    Stopwatch        = $null
    LoggerReady      = $false
    ExitHint         = $null
    ReportPaths      = $null
}

# ============================================================================
#  UTILITARIOS
# ============================================================================

function Get-CoreProp {
    # Leitura segura de propriedade/chave, compativel com StrictMode 2.0,
    # funcionando tanto para hashtable quanto para PSCustomObject.
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter()] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) { return $prop.Value }
    return $Default
}

function Write-CoreBootstrapLog {
    # Logger minimo de bootstrap. Nunca lanca excecao. Usado antes do
    # subsistema de log avancado (Etapa 6) e como fallback caso ele falhe.
    param(
        [string] $Level,
        [string] $Module,
        [string] $Operation,
        [string] $Message,
        [System.Management.Automation.ErrorRecord] $Exception
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $lvl = $Level.ToUpperInvariant()
    $line = '{0} [{1}] [{2}] {3} - {4}' -f $ts, $lvl, $Module, $Operation, $Message

    if (-not $script:Ctx.Quiet) {
        $color = 'DarkGray'
        switch ($Level) {
            'Error' { $color = 'Red' }
            'Warn'  { $color = 'Yellow' }
            'Info'  { $color = 'Gray' }
        }
        try {
            Write-Host ('  [{0}] {1} - {2}' -f $lvl, $Operation, $Message) -ForegroundColor $color
        }
        catch {
            Write-Output $line
        }
    }

    try {
        $logFile = $null
        if ($null -ne $script:Ctx.Paths) {
            $logFile = Get-CoreProp -Object $script:Ctx.Paths -Name 'CurrentLogFile'
        }
        if ($logFile) {
            $text = $line + [Environment]::NewLine
            if ($Exception) {
                $st = $Exception.ScriptStackTrace
                if ($st) { $text += ('    StackTrace: ' + $st) + [Environment]::NewLine }
            }
            $enc = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::AppendAllText($logFile, $text, $enc)
        }
    }
    catch {
        # Logging nunca pode derrubar a aplicacao.
    }
}

function Write-CoreLog {
    # Roteador de log: usa o subsistema avancado quando pronto, senao bootstrap.
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error')]
        [string] $Level,

        [Parameter(Mandatory = $true)] [string] $Module,
        [Parameter(Mandatory = $true)] [string] $Operation,
        [Parameter(Mandatory = $true)] [string] $Message,
        [Parameter()] [System.Management.Automation.ErrorRecord] $Exception
    )

    if ($script:Ctx.LoggerReady -and (Get-Command -Name 'Write-WRALog' -ErrorAction SilentlyContinue)) {
        try {
            if ($PSBoundParameters.ContainsKey('Exception') -and $Exception) {
                Write-WRALog -Level $Level -Module $Module -Operation $Operation -Message $Message -Exception $Exception
            }
            else {
                Write-WRALog -Level $Level -Module $Module -Operation $Operation -Message $Message
            }
            return
        }
        catch {
            # Falha do logger avancado -> cai para o bootstrap silenciosamente.
        }
    }

    if ($PSBoundParameters.ContainsKey('Exception') -and $Exception) {
        Write-CoreBootstrapLog -Level $Level -Module $Module -Operation $Operation -Message $Message -Exception $Exception
    }
    else {
        Write-CoreBootstrapLog -Level $Level -Module $Module -Operation $Operation -Message $Message
    }
}

function New-CoreEnvelope {
    # Constroi o envelope universal de resultado (contrato da Etapa 1).
    # Usado para encapsular falhas de nivel-Core de forma uniforme, mesmo
    # quando o modulo de contratos (Etapa 7) ainda nao esta carregado.
    param(
        [bool] $Success,
        [string] $Module,
        [string] $Operation,
        $Data = $null,
        $Warnings = @(),
        $Errors = @(),
        [double] $DurationMs = 0
    )
    return [PSCustomObject]([ordered]@{
        Success      = $Success
        Module       = $Module
        Operation    = $Operation
        Duration     = $DurationMs
        Timestamp    = (Get-Date).ToString('o')
        ComputerName = $script:Ctx.ComputerName
        Data         = $Data
        Warnings     = @($Warnings)
        Errors       = @($Errors)
    })
}

function Get-CoreContextSnapshot {
    # Subconjunto somente-leitura do contexto, repassado aos modulos.
    return [PSCustomObject]([ordered]@{
        Product      = $script:CoreProduct
        Version      = $script:CoreVersion
        ComputerName = $script:Ctx.ComputerName
        Root         = $script:Ctx.Paths.Root
        Paths        = $script:Ctx.Paths
        Config       = $script:Ctx.Config
        Elevated     = $script:Ctx.Elevated
        PSVersion    = $script:Ctx.PSVersion
        Run          = $script:Ctx.Run
    })
}

# ============================================================================
#  FASE 1 - INICIALIZACAO DO AMBIENTE
# ============================================================================

function Initialize-CoreContext {
    $script:Ctx.Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not $script:CoreScriptRoot) {
        throw 'Nao foi possivel resolver o diretorio raiz do projeto.'
    }
    $root = $script:CoreScriptRoot

    $modules = Join-Path $root 'Modules'
    $logs = Join-Path $root 'Logs'
    $cfgFile = $script:Ctx.ConfigPath
    if (-not $cfgFile) { $cfgFile = Join-Path (Join-Path $root 'Config') 'Config.json' }

    $paths = [PSCustomObject]([ordered]@{
        Root                  = $root
        Config                = (Join-Path $root 'Config')
        ConfigFile            = $cfgFile
        ConfigSchema          = (Join-Path (Join-Path $root 'Config') 'Config.schema.json')
        Modules               = $modules
        ModulesContracts      = (Join-Path $modules 'Contracts')
        ModulesInfrastructure = (Join-Path $modules 'Infrastructure')
        ModulesDomain         = (Join-Path $modules 'Domain')
        Reports               = (Join-Path $root 'Reports')
        Logs                  = $logs
        Assets                = (Join-Path $root 'Assets')
        Templates             = (Join-Path $root 'Templates')
        Cache                 = (Join-Path $root 'Cache')
        Docs                  = (Join-Path $root 'Docs')
        Tests                 = (Join-Path $root 'Tests')
        CurrentLogFile        = (Join-Path $logs ('WRA_' + (Get-Date).ToString('yyyyMMdd') + '.log'))
    })
    $script:Ctx.Paths = $paths

    # Criacao idempotente dos diretorios volateis (Etapa 2).
    foreach ($d in @($paths.Logs, $paths.Reports, $paths.Cache)) {
        if (-not (Test-Path -LiteralPath $d)) {
            try { [void](New-Item -ItemType Directory -Path $d -Force) } catch { }
        }
    }

    # Deteccao de elevacao (apenas informativa; coleta degrada sem privilegios).
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        $script:Ctx.Elevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        $script:Ctx.Elevated = $false
    }

    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Init' -Message '===== Inicio de sessao do Core ====='
    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Init' -Message ('Produto: {0} v{1}' -f $script:CoreProduct, $script:CoreVersion)
    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Init' -Message ('Host: PowerShell {0} | Elevado: {1} | Maquina: {2}' -f $script:Ctx.PSVersion, $script:Ctx.Elevated, $script:Ctx.ComputerName)
    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Init' -Message ('Raiz: {0}' -f $root)
}

# ============================================================================
#  FASE 2 - CARREGAMENTO DINAMICO DA INFRAESTRUTURA
# ============================================================================

function Import-CoreModuleFile {
    param([Parameter(Mandatory = $true)][string] $Path)
    try {
        Import-Module -Name $Path -Force -Global -DisableNameChecking -ErrorAction Stop
        return $true
    }
    catch {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'ImportModule' `
            -Message ("Falha ao importar '{0}': {1}" -f (Split-Path -Leaf $Path), $_.Exception.Message) -Exception $_
        return $false
    }
}

function Import-CoreInfrastructure {
    $dirs = @($script:Ctx.Paths.ModulesContracts, $script:Ctx.Paths.ModulesInfrastructure)
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) {
            Write-CoreLog -Level 'Debug' -Module 'CORE' -Operation 'Discover' -Message ('Diretorio ausente: {0}' -f $dir)
            continue
        }
        $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.psm1' -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($f in $files) {
            [void](Import-CoreModuleFile -Path $f.FullName)
        }
    }

    # Deteccao de capacidades pelas funcoes de contrato expostas.
    $script:Ctx.Caps.Config    = [bool](Get-Command -Name 'Initialize-WRAConfiguration' -ErrorAction SilentlyContinue)
    $script:Ctx.Caps.Logger    = [bool](Get-Command -Name 'Write-WRALog' -ErrorAction SilentlyContinue)
    $script:Ctx.Caps.Modules   = [bool](Get-Command -Name 'Register-WRAModules' -ErrorAction SilentlyContinue)
    $script:Ctx.Caps.Reporting = [bool](Get-Command -Name 'Invoke-WRAReporting' -ErrorAction SilentlyContinue)
    $script:Ctx.Caps.Envelope  = [bool](Get-Command -Name 'New-WRAResult' -ErrorAction SilentlyContinue)
    $script:Ctx.Caps.Scheduler = [bool](Get-Command -Name 'Install-WRASchedule' -ErrorAction SilentlyContinue)
    $script:Ctx.Caps.Triggers  = [bool](Get-Command -Name 'Start-WRATriggerWatch' -ErrorAction SilentlyContinue)

    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Discover' `
        -Message ('Capacidades: Config={0} Logger={1} Modulos={2} Relatorios={3}' -f `
            $script:Ctx.Caps.Config, $script:Ctx.Caps.Logger, $script:Ctx.Caps.Modules, $script:Ctx.Caps.Reporting)
}

# ============================================================================
#  FASE 3 - CONFIGURACAO
# ============================================================================

function Initialize-CoreConfiguration {
    if (-not $script:Ctx.Caps.Config) {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Config' `
            -Message 'Subsistema de configuracao indisponivel; utilizando perfil minimo interno.'
        $script:Ctx.Config = [PSCustomObject]@{ }
        return
    }
    try {
        $cfg = Initialize-WRAConfiguration -Root $script:Ctx.Paths.Root -ConfigPath $script:Ctx.Paths.ConfigFile
        $script:Ctx.Config = $cfg

        # Os diagnosticos sao acumulados pela configuracao (o logger avancado
        # ainda nao existe nesta fase) e registrados aqui pelo Core.
        if (Get-Command -Name 'Get-WRAConfigurationDiagnostics' -ErrorAction SilentlyContinue) {
            foreach ($d in @(Get-WRAConfigurationDiagnostics)) {
                $lvl = [string](Get-CoreProp -Object $d -Name 'Level' -Default 'Info')
                $msg = [string](Get-CoreProp -Object $d -Name 'Message' -Default '')
                if ($msg) {
                    Write-CoreLog -Level $lvl -Module 'CORE' -Operation 'Config' -Message $msg
                }
            }
        }

        Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Config' -Message 'Configuracao carregada e validada.'
    }
    catch {
        Write-CoreLog -Level 'Error' -Module 'CORE' -Operation 'Config' `
            -Message ('Falha ao inicializar a configuracao: {0}' -f $_.Exception.Message) -Exception $_
        $script:Ctx.Config = [PSCustomObject]@{ }
        $script:Ctx.ExitHint = $script:ExitCodes.ConfigurationUnavailable
    }
}

# ============================================================================
#  FASE 4 - LOG AVANCADO
# ============================================================================

function Initialize-CoreLogging {
    if (-not $script:Ctx.Caps.Logger) {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Logger' `
            -Message 'Subsistema de log avancado indisponivel; mantendo o log de bootstrap.'
        return
    }
    try {
        $params = @{
            Config = $script:Ctx.Config
            Root   = $script:Ctx.Paths.Root
        }
        if ($script:Ctx.LogLevelOverride) { $params['LogLevel'] = $script:Ctx.LogLevelOverride }
        if ($script:Ctx.Quiet) { $params['Quiet'] = $true }
        Initialize-WRALogger @params
        $script:Ctx.LoggerReady = $true
        Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Logger' -Message 'Subsistema de log inicializado.'
    }
    catch {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Logger' `
            -Message ('Falha ao inicializar o log avancado: {0}. Mantendo o bootstrap.' -f $_.Exception.Message) -Exception $_
    }
}

# ============================================================================
#  FASE 5 - FRAMEWORK DE MODULOS
# ============================================================================

function Initialize-CoreModuleFramework {
    if (-not $script:Ctx.Caps.Modules) {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Modules' `
            -Message 'Framework de modulos indisponivel; nenhuma operacao podera ser executada.'
        return
    }
    try {
        if (Get-Command -Name 'Initialize-WRAModuleRegistry' -ErrorAction SilentlyContinue) {
            [void](Initialize-WRAModuleRegistry -Config $script:Ctx.Config -Root $script:Ctx.Paths.Root)
        }
        $registry = Register-WRAModules -Path $script:Ctx.Paths.ModulesDomain -Config $script:Ctx.Config
        $script:Ctx.Registry = $registry

        $count = 0
        if ($null -ne $registry) { $count = @($registry).Count }
        Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Modules' -Message ('Modulos registrados: {0}.' -f $count)
    }
    catch {
        Write-CoreLog -Level 'Error' -Module 'CORE' -Operation 'Modules' `
            -Message ('Falha ao registrar modulos: {0}' -f $_.Exception.Message) -Exception $_
    }
}

# ============================================================================
#  FASE 6 - EXECUCAO (DISPATCH)
# ============================================================================

function Resolve-CoreSelection {
    # Resolve a selecao (-Run) contra o registro do framework. Espera entradas
    # com as propriedades 'Module' e 'Operations' (contrato da Etapa 7).
    param(
        [Parameter(Mandatory = $true)] $Registry,
        [Parameter(Mandatory = $true)] [string[]] $Selection
    )
    $resolved = New-Object System.Collections.Generic.List[object]
    $all = ($Selection -contains 'All' -or $Selection -contains '*')

    foreach ($entry in @($Registry)) {
        $modName = Get-CoreProp -Object $entry -Name 'Module'
        $ops = @(Get-CoreProp -Object $entry -Name 'Operations' -Default @())
        if (-not $modName) { continue }

        foreach ($op in $ops) {
            $opName = $op
            if ($op -isnot [string]) { $opName = Get-CoreProp -Object $op -Name 'Name' }
            if (-not $opName) { continue }

            $include = $all
            if (-not $include) {
                if ($Selection -contains $modName) { $include = $true }
                elseif ($Selection -contains ('{0}.{1}' -f $modName, $opName)) { $include = $true }
            }
            if ($include) {
                [void]$resolved.Add([PSCustomObject]@{ Module = $modName; Operation = $opName })
            }
        }
    }
    return , $resolved.ToArray()
}

function Invoke-CoreAuditPipeline {
    $results = New-Object System.Collections.Generic.List[object]

    if (-not $script:Ctx.Caps.Modules) {
        return $results.ToArray()
    }

    $context = Get-CoreContextSnapshot

    # Caminho preferencial: entrada em lote (o framework decide paralelismo).
    if (Get-Command -Name 'Invoke-WRAOperationSet' -ErrorAction SilentlyContinue) {
        try {
            $set = Invoke-WRAOperationSet -Selection $script:Ctx.Run -Context $context
            foreach ($r in @($set)) { if ($null -ne $r) { [void]$results.Add($r) } }
        }
        catch {
            Write-CoreLog -Level 'Error' -Module 'CORE' -Operation 'Run' `
                -Message ('Falha ao executar conjunto de operacoes: {0}' -f $_.Exception.Message) -Exception $_
        }
        return $results.ToArray()
    }

    # Fallback: resolver selecao e iterar operacao a operacao.
    if ((Get-Command -Name 'Get-WRAModuleRegistry' -ErrorAction SilentlyContinue) -and
        (Get-Command -Name 'Invoke-WRAOperation' -ErrorAction SilentlyContinue)) {

        $registry = Get-WRAModuleRegistry
        $selection = @(Resolve-CoreSelection -Registry $registry -Selection $script:Ctx.Run)

        foreach ($op in $selection) {
            $opModule = Get-CoreProp -Object $op -Name 'Module'
            $opOperation = Get-CoreProp -Object $op -Name 'Operation'
            if (-not $opModule -or -not $opOperation) { continue }
            $envelope = $null
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $envelope = Invoke-WRAOperation -Module $opModule -Operation $opOperation -Context $context
            }
            catch {
                $sw.Stop()
                Write-CoreLog -Level 'Error' -Module $opModule -Operation $opOperation `
                    -Message ('Excecao durante a operacao: {0}' -f $_.Exception.Message) -Exception $_
                $errObj = [PSCustomObject]@{
                    Message    = $_.Exception.Message
                    Category   = $_.CategoryInfo.Category.ToString()
                    StackTrace = $_.ScriptStackTrace
                }
                $envelope = New-CoreEnvelope -Success $false -Module $opModule -Operation $opOperation `
                    -Errors @($errObj) -DurationMs $sw.Elapsed.TotalMilliseconds
            }
            if ($null -ne $envelope) { [void]$results.Add($envelope) }
        }
        return $results.ToArray()
    }

    Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Run' `
        -Message 'Nenhum ponto de entrada de execucao disponivel no framework.'
    return $results.ToArray()
}

# ============================================================================
#  FASE 7 - RELATORIOS
# ============================================================================

function Invoke-CoreReporting {
    param([Parameter()] $Results)

    if ($script:Ctx.NoReport) {
        Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Report' -Message 'Geracao de relatorios desabilitada (-NoReport).'
        return
    }
    if (-not $script:Ctx.Caps.Reporting) {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Report' -Message 'Subsistema de relatorios indisponivel; etapa ignorada.'
        return
    }
    try {
        $params = @{
            Results = @($Results)
            Config  = $script:Ctx.Config
            Root    = $script:Ctx.Paths.Root
        }
        if ($script:Ctx.Formats) { $params['Formats'] = $script:Ctx.Formats }
        $paths = Invoke-WRAReporting @params
        $script:Ctx.ReportPaths = $paths
        Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Report' -Message 'Relatorios gerados.'
    }
    catch {
        Write-CoreLog -Level 'Error' -Module 'CORE' -Operation 'Report' `
            -Message ('Falha ao gerar relatorios: {0}' -f $_.Exception.Message) -Exception $_
        $script:Ctx.ExitHint = $script:ExitCodes.ReportingFailed
    }
}

# ============================================================================
#  FASE 8 - ENCERRAMENTO
# ============================================================================

function Invoke-CoreShutdown {
    param([Parameter()] $Results)

    $total = 0; $ok = 0; $fail = 0; $warn = 0
    foreach ($r in @($Results)) {
        $total++
        if ([bool](Get-CoreProp -Object $r -Name 'Success' -Default $false)) { $ok++ } else { $fail++ }
        $w = @(Get-CoreProp -Object $r -Name 'Warnings' -Default @())
        $warn += $w.Count
    }

    $elapsed = [TimeSpan]::Zero
    if ($null -ne $script:Ctx.Stopwatch) {
        $script:Ctx.Stopwatch.Stop()
        $elapsed = $script:Ctx.Stopwatch.Elapsed
    }

    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Shutdown' `
        -Message ('Resumo: {0} operacoes | {1} ok | {2} com falha | {3} avisos | tempo {4:c}' -f $total, $ok, $fail, $warn, $elapsed)

    if (Get-Command -Name 'Close-WRACimSession' -ErrorAction SilentlyContinue) {
        try { Close-WRACimSession } catch { }
    }

    if (Get-Command -Name 'Stop-WRALogger' -ErrorAction SilentlyContinue) {
        try { Stop-WRALogger } catch { }
    }

    if ($null -ne $script:Ctx.RunMutex) {
        try { $script:Ctx.RunMutex.ReleaseMutex() } catch { }
        try { $script:Ctx.RunMutex.Dispose() } catch { }
        $script:Ctx.RunMutex = $null
    }

    return [PSCustomObject]@{ Total = $total; Ok = $ok; Fail = $fail; Warnings = $warn }
}

# ============================================================================
#  COMANDOS AUXILIARES (-Help / -Version / -ListModules)
# ============================================================================

function Show-CoreVersion {
    Write-Host ('{0} v{1}' -f $script:CoreProduct, $script:CoreVersion)
    Write-Host ('PowerShell: {0}' -f $script:Ctx.PSVersion)
}

function Show-CoreHelp {
    Write-Host ''
    Write-Host ('{0} v{1} - Core' -f $script:CoreProduct, $script:CoreVersion)
    Write-Host ''
    Write-Host 'Uso: Core.ps1 [-Run <itens>] [-ConfigPath <arquivo>] [-LogLevel <nivel>]'
    Write-Host '              [-Format <HTML|JSON|CSV>] [-NoReport] [-ListModules]'
    Write-Host '              [-InstallSchedule] [-RemoveSchedule] [-ListSchedule] [-Watch]'
    Write-Host '              [-Quiet] [-Version] [-Help]'
    Write-Host ''
    Write-Host 'Parametros:'
    Write-Host '  -Run             Modulos/operacoes a executar. Padrao: All.'
    Write-Host '  -ConfigPath      Caminho alternativo para o Config.json.'
    Write-Host '  -LogLevel        Trace, Debug, Info, Warn ou Error.'
    Write-Host '  -Format          Formato(s) de relatorio.'
    Write-Host '  -NoReport        Nao gera relatorios.'
    Write-Host '  -ListModules     Lista os modulos registrados e encerra.'
    Write-Host '  -InstallSchedule Instala as tarefas agendadas definidas no Config.json.'
    Write-Host '  -RemoveSchedule  Remove as tarefas agendadas do WRA.'
    Write-Host '  -ListSchedule    Lista as tarefas agendadas do WRA.'
    Write-Host '  -Watch           Modo de vigilancia continua (dispara auditorias por gatilho).'
    Write-Host '  -Quiet           Suprime a saida de console.'
    Write-Host ''
}

function Show-CoreModules {
    if (-not $script:Ctx.Caps.Modules -or -not (Get-Command -Name 'Get-WRAModuleRegistry' -ErrorAction SilentlyContinue)) {
        Write-Host 'Framework de modulos indisponivel nesta etapa do projeto.'
        return
    }
    $registry = Get-WRAModuleRegistry
    if ($null -eq $registry -or @($registry).Count -eq 0) {
        Write-Host 'Nenhum modulo registrado.'
        return
    }
    Write-Host ''
    Write-Host 'Modulos registrados:'
    foreach ($entry in @($registry)) {
        $modName = Get-CoreProp -Object $entry -Name 'Module' -Default '(desconhecido)'
        $ops = @(Get-CoreProp -Object $entry -Name 'Operations' -Default @())
        Write-Host ('  - {0} ({1} operacoes)' -f $modName, $ops.Count)
    }
    Write-Host ''
}

# ============================================================================
#  INSTANCIA UNICA E COMANDOS DE AGENDAMENTO / VIGILANCIA
# ============================================================================

function Initialize-CoreCimSession {
    if (-not (Get-Command -Name 'Initialize-WRACimSession' -ErrorAction SilentlyContinue)) { return }
    $use = $true
    $proto = 'Dcom'
    if (Get-Command -Name 'Get-WRAConfigValue' -ErrorAction SilentlyContinue) {
        try {
            $use = [bool](Get-WRAConfigValue -Path 'Performance.UseSharedCimSession' -Default $true)
            $proto = [string](Get-WRAConfigValue -Path 'Performance.CimProtocol' -Default 'Dcom')
        }
        catch { }
    }
    if (-not $use) { return }
    $session = Initialize-WRACimSession -Protocol $proto
    if ($null -ne $session) {
        Write-CoreLog -Level 'Debug' -Module 'CORE' -Operation 'Cim' -Message ('Sessao CIM compartilhada ativa ({0}).' -f $proto)
    }
    else {
        Write-CoreLog -Level 'Debug' -Module 'CORE' -Operation 'Cim' -Message 'Sessao CIM compartilhada indisponivel; usando consultas diretas.'
    }
}

function Enter-CoreSingleInstance {
    # Evita auditorias concorrentes (agendada + manual). Fail Safe: qualquer
    # falha na criacao do mutex nao impede a execucao.
    $prevent = $true
    if (Get-Command -Name 'Get-WRAConfigValue' -ErrorAction SilentlyContinue) {
        try { $prevent = [bool](Get-WRAConfigValue -Path 'General.PreventMultipleInstances' -Default $true) } catch { }
    }
    if (-not $prevent) { return $true }

    try {
        $root = [string]$script:Ctx.Paths.Root
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())
        $hash = (([BitConverter]::ToString($md5.ComputeHash($bytes))) -replace '-', '').ToLowerInvariant()
        $md5.Dispose()

        foreach ($prefix in @('Global\', 'Local\')) {
            try {
                $created = $false
                $mutex = New-Object System.Threading.Mutex($true, ($prefix + 'WRA_Run_' + $hash), [ref]$created)
                if (-not $created) {
                    $got = $false
                    try { $got = $mutex.WaitOne(0) } catch { $got = $false }
                    if (-not $got) {
                        $mutex.Dispose()
                        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Instance' `
                            -Message 'Outra instancia da auditoria ja esta em execucao; encerrando.'
                        $script:Ctx.ExitHint = $script:ExitCodes.AlreadyRunning
                        return $false
                    }
                }
                $script:Ctx.RunMutex = $mutex
                return $true
            }
            catch { continue }
        }
        return $true
    }
    catch { return $true }
}

function Invoke-CoreInstallSchedule {
    if (-not $script:Ctx.Caps.Scheduler) {
        Write-Host 'Subsistema de agendamento indisponivel nesta instalacao.'
        return $script:ExitCodes.ModuleFrameworkUnavailable
    }
    if (-not $script:Ctx.Elevated) {
        Write-CoreLog -Level 'Warn' -Module 'CORE' -Operation 'Schedule' `
            -Message 'A instalacao de tarefas agendadas normalmente requer privilegios administrativos.'
    }
    $res = @(Install-WRASchedule -Config $script:Ctx.Config -Root $script:Ctx.Paths.Root)
    $anyFail = $false
    foreach ($r in $res) {
        $okFlag = [bool](Get-CoreProp -Object $r -Name 'Success' -Default $false)
        if (-not $okFlag) { $anyFail = $true }
        Write-Host ('  [{0}] {1}' -f (& { if ($okFlag) { 'OK' } else { 'FALHA' } }), (Get-CoreProp -Object $r -Name 'Task' -Default '?'))
    }
    if ($res.Count -eq 0) { Write-Host 'Nenhuma tarefa definida em Scheduler.Tasks.' }
    if ($anyFail) { return $script:ExitCodes.ScheduleFailed }
    return $script:ExitCodes.Success
}

function Invoke-CoreRemoveSchedule {
    if (-not $script:Ctx.Caps.Scheduler) {
        Write-Host 'Subsistema de agendamento indisponivel nesta instalacao.'
        return $script:ExitCodes.ModuleFrameworkUnavailable
    }
    $res = @(Remove-WRASchedule -Config $script:Ctx.Config)
    if ($res.Count -eq 0) { Write-Host 'Nenhuma tarefa WRA encontrada.'; return $script:ExitCodes.Success }
    $anyFail = $false
    foreach ($r in $res) {
        $okFlag = [bool](Get-CoreProp -Object $r -Name 'Success' -Default $false)
        if (-not $okFlag) { $anyFail = $true }
        Write-Host ('  [{0}] {1}' -f (& { if ($okFlag) { 'OK' } else { 'FALHA' } }), (Get-CoreProp -Object $r -Name 'Task' -Default '?'))
    }
    if ($anyFail) { return $script:ExitCodes.ScheduleFailed }
    return $script:ExitCodes.Success
}

function Invoke-CoreListSchedule {
    if (-not $script:Ctx.Caps.Scheduler) {
        Write-Host 'Subsistema de agendamento indisponivel nesta instalacao.'
        return $script:ExitCodes.ModuleFrameworkUnavailable
    }
    $res = @(Get-WRASchedule -Config $script:Ctx.Config)
    if ($res.Count -eq 0) { Write-Host 'Nenhuma tarefa WRA registrada.'; return $script:ExitCodes.Success }
    Write-Host ''
    Write-Host 'Tarefas agendadas (WRA):'
    foreach ($r in $res) { Write-Host ('  - {0}' -f (Get-CoreProp -Object $r -Name 'Task' -Default '?')) }
    Write-Host ''
    return $script:ExitCodes.Success
}

function Invoke-CoreWatch {
    if (-not $script:Ctx.Caps.Triggers) {
        Write-Host 'Subsistema de triggers indisponivel nesta instalacao.'
        return $script:ExitCodes.ModuleFrameworkUnavailable
    }

    $onTrigger = {
        param($selection)
        try {
            $ctx = Get-CoreContextSnapshot
            $res = New-Object System.Collections.Generic.List[object]
            if (Get-Command -Name 'Invoke-WRAOperationSet' -ErrorAction SilentlyContinue) {
                $set = Invoke-WRAOperationSet -Selection $selection -Context $ctx
                foreach ($r in @($set)) { if ($null -ne $r) { [void]$res.Add($r) } }
            }
            Invoke-CoreReporting -Results @($res.ToArray())
        }
        catch {
            Write-CoreLog -Level 'Error' -Module 'CORE' -Operation 'Watch' `
                -Message ('Falha na auditoria disparada por trigger: {0}' -f $_.Exception.Message)
        }
    }

    Write-CoreLog -Level 'Info' -Module 'CORE' -Operation 'Watch' `
        -Message 'Modo de vigilancia ativo. Pressione Ctrl+C para encerrar.'
    [void](Start-WRATriggerWatch -Config $script:Ctx.Config -Root $script:Ctx.Paths.Root `
            -Context (Get-CoreContextSnapshot) -OnTrigger $onTrigger -MaxCycles 0)
    return $script:ExitCodes.Success
}

# ============================================================================
#  PONTO DE ENTRADA
# ============================================================================

function Invoke-CoreMain {
    $exit = $script:ExitCodes.Success
    $results = @()

    try {
        Initialize-CoreContext

        if ($ShowVersion) { Show-CoreVersion; return $script:ExitCodes.Success }
        if ($ShowHelp)    { Show-CoreHelp;    return $script:ExitCodes.Success }

        Import-CoreInfrastructure
        Initialize-CoreConfiguration
        Initialize-CoreLogging
        Initialize-CoreModuleFramework

        if ($script:Ctx.ListModules) {
            Show-CoreModules
            return $script:ExitCodes.Success
        }

        if ($script:Ctx.InstallSchedule) { return (Invoke-CoreInstallSchedule) }
        if ($script:Ctx.RemoveSchedule)  { return (Invoke-CoreRemoveSchedule) }
        if ($script:Ctx.ListSchedule)    { return (Invoke-CoreListSchedule) }

        # A partir daqui, modos que executam auditoria: garante instancia unica.
        if (-not (Enter-CoreSingleInstance)) {
            return $script:Ctx.ExitHint
        }

        # Otimizacao: cria uma sessao CIM compartilhada antes da coleta, reduzindo
        # o custo de conexao por consulta. Degrada com seguranca se indisponivel.
        Initialize-CoreCimSession

        if ($script:Ctx.Watch) {
            return (Invoke-CoreWatch)
        }

        $results = @(Invoke-CoreAuditPipeline)
        Invoke-CoreReporting -Results $results
    }
    catch {
        Write-CoreLog -Level 'Error' -Module 'CORE' -Operation 'Fatal' `
            -Message ('Excecao nao tratada: {0}' -f $_.Exception.Message) -Exception $_
        $exit = $script:ExitCodes.Unhandled
    }
    finally {
        $summary = Invoke-CoreShutdown -Results $results

        if ($exit -eq $script:ExitCodes.Success) {
            if ($null -ne $script:Ctx.ExitHint) {
                $exit = $script:Ctx.ExitHint
            }
            elseif (-not $script:Ctx.Caps.Modules) {
                $exit = $script:ExitCodes.ModuleFrameworkUnavailable
            }
            elseif ($summary.Total -eq 0) {
                $exit = $script:ExitCodes.NoModulesExecuted
            }
            elseif ($summary.Fail -gt 0) {
                $exit = $script:ExitCodes.CompletedWithErrors
            }
        }
    }

    return $exit
}

$script:CoreExit = $script:ExitCodes.Unhandled
try {
    $script:CoreExit = Invoke-CoreMain
}
catch {
    try {
        Write-CoreBootstrapLog -Level 'Error' -Module 'CORE' -Operation 'Bootstrap' `
            -Message ('Falha critica de bootstrap: {0}' -f $_.Exception.Message) -Exception $_
    }
    catch { }
    $script:CoreExit = $script:ExitCodes.BootstrapFailure
}

exit $script:CoreExit
