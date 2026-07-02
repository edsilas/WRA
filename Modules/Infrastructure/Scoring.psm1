#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Scoring.psm1
#  Versao  : 4.1.0
#  Camada  : 1 - Infraestrutura
#
#  Responsabilidade unica:
#    Compor os indicadores globais (Health, Security, Performance, Risk) a
#    partir dos envelopes de todos os modulos. Aqui e onde os dados de Monitor
#    e Security se combinam no Health Score global (conforme a Etapa 11).
#
#  Exposto: Get-WRAScores -Results -Config
# ============================================================================

Set-StrictMode -Version 2.0

function Get-WRAScores {
    [CmdletBinding()]
    param(
        [Parameter()] $Results,
        [Parameter()] $Config
    )

    $byModule = @{ }
    foreach ($r in @($Results)) {
        $m = [string](Get-WRAProp -Object $r -Path 'Module' -Default '')
        if ($m) { $byModule[$m] = $r }
    }

    $getData = {
        param($name)
        if ($byModule.ContainsKey($name)) { return (Get-WRAProp -Object $byModule[$name] -Path 'Data') }
        return $null
    }

    # ----- Performance (do modulo Monitor) -----
    $perfScore = $null
    $monData = & $getData 'Monitor'
    if ($null -ne $monData) {
        $cpu = [double](Get-WRANum -Object $monData -Name 'Cpu.AveragePercent')
        $mem = [double](Get-WRANum -Object $monData -Name 'Memory.UsedPercent')
        $disk = [double](Get-WRANum -Object $monData -Name 'Disk.AverageBusyPercent')
        $cpu = [Math]::Min(100, [Math]::Max(0, $cpu))
        $mem = [Math]::Min(100, [Math]::Max(0, $mem))
        $disk = [Math]::Min(100, [Math]::Max(0, $disk))

        $wCpu = [double](Get-WRAProp -Object $Config -Path 'Scoring.Performance.Weights.Cpu' -Default 0.34)
        $wMem = [double](Get-WRAProp -Object $Config -Path 'Scoring.Performance.Weights.Memory' -Default 0.33)
        $wDisk = [double](Get-WRAProp -Object $Config -Path 'Scoring.Performance.Weights.Disk' -Default 0.33)
        $wSum = $wCpu + $wMem + $wDisk
        if ($wSum -le 0) { $wSum = 1 }

        $perfScore = [Math]::Round((($wCpu * (100 - $cpu)) + ($wMem * (100 - $mem)) + ($wDisk * (100 - $disk))) / $wSum, 1)
    }

    # ----- Reliability / Confiabilidade (sensivel a determinabilidade) -----
    # Principio: dados ausentes NAO devem ser tratados como "saudavel" (verde).
    # A base de saude vem apenas de sinais efetivamente medidos (eventos + pressao
    # de recursos); a ausencia de dados reduz a confiabilidade via fator de
    # cobertura e, quando insuficiente, o indicador e marcado como indeterminado.
    $reliability = $null
    $relDeterminable = $false
    $relCoverage = $null

    $eventsKnown = $false
    $healthKnownW = 0.0; $healthAccum = 0.0
    $detKnown = 0; $detTotal = 0

    if ($null -ne $monData) {
        $evObj = Get-WRAProp -Object $monData -Path 'Events'
        if ($null -ne $evObj) {
            $crit = [double](Get-WRANum -Object $monData -Name 'Events.Critical')
            $err = [double](Get-WRANum -Object $monData -Name 'Events.Error')
            $eventScore = [Math]::Max(0, 100 - [Math]::Min(100, ($crit * 12) + ($err * 3)))
            $eventsKnown = $true
            $healthKnownW += 2.0; $healthAccum += 2.0 * $eventScore
        }
        $detTotal++; if ($eventsKnown) { $detKnown++ }

        foreach ($p in @('Cpu.AveragePercent', 'Memory.UsedPercent', 'Disk.AverageBusyPercent')) {
            $raw = Get-WRAProp -Object $monData -Path $p
            $detTotal++
            if ($null -ne $raw) {
                $v = [Math]::Min(100, [Math]::Max(0, [double](Get-WRANum -Object $monData -Name $p)))
                $healthKnownW += 1.0; $healthAccum += 1.0 * (100 - $v); $detKnown++
            }
        }
    }
    else {
        # Monitor ausente: sinais de saude indisponiveis.
        $detTotal += 4
    }

    # Cobertura de dados: cada modulo esperado que reportou dados conta como
    # determinado; modulos que nao reportaram reduzem a cobertura.
    foreach ($modName in @('Inventory', 'Network', 'Security')) {
        $detTotal++
        if ($byModule.ContainsKey($modName)) {
            $ok = [bool](Get-WRAProp -Object $byModule[$modName] -Path 'Success' -Default $false)
            $d = Get-WRAProp -Object $byModule[$modName] -Path 'Data'
            if ($ok -and $null -ne $d) { $detKnown++ }
        }
    }

    if ($detTotal -gt 0) { $relCoverage = [Math]::Round([double]$detKnown / $detTotal, 3) }
    $minCoverage = [double](Get-WRAProp -Object $Config -Path 'Scoring.Reliability.MinCoverage' -Default 0.4)

    if ($healthKnownW -le 0 -or $null -eq $relCoverage -or $relCoverage -lt $minCoverage) {
        $reliability = $null
        $relDeterminable = $false
    }
    else {
        $base = $healthAccum / $healthKnownW
        $reliability = [Math]::Round($base * (0.7 + (0.3 * $relCoverage)), 1)
        if (-not $eventsKnown) { $reliability = [Math]::Min($reliability, 65.0) }
        $relDeterminable = $true
    }

    # ----- Security / Risk (do modulo Security) -----
    $securityScore = $null
    $riskScore = $null
    $secData = & $getData 'Security'
    if ($null -ne $secData) {
        $securityScore = Get-WRAProp -Object $secData -Path 'Scores.SecurityScore'
        $riskScore = Get-WRAProp -Object $secData -Path 'Scores.RiskScore'
    }

    # ----- Health (mistura ponderada das partes disponiveis) -----
    $hwPerf = [double](Get-WRAProp -Object $Config -Path 'Scoring.Health.Weights.Performance' -Default 0.4)
    $hwSec = [double](Get-WRAProp -Object $Config -Path 'Scoring.Health.Weights.Security' -Default 0.4)
    $hwRel = [double](Get-WRAProp -Object $Config -Path 'Scoring.Health.Weights.Reliability' -Default 0.2)

    $num = 0.0; $den = 0.0
    if ($null -ne $perfScore) { $num += $hwPerf * $perfScore; $den += $hwPerf }
    if ($null -ne $securityScore) { $num += $hwSec * [double]$securityScore; $den += $hwSec }
    if ($null -ne $reliability) { $num += $hwRel * $reliability; $den += $hwRel }
    $health = $null
    if ($den -gt 0) { $health = [Math]::Round($num / $den, 1) }

    $reliabilityRounded = $null
    if ($null -ne $reliability) { $reliabilityRounded = [Math]::Round($reliability, 1) }

    return [PSCustomObject]@{
        Health                  = $health
        Security                = $securityScore
        Performance             = $perfScore
        Risk                    = $riskScore
        Reliability             = $reliabilityRounded
        ReliabilityDeterminable = $relDeterminable
        ReliabilityCoverage     = $relCoverage
        Breakdown               = [PSCustomObject]@{
            HasMonitor  = ($null -ne $monData)
            HasSecurity = ($null -ne $secData)
        }
    }
}

Export-ModuleMember -Function @('Get-WRAScores')
