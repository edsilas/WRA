#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Reporting.psm1
#  Versao  : 1.1.0
#  Camada  : 3 - Apresentacao
#
#  Responsabilidade unica:
#    A partir dos envelopes de resultado, compor o dataset, calcular os scores
#    globais e gerar os artefatos de saida: dashboard.html (autocontido,
#    offline), data.json e CSVs, por execucao (RunId) com copia em Latest.
#
#  Contrato exposto (consumido pelo Core - Etapa 4):
#    Invoke-WRAReporting -Results <envelope[]> -Config -Root [-Formats <string[]>]
# ============================================================================

Set-StrictMode -Version 2.0

function Write-WRAReportLog {
    param([string] $Level = 'Info', [string] $Op = '', [string] $Message = '')
    if (Get-Command -Name 'Write-WRALog' -ErrorAction SilentlyContinue) {
        Write-WRALog -Level $Level -Module 'Reporting' -Operation $Op -Message $Message
    }
}

function Write-WRAText {
    param([string] $Path, [string] $Text)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Export-WRAReportCsv {
    param($Items, [string] $Path)
    if ($null -eq $Items -or @($Items).Count -eq 0) { return $false }
    try {
        $csv = @($Items) | ConvertTo-Csv -NoTypeInformation
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($Path, [string[]]$csv, $enc)
        return $true
    }
    catch { return $false }
}

function Resolve-WRAUnderRoot {
    param([string] $Root, [string] $Relative, [string] $Default)
    $rel = $Relative
    if (-not $rel) { $rel = $Default }
    if ([System.IO.Path]::IsPathRooted($rel)) { return $rel }
    return (Join-Path $Root $rel)
}

function Invoke-WRAReporting {
    [CmdletBinding()]
    param(
        [Parameter()] $Results,
        [Parameter()] $Config,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter()][string[]] $Formats
    )

    $resultsArr = @($Results)

    # ----- Formatos -----
    if (-not $Formats -or $Formats.Count -eq 0) {
        $Formats = @(Get-WRAProp -Object $Config -Path 'Reports.Formats' -Default @('HTML', 'JSON', 'CSV'))
    }
    $fmtSet = @{ }
    foreach ($f in $Formats) { $fmtSet[$f.ToUpperInvariant()] = $true }

    # ----- Diretorios -----
    $reportsDir = Resolve-WRAUnderRoot -Root $Root -Relative ([string](Get-WRAProp -Object $Config -Path 'Reports.Directory' -Default 'Reports')) -Default 'Reports'
    if (-not (Test-Path -LiteralPath $reportsDir)) { [void](New-Item -ItemType Directory -Path $reportsDir -Force) }

    $computerName = $env:COMPUTERNAME
    if ($resultsArr.Count -gt 0) {
        $cn = Get-WRAProp -Object $resultsArr[0] -Path 'ComputerName'
        if ($cn) { $computerName = [string]$cn }
    }

    $runId = ('{0}_{1}' -f (Get-Date).ToString('yyyyMMdd_HHmmss'), $computerName)
    $runDir = Join-Path $reportsDir $runId
    [void](New-Item -ItemType Directory -Path $runDir -Force)

    # ----- Mapa de modulos -----
    $modules = [ordered]@{ }
    $totalDuration = 0.0
    foreach ($r in $resultsArr) {
        $name = [string](Get-WRAProp -Object $r -Path 'Module' -Default 'Unknown')
        $dur = [double](Get-WRANum -Object $r -Name 'Duration')
        $totalDuration += $dur
        $modules[$name] = [PSCustomObject]@{
            success    = [bool](Get-WRAProp -Object $r -Path 'Success' -Default $false)
            operation  = [string](Get-WRAProp -Object $r -Path 'Operation' -Default '')
            durationMs = $dur
            warnings   = @(Get-WRAProp -Object $r -Path 'Warnings' -Default @())
            errors     = @(Get-WRAProp -Object $r -Path 'Errors' -Default @())
            data       = (Get-WRAProp -Object $r -Path 'Data')
        }
    }

    # ----- Dataset -----
    $dataset = [PSCustomObject]@{
        meta = [PSCustomObject]@{
            product        = 'Windows Resource Auditor'
            version        = [string](Get-WRAProp -Object $Config -Path 'Version' -Default '1.1.0')
            computerName   = $computerName
            generatedUtc   = (Get-Date).ToUniversalTime().ToString('o')
            generatedLocal = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            durationMs     = [Math]::Round($totalDuration, 0)
            severityColors = (Get-WRAProp -Object $Config -Path 'Severity.Colors')
        }
        modules = $modules
    }

    $jsonText = $dataset | ConvertTo-Json -Depth 14 -Compress
    # Blindagem de JSON: em alguns ambientes (ex.: dados WMI em Windows antigos) o
    # ConvertTo-Json pode emitir caracteres de controle crus dentro de strings,
    # produzindo JSON invalido. Nesse caso o dashboard cai no fallback e o relatorio
    # sai em branco. Com -Compress nao ha espacamento estrutural, portanto qualquer
    # caractere de controle remanescente esta dentro de uma string e e escapado aqui.
    $jsonText = [regex]::Replace($jsonText, '[\x00-\x1F]', {
            param($m)
            $code = [int][char]($m.Value)
            if ($code -eq 9) { return '\t' }
            if ($code -eq 10) { return '\n' }
            if ($code -eq 13) { return '\r' }
            if ($code -eq 8) { return '\b' }
            if ($code -eq 12) { return '\f' }
            return ('\u{0:x4}' -f $code)
        })
    $files = New-Object System.Collections.Generic.List[string]
    $htmlPath = $null
    $jsonPath = $null

    # ----- JSON -----
    if ($fmtSet.ContainsKey('JSON')) {
        $jsonPath = Join-Path $runDir 'data.json'
        Write-WRAText -Path $jsonPath -Text $jsonText
        [void]$files.Add($jsonPath)
    }

    # ----- CSV -----
    if ($fmtSet.ContainsKey('CSV')) {
        $proc = Get-WRAProp -Object $modules -Path 'ProcessAnalyzer.data'
        if ($proc) {
            $rows = @(Get-WRAProp -Object $proc -Path 'Processes' -Default @()) | Select-Object Name, ProcessId, ParentProcessId, User, WorkingSetMB, ThreadCount, HandleCount, SignatureStatus, Sha256
            $p = Join-Path $runDir 'processes.csv'
            if (Export-WRAReportCsv -Items $rows -Path $p) { [void]$files.Add($p) }
        }
        $netData = Get-WRAProp -Object $modules -Path 'Network.data'
        if ($netData) {
            $rows = @(Get-WRAProp -Object $netData -Path 'Connections' -Default @()) | Select-Object Protocol, LocalAddress, LocalPort, RemoteAddress, RemotePort, State, ProcessId, ProcessName, Interface
            $p = Join-Path $runDir 'connections.csv'
            if (Export-WRAReportCsv -Items $rows -Path $p) { [void]$files.Add($p) }
        }
        $invData = Get-WRAProp -Object $modules -Path 'Inventory.data'
        if ($invData) {
            $rows = @(Get-WRAProp -Object $invData -Path 'Programs' -Default @()) | Select-Object Name, Version, Publisher, InstallDate
            $p = Join-Path $runDir 'programs.csv'
            if (Export-WRAReportCsv -Items $rows -Path $p) { [void]$files.Add($p) }
        }
        $secData = Get-WRAProp -Object $modules -Path 'Security.data'
        if ($secData) {
            $rows = @(Get-WRAProp -Object $secData -Path 'Recommendations' -Default @()) | Select-Object Area, Severity, Finding, Recommendation
            $p = Join-Path $runDir 'recommendations.csv'
            if (Export-WRAReportCsv -Items $rows -Path $p) { [void]$files.Add($p) }
        }
    }

    # ----- HTML (autocontido) -----
    if ($fmtSet.ContainsKey('HTML')) {
        $templatePath = Join-Path (Join-Path $Root 'Templates') 'Dashboard.template.html'
        $cssPath = Join-Path (Join-Path (Join-Path $Root 'Assets') 'css') 'dashboard.css'
        $jsPath = Join-Path (Join-Path (Join-Path $Root 'Assets') 'js') 'dashboard.js'

        if (Test-Path -LiteralPath $templatePath) {
            try {
                $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
                $css = ''
                if (Test-Path -LiteralPath $cssPath) { $css = Get-Content -LiteralPath $cssPath -Raw -Encoding UTF8 }
                $js = ''
                if (Test-Path -LiteralPath $jsPath) { $js = Get-Content -LiteralPath $jsPath -Raw -Encoding UTF8 }

                $title = [string](Get-WRAProp -Object $Config -Path 'Reports.Title' -Default 'Windows Resource Auditor Report')
                $title = ('{0} - {1}' -f $title, $computerName)

                # Neutraliza qualquer sequencia </script> dentro do JSON embutido.
                $safeJson = $jsonText.Replace('<', '\u003c')

                $html = $template
                $html = $html.Replace('<!--WRA:TITLE-->', $title)
                $html = $html.Replace('<!--WRA:STYLE-->', $css)
                $html = $html.Replace('<!--WRA:SCRIPT-->', $js)
                $html = $html.Replace('<!--WRA:DATA-->', $safeJson)

                $htmlPath = Join-Path $runDir 'dashboard.html'
                Write-WRAText -Path $htmlPath -Text $html
                [void]$files.Add($htmlPath)
            }
            catch {
                Write-WRAReportLog -Level 'Error' -Op 'Html' -Message ('Falha ao gerar o dashboard: {0}' -f $_.Exception.Message)
            }
        }
        else {
            Write-WRAReportLog -Level 'Warn' -Op 'Html' -Message 'Template do dashboard nao encontrado; HTML ignorado.'
        }
    }

    # ----- Latest -----
    if ([bool](Get-WRAProp -Object $Config -Path 'Reports.KeepLatest' -Default $true)) {
        try {
            $latest = Join-Path $reportsDir 'Latest'
            if (Test-Path -LiteralPath $latest) { Remove-Item -LiteralPath $latest -Recurse -Force -ErrorAction SilentlyContinue }
            [void](New-Item -ItemType Directory -Path $latest -Force)
            Copy-Item -Path (Join-Path $runDir '*') -Destination $latest -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }

    # ----- Retencao -----
    $retention = [int](Get-WRAProp -Object $Config -Path 'Reports.RetentionRuns' -Default 30)
    if ($retention -gt 0) {
        try {
            $runs = @(Get-ChildItem -LiteralPath $reportsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Latest' } | Sort-Object Name -Descending)
            if ($runs.Count -gt $retention) {
                for ($i = $retention; $i -lt $runs.Count; $i++) {
                    Remove-Item -LiteralPath $runs[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch { }
    }

    Write-WRAReportLog -Level 'Info' -Op 'Generate' -Message ('Relatorios gerados em {0} ({1} arquivos).' -f $runDir, $files.Count)

    return [PSCustomObject]@{
        RunId  = $runId
        RunDir = $runDir
        Html   = $htmlPath
        Json   = $jsonPath
        Files  = $files.ToArray()
    }
}

Export-ModuleMember -Function @('Invoke-WRAReporting')
