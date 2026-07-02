#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Monitor.psm1
#  Versao  : 4.1.0
#  Camada  : 2 - Dominio
#
#  Responsabilidade unica:
#    Coletar um snapshot AMOSTRADO dos recursos do sistema (CPU, memoria, GPU,
#    disco, rede, processos, servicos e eventos) e avaliar contra os limites
#    configurados.
#
#  Fonte de dados: CIM Win32_PerfFormattedData_* (dados de performance counters
#  sem localizacao de nomes), Win32_OperatingSystem, Win32_Service e
#  Windows Event Log. ETW e reservado ao modo continuo (Triggers - Etapa 14).
#
#  Operacao: Collect  ->  Invoke-WRAMonitorCollect -Context
# ============================================================================

Set-StrictMode -Version 2.0

# --------------------------------------------------------------- Utilitarios

function Invoke-WRAMonitorCim {
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
        if ($null -ne $Warnings) {
            [void]$Warnings.Add(("Falha ao consultar {0}: {1}" -f $ClassName, $_.Exception.Message))
        }
        return @()
    }
}

function Get-WRANum {
    param([Parameter()] $Object, [Parameter(Mandatory = $true)][string] $Name, [Parameter()][double] $Default = 0)
    $v = Get-WRAProp -Object $Object -Path $Name -Default $Default
    if ($null -eq $v) { return $Default }
    try { return [double]$v } catch { return $Default }
}

function Get-WRAStatus {
    param([double] $Value, [double] $Warn, [double] $Critical)
    if ($Value -ge $Critical) { return 'Critical' }
    if ($Value -ge $Warn) { return 'Warning' }
    return 'OK'
}

function Get-WRAAverage {
    param([Parameter()] $Samples)
    $arr = @($Samples)
    if ($arr.Count -eq 0) { return 0 }
    $sum = 0.0
    foreach ($s in $arr) { $sum += [double]$s }
    return [Math]::Round($sum / $arr.Count, 2)
}

function Get-WRAMax {
    param([Parameter()] $Samples)
    $arr = @($Samples)
    if ($arr.Count -eq 0) { return 0 }
    $max = [double]$arr[0]
    foreach ($s in $arr) { if ([double]$s -gt $max) { $max = [double]$s } }
    return [Math]::Round($max, 2)
}

# ----------------------------------------------------------- Coletores

