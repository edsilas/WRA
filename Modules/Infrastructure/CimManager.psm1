#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : CimManager.psm1
#  Versao  : 1.1.0
#  Camada  : 1 - Infraestrutura  (otimizacao)
#
#  Responsabilidade unica:
#    Prover uma sessao CIM compartilhada e reutilizada por todos os modulos
#    durante uma execucao, evitando o custo de estabelecer conexao a cada
#    consulta WMI/CIM; e um cache de memoizacao com TTL para dados estaveis.
#
#  Fail Safe: se a sessao nao puder ser criada (ex.: ambiente sem CIM), as
#  funcoes retornam nulo e os modulos caem no Get-CimInstance sem sessao.
#
#  Exposto:
#    Initialize-WRACimSession / Get-WRACimSession / Close-WRACimSession
#    Get-WRACacheValue / Set-WRACacheValue / Clear-WRACache
# ============================================================================

Set-StrictMode -Version 2.0

$script:WRACimSession = $null
$script:WRACache = @{ }

function Initialize-WRACimSession {
    [CmdletBinding()]
    param([Parameter()][string] $Protocol = 'Dcom')

    # Sessao ja ativa: reutiliza.
    if ($null -ne $script:WRACimSession) { return $script:WRACimSession }

    if (-not (Get-Command -Name 'New-CimSession' -ErrorAction SilentlyContinue)) { return $null }

    $session = $null
    try {
        $proto = 'Dcom'
        if ($Protocol -and ($Protocol -ieq 'Wsman')) { $proto = 'Wsman' }
        $opt = New-CimSessionOption -Protocol $proto -ErrorAction Stop
        $session = New-CimSession -SessionOption $opt -ErrorAction Stop
        # Validacao: em Windows antigos a sessao DCOM pode ser criada mas nao
        # responder. Sem este teste, toda consulta com -CimSession falharia e o
        # relatorio sairia zerado "sem erros". Se a sondagem falhar, descartamos a
        # sessao para que os modulos usem consulta direta / WMI.
        $null = Get-CimInstance -CimSession $session -ClassName 'Win32_OperatingSystem' -Property 'Caption' -OperationTimeoutSec 15 -ErrorAction Stop
        $script:WRACimSession = $session
        return $script:WRACimSession
    }
    catch {
        if ($null -ne $session) { try { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue } catch { } }
        $script:WRACimSession = $null
        return $null
    }
}

# ---------------------------------------------------- Coleta CIM resiliente
# Cascata de compatibilidade usada por todos os modulos de dominio:
#   1) Get-CimInstance via sessao compartilhada (quando valida);
#   2) Get-CimInstance direto (sem sessao) se a sessao falhar;
#   3) Get-WmiObject (DCOM nativo) para Windows antigos onde a pilha CIM/MI
#      possa nao responder. Garante que a coleta nao seja silenciosamente zerada.
function Invoke-WRACimQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $ClassName,
        [Parameter()][string] $Namespace,
        [Parameter()][string] $Filter,
        [Parameter()][string[]] $Property,
        [Parameter()][int] $TimeoutSec = 30,
        [Parameter()] $Warnings,
        [Parameter()][switch] $Quiet
    )
    $cimBase = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
    if ($Namespace) { $cimBase['Namespace'] = $Namespace }
    if ($Filter) { $cimBase['Filter'] = $Filter }
    if ($Property) { $cimBase['Property'] = $Property }
    if ($TimeoutSec -gt 0) { $cimBase['OperationTimeoutSec'] = $TimeoutSec }

    $attempts = New-Object System.Collections.Generic.List[hashtable]
    $cs = $null
    if (Get-Command -Name 'Get-WRACimSession' -ErrorAction SilentlyContinue) { $cs = Get-WRACimSession }
    if ($null -ne $cs) { $withSession = [hashtable]$cimBase.Clone(); $withSession['CimSession'] = $cs; [void]$attempts.Add($withSession) }
    [void]$attempts.Add($cimBase)

    foreach ($a in $attempts) {
        try { return @(Get-CimInstance @a) } catch { }
    }

    if (Get-Command -Name 'Get-WmiObject' -ErrorAction SilentlyContinue) {
        try {
            $wmi = @{ Class = $ClassName; ErrorAction = 'Stop' }
            if ($Namespace) { $wmi['Namespace'] = $Namespace }
            if ($Filter) { $wmi['Filter'] = $Filter }
            if ($Property) { $wmi['Property'] = $Property }
            return @(Get-WmiObject @wmi)
        }
        catch {
            if (-not $Quiet -and $null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar {0}: {1}" -f $ClassName, $_.Exception.Message)) }
            return @()
        }
    }
    if (-not $Quiet -and $null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar {0}." -f $ClassName)) }
    return @()
}

function Get-WRACimSession {
    if ($null -eq $script:WRACimSession) { return $null }
    return $script:WRACimSession
}

function Close-WRACimSession {
    if ($null -ne $script:WRACimSession) {
        try { Remove-CimSession -CimSession $script:WRACimSession -ErrorAction SilentlyContinue } catch { }
        $script:WRACimSession = $null
    }
}

# ----------------------------------------------------- Memoizacao com TTL
function Get-WRACacheValue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Key)
    if (-not $script:WRACache.ContainsKey($Key)) { return $null }
    $entry = $script:WRACache[$Key]
    if ($null -ne $entry.Expires -and (Get-Date) -gt $entry.Expires) {
        [void]$script:WRACache.Remove($Key)
        return $null
    }
    return $entry.Value
}

function Set-WRACacheValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Key,
        [Parameter()] $Value,
        [Parameter()][int] $TtlSeconds = 300
    )
    $expires = $null
    if ($TtlSeconds -gt 0) { $expires = (Get-Date).AddSeconds($TtlSeconds) }
    $script:WRACache[$Key] = [PSCustomObject]@{ Value = $Value; Expires = $expires }
    return $Value
}

function Clear-WRACache {
    $script:WRACache = @{ }
}

Export-ModuleMember -Function @(
    'Initialize-WRACimSession', 'Get-WRACimSession', 'Close-WRACimSession', 'Invoke-WRACimQuery',
    'Get-WRACacheValue', 'Set-WRACacheValue', 'Clear-WRACache'
)
