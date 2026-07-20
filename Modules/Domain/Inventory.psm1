#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Inventory.psm1
#  Versao  : 1.1.0
#  Camada  : 2 - Dominio
#
#  Responsabilidade unica:
#    Inventariar hardware, firmware/BIOS/UEFI, CPU, RAM, GPU, discos,
#    controladoras, sistema operacional, licenciamento, programas,
#    recursos instalados, impressoras e adaptadores de rede.
#
#  Fontes: CIM Win32_*; Registro SOMENTE LEITURA para programas instalados
#  (evita Win32_Product, que e lento e dispara reconfiguracao de MSI).
#  Recursos via Win32_OptionalFeature/Win32_ServerFeature (nunca DISM).
#
#  Operacao: Collect  ->  Invoke-WRAInventoryCollect -Context
# ============================================================================

Set-StrictMode -Version 2.0

# --------------------------------------------------------------- Utilitarios

function Invoke-WRAInvCim {
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
        if (-not $Quiet -and $null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar {0}: {1}" -f $ClassName, $_.Exception.Message)) }
        return @()
    }
}

function ConvertTo-WRADateStr {
    param([Parameter()] $Value)
    if ($null -eq $Value) { return $null }
    try { return ([datetime]$Value).ToString('o') } catch { }
    # Fallback WMI: datas vem como CIM_DATETIME (ex.: 20231201083000.000000-180).
    try { return ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToString('o') } catch { }
    try { return $Value.ToString() } catch { return $null }
}

# ----------------------------------------------------------- Coletores

