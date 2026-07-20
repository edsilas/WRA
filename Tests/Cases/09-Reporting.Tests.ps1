# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Reporting.psm1  (geracao fim-a-fim)
Describe 'Reporting' {

    It 'Gera data.json + dashboard.html e neutraliza </script> nos dados' {
        $tempReports = Join-Path $env:TEMP ('wra_rep_{0}' -f ([guid]::NewGuid().ToString('N')))
        try {
            $cfg = [pscustomobject]@{
                Version  = '1.1.0'
                Reports  = [pscustomobject]@{ Directory = $tempReports; Formats = @('HTML', 'JSON', 'CSV'); KeepLatest = $false; RetentionRuns = 0; Title = 'Teste' }
                Severity = [pscustomobject]@{ Colors = [pscustomobject]@{ Info = '#3b82f6'; Low = '#22c55e'; Medium = '#eab308'; High = '#f97316'; Critical = '#ef4444' } }
            }

            $monitor = New-WRAResult -Success $true -Module 'Monitor' -Operation 'Collect' -DurationMs 10 -Data ([pscustomobject]@{
                    Cpu    = [pscustomobject]@{ AveragePercent = 5; Status = 'OK' }
                    Memory = [pscustomobject]@{ UsedPercent = 40; Status = 'OK' }
                    Disk   = [pscustomobject]@{ AverageBusyPercent = 2 }
                    Events = [pscustomobject]@{ Critical = 0; Error = 0; Items = @() }
                })
            # Nome de processo malicioso para exercitar o escaping de '<'.
            $proc = New-WRAResult -Success $true -Module 'ProcessAnalyzer' -Operation 'Analyze' -DurationMs 20 -Data ([pscustomobject]@{
                    Processes = @([pscustomobject]@{ Name = 'evil</script>'; ProcessId = 1; WorkingSetMB = 1; SignatureStatus = 'NotSigned' })
                })

            $res = Invoke-WRAReporting -Results @($monitor, $proc) -Config $cfg -Root $script:WRATestRoot -Formats @('HTML', 'JSON', 'CSV')
            Assert-NotNull $res
            Assert-True (Test-Path -LiteralPath $res.RunDir) 'RunDir inexistente'

            $jsonPath = Join-Path $res.RunDir 'data.json'
            Assert-True (Test-Path -LiteralPath $jsonPath) 'data.json ausente'
            Assert-NotThrows { [void]((Get-Content -LiteralPath $jsonPath -Raw) | ConvertFrom-Json) } 'data.json invalido'

            $htmlPath = Join-Path $res.RunDir 'dashboard.html'
            Assert-True (Test-Path -LiteralPath $htmlPath) 'dashboard.html ausente'
            $html = Get-Content -LiteralPath $htmlPath -Raw
            Assert-Match $html 'id="wra-data"' 'bloco de dados ausente'
            Assert-Match $html '\\u003c' 'escaping de < nao aplicado'
            Assert-False ($html -match 'evil</script>') 'sequencia </script> crua vazou para o HTML'
        }
        finally {
            if (Test-Path -LiteralPath $tempReports) { Remove-Item -LiteralPath $tempReports -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
