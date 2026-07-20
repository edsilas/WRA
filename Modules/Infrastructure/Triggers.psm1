#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Triggers.psm1
#  Versao  : 1.1.0
#  Camada  : 1 - Infraestrutura
#
#  Responsabilidade unica:
#    Vigiar metricas continuamente (CPU, RAM, Disco, eventos criticos, servicos
#    parados) e disparar uma auditoria quando uma regra configurada e violada
#    por tempo suficiente, respeitando um periodo de cooldown.
#
#  Exposto: Start-WRATriggerWatch -Config -Root -Context [-OnTrigger] [-MaxCycles]
#           Get-WRATriggerMetric  (auxiliar/testavel)
# ============================================================================

Set-StrictMode -Version 2.0

function Invoke-WRATrigCim {
    param([string] $ClassName, [string] $Filter, [string[]] $Property, [int] $TimeoutSec = 15)
    if (Get-Command -Name 'Invoke-WRACimQuery' -ErrorAction SilentlyContinue) {
        return @(Invoke-WRACimQuery -ClassName $ClassName -Filter $Filter -Property $Property -TimeoutSec $TimeoutSec -Quiet)
    }
    try {
        $params = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
        if ($Filter) { $params['Filter'] = $Filter }
        if ($Property) { $params['Property'] = $Property }
        return @(Get-CimInstance @params)
    }
    catch { return @() }
}

function Get-WRATriggerMetric {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Metric, [Parameter()][datetime] $Since, [Parameter()][int] $TimeoutSec = 15)

    switch ($Metric.ToLowerInvariant()) {
        'cpu' {
            $c = @(Invoke-WRATrigCim -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -Filter "Name='_Total'" -Property @('PercentProcessorTime') -TimeoutSec $TimeoutSec)
            if ($c.Count -gt 0) { return [double](Get-WRANum -Object $c[0] -Name 'PercentProcessorTime') }
            return $null
        }
        'memory' {
            $os = @(Invoke-WRATrigCim -ClassName 'Win32_OperatingSystem' -Property @('TotalVisibleMemorySize', 'FreePhysicalMemory') -TimeoutSec $TimeoutSec)
            if ($os.Count -gt 0) {
                $total = [double](Get-WRANum -Object $os[0] -Name 'TotalVisibleMemorySize')
                $free = [double](Get-WRANum -Object $os[0] -Name 'FreePhysicalMemory')
                if ($total -gt 0) { return [Math]::Round((($total - $free) / $total) * 100, 1) }
            }
            return $null
        }
        'disk' {
            $d = @(Invoke-WRATrigCim -ClassName 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' -Filter "Name='_Total'" -Property @('PercentDiskTime') -TimeoutSec $TimeoutSec)
            if ($d.Count -gt 0) { return [double](Get-WRANum -Object $d[0] -Name 'PercentDiskTime') }
            return $null
        }
        'criticalevents' {
            try {
                $start = $Since
                if ($null -eq $start) { $start = (Get-Date).AddMinutes(-1) }
                $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1; StartTime = $start } -MaxEvents 100 -ErrorAction Stop)
                return [double]$ev.Count
            }
            catch { return 0 }
        }
        'servicestopped' {
            $svc = @(Invoke-WRATrigCim -ClassName 'Win32_Service' -Property @('State', 'StartMode') -TimeoutSec $TimeoutSec)
            $count = 0
            foreach ($s in $svc) {
                if (([string](Get-WRAProp -Object $s -Path 'StartMode' -Default '') -eq 'Auto') -and ([string](Get-WRAProp -Object $s -Path 'State' -Default '') -ne 'Running')) { $count++ }
            }
            return [double]$count
        }
        default { return $null }
    }
}

function Test-WRATriggerCompare {
    param([double] $Current, [string] $Operator, [double] $Value)
    switch ($Operator) {
        '>=' { return ($Current -ge $Value) }
        '>'  { return ($Current -gt $Value) }
        '<=' { return ($Current -le $Value) }
        '<'  { return ($Current -lt $Value) }
        '==' { return ($Current -eq $Value) }
        '='  { return ($Current -eq $Value) }
        default { return $false }
    }
}