function Get-WRAInvHardware {
    param([int] $TimeoutSec, $Warnings)
    $cs = @(Invoke-WRAInvCim -ClassName 'Win32_ComputerSystem' -Property @('Manufacturer', 'Model', 'SystemType', 'TotalPhysicalMemory', 'NumberOfProcessors', 'NumberOfLogicalProcessors', 'Domain', 'PartOfDomain') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    $enc = @(Invoke-WRAInvCim -ClassName 'Win32_SystemEnclosure' -Property @('SerialNumber', 'ChassisTypes', 'Manufacturer') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)

    $cpu = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Invoke-WRAInvCim -ClassName 'Win32_Processor' -Property @('Name', 'Manufacturer', 'NumberOfCores', 'NumberOfLogicalProcessors', 'MaxClockSpeed', 'ProcessorId', 'SocketDesignation', 'L2CacheSize', 'L3CacheSize', 'VirtualizationFirmwareEnabled') -TimeoutSec $TimeoutSec -Warnings $Warnings)) {
        [void]$cpu.Add([PSCustomObject]@{
            Name           = [string](Get-WRAProp -Object $p -Path 'Name' -Default '')
            Manufacturer   = [string](Get-WRAProp -Object $p -Path 'Manufacturer' -Default '')
            Cores          = [int](Get-WRANum -Object $p -Name 'NumberOfCores')
            LogicalProcs   = [int](Get-WRANum -Object $p -Name 'NumberOfLogicalProcessors')
            MaxClockMHz    = [int](Get-WRANum -Object $p -Name 'MaxClockSpeed')
            Socket         = [string](Get-WRAProp -Object $p -Path 'SocketDesignation' -Default '')
            VtFirmware     = [bool](Get-WRAProp -Object $p -Path 'VirtualizationFirmwareEnabled' -Default $false)
        })
    }

    $ram = New-Object System.Collections.Generic.List[object]
    $ramTotal = 0.0
    foreach ($m in @(Invoke-WRAInvCim -ClassName 'Win32_PhysicalMemory' -Property @('Capacity', 'Speed', 'Manufacturer', 'PartNumber', 'DeviceLocator', 'BankLabel', 'FormFactor') -TimeoutSec $TimeoutSec -Warnings $Warnings)) {
        $cap = [double](Get-WRANum -Object $m -Name 'Capacity')
        $ramTotal += $cap
        [void]$ram.Add([PSCustomObject]@{
            CapacityGB   = [Math]::Round($cap / 1GB, 1)
            SpeedMHz     = [int](Get-WRANum -Object $m -Name 'Speed')
            Manufacturer = [string](Get-WRAProp -Object $m -Path 'Manufacturer' -Default '')
            PartNumber   = ([string](Get-WRAProp -Object $m -Path 'PartNumber' -Default '')).Trim()
            Slot         = [string](Get-WRAProp -Object $m -Path 'DeviceLocator' -Default '')
        })
    }

    $gpu = New-Object System.Collections.Generic.List[object]
    foreach ($g in @(Invoke-WRAInvCim -ClassName 'Win32_VideoController' -Property @('Name', 'AdapterRAM', 'DriverVersion', 'DriverDate', 'VideoProcessor', 'CurrentHorizontalResolution', 'CurrentVerticalResolution') -TimeoutSec $TimeoutSec -Warnings $Warnings)) {
        [void]$gpu.Add([PSCustomObject]@{
            Name          = [string](Get-WRAProp -Object $g -Path 'Name' -Default '')
            VideoProcessor = [string](Get-WRAProp -Object $g -Path 'VideoProcessor' -Default '')
            MemoryGB      = [Math]::Round((Get-WRANum -Object $g -Name 'AdapterRAM') / 1GB, 2)
            DriverVersion = [string](Get-WRAProp -Object $g -Path 'DriverVersion' -Default '')
            DriverDate    = ConvertTo-WRADateStr -Value (Get-WRAProp -Object $g -Path 'DriverDate')
            Resolution    = ('{0}x{1}' -f [int](Get-WRANum -Object $g -Name 'CurrentHorizontalResolution'), [int](Get-WRANum -Object $g -Name 'CurrentVerticalResolution'))
        })
    }

    $sysObj = $null
    if ($cs.Count -gt 0) { $sysObj = $cs[0] }
    $encObj = $null
    if ($enc.Count -gt 0) { $encObj = $enc[0] }

    return [PSCustomObject]@{
        Manufacturer  = [string](Get-WRAProp -Object $sysObj -Path 'Manufacturer' -Default '')
        Model         = [string](Get-WRAProp -Object $sysObj -Path 'Model' -Default '')
        SystemType    = [string](Get-WRAProp -Object $sysObj -Path 'SystemType' -Default '')
        SerialNumber  = [string](Get-WRAProp -Object $encObj -Path 'SerialNumber' -Default '')
        TotalRamGB    = [Math]::Round([double]$ramTotal / 1GB, 1)
        Domain        = [string](Get-WRAProp -Object $sysObj -Path 'Domain' -Default '')
        PartOfDomain  = [bool](Get-WRAProp -Object $sysObj -Path 'PartOfDomain' -Default $false)
        Cpu           = $cpu.ToArray()
        Ram           = $ram.ToArray()
        Gpu           = $gpu.ToArray()
    }
}

