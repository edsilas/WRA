# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Scoring.psm1
Describe 'Scoring' {

    $cfg = [pscustomobject]@{
        Scoring = [pscustomobject]@{
            Health      = [pscustomobject]@{ Weights = [pscustomobject]@{ Performance = 0.4; Security = 0.4; Reliability = 0.2 } }
            Performance = [pscustomobject]@{ Weights = [pscustomobject]@{ Cpu = 0.34; Memory = 0.33; Disk = 0.33 } }
        }
    }

    $monitor = New-WRAResult -Success $true -Module 'Monitor' -Operation 'Collect' -Data ([pscustomobject]@{
            Cpu    = [pscustomobject]@{ AveragePercent = 0 }
            Memory = [pscustomobject]@{ UsedPercent = 0 }
            Disk   = [pscustomobject]@{ AverageBusyPercent = 0 }
            Events = [pscustomobject]@{ Critical = 0; Error = 0 }
        })
    $security = New-WRAResult -Success $true -Module 'Security' -Operation 'Audit' -Data ([pscustomobject]@{
            Scores = [pscustomobject]@{ SecurityScore = 80; RiskScore = 10 }
        })

    It 'Compoe Performance, Security e Health a partir dos envelopes' {
        $s = Get-WRAScores -Results @($monitor, $security) -Config $cfg
        Assert-Equal 100 $s.Performance      # utilizacoes zero => desempenho 100
        Assert-Equal 80 $s.Security
        Assert-Equal 10 $s.Risk
        Assert-NotNull $s.Health
        Assert-True ($s.Health -ge 0 -and $s.Health -le 100) 'Health fora de faixa'
    }

    It 'Renormaliza quando o Monitor esta ausente (Health = Security)' {
        $s = Get-WRAScores -Results @($security) -Config $cfg
        Assert-Null $s.Performance
        Assert-Equal 80 $s.Health
    }

    It 'Penaliza desempenho sob alta utilizacao' {
        $busy = New-WRAResult -Success $true -Module 'Monitor' -Operation 'Collect' -Data ([pscustomobject]@{
                Cpu    = [pscustomobject]@{ AveragePercent = 100 }
                Memory = [pscustomobject]@{ UsedPercent = 100 }
                Disk   = [pscustomobject]@{ AverageBusyPercent = 100 }
                Events = [pscustomobject]@{ Critical = 0; Error = 0 }
            })
        $s = Get-WRAScores -Results @($busy) -Config $cfg
        Assert-Equal 0 $s.Performance
    }

    It 'Confiabilidade fica indeterminada quando os dados sao insuficientes' {
        # Apenas Security presente: cobertura de sinais abaixo do minimo =>
        # confiabilidade NAO pode ser inferida (e nunca deve virar verde).
        $s = Get-WRAScores -Results @($security) -Config $cfg
        Assert-Null $s.Reliability
        Assert-True (-not $s.ReliabilityDeterminable) 'Confiabilidade deveria ser indeterminavel'
    }

    It 'Confiabilidade e limitada quando os eventos nao podem ser lidos' {
        # Metricas saudaveis mas SEM leitura de eventos: resultado nao pode ser
        # otimista (teto aplicado para evitar falso verde).
        $noEvents = New-WRAResult -Success $true -Module 'Monitor' -Operation 'Collect' -Data ([pscustomobject]@{
                Cpu    = [pscustomobject]@{ AveragePercent = 0 }
                Memory = [pscustomobject]@{ UsedPercent = 0 }
                Disk   = [pscustomobject]@{ AverageBusyPercent = 0 }
            })
        $s = Get-WRAScores -Results @($noEvents, $security) -Config $cfg
        Assert-NotNull $s.Reliability
        Assert-True ($s.Reliability -le 65) 'Sem eventos legiveis, a confiabilidade deve ser limitada (<= 65)'
    }
}
