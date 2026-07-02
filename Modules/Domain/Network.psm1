#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Network.psm1
#  Versao  : 4.1.0
#  Camada  : 2 - Dominio
#
#  Responsabilidade unica:
#    Auditar a pilha de rede do Windows (interfaces, adaptadores, drivers,
#    IPv4/IPv6, DNS, DHCP, gateway, MTU, velocidade, TCP/UDP, conexoes, portas,
#    proxy, VPN, SMB, firewall, rotas, sessoes, compartilhamentos e Hyper-V),
#    correlacionando Processo/PID/Porta/Conexao/Interface/Servico.
#
#  REGRA INVIOLAVEL: nunca captura conteudo de pacotes. Apenas metadados.
#
#  Fontes: Win32_* (CIM, ampla compatibilidade), Get-NetTCPConnection /
#  Get-NetUDPEndpoint quando disponiveis (fallback: netstat -ano), e Registro
#  (somente leitura) para proxy.
#
#  Operacao: Audit  ->  Invoke-WRANetworkAudit -Context
# ============================================================================

Set-StrictMode -Version 2.0

# --------------------------------------------------------------- Utilitarios

function Invoke-WRANetCim {
    param(
        [Parameter(Mandatory = $true)][string] $ClassName,
        [Parameter()][string] $Namespace,
        [Parameter()][string] $Filter,
        [Parameter()][string[]] $Property,
        [Parameter()][int] $TimeoutSec = 30,
        [Parameter()] $Warnings,
        [Parameter()][switch] $Quiet
    )
    if (Get-Command -Name 'Invoke-WRACimQuery' -ErrorAction SilentlyContinue) {
        return @(Invoke-WRACimQuery -ClassName $ClassName -Namespace $Namespace -Filter $Filter -Property $Property -TimeoutSec $TimeoutSec -Warnings $Warnings -Quiet:$Quiet)
    }
    try {
        $params = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
        if ($Namespace) { $params['Namespace'] = $Namespace }
        if ($Filter) { $params['Filter'] = $Filter }
        if ($Property) { $params['Property'] = $Property }
        return @(Get-CimInstance @params)
    }
    catch {
        if (-not $Quiet -and $null -ne $Warnings) {
            [void]$Warnings.Add(("Falha ao consultar {0}: {1}" -f $ClassName, $_.Exception.Message))
        }
        return @()
    }
}

function Split-WRAEndpoint {
    param([Parameter()][string] $Value)
    $result = [PSCustomObject]@{ Address = $Value; Port = 0 }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $result }
    $m = [System.Text.RegularExpressions.Regex]::Match($Value, '^\[(.+)\]:(\d+|\*)$')
    if ($m.Success) {
        $result.Address = $m.Groups[1].Value
        $p = $m.Groups[2].Value
        if ($p -ne '*') { $result.Port = [int]$p }
        return $result
    }
    $idx = $Value.LastIndexOf(':')
    if ($idx -ge 0) {
        $result.Address = $Value.Substring(0, $idx)
        $portStr = $Value.Substring($idx + 1)
        $parsed = 0
        if ([int]::TryParse($portStr, [ref]$parsed)) { $result.Port = $parsed }
    }
    return $result
}

# ----------------------------------------------------------- Coletores

