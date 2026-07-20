# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Logger.psm1
Describe 'Logger' {

    It 'Initialize + Write geram arquivo de log com a mensagem' {
        $temp = Join-Path $env:TEMP ('wra_logtest_{0}' -f ([guid]::NewGuid().ToString('N')))
        [void](New-Item -ItemType Directory -Path $temp -Force)
        try {
            $cfg = [pscustomobject]@{ Logging = [pscustomobject]@{ Directory = 'Logs' } }
            [void](Initialize-WRALogger -Config $cfg -Root $temp -LogLevel 'Trace')
            $token = ('TOKEN_{0}' -f ([guid]::NewGuid().ToString('N')))
            Write-WRALog -Level 'Info' -Module 'TEST' -Operation 'Unit' -Message $token
            Stop-WRALogger

            $logs = @(Get-ChildItem -LiteralPath (Join-Path $temp 'Logs') -Filter '*.log' -File -ErrorAction SilentlyContinue)
            Assert-True ($logs.Count -ge 1) 'nenhum arquivo de log criado'
            $content = (Get-Content -LiteralPath $logs[0].FullName -Raw)
            Assert-Match $content ([regex]::Escape($token)) 'mensagem ausente no log'
        }
        finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'Write-WRALog antes de inicializar nao lanca' {
        Stop-WRALogger
        Assert-NotThrows { Write-WRALog -Level 'Info' -Module 'TEST' -Message 'sem logger' }
    }
}