function Get-WRAInvFirmware {
    param([int] $TimeoutSec, $Warnings)
    $bios = @(Invoke-WRAInvCim -ClassName 'Win32_BIOS' -Property @('Manufacturer', 'SMBIOSBIOSVersion', 'ReleaseDate', 'SerialNumber', 'Version') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    $b = $null
    if ($bios.Count -gt 0) { $b = $bios[0] }
    $firmwareType = 'Unknown'
    try { if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State') { $firmwareType = 'UEFI' } } catch { }
    return [PSCustomObject]@{
        Manufacturer = [string](Get-WRAProp -Object $b -Path 'Manufacturer' -Default '')
        BiosVersion  = [string](Get-WRAProp -Object $b -Path 'SMBIOSBIOSVersion' -Default '')
        ReleaseDate  = ConvertTo-WRADateStr -Value (Get-WRAProp -Object $b -Path 'ReleaseDate')
        SerialNumber = [string](Get-WRAProp -Object $b -Path 'SerialNumber' -Default '')
        FirmwareType = $firmwareType
    }
}

function Get-WRAInvStorage {
    param([int] $TimeoutSec, $Warnings)
    $disks = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Invoke-WRAInvCim -ClassName 'Win32_DiskDrive' -Property @('Model', 'Size', 'InterfaceType', 'MediaType', 'SerialNumber', 'Partitions') -TimeoutSec $TimeoutSec -Warnings $Warnings)) {
        [void]$disks.Add([PSCustomObject]@{
            Model      = [string](Get-WRAProp -Object $d -Path 'Model' -Default '')
            SizeGB     = [Math]::Round((Get-WRANum -Object $d -Name 'Size') / 1GB, 1)
            Interface  = [string](Get-WRAProp -Object $d -Path 'InterfaceType' -Default '')
            MediaType  = [string](Get-WRAProp -Object $d -Path 'MediaType' -Default '')
            Serial     = ([string](Get-WRAProp -Object $d -Path 'SerialNumber' -Default '')).Trim()
            Partitions = [int](Get-WRANum -Object $d -Name 'Partitions')
        })
    }
    $volumes = New-Object System.Collections.Generic.List[object]
    foreach ($v in @(Invoke-WRAInvCim -ClassName 'Win32_LogicalDisk' -Filter 'DriveType=3' -Property @('DeviceID', 'Size', 'FreeSpace', 'FileSystem', 'VolumeName') -TimeoutSec $TimeoutSec -Warnings $Warnings)) {
        $size = [double](Get-WRANum -Object $v -Name 'Size')
        $free = [double](Get-WRANum -Object $v -Name 'FreeSpace')
        $usedPct = 0
        if ($size -gt 0) { $usedPct = [Math]::Round((($size - $free) / $size) * 100, 1) }
        [void]$volumes.Add([PSCustomObject]@{
            Drive       = [string](Get-WRAProp -Object $v -Path 'DeviceID' -Default '')
            Label       = [string](Get-WRAProp -Object $v -Path 'VolumeName' -Default '')
            FileSystem  = [string](Get-WRAProp -Object $v -Path 'FileSystem' -Default '')
            SizeGB      = [Math]::Round($size / 1GB, 1)
            FreeGB      = [Math]::Round($free / 1GB, 1)
            UsedPercent = $usedPct
        })
    }
    return [PSCustomObject]@{ Disks = $disks.ToArray(); Volumes = $volumes.ToArray() }
}