function Get-WRANetInterfaces {
    param([int] $TimeoutSec, $Warnings)

    $adapters = @(Invoke-WRANetCim -ClassName 'Win32_NetworkAdapter' -Property @('Index', 'InterfaceIndex', 'Name', 'NetConnectionID', 'MACAddress', 'Speed', 'NetEnabled', 'AdapterType', 'Manufacturer', 'ServiceName', 'PNPDeviceID') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    $configs = @(Invoke-WRANetCim -ClassName 'Win32_NetworkAdapterConfiguration' -Property @('Index', 'InterfaceIndex', 'Description', 'IPAddress', 'IPSubnet', 'DefaultIPGateway', 'DNSServerSearchOrder', 'DHCPEnabled', 'DHCPServer', 'MACAddress', 'MTU') -TimeoutSec $TimeoutSec -Warnings $Warnings)

    $cfgByIndex = @{ }
    foreach ($c in $configs) {
        $idx = [int](Get-WRANum -Object $c -Name 'Index')
        $cfgByIndex[$idx] = $c
    }

    $list = New-Object System.Collections.Generic.List[object]
    foreach ($a in $adapters) {
        $idx = [int](Get-WRANum -Object $a -Name 'Index')
        $cfg = $null
        if ($cfgByIndex.ContainsKey($idx)) { $cfg = $cfgByIndex[$idx] }

        $ipv4 = New-Object System.Collections.Generic.List[string]
        $ipv6 = New-Object System.Collections.Generic.List[string]
        if ($null -ne $cfg) {
            foreach ($ip in @(Get-WRAProp -Object $cfg -Path 'IPAddress' -Default @())) {
                if ($ip -match ':') { [void]$ipv6.Add([string]$ip) } else { [void]$ipv4.Add([string]$ip) }
            }
        }

        $speed = [double](Get-WRANum -Object $a -Name 'Speed')
        $speedMbps = 0
        if ($speed -gt 0) { $speedMbps = [Math]::Round($speed / 1000000, 0) }

        [void]$list.Add([PSCustomObject]@{
            Name             = [string](Get-WRAProp -Object $a -Path 'NetConnectionID' -Default '')
            Description      = [string](Get-WRAProp -Object $cfg -Path 'Description' -Default ([string](Get-WRAProp -Object $a -Path 'Name' -Default '')))
            InterfaceIndex   = [int](Get-WRANum -Object $a -Name 'InterfaceIndex')
            MacAddress       = [string](Get-WRAProp -Object $a -Path 'MACAddress' -Default '')
            AdapterType      = [string](Get-WRAProp -Object $a -Path 'AdapterType' -Default '')
            Manufacturer     = [string](Get-WRAProp -Object $a -Path 'Manufacturer' -Default '')
            Driver           = [string](Get-WRAProp -Object $a -Path 'ServiceName' -Default '')
            Enabled          = [bool](Get-WRAProp -Object $a -Path 'NetEnabled' -Default $false)
            SpeedMbps        = $speedMbps
            Mtu              = [int](Get-WRANum -Object $cfg -Name 'MTU')
            IPv4             = $ipv4.ToArray()
            IPv6             = $ipv6.ToArray()
            Gateway          = @(Get-WRAProp -Object $cfg -Path 'DefaultIPGateway' -Default @())
            DnsServers       = @(Get-WRAProp -Object $cfg -Path 'DNSServerSearchOrder' -Default @())
            DhcpEnabled      = [bool](Get-WRAProp -Object $cfg -Path 'DHCPEnabled' -Default $false)
            DhcpServer       = [string](Get-WRAProp -Object $cfg -Path 'DHCPServer' -Default '')
        })
    }
    return $list.ToArray()
}

function Get-WRANetConnectionsRaw {
    # Retorna conexoes TCP/UDP normalizadas, com PID. Prefere os cmdlets Net*;
    # cai para netstat -ano (tokens TCP/UDP/PID nao sao localizados).
    param($Warnings)
    $list = New-Object System.Collections.Generic.List[object]

    $haveTcp = [bool](Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue)
    $haveUdp = [bool](Get-Command -Name 'Get-NetUDPEndpoint' -ErrorAction SilentlyContinue)

    if ($haveTcp) {
        try {
            foreach ($c in @(Get-NetTCPConnection -ErrorAction Stop)) {
                [void]$list.Add([PSCustomObject]@{
                    Protocol      = 'TCP'
                    LocalAddress  = [string](Get-WRAProp -Object $c -Path 'LocalAddress' -Default '')
                    LocalPort     = [int](Get-WRANum -Object $c -Name 'LocalPort')
                    RemoteAddress = [string](Get-WRAProp -Object $c -Path 'RemoteAddress' -Default '')
                    RemotePort    = [int](Get-WRANum -Object $c -Name 'RemotePort')
                    State         = [string](Get-WRAProp -Object $c -Path 'State' -Default '')
                    ProcessId     = [int](Get-WRANum -Object $c -Name 'OwningProcess')
                })
            }
        }
        catch { [void]$Warnings.Add(("Falha em Get-NetTCPConnection: {0}" -f $_.Exception.Message)) }
    }
    if ($haveUdp) {
        try {
            foreach ($u in @(Get-NetUDPEndpoint -ErrorAction Stop)) {
                [void]$list.Add([PSCustomObject]@{
                    Protocol      = 'UDP'
                    LocalAddress  = [string](Get-WRAProp -Object $u -Path 'LocalAddress' -Default '')
                    LocalPort     = [int](Get-WRANum -Object $u -Name 'LocalPort')
                    RemoteAddress = ''
                    RemotePort    = 0
                    State         = 'Listen'
                    ProcessId     = [int](Get-WRANum -Object $u -Name 'OwningProcess')
                })
            }
        }
        catch { [void]$Warnings.Add(("Falha em Get-NetUDPEndpoint: {0}" -f $_.Exception.Message)) }
    }

    if (-not $haveTcp -and -not $haveUdp) {
        try {
            $lines = @(netstat -ano 2>$null)
            foreach ($line in $lines) {
                $t = $line.Trim()
                if ($t -notmatch '^(TCP|UDP)\s') { continue }
                $parts = @($t -split '\s+')
                if ($parts.Count -lt 4) { continue }
                $proto = $parts[0]
                $local = Split-WRAEndpoint -Value $parts[1]
                if ($proto -eq 'TCP') {
                    if ($parts.Count -lt 5) { continue }
                    $remote = Split-WRAEndpoint -Value $parts[2]
                    [void]$list.Add([PSCustomObject]@{
                        Protocol = 'TCP'; LocalAddress = $local.Address; LocalPort = $local.Port
                        RemoteAddress = $remote.Address; RemotePort = $remote.Port
                        State = $parts[3]; ProcessId = [int]$parts[4]
                    })
                }
                else {
                    [void]$list.Add([PSCustomObject]@{
                        Protocol = 'UDP'; LocalAddress = $local.Address; LocalPort = $local.Port
                        RemoteAddress = ''; RemotePort = 0; State = 'Listen'; ProcessId = [int]$parts[$parts.Count - 1]
                    })
                }
            }
        }
        catch { [void]$Warnings.Add(("Falha ao executar netstat: {0}" -f $_.Exception.Message)) }
    }

    return $list.ToArray()
}

function Get-WRANetProxy {
    param($Warnings)
    $proxy = [PSCustomObject]@{ Enabled = $false; Server = ''; AutoConfigUrl = '' }
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if (Test-Path -LiteralPath $key) {
            $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $proxy.Enabled = [bool](Get-WRANum -Object $p -Name 'ProxyEnable')
            $proxy.Server = [string](Get-WRAProp -Object $p -Path 'ProxyServer' -Default '')
            $proxy.AutoConfigUrl = [string](Get-WRAProp -Object $p -Path 'AutoConfigURL' -Default '')
        }
    }
    catch {
        if ($null -ne $Warnings) { [void]$Warnings.Add(("Falha ao ler proxy do registro: {0}" -f $_.Exception.Message)) }
    }
    return $proxy
}

