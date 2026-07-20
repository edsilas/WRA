#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Scheduler.psm1
#  Versao  : 1.1.0
#  Camada  : 1 - Infraestrutura
#
#  Responsabilidade unica:
#    Criar, remover e listar tarefas agendadas que executam a auditoria
#    (inicializacao, logon, intervalos, diaria, semanal), evitando multiplas
#    instancias (MultipleInstancesPolicy=IgnoreNew).
#
#  Implementacao via schtasks.exe + XML de tarefa: universal (Server 2012+,
#  PS 4.0), sem dependencia de modulo, e sem o inferno de aspas da CLI.
#
#  Exposto: Install-WRASchedule / Remove-WRASchedule / Get-WRASchedule
# ============================================================================

Set-StrictMode -Version 2.0

function ConvertTo-WRAXmlText {
    param([Parameter()][string] $Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function Get-WRADayOfWeekXml {
    param([Parameter()] $Days)
    $valid = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
    $out = ''
    $set = @($Days)
    if ($set.Count -eq 0) { $set = @('Monday') }
    foreach ($d in $set) {
        foreach ($v in $valid) {
            if ([string]$d -ieq $v) { $out += ('<{0} />' -f $v) }
        }
    }
    if (-not $out) { $out = '<Monday />' }
    return $out
}

function New-WRATriggerXml {
    param([string] $Trigger, [string] $At, [int] $IntervalMinutes, $DaysOfWeek)

    $time = $At
    if (-not $time -or $time -notmatch '^\d{1,2}:\d{2}$') { $time = '03:00' }
    $startBoundary = ('{0}T{1}:00' -f (Get-Date).ToString('yyyy-MM-dd'), $time)

    switch ($Trigger.ToLowerInvariant()) {
        'startup' { return '<BootTrigger><Enabled>true</Enabled></BootTrigger>' }
        'logon' { return '<LogonTrigger><Enabled>true</Enabled></LogonTrigger>' }
        'weekly' {
            return ('<CalendarTrigger><StartBoundary>{0}</StartBoundary><Enabled>true</Enabled><ScheduleByWeek><DaysOfWeek>{1}</DaysOfWeek><WeeksInterval>1</WeeksInterval></ScheduleByWeek></CalendarTrigger>' -f $startBoundary, (Get-WRADayOfWeekXml -Days $DaysOfWeek))
        }
        'hourly' {
            return ('<TimeTrigger><StartBoundary>{0}</StartBoundary><Enabled>true</Enabled><Repetition><Interval>PT1H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></TimeTrigger>' -f $startBoundary)
        }
        'interval' {
            $n = $IntervalMinutes
            if ($n -lt 1) { $n = 60 }
            return ('<TimeTrigger><StartBoundary>{0}</StartBoundary><Enabled>true</Enabled><Repetition><Interval>PT{1}M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></TimeTrigger>' -f $startBoundary, $n)
        }
        default {
            return ('<CalendarTrigger><StartBoundary>{0}</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>' -f $startBoundary)
        }
    }
}

function New-WRATaskXml {
    param([string] $LauncherPath, [string] $RunSelection, [string] $Trigger, [string] $At, [int] $IntervalMinutes, $DaysOfWeek, [bool] $RunHighest)

    $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $taskArgs = ('/c "{0}" -Run {1} -Quiet' -f $LauncherPath, $RunSelection)
    $runLevel = if ($RunHighest) { 'HighestAvailable' } else { 'LeastPrivilege' }
    $triggerXml = New-WRATriggerXml -Trigger $Trigger -At $At -IntervalMinutes $IntervalMinutes -DaysOfWeek $DaysOfWeek

    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Windows Resource Auditor - auditoria agendada</Description>
    <Author>Windows Resource Auditor</Author>
  </RegistrationInfo>
  <Triggers>$triggerXml</Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>$runLevel</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$(ConvertTo-WRAXmlText -Text $cmd)</Command>
      <Arguments>$(ConvertTo-WRAXmlText -Text $taskArgs)</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    return $xml
}

function Invoke-WRASchTasks {
    param([Parameter()][string[]] $Arguments)
    $output = & schtasks.exe @Arguments 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine) }
}