function Get-WRAInvControllers {
    param([int] $TimeoutSec, $Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($cls in @('Win32_SCSIController', 'Win32_IDEController')) {
        foreach ($c in @(Invoke-WRAInvCim -ClassName $cls -Property @('Name', 'Manufacturer') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)) {
            [void]$list.Add([PSCustomObject]@{
                Name         = [string](Get-WRAProp -Object $c -Path 'Name' -Default '')
                Manufacturer = [string](Get-WRAProp -Object $c -Path 'Manufacturer' -Default '')
                Type         = $cls
            })
        }
    }
    return $list.ToArray()
}

function Get-WRAInvOperatingSystem {
    param([int] $TimeoutSec, $Warnings)
    $os = @(Invoke-WRAInvCim -ClassName 'Win32_OperatingSystem' -Property @('Caption', 'Version', 'BuildNumber', 'OSArchitecture', 'InstallDate', 'LastBootUpTime', 'RegisteredUser', 'ServicePackMajorVersion', 'SerialNumber') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    if ($os.Count -eq 0) { return $null }
    $o = $os[0]
    return [PSCustomObject]@{
        Caption        = [string](Get-WRAProp -Object $o -Path 'Caption' -Default '')
        Version        = [string](Get-WRAProp -Object $o -Path 'Version' -Default '')
        Build          = [string](Get-WRAProp -Object $o -Path 'BuildNumber' -Default '')
        Architecture   = [string](Get-WRAProp -Object $o -Path 'OSArchitecture' -Default '')
        InstallDate    = ConvertTo-WRADateStr -Value (Get-WRAProp -Object $o -Path 'InstallDate')
        LastBootUpTime = ConvertTo-WRADateStr -Value (Get-WRAProp -Object $o -Path 'LastBootUpTime')
        RegisteredUser = [string](Get-WRAProp -Object $o -Path 'RegisteredUser' -Default '')
        ServicePack    = [int](Get-WRANum -Object $o -Name 'ServicePackMajorVersion')
    }
}

function Get-WRAInvLicensing {
    param([int] $TimeoutSec, $Warnings)
    $statusMap = @{ 0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'OOBGrace'; 3 = 'OOTGrace'; 4 = 'NonGenuineGrace'; 5 = 'Notification'; 6 = 'ExtendedGrace' }
    # Rotulos amigaveis (pt-BR) para o status de ativacao do Windows.
    $statusLabel = @{
        0 = 'Windows nao ativado'; 1 = 'Ativado'; 2 = 'Periodo de carencia (ativacao pendente)';
        3 = 'Necessita reativacao'; 4 = 'Nao genuino (carencia)'; 5 = 'Notificacao (nao ativado ou expirado)';
        6 = 'Carencia estendida'
    }
    $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    # Sem -Property: obtem o objeto completo, compativel com qualquer versao do
    # Windows (evita erro de propriedade inexistente em sistemas mais antigos).
    $prods = @(Invoke-WRAInvCim -ClassName 'SoftwareLicensingProduct' -TimeoutSec $TimeoutSec -Warnings $null -Quiet)

    $activation = 'Unknown'; $name = ''
    $statusCode = $null; $statusText = 'Desconhecido'
    $licType = 'Desconhecido'; $channel = ''; $situation = 'Desconhecido'
    $graceDays = $null; $expiry = $null; $ppk = ''

    foreach ($p in $prods) {
        $appId = [string](Get-WRAProp -Object $p -Path 'ApplicationID' -Default '')
        $key = [string](Get-WRAProp -Object $p -Path 'PartialProductKey' -Default '')
        if ($appId -ne $winAppId -or -not $key) { continue }

        $st = [int](Get-WRANum -Object $p -Name 'LicenseStatus')
        $statusCode = $st
        if ($statusMap.ContainsKey($st)) { $activation = $statusMap[$st] } else { $activation = ('Status' + $st) }
        if ($statusLabel.ContainsKey($st)) { $statusText = $statusLabel[$st] } else { $statusText = ('Status ' + $st) }
        $name = [string](Get-WRAProp -Object $p -Path 'Name' -Default '')
        $ppk = $key
        $desc = [string](Get-WRAProp -Object $p -Path 'Description' -Default '')
        $pkc = [string](Get-WRAProp -Object $p -Path 'ProductKeyChannel' -Default '')
        $channel = if ($pkc) { $pkc } else { $desc }

        # Tipo de licenca a partir de Description/ProductKeyChannel (dados oficiais).
        $probe = ($desc + ' ' + $pkc).ToUpperInvariant()
        if ($probe -match 'TIMEBASED|EVAL') { $licType = 'Avaliacao (Evaluation)' }
        elseif ($probe -match 'OEM') { $licType = 'OEM' }
        elseif ($probe -match 'RETAIL') { $licType = 'Retail' }
        elseif ($probe -match 'KMSCLIENT|GVLK|KMS') { $licType = 'Volume (KMS)' }
        elseif ($probe -match 'MAK') { $licType = 'Volume (MAK)' }
        elseif ($probe -match 'VOLUME') { $licType = 'Volume' }
        elseif ($probe -match 'DIGITAL') { $licType = 'Digital' }

        # Tempo restante (carencia/KMS/avaliacao) via GracePeriodRemaining (minutos).
        $graceMin = [double](Get-WRANum -Object $p -Name 'GracePeriodRemaining')
        if ($graceMin -gt 0) {
            $graceDays = [int][Math]::Ceiling($graceMin / 1440.0)
            $expiry = (Get-Date).AddMinutes($graceMin).ToString('yyyy-MM-dd')
        }
        # Data de avaliacao explicita, quando houver (1601 = "nulo" do WMI).
        $evalStr = ConvertTo-WRADateStr -Value (Get-WRAProp -Object $p -Path 'EvaluationEndDate' -Default $null)
        if ($evalStr) {
            try {
                $evalDt = [datetime]$evalStr
                if ($evalDt.Year -gt 1601) {
                    $expiry = $evalDt.ToString('yyyy-MM-dd')
                    $graceDays = [int][Math]::Ceiling(($evalDt - (Get-Date)).TotalDays)
                    if ($licType -eq 'Desconhecido') { $licType = 'Avaliacao (Evaluation)' }
                }
            }
            catch { }
        }

        # Situacao consolidada, em linguagem clara.
        if ($st -eq 0) { $situation = 'Windows nao ativado' }
        elseif ($st -eq 3) { $situation = 'Necessita reativacao' }
        elseif ($licType -eq 'Avaliacao (Evaluation)') {
            $situation = if ($null -ne $graceDays) { ('Periodo de avaliacao - expira em {0} dias' -f $graceDays) } else { 'Periodo de avaliacao (Evaluation)' }
        }
        elseif ($null -ne $graceDays -and $graceDays -gt 0) { $situation = ('Licenca valida por {0} dias' -f $graceDays) }
        elseif ($st -eq 1) { $situation = 'Licenciamento Permanente' }
        else { $situation = $statusText }

        break
    }

    return [PSCustomObject]@{
        WindowsActivation  = $activation
        LicenseName        = $name
        Status             = $statusText
        StatusCode         = $statusCode
        Type               = $licType
        Channel            = $channel
        Situation          = $situation
        GraceDaysRemaining = $graceDays
        ExpiryDate         = $expiry
        PartialProductKey  = $ppk
    }
}

function Get-WRAInvPrograms {
    param($Warnings)
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $seen = @{ }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        try {
            foreach ($k in @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)) {
                $name = [string](Get-WRAProp -Object $k -Path 'DisplayName' -Default '')
                if (-not $name) { continue }
                $sysComp = [int](Get-WRANum -Object $k -Name 'SystemComponent' -Default 0)
                if ($sysComp -eq 1) { continue }
                $ver = [string](Get-WRAProp -Object $k -Path 'DisplayVersion' -Default '')
                $key = ($name + '|' + $ver).ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$list.Add([PSCustomObject]@{
                    Name        = $name
                    Version     = $ver
                    Publisher   = [string](Get-WRAProp -Object $k -Path 'Publisher' -Default '')
                    InstallDate = [string](Get-WRAProp -Object $k -Path 'InstallDate' -Default '')
                })
            }
        }
        catch { }
    }
    return @($list | Sort-Object -Property Name)
}