function Get-WRAMonitorSamples {
    # Loop unico de amostragem para metricas de taxa (CPU, disco, rede),
    # compartilhando a janela de tempo para minimizar custo.
    param([int] $Interval, [int] $Duration, [int] $TimeoutSec, $Warnings)

    $count = [Math]::Max(1, [int][Math]::Floor($Duration / [Math]::Max(1, $Interval)))

    $cpu = New-Object System.Collections.Generic.List[double]
    $diskTime = New-Object System.Collections.Generic.List[double]
    $diskQueue = New-Object System.Collections.Generic.List[double]
    $diskBytes = New-Object System.Collections.Generic.List[double]
    $netBytes = New-Object System.Collections.Generic.List[double]

    for ($i = 0; $i -lt $count; $i++) {
        $c = @(Invoke-WRAMonitorCim -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -Filter "Name='_Total'" -Property @('PercentProcessorTime') -TimeoutSec $TimeoutSec -Warnings $Warnings)
        if ($c.Count -gt 0) { [void]$cpu.Add((Get-WRANum -Object $c[0] -Name 'PercentProcessorTime')) }

        $d = @(Invoke-WRAMonitorCim -ClassName 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' -Filter "Name='_Total'" -Property @('PercentDiskTime', 'CurrentDiskQueueLength', 'DiskBytesPersec') -TimeoutSec $TimeoutSec -Warnings $Warnings)
        if ($d.Count -gt 0) {
            [void]$diskTime.Add((Get-WRANum -Object $d[0] -Name 'PercentDiskTime'))
            [void]$diskQueue.Add((Get-WRANum -Object $d[0] -Name 'CurrentDiskQueueLength'))
            [void]$diskBytes.Add((Get-WRANum -Object $d[0] -Name 'DiskBytesPersec'))
        }

        $n = @(Invoke-WRAMonitorCim -ClassName 'Win32_PerfFormattedData_Tcpip_NetworkInterface' -Property @('Name', 'BytesTotalPersec') -TimeoutSec $TimeoutSec -Warnings $Warnings)
        if ($n.Count -gt 0) {
            $sum = 0.0
            foreach ($iface in $n) { $sum += (Get-WRANum -Object $iface -Name 'BytesTotalPersec') }
            [void]$netBytes.Add($sum)
        }

        if ($i -lt ($count - 1)) { Start-Sleep -Seconds $Interval }
    }

    return [PSCustomObject]@{
        SampleCount = $count
        Cpu         = $cpu
        DiskTime    = $diskTime
        DiskQueue   = $diskQueue
        DiskBytes   = $diskBytes
        NetBytes    = $netBytes
    }
}

function Get-WRAMonitorMemory {
    param([int] $TimeoutSec, $Warnings)
    $os = @(Invoke-WRAMonitorCim -ClassName 'Win32_OperatingSystem' -Property @('TotalVisibleMemorySize', 'FreePhysicalMemory') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    if ($os.Count -eq 0) {
        return [PSCustomObject]@{ TotalMB = 0; UsedMB = 0; FreeMB = 0; UsedPercent = 0 }
    }
    $totalKb = Get-WRANum -Object $os[0] -Name 'TotalVisibleMemorySize'
    $freeKb = Get-WRANum -Object $os[0] -Name 'FreePhysicalMemory'
    $usedKb = $totalKb - $freeKb
    $usedPct = 0
    if ($totalKb -gt 0) { $usedPct = [Math]::Round(($usedKb / $totalKb) * 100, 2) }
    return [PSCustomObject]@{
        TotalMB     = [Math]::Round($totalKb / 1024, 1)
        UsedMB      = [Math]::Round($usedKb / 1024, 1)
        FreeMB      = [Math]::Round($freeKb / 1024, 1)
        UsedPercent = $usedPct
    }
}

function Get-WRAMonitorGpu {
    param([int] $TimeoutSec, $Warnings)
    $eng = @(Invoke-WRAMonitorCim -ClassName 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' -Property @('Name', 'UtilizationPercentage') -TimeoutSec $TimeoutSec -Warnings $null)
    if ($eng.Count -eq 0) {
        if ($null -ne $Warnings) { [void]$Warnings.Add('Contadores de GPU indisponiveis neste sistema.') }
        return [PSCustomObject]@{ Available = $false; MaxUtilizationPercent = 0; SumUtilizationPercent = 0; EngineCount = 0 }
    }
    $maxU = 0.0; $sumU = 0.0
    foreach ($e in $eng) {
        $u = Get-WRANum -Object $e -Name 'UtilizationPercentage'
        $sumU += $u
        if ($u -gt $maxU) { $maxU = $u }
    }
    return [PSCustomObject]@{
        Available             = $true
        MaxUtilizationPercent = [Math]::Round($maxU, 2)
        SumUtilizationPercent = [Math]::Round($sumU, 2)
        EngineCount           = $eng.Count
    }
}

function Get-WRAMonitorProcesses {
    param([int] $Top, [int] $TimeoutSec, $Warnings)
    $perf = @(Invoke-WRAMonitorCim -ClassName 'Win32_PerfFormattedData_PerfProc_Process' -Property @('Name', 'IDProcess', 'PercentProcessorTime', 'WorkingSetPrivate', 'WorkingSet') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in $perf) {
        $name = [string](Get-WRAProp -Object $p -Path 'Name' -Default '')
        if ($name -eq '_Total') { continue }
        [void]$list.Add([PSCustomObject]@{
            Name          = $name
            ProcessId     = [int](Get-WRANum -Object $p -Name 'IDProcess')
            CpuPercent    = [Math]::Round((Get-WRANum -Object $p -Name 'PercentProcessorTime'), 1)
            WorkingSetMB  = [Math]::Round((Get-WRANum -Object $p -Name 'WorkingSet') / 1MB, 1)
            PrivateSetMB  = [Math]::Round((Get-WRANum -Object $p -Name 'WorkingSetPrivate') / 1MB, 1)
        })
    }
    $byCpu = @($list | Sort-Object -Property CpuPercent -Descending | Select-Object -First $Top)
    $byMem = @($list | Sort-Object -Property WorkingSetMB -Descending | Select-Object -First $Top)
    return [PSCustomObject]@{
        Total  = $list.Count
        TopCpu = $byCpu
        TopMem = $byMem
    }
}

function Get-WRAMonitorServices {
    param([int] $MaxAutoStopped, [int] $TimeoutSec, $Warnings)
    $svc = @(Invoke-WRAMonitorCim -ClassName 'Win32_Service' -Property @('Name', 'DisplayName', 'State', 'StartMode', 'DelayedAutoStart', 'ExitCode') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    $running = 0; $stopped = 0; $other = 0
    $autoStopped = New-Object System.Collections.Generic.List[object]
    foreach ($s in $svc) {
        $state = [string](Get-WRAProp -Object $s -Path 'State' -Default '')
        $start = [string](Get-WRAProp -Object $s -Path 'StartMode' -Default '')
        if ($state -eq 'Running') { $running++ }
        elseif ($state -eq 'Stopped') { $stopped++ }
        else { $other++ }
        if ($start -eq 'Auto' -and $state -ne 'Running') {
            # Distingue "Automatico (Inicio Atrasado)": esses servicos podem
            # permanecer parados por design apos concluirem sua tarefa (saida 0),
            # o que NAO representa um problema (reducao de falsos positivos).
            $delayed = [bool](Get-WRAProp -Object $s -Path 'DelayedAutoStart' -Default $false)
            $exitCode = Get-WRAProp -Object $s -Path 'ExitCode' -Default $null
            $cleanExit = ($null -ne $exitCode -and ([int]$exitCode) -eq 0)
            if ($autoStopped.Count -lt $MaxAutoStopped) {
                [void]$autoStopped.Add([PSCustomObject]@{
                    Name        = [string](Get-WRAProp -Object $s -Path 'Name' -Default '')
                    DisplayName = [string](Get-WRAProp -Object $s -Path 'DisplayName' -Default '')
                    State       = $state
                    Delayed     = $delayed
                    CleanExit   = $cleanExit
                })
            }
        }
    }
    return [PSCustomObject]@{
        Total              = $svc.Count
        Running            = $running
        Stopped            = $stopped
        Other              = $other
        AutoStartNotRunning = $autoStopped.ToArray()
    }
}

function Get-WRAMonitorEvents {
    param([int] $LookbackHours, [int] $MaxItems, $Warnings)
    $result = [PSCustomObject]@{ Critical = 0; Error = 0; Items = @() }
    try {
        $start = (Get-Date).AddHours(-1 * $LookbackHours)
        $filter = @{ LogName = @('System', 'Application'); Level = @(1, 2); StartTime = $start }
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents ($MaxItems * 4) -ErrorAction Stop)
        $crit = 0; $err = 0
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($e in $events) {
            $level = [int](Get-WRAProp -Object $e -Path 'Level' -Default 0)
            if ($level -eq 1) { $crit++ } elseif ($level -eq 2) { $err++ }
            if ($items.Count -lt $MaxItems) {
                $msg = [string](Get-WRAProp -Object $e -Path 'Message' -Default '')
                if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) + '...' }
                [void]$items.Add([PSCustomObject]@{
                    TimeCreated = (Get-WRAProp -Object $e -Path 'TimeCreated' -Default $null)
                    LogName     = [string](Get-WRAProp -Object $e -Path 'LogName' -Default '')
                    Id          = [int](Get-WRAProp -Object $e -Path 'Id' -Default 0)
                    Level       = [string](Get-WRAProp -Object $e -Path 'LevelDisplayName' -Default '')
                    Provider    = [string](Get-WRAProp -Object $e -Path 'ProviderName' -Default '')
                    Message     = $msg
                })
            }
        }
        $result = [PSCustomObject]@{ Critical = $crit; Error = $err; Items = $items.ToArray() }
    }
    catch {
        if ($null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar o log de eventos: {0}" -f $_.Exception.Message)) }
    }
    return $result
}

# --------------------------------------------------- Analise de eventos (7 dias)
# Coleta nativa via Get-WinEvent (filtragem no servidor) com orcamento por
# consulta, classificacao por nivel estavel (independente de idioma do SO),
# deduplicacao/agrupamento e indicadores agregados. Aditivo: nao altera 'Events'.

function Convert-WRAEventLevelKey {
    param([int] $LevelValue, [bool] $IsAudit)
    if ($IsAudit) { return 'Auditoria' }
    if ($LevelValue -eq 1) { return 'Critico' }
    if ($LevelValue -eq 2) { return 'Erro' }
    if ($LevelValue -eq 3) { return 'Aviso' }
    return 'Informacao'
}

function Get-WRAEventMessageDigest {
    param([string] $Message, [int] $Max = 180)
    if ([string]::IsNullOrWhiteSpace($Message)) { return '' }
    $m = ($Message -replace '\s+', ' ').Trim()
    if ($m.Length -gt $Max) { $m = $m.Substring(0, $Max) + '...' }
    return $m
}

function Get-WRAMonitorEventAnalysis {
    param([int] $LookbackDays = 7, [int] $MaxEvents = 2000, [int] $RecurringThreshold = 5, $Warnings)

    $sevRank = @{ 'Critico' = 0; 'Erro' = 1; 'Auditoria' = 2; 'Aviso' = 3; 'Informacao' = 4 }
    $emptyResult = [PSCustomObject]@{
        LookbackDays = $LookbackDays; TotalCollected = 0; GroupCount = 0; Capped = $false
        Summary = [PSCustomObject]@{ Critico = 0; Erro = 0; Aviso = 0; Informacao = 0; Auditoria = 0 }
        ByLevel = @(); ByLog = @(); ByProvider = @(); ByDay = @(); Groups = @()
    }

    $days = [Math]::Abs($LookbackDays); if ($days -lt 1) { $days = 7 }
    $budget = $MaxEvents; if ($budget -lt 200) { $budget = 200 }
    $startTime = (Get-Date).AddDays(-1 * $days)

    # Orcamento por consulta -> desempenho previsivel mesmo com logs enormes.
    $mainMax = [int][Math]::Floor($budget * 0.6); if ($mainMax -lt 100) { $mainMax = 100 }
    $auditMax = [int][Math]::Floor($budget * 0.2); if ($auditMax -lt 50) { $auditMax = 50 }
    $infoMax = [int][Math]::Floor($budget * 0.2); if ($infoMax -lt 50) { $infoMax = 50 }

    $queries = @(
        [PSCustomObject]@{ Filter = @{ LogName = @('System', 'Application'); Level = @(1, 2, 3); StartTime = $startTime }; Max = $mainMax; Audit = $false },
        [PSCustomObject]@{ Filter = @{ LogName = 'Security'; Keywords = 4503599627370496; StartTime = $startTime }; Max = $auditMax; Audit = $true },
        [PSCustomObject]@{ Filter = @{ LogName = 'System'; Level = @(4); StartTime = $startTime }; Max = $infoMax; Audit = $false }
    )

    $raw = New-Object System.Collections.Generic.List[object]
    $reqTotal = 0
    foreach ($q in $queries) {
        $reqTotal += [int]$q.Max
        try {
            $ev = @(Get-WinEvent -FilterHashtable $q.Filter -MaxEvents ([int]$q.Max) -ErrorAction Stop)
            foreach ($e in $ev) { [void]$raw.Add([PSCustomObject]@{ Event = $e; Audit = [bool]$q.Audit }) }
        }
        catch {
            $ln = $q.Filter['LogName']; if ($ln -is [array]) { $ln = ($ln -join ',') }
            if ($null -ne $Warnings) { [void]$Warnings.Add(("Analise de eventos: '{0}' sem registros no periodo ou indisponivel ({1})." -f $ln, $_.Exception.Message)) }
        }
    }
    if ($raw.Count -eq 0) { return $emptyResult }

    $sum = @{ 'Critico' = 0; 'Erro' = 0; 'Aviso' = 0; 'Informacao' = 0; 'Auditoria' = 0 }
    $byLog = @{}; $byProvider = @{}
    $byDay = [ordered]@{}
    for ($i = $days - 1; $i -ge 0; $i--) { $byDay[((Get-Date).Date.AddDays(-1 * $i).ToString('yyyy-MM-dd'))] = 0 }
    $groups = @{}

    foreach ($wrap in $raw) {
        $e = $wrap.Event
        $lvlVal = [int](Get-WRAProp -Object $e -Path 'Level' -Default 4)
        $key = Convert-WRAEventLevelKey -LevelValue $lvlVal -IsAudit ([bool]$wrap.Audit)
        if (-not $sum.ContainsKey($key)) { $key = 'Informacao' }
        $sum[$key] = [int]$sum[$key] + 1

        $log = [string](Get-WRAProp -Object $e -Path 'LogName' -Default '')
        if ($log) { if ($byLog.ContainsKey($log)) { $byLog[$log] = [int]$byLog[$log] + 1 } else { $byLog[$log] = 1 } }
        $prov = [string](Get-WRAProp -Object $e -Path 'ProviderName' -Default '')
        if ($prov) { if ($byProvider.ContainsKey($prov)) { $byProvider[$prov] = [int]$byProvider[$prov] + 1 } else { $byProvider[$prov] = 1 } }

        $id = [int](Get-WRAProp -Object $e -Path 'Id' -Default 0)
        $task = [string](Get-WRAProp -Object $e -Path 'TaskDisplayName' -Default '')
        if ([string]::IsNullOrWhiteSpace($task)) { $task = $log }
        $tc = Get-WRAProp -Object $e -Path 'TimeCreated' -Default $null
        if ($null -ne $tc) {
            $dk = ([datetime]$tc).ToString('yyyy-MM-dd')
            if ($byDay.Contains($dk)) { $byDay[$dk] = [int]$byDay[$dk] + 1 }
        }

        $gkey = ('{0}|{1}|{2}|{3}' -f $key, $log, $id, $prov)
        if ($groups.ContainsKey($gkey)) {
            $g = $groups[$gkey]
            $g.Count = [int]$g.Count + 1
            if ($null -ne $tc) {
                if ($null -eq $g.LastSeen -or [datetime]$tc -gt [datetime]$g.LastSeen) { $g.LastSeen = $tc }
                if ($null -eq $g.FirstSeen -or [datetime]$tc -lt [datetime]$g.FirstSeen) { $g.FirstSeen = $tc }
            }
        }
        else {
            $groups[$gkey] = [PSCustomObject]@{
                Level = $key; Log = $log; Id = $id; Provider = $prov; Category = $task
                Count = 1; FirstSeen = $tc; LastSeen = $tc
                Message = (Get-WRAEventMessageDigest -Message ([string](Get-WRAProp -Object $e -Path 'Message' -Default '')))
                Recurring = $false; Critical = ($key -eq 'Critico')
            }
        }
    }

    $groupList = New-Object System.Collections.Generic.List[object]
    foreach ($g in $groups.Values) { $g.Recurring = ([int]$g.Count -ge $RecurringThreshold); [void]$groupList.Add($g) }
    $sorted = @($groupList.ToArray() | Sort-Object `
            @{ Expression = { if ($sevRank.ContainsKey($_.Level)) { $sevRank[$_.Level] } else { 9 } } }, `
        @{ Expression = 'Count'; Descending = $true }, `
        @{ Expression = 'LastSeen'; Descending = $true })
    $maxGroups = 500
    if ($sorted.Count -gt $maxGroups) { $sorted = $sorted[0..($maxGroups - 1)] }

    $byLevelArr = New-Object System.Collections.Generic.List[object]
    foreach ($lk in @('Critico', 'Erro', 'Auditoria', 'Aviso', 'Informacao')) {
        if ([int]$sum[$lk] -gt 0) { [void]$byLevelArr.Add([PSCustomObject]@{ Key = $lk; Count = [int]$sum[$lk] }) }
    }
    $byLogArr = New-Object System.Collections.Generic.List[object]
    foreach ($kv in ($byLog.GetEnumerator() | Sort-Object Value -Descending)) {
        [void]$byLogArr.Add([PSCustomObject]@{ Key = [string]$kv.Key; Count = [int]$kv.Value })
    }
    $byProvArr = New-Object System.Collections.Generic.List[object]
    $provSorted = @($byProvider.GetEnumerator() | Sort-Object Value -Descending)
    $provTop = if ($provSorted.Count -gt 12) { $provSorted[0..11] } else { $provSorted }
    foreach ($kv in $provTop) { [void]$byProvArr.Add([PSCustomObject]@{ Key = [string]$kv.Key; Count = [int]$kv.Value }) }
    $byDayArr = New-Object System.Collections.Generic.List[object]
    foreach ($dk in $byDay.Keys) { [void]$byDayArr.Add([PSCustomObject]@{ Date = [string]$dk; Count = [int]$byDay[$dk] }) }

    return [PSCustomObject]@{
        LookbackDays = $days
        TotalCollected = $raw.Count
        GroupCount = $sorted.Count
        Capped = ($raw.Count -ge $reqTotal)
        Summary = [PSCustomObject]@{
            Critico = [int]$sum['Critico']; Erro = [int]$sum['Erro']; Aviso = [int]$sum['Aviso']
            Informacao = [int]$sum['Informacao']; Auditoria = [int]$sum['Auditoria']
        }
        ByLevel = $byLevelArr.ToArray()
        ByLog = $byLogArr.ToArray()
        ByProvider = $byProvArr.ToArray()
        ByDay = $byDayArr.ToArray()
        Groups = $sorted
    }
}

# ----------------------------------------------------------- Operacao

function Invoke-WRAMonitorCollect {
    [CmdletBinding()]
    param([Parameter()] $Context)

    $warnings = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]

    $config = Get-WRAProp -Object $Context -Path 'Config'

    $interval = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.SampleIntervalSeconds' -Default 2)
    $duration = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.DurationSeconds' -Default 10)
    $topN = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.TopProcesses' -Default 10)
    $collectGpu = [bool](Get-WRAProp -Object $config -Path 'Modules.Monitor.CollectGpu' -Default $true)
    $useEtw = [bool](Get-WRAProp -Object $config -Path 'Modules.Monitor.UseEtw' -Default $true)
    $includeServices = [bool](Get-WRAProp -Object $config -Path 'Modules.Monitor.IncludeServices' -Default $true)
    $includeEvents = [bool](Get-WRAProp -Object $config -Path 'Modules.Monitor.IncludeEvents' -Default $true)
    $eventsHours = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.EventsLookbackHours' -Default 24)
    $eventsMax = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.EventsMaxItems' -Default 25)
    $eaEnabled = [bool](Get-WRAProp -Object $config -Path 'Modules.Monitor.EventAnalysis.Enabled' -Default $true)
    $eaDays = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.EventAnalysis.LookbackDays' -Default 7)
    $eaMax = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.EventAnalysis.MaxEvents' -Default 2000)
    $autoStopMax = [int](Get-WRAProp -Object $config -Path 'Modules.Monitor.AutoStoppedServicesMax' -Default 25)
    $cimTimeout = [int](Get-WRAProp -Object $config -Path 'Timeouts.CimSeconds' -Default 30)

    $cpuWarn = [double](Get-WRAProp -Object $config -Path 'Thresholds.Cpu.WarnPercent' -Default 80)
    $cpuCrit = [double](Get-WRAProp -Object $config -Path 'Thresholds.Cpu.CriticalPercent' -Default 95)
    $memWarn = [double](Get-WRAProp -Object $config -Path 'Thresholds.Memory.WarnPercent' -Default 80)
    $memCrit = [double](Get-WRAProp -Object $config -Path 'Thresholds.Memory.CriticalPercent' -Default 92)
    $diskWarn = [double](Get-WRAProp -Object $config -Path 'Thresholds.Disk.WarnPercent' -Default 85)
    $diskCrit = [double](Get-WRAProp -Object $config -Path 'Thresholds.Disk.CriticalPercent' -Default 95)
    $netWarnMbps = [double](Get-WRAProp -Object $config -Path 'Thresholds.Network.WarnMbps' -Default 800)

    if ($useEtw) {
        [void]$warnings.Add('UseEtw esta habilitado, porem o snapshot utiliza Performance Counters (CIM). ETW e aplicado no modo continuo (Triggers).')
    }

    # Amostragem compartilhada das metricas de taxa.
    $samples = Get-WRAMonitorSamples -Interval $interval -Duration $duration -TimeoutSec $cimTimeout -Warnings $warnings

    $cpuAvg = Get-WRAAverage -Samples $samples.Cpu
    $cpuMax = Get-WRAMax -Samples $samples.Cpu
    $diskAvg = Get-WRAAverage -Samples $samples.DiskTime
    $diskQueueAvg = Get-WRAAverage -Samples $samples.DiskQueue
    $diskBytesAvg = Get-WRAAverage -Samples $samples.DiskBytes
    $netBytesAvg = Get-WRAAverage -Samples $samples.NetBytes
    $netMbpsAvg = [Math]::Round(($netBytesAvg * 8) / 1000000, 2)

    $memory = Get-WRAMonitorMemory -TimeoutSec $cimTimeout -Warnings $warnings

    $gpu = $null
    if ($collectGpu) { $gpu = Get-WRAMonitorGpu -TimeoutSec $cimTimeout -Warnings $warnings }

    $processes = Get-WRAMonitorProcesses -Top $topN -TimeoutSec $cimTimeout -Warnings $warnings

    $services = $null
    if ($includeServices) { $services = Get-WRAMonitorServices -MaxAutoStopped $autoStopMax -TimeoutSec $cimTimeout -Warnings $warnings }

    $events = $null
    if ($includeEvents) { $events = Get-WRAMonitorEvents -LookbackHours $eventsHours -MaxItems $eventsMax -Warnings $warnings }

    $eventAnalysis = $null
    if ($includeEvents -and $eaEnabled) {
        $eventAnalysis = Get-WRAMonitorEventAnalysis -LookbackDays $eaDays -MaxEvents $eaMax -Warnings $warnings
    }

    $cpuStatus = Get-WRAStatus -Value $cpuAvg -Warn $cpuWarn -Critical $cpuCrit
    $memStatus = Get-WRAStatus -Value $memory.UsedPercent -Warn $memWarn -Critical $memCrit
    $diskStatus = Get-WRAStatus -Value $diskAvg -Warn $diskWarn -Critical $diskCrit
    $netStatus = 'OK'
    if ($netMbpsAvg -ge $netWarnMbps) { $netStatus = 'Warning' }

    $data = [PSCustomObject]@{
        Window = [PSCustomObject]@{
            IntervalSeconds = $interval
            DurationSeconds = $duration
            SampleCount     = $samples.SampleCount
        }
        Cpu = [PSCustomObject]@{
            AveragePercent = $cpuAvg
            MaxPercent     = $cpuMax
            WarnPercent    = $cpuWarn
            CriticalPercent = $cpuCrit
            Status         = $cpuStatus
        }
        Memory = [PSCustomObject]@{
            TotalMB        = $memory.TotalMB
            UsedMB         = $memory.UsedMB
            FreeMB         = $memory.FreeMB
            UsedPercent    = $memory.UsedPercent
            WarnPercent    = $memWarn
            CriticalPercent = $memCrit
            Status         = $memStatus
        }
        Gpu = $gpu
        Disk = [PSCustomObject]@{
            AverageBusyPercent = $diskAvg
            AverageQueueLength = $diskQueueAvg
            AverageBytesPerSec = $diskBytesAvg
            WarnPercent        = $diskWarn
            CriticalPercent    = $diskCrit
            Status             = $diskStatus
        }
        Network = [PSCustomObject]@{
            AverageBytesPerSec = $netBytesAvg
            AverageMbps        = $netMbpsAvg
            WarnMbps           = $netWarnMbps
            Status             = $netStatus
        }
        Processes = $processes
        Services  = $services
        Events    = $events
        EventAnalysis = $eventAnalysis
    }

    return New-WRAModulePayload -Data $data -Warnings $warnings.ToArray() -Errors $errors.ToArray()
}

# ----------------------------------------------------------- Auto-registro

$WRAMonitorManifest = $null
if (Get-Command -Name 'New-WRAModuleManifest' -ErrorAction SilentlyContinue) {
    $ops = @(
        (New-WRAOperation -Name 'Collect' -Handler 'Invoke-WRAMonitorCollect' `
            -Description 'Coleta um snapshot amostrado de CPU, memoria, GPU, disco, rede, processos, servicos e eventos.')
    )
    $WRAMonitorManifest = New-WRAModuleManifest -Module 'Monitor' -Operations $ops `
        -Version '4.1.0' -Description 'Monitoramento amostrado de recursos do sistema.'
}
if ($null -ne $WRAMonitorManifest -and (Get-Command -Name 'Register-WRAModule' -ErrorAction SilentlyContinue)) {
    [void](Register-WRAModule -Manifest $WRAMonitorManifest)
}

Export-ModuleMember -Function @('Invoke-WRAMonitorCollect')