function Install-WRASchedule {
    [CmdletBinding()]
    param(
        [Parameter()] $Config,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter()][string] $LauncherPath
    )
    if (-not $LauncherPath) { $LauncherPath = Join-Path $Root 'Launcher.bat' }
    $prefix = [string](Get-WRAProp -Object $Config -Path 'Scheduler.TaskNamePrefix' -Default 'WRA_')
    $highest = [bool](Get-WRAProp -Object $Config -Path 'Scheduler.RunAsHighest' -Default $true)
    $tasks = @(Get-WRAProp -Object $Config -Path 'Scheduler.Tasks' -Default @())

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($t in $tasks) {
        $tname = [string](Get-WRAProp -Object $t -Path 'Name' -Default 'Audit')
        $full = $prefix + $tname
        $trigger = [string](Get-WRAProp -Object $t -Path 'Trigger' -Default 'Daily')
        $at = [string](Get-WRAProp -Object $t -Path 'At' -Default '03:00')
        $interval = [int](Get-WRANum -Object $t -Name 'IntervalMinutes' -Default 60)
        $dow = Get-WRAProp -Object $t -Path 'DaysOfWeek' -Default @('Monday')
        $run = @(Get-WRAProp -Object $t -Path 'Run' -Default @('All'))
        $runStr = ($run -join ',')

        $xml = New-WRATaskXml -LauncherPath $LauncherPath -RunSelection $runStr -Trigger $trigger -At $at -IntervalMinutes $interval -DaysOfWeek $dow -RunHighest $highest
        $xmlFile = Join-Path $env:TEMP ('wra_task_{0}.xml' -f ([guid]::NewGuid().ToString('N')))
        try {
            [System.IO.File]::WriteAllText($xmlFile, $xml, [System.Text.Encoding]::Unicode)
            $r = Invoke-WRASchTasks -Arguments @('/Create', '/TN', $full, '/XML', $xmlFile, '/F')
            [void]$results.Add([PSCustomObject]@{ Task = $full; Success = ($r.ExitCode -eq 0); ExitCode = $r.ExitCode; Output = $r.Output })
        }
        catch {
            [void]$results.Add([PSCustomObject]@{ Task = $full; Success = $false; ExitCode = -1; Output = $_.Exception.Message })
        }
        finally {
            if (Test-Path -LiteralPath $xmlFile) { Remove-Item -LiteralPath $xmlFile -Force -ErrorAction SilentlyContinue }
        }
    }
    return $results.ToArray()
}

function Get-WRAScheduleNames {
    param([string] $Prefix)
    $names = New-Object System.Collections.Generic.List[string]
    try {
        $r = Invoke-WRASchTasks -Arguments @('/Query', '/FO', 'CSV', '/NH')
        foreach ($line in ($r.Output -split "`r?`n")) {
            if (-not $line) { continue }
            $first = $line.Split(',')[0].Trim('"')
            $leaf = $first.TrimStart('\')
            if ($leaf -like ($Prefix + '*')) { [void]$names.Add($first) }
        }
    }
    catch { }
    return $names.ToArray()
}

function Remove-WRASchedule {
    [CmdletBinding()]
    param([Parameter()] $Config)
    $prefix = [string](Get-WRAProp -Object $Config -Path 'Scheduler.TaskNamePrefix' -Default 'WRA_')
    $names = Get-WRAScheduleNames -Prefix $prefix
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($n in $names) {
        $r = Invoke-WRASchTasks -Arguments @('/Delete', '/TN', $n, '/F')
        [void]$results.Add([PSCustomObject]@{ Task = $n; Success = ($r.ExitCode -eq 0); ExitCode = $r.ExitCode })
    }
    return $results.ToArray()
}

function Get-WRASchedule {
    [CmdletBinding()]
    param([Parameter()] $Config)
    $prefix = [string](Get-WRAProp -Object $Config -Path 'Scheduler.TaskNamePrefix' -Default 'WRA_')
    return @(Get-WRAScheduleNames -Prefix $prefix | ForEach-Object { [PSCustomObject]@{ Task = $_ } })
}

Export-ModuleMember -Function @('Install-WRASchedule', 'Remove-WRASchedule', 'Get-WRASchedule')