function Get-WRAInvFeatures {
    param([int] $TimeoutSec, $Warnings)
    $features = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Invoke-WRAInvCim -ClassName 'Win32_OptionalFeature' -Property @('Name', 'InstallState') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)) {
        if ([int](Get-WRANum -Object $f -Name 'InstallState') -eq 1) {
            [void]$features.Add([PSCustomObject]@{ Name = [string](Get-WRAProp -Object $f -Path 'Name' -Default ''); Source = 'OptionalFeature' })
        }
    }
    foreach ($sf in @(Invoke-WRAInvCim -ClassName 'Win32_ServerFeature' -Property @('Name', 'ID') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)) {
        [void]$features.Add([PSCustomObject]@{ Name = [string](Get-WRAProp -Object $sf -Path 'Name' -Default ''); Source = 'ServerFeature' })
    }
    return $features.ToArray()
}

function Get-WRAInvPrinters {
    param([int] $TimeoutSec, $Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Invoke-WRAInvCim -ClassName 'Win32_Printer' -Property @('Name', 'DriverName', 'PortName', 'Default', 'Shared', 'Network', 'WorkOffline') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)) {
        [void]$list.Add([PSCustomObject]@{
            Name      = [string](Get-WRAProp -Object $p -Path 'Name' -Default '')
            Driver    = [string](Get-WRAProp -Object $p -Path 'DriverName' -Default '')
            Port      = [string](Get-WRAProp -Object $p -Path 'PortName' -Default '')
            IsDefault = [bool](Get-WRAProp -Object $p -Path 'Default' -Default $false)
            Shared    = [bool](Get-WRAProp -Object $p -Path 'Shared' -Default $false)
            Network   = [bool](Get-WRAProp -Object $p -Path 'Network' -Default $false)
        })
    }
    return $list.ToArray()
}