function Get-WRANetFirewallProfiles {
    param($Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    if (Get-Command -Name 'Get-NetFirewallProfile' -ErrorAction SilentlyContinue) {
        try {
            foreach ($fp in @(Get-NetFirewallProfile -ErrorAction Stop)) {
                [void]$list.Add([PSCustomObject]@{
                    Name    = [string](Get-WRAProp -Object $fp -Path 'Name' -Default '')
                    Enabled = [string](Get-WRAProp -Object $fp -Path 'Enabled' -Default '')
                })
            }
            return $list.ToArray()
        }
        catch { }
    }
    # Fallback: registro (somente leitura).
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy'
    foreach ($prof in @('DomainProfile', 'StandardProfile', 'PublicProfile')) {
        try {
            $key = Join-Path $base $prof
            if (Test-Path -LiteralPath $key) {
                $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
                $en = [int](Get-WRANum -Object $p -Name 'EnableFirewall' -Default 0)
                [void]$list.Add([PSCustomObject]@{ Name = $prof; Enabled = ($en -eq 1) })
            }
        }
        catch { }
    }
    if ($list.Count -eq 0 -and $null -ne $Warnings) { [void]$Warnings.Add('Perfis de firewall indisponiveis.') }
    return $list.ToArray()
}

function Get-WRANetVpn {
    param($Interfaces, $Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($i in @($Interfaces)) {
        $desc = ('{0} {1} {2}' -f (Get-WRAProp -Object $i -Path 'Name' -Default ''), (Get-WRAProp -Object $i -Path 'Description' -Default ''), (Get-WRAProp -Object $i -Path 'AdapterType' -Default ''))
        if ($desc -match '(?i)\b(vpn|wan miniport|tap-|tap0|wireguard|openvpn|anyconnect|globalprotect|pangp|ras)\b') {
            [void]$list.Add([PSCustomObject]@{
                Name        = [string](Get-WRAProp -Object $i -Path 'Name' -Default '')
                Description = [string](Get-WRAProp -Object $i -Path 'Description' -Default '')
                Enabled     = [bool](Get-WRAProp -Object $i -Path 'Enabled' -Default $false)
            })
        }
    }
    return $list.ToArray()
}

function Get-WRANetHyperVSwitch {
    param([int] $TimeoutSec, $Warnings)
    $sw = @(Invoke-WRANetCim -ClassName 'Msvm_VirtualEthernetSwitch' -Namespace 'root/virtualization/v2' -Property @('Name', 'ElementName') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)
    if ($sw.Count -eq 0) { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($s in $sw) {
        [void]$list.Add([PSCustomObject]@{
            Name = [string](Get-WRAProp -Object $s -Path 'ElementName' -Default '')
            Id   = [string](Get-WRAProp -Object $s -Path 'Name' -Default '')
        })
    }
    return $list.ToArray()
}

# ----------------------------------------------------------- Operacao

function Invoke-WRANetworkAudit {
    [CmdletBinding()]
    param([Parameter()] $Context)

    $warnings = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]

    $config = Get-WRAProp -Object $Context -Path 'Config'

    $incInterfaces = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeInterfaces' -Default $true)
    $incConnections = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeConnections' -Default $true)
    $incListeners = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeListeners' -Default $true)
    $incRoutes = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeRoutes' -Default $true)
    $incShares = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeShares' -Default $true)
    $incSessions = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeSessions' -Default $true)
    $incFirewall = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeFirewallProfiles' -Default $true)
    $incVpn = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeVpn' -Default $true)
    $incHyperV = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.IncludeHyperVSwitch' -Default $true)
    $correlate = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.CorrelateProcesses' -Default $true)
    $maxConn = [int](Get-WRAProp -Object $config -Path 'Modules.Network.MaxConnections' -Default 0)
    $capture = [bool](Get-WRAProp -Object $config -Path 'Modules.Network.CapturePacketContent' -Default $false)
    $cimTimeout = [int](Get-WRAProp -Object $config -Path 'Timeouts.CimSeconds' -Default 30)

    # Regra inviolavel reforcada no codigo.
    if ($capture) {
        [void]$warnings.Add('CapturePacketContent ignorado: a ferramenta nunca captura conteudo de pacotes.')
    }

    # Interfaces (necessarias tambem para correlacao e VPN).
    $interfaces = @()
    if ($incInterfaces -or $incVpn -or $correlate) {
        $interfaces = Get-WRANetInterfaces -TimeoutSec $cimTimeout -Warnings $warnings
    }

    # Mapa IP -> interface para correlacao.
    $ipToInterface = @{ }
    foreach ($i in $interfaces) {
        foreach ($ip in @(Get-WRAProp -Object $i -Path 'IPv4' -Default @())) { $ipToInterface[[string]$ip] = (Get-WRAProp -Object $i -Path 'Name' -Default '') }
        foreach ($ip in @(Get-WRAProp -Object $i -Path 'IPv6' -Default @())) { $ipToInterface[[string]$ip] = (Get-WRAProp -Object $i -Path 'Name' -Default '') }
    }

    # Mapas de correlacao processo/servico.
    $pidName = @{ }
    $pidServices = @{ }
    if ($correlate) {
        foreach ($pr in @(Invoke-WRANetCim -ClassName 'Win32_Process' -Property @('ProcessId', 'Name') -TimeoutSec $cimTimeout -Warnings $warnings)) {
            $pidName[[int](Get-WRANum -Object $pr -Name 'ProcessId')] = [string](Get-WRAProp -Object $pr -Path 'Name' -Default '')
        }
        foreach ($s in @(Invoke-WRANetCim -ClassName 'Win32_Service' -Property @('Name', 'ProcessId') -TimeoutSec $cimTimeout -Warnings $warnings)) {
            $sp = [int](Get-WRANum -Object $s -Name 'ProcessId')
            if ($sp -le 0) { continue }
            if (-not $pidServices.ContainsKey($sp)) { $pidServices[$sp] = New-Object System.Collections.Generic.List[string] }
            [void]$pidServices[$sp].Add([string](Get-WRAProp -Object $s -Path 'Name' -Default ''))
        }
    }

    # Conexoes / portas com correlacao.
    $connections = @()
    $listeners = @()
    if ($incConnections -or $incListeners) {
        $raw = Get-WRANetConnectionsRaw -Warnings $warnings
        $enriched = New-Object System.Collections.Generic.List[object]
        foreach ($c in $raw) {
            $thePid = [int](Get-WRANum -Object $c -Name 'ProcessId')
            $pname = $null
            if ($pidName.ContainsKey($thePid)) { $pname = $pidName[$thePid] }
            $svcs = @()
            if ($pidServices.ContainsKey($thePid)) { $svcs = $pidServices[$thePid].ToArray() }
            $localAddr = [string](Get-WRAProp -Object $c -Path 'LocalAddress' -Default '')
            $iface = $null
            if ($ipToInterface.ContainsKey($localAddr)) { $iface = $ipToInterface[$localAddr] }
            elseif ($localAddr -eq '0.0.0.0' -or $localAddr -eq '::' -or $localAddr -eq '[::]') { $iface = 'Any' }

            [void]$enriched.Add([PSCustomObject]@{
                Protocol      = [string](Get-WRAProp -Object $c -Path 'Protocol' -Default '')
                LocalAddress  = $localAddr
                LocalPort     = [int](Get-WRANum -Object $c -Name 'LocalPort')
                RemoteAddress = [string](Get-WRAProp -Object $c -Path 'RemoteAddress' -Default '')
                RemotePort    = [int](Get-WRANum -Object $c -Name 'RemotePort')
                State         = [string](Get-WRAProp -Object $c -Path 'State' -Default '')
                ProcessId     = $thePid
                ProcessName   = $pname
                Services      = $svcs
                Interface     = $iface
            })
        }

        $all = $enriched.ToArray()
        if ($incListeners) {
            $listeners = @($all | Where-Object { (Get-WRAProp -Object $_ -Path 'State') -match '(?i)listen' -or (Get-WRAProp -Object $_ -Path 'Protocol') -eq 'UDP' })
        }
        if ($incConnections) {
            $connections = $all
            if ($maxConn -gt 0 -and $connections.Count -gt $maxConn) {
                $connections = @($connections | Select-Object -First $maxConn)
                [void]$warnings.Add(("Lista de conexoes limitada a {0} itens." -f $maxConn))
            }
        }
    }

    # Rotas (IPv4).
    $routes = @()
    if ($incRoutes) {
        foreach ($r in @(Invoke-WRANetCim -ClassName 'Win32_IP4RouteTable' -Property @('Destination', 'Mask', 'NextHop', 'Metric1', 'InterfaceIndex') -TimeoutSec $cimTimeout -Warnings $warnings)) {
            $routes += [PSCustomObject]@{
                Destination    = [string](Get-WRAProp -Object $r -Path 'Destination' -Default '')
                Mask           = [string](Get-WRAProp -Object $r -Path 'Mask' -Default '')
                NextHop        = [string](Get-WRAProp -Object $r -Path 'NextHop' -Default '')
                Metric         = [int](Get-WRANum -Object $r -Name 'Metric1')
                InterfaceIndex = [int](Get-WRANum -Object $r -Name 'InterfaceIndex')
            }
        }
    }

    # Compartilhamentos SMB.
    $shares = @()
    if ($incShares) {
        foreach ($sh in @(Invoke-WRANetCim -ClassName 'Win32_Share' -Property @('Name', 'Path', 'Description', 'Type') -TimeoutSec $cimTimeout -Warnings $warnings)) {
            $shares += [PSCustomObject]@{
                Name        = [string](Get-WRAProp -Object $sh -Path 'Name' -Default '')
                Path        = [string](Get-WRAProp -Object $sh -Path 'Path' -Default '')
                Description = [string](Get-WRAProp -Object $sh -Path 'Description' -Default '')
                Type        = [long](Get-WRANum -Object $sh -Name 'Type')
            }
        }
    }

    # Sessoes SMB (servidor).
    $sessions = @()
    if ($incSessions) {
        foreach ($ss in @(Invoke-WRANetCim -ClassName 'Win32_ServerSession' -Property @('ComputerName', 'UserName', 'ActiveTime', 'IdleTime') -TimeoutSec $cimTimeout -Warnings $null -Quiet)) {
            $sessions += [PSCustomObject]@{
                ComputerName = [string](Get-WRAProp -Object $ss -Path 'ComputerName' -Default '')
                UserName     = [string](Get-WRAProp -Object $ss -Path 'UserName' -Default '')
                ActiveTime   = [int](Get-WRANum -Object $ss -Name 'ActiveTime')
                IdleTime     = [int](Get-WRANum -Object $ss -Name 'IdleTime')
            }
        }
    }

    $proxy = Get-WRANetProxy -Warnings $warnings
    $firewall = @()
    if ($incFirewall) { $firewall = Get-WRANetFirewallProfiles -Warnings $warnings }
    $vpn = @()
    if ($incVpn) { $vpn = Get-WRANetVpn -Interfaces $interfaces -Warnings $warnings }
    $hyperV = @()
    if ($incHyperV) { $hyperV = Get-WRANetHyperVSwitch -TimeoutSec $cimTimeout -Warnings $warnings }

    $data = [PSCustomObject]@{
        Summary = [PSCustomObject]@{
            Interfaces   = @($interfaces).Count
            Connections  = @($connections).Count
            Listeners    = @($listeners).Count
            Routes       = @($routes).Count
            Shares       = @($shares).Count
            Sessions     = @($sessions).Count
            VpnAdapters  = @($vpn).Count
            HyperVSwitch = @($hyperV).Count
            ProxyEnabled = $proxy.Enabled
        }
        Interfaces      = @($interfaces)
        Connections     = @($connections)
        Listeners       = @($listeners)
        Routes          = @($routes)
        Shares          = @($shares)
        Sessions        = @($sessions)
        FirewallProfiles = @($firewall)
        Proxy           = $proxy
        Vpn             = @($vpn)
        HyperVSwitch    = @($hyperV)
    }

    return New-WRAModulePayload -Data $data -Warnings $warnings.ToArray() -Errors $errors.ToArray()
}

# ----------------------------------------------------------- Auto-registro

$WRANetManifest = $null
if (Get-Command -Name 'New-WRAModuleManifest' -ErrorAction SilentlyContinue) {
    $ops = @(
        (New-WRAOperation -Name 'Audit' -Handler 'Invoke-WRANetworkAudit' `
            -Description 'Auditoria da pilha de rede com correlacao processo/porta/interface/servico.')
    )
    $WRANetManifest = New-WRAModuleManifest -Module 'Network' -Operations $ops `
        -Version '4.1.0' -Description 'Auditoria integral da pilha de rede do Windows.'
}
if ($null -ne $WRANetManifest -and (Get-Command -Name 'Register-WRAModule' -ErrorAction SilentlyContinue)) {
    [void](Register-WRAModule -Manifest $WRANetManifest)
}

Export-ModuleMember -Function @('Invoke-WRANetworkAudit')