function Start-WRATriggerWatch {
    [CmdletBinding()]
    param(
        [Parameter()] $Config,
        [Parameter()][string] $Root,
        [Parameter()] $Context,
        [Parameter()] [scriptblock] $OnTrigger,
        [Parameter()][int] $MaxCycles = 0
    )

    $poll = [int](Get-WRAProp -Object $Config -Path 'Triggers.PollSeconds' -Default 15)
    if ($poll -lt 1) { $poll = 15 }
    $cooldown = [int](Get-WRAProp -Object $Config -Path 'Triggers.CooldownSeconds' -Default 300)
    $cimTimeout = [int](Get-WRAProp -Object $Config -Path 'Timeouts.CimSeconds' -Default 15)
    $rules = @(Get-WRAProp -Object $Config -Path 'Triggers.Rules' -Default @())

    $state = @{ }
    for ($i = 0; $i -lt $rules.Count; $i++) {
        $state[$i] = [PSCustomObject]@{ BreachStart = $null; CooldownUntil = $null }
    }

    $log = {
        param($lvl, $msg)
        if (Get-Command -Name 'Write-WRALog' -ErrorAction SilentlyContinue) { Write-WRALog -Level $lvl -Module 'Triggers' -Operation 'Watch' -Message $msg }
    }

    & $log 'Info' ('Vigilancia de triggers iniciada: {0} regras, poll {1}s, cooldown {2}s.' -f $rules.Count, $poll, $cooldown)

    $lastPoll = (Get-Date).AddSeconds(-1 * $poll)
    $cycle = 0
    $running = $true

    while ($running) {
        $now = Get-Date
        for ($i = 0; $i -lt $rules.Count; $i++) {
            $rule = $rules[$i]
            $st = $state[$i]
            $name = [string](Get-WRAProp -Object $rule -Path 'Name' -Default ('Rule' + $i))
            $metric = [string](Get-WRAProp -Object $rule -Path 'Metric' -Default '')
            $op = [string](Get-WRAProp -Object $rule -Path 'Operator' -Default '>=')
            $value = [double](Get-WRANum -Object $rule -Name 'Value')
            $forSec = [int](Get-WRANum -Object $rule -Name 'ForSeconds')
            $run = @(Get-WRAProp -Object $rule -Path 'Run' -Default @('All'))

            if ($null -ne $st.CooldownUntil -and $now -lt $st.CooldownUntil) { continue }

            $current = $null
            try { $current = Get-WRATriggerMetric -Metric $metric -Since $lastPoll -TimeoutSec $cimTimeout } catch { }
            if ($null -eq $current) { continue }

            if (Test-WRATriggerCompare -Current ([double]$current) -Operator $op -Value $value) {
                if ($null -eq $st.BreachStart) { $st.BreachStart = $now }
                $elapsed = ($now - $st.BreachStart).TotalSeconds
                if ($elapsed -ge $forSec) {
                    & $log 'Warn' ("Trigger '{0}' disparado: {1}={2} {3} {4} por {5}s." -f $name, $metric, $current, $op, $value, [int]$elapsed)
                    if ($null -ne $OnTrigger) {
                        try { & $OnTrigger $run } catch { & $log 'Error' ("Falha ao executar acao do trigger '{0}': {1}" -f $name, $_.Exception.Message) }
                    }
                    $st.BreachStart = $null
                    if ($cooldown -gt 0) { $st.CooldownUntil = $now.AddSeconds($cooldown) }
                }
            }
            else {
                $st.BreachStart = $null
            }
        }

        $lastPoll = $now
        $cycle++
        if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) { $running = $false; break }
        Start-Sleep -Seconds $poll
    }

    & $log 'Info' 'Vigilancia de triggers encerrada.'
    return [PSCustomObject]@{ Cycles = $cycle }
}

Export-ModuleMember -Function @('Start-WRATriggerWatch', 'Get-WRATriggerMetric')