function Get-WRAInvNetworkAdapters {
    param([int] $TimeoutSec, $Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($a in @(Invoke-WRAInvCim -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True' -Property @('Name', 'MACAddress', 'Speed', 'Manufacturer', 'NetEnabled') -TimeoutSec $TimeoutSec -Warnings $null -Quiet)) {
        $speed = [double](Get-WRANum -Object $a -Name 'Speed')
        $speedMbps = 0
        if ($speed -gt 0) { $speedMbps = [Math]::Round($speed / 1000000, 0) }
        [void]$list.Add([PSCustomObject]@{
            Name         = [string](Get-WRAProp -Object $a -Path 'Name' -Default '')
            MacAddress   = [string](Get-WRAProp -Object $a -Path 'MACAddress' -Default '')
            SpeedMbps    = $speedMbps
            Manufacturer = [string](Get-WRAProp -Object $a -Path 'Manufacturer' -Default '')
            Enabled      = [bool](Get-WRAProp -Object $a -Path 'NetEnabled' -Default $false)
        })
    }
    return $list.ToArray()
}

# ----------------------------------------------------------- Operacao

function Invoke-WRAInventoryCollect {
    [CmdletBinding()]
    param([Parameter()] $Context)

    $warnings = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]
    $config = Get-WRAProp -Object $Context -Path 'Config'
    $cimTimeout = [int](Get-WRAProp -Object $config -Path 'Timeouts.CimSeconds' -Default 30)

    $hardware = $null; $firmware = $null; $storage = $null; $controllers = @()
    $os = $null; $licensing = $null; $programs = @(); $features = @()
    $printers = @(); $nics = @()

    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeHardware' -Default $true)) {
        $hardware = Get-WRAInvHardware -TimeoutSec $cimTimeout -Warnings $warnings
        $storage = Get-WRAInvStorage -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeControllers' -Default $true)) {
        $controllers = Get-WRAInvControllers -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeFirmware' -Default $true)) {
        $firmware = Get-WRAInvFirmware -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeOperatingSystem' -Default $true)) {
        $os = Get-WRAInvOperatingSystem -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeLicensing' -Default $true)) {
        $licensing = Get-WRAInvLicensing -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeSoftware' -Default $true)) {
        $programs = Get-WRAInvPrograms -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeFeatures' -Default $true)) {
        $features = Get-WRAInvFeatures -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludePrinters' -Default $true)) {
        $printers = Get-WRAInvPrinters -TimeoutSec $cimTimeout -Warnings $warnings
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Inventory.IncludeNetworkAdapters' -Default $true)) {
        $nics = Get-WRAInvNetworkAdapters -TimeoutSec $cimTimeout -Warnings $warnings
    }

    $data = [PSCustomObject]@{
        Summary = [PSCustomObject]@{
            Manufacturer    = [string](Get-WRAProp -Object $hardware -Path 'Manufacturer' -Default '')
            Model           = [string](Get-WRAProp -Object $hardware -Path 'Model' -Default '')
            OperatingSystem = [string](Get-WRAProp -Object $os -Path 'Caption' -Default '')
            TotalRamGB      = (Get-WRAProp -Object $hardware -Path 'TotalRamGB' -Default 0)
            Activation      = [string](Get-WRAProp -Object $licensing -Path 'WindowsActivation' -Default 'Unknown')
            ProgramsCount   = @($programs).Count
        }
        Hardware        = $hardware
        Firmware        = $firmware
        Storage         = $storage
        Controllers     = @($controllers)
        OperatingSystem = $os
        Licensing       = $licensing
        Programs        = @($programs)
        Features        = @($features)
        Printers        = @($printers)
        NetworkAdapters = @($nics)
    }

    return New-WRAModulePayload -Data $data -Warnings $warnings.ToArray() -Errors $errors.ToArray()
}

# ----------------------------------------------------------- Auto-registro

$WRAInvManifest = $null
if (Get-Command -Name 'New-WRAModuleManifest' -ErrorAction SilentlyContinue) {
    $ops = @(
        (New-WRAOperation -Name 'Collect' -Handler 'Invoke-WRAInventoryCollect' `
            -Description 'Inventario completo de hardware, firmware, SO, software, impressoras e rede.')
    )
    $WRAInvManifest = New-WRAModuleManifest -Module 'Inventory' -Operations $ops `
        -Version '1.1.0' -Description 'Inventario detalhado do sistema.'
}
if ($null -ne $WRAInvManifest -and (Get-Command -Name 'Register-WRAModule' -ErrorAction SilentlyContinue)) {
    [void](Register-WRAModule -Manifest $WRAInvManifest)
}

Export-ModuleMember -Function @('Invoke-WRAInventoryCollect')
