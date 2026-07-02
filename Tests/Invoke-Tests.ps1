#Requires -Version 4.0
# Desenvolvido por Edsilas
[CmdletBinding()]
param(
    [Parameter()][string] $Filter = '',
    [Parameter()][switch] $Plain,
    [Parameter()][string] $Path
)
# ============================================================================
#  Windows Resource Auditor - Runner de testes
#
#  Importa contratos e infraestrutura (na mesma ordem do Core), carrega o
#  framework WRATest e executa todos os Tests\Cases\*.Tests.ps1. Retorna o
#  numero de falhas como codigo de saida (0 = tudo verde).
#
#  Uso:  powershell -File Tests\Invoke-Tests.ps1 [-Filter <texto>] [-Plain]
# ============================================================================

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$TestsRoot = $PSScriptRoot
if (-not $TestsRoot) { $TestsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = Split-Path -Parent $TestsRoot

$script:WRATestRoot = $Root
$script:WRATestConfig = Join-Path (Join-Path $Root 'Config') 'Config.json'
$script:WRATestSchema = Join-Path (Join-Path $Root 'Config') 'Config.schema.json'
$script:WRATestIsWindows = ($env:OS -eq 'Windows_NT')

function Import-WRATestModule {
    param([string] $FilePath)
    try { Import-Module -Name $FilePath -Force -Global -DisableNameChecking -ErrorAction Stop }
    catch { Write-Host ("AVISO: falha ao importar {0}: {1}" -f (Split-Path -Leaf $FilePath), $_.Exception.Message) -ForegroundColor Yellow }
}

# 1) Contratos, depois Infraestrutura (mesma ordem de carga do Core).
foreach ($sub in @('Contracts', 'Infrastructure')) {
    $dir = Join-Path (Join-Path $Root 'Modules') $sub
    if (Test-Path -LiteralPath $dir) {
        foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.psm1' -File | Sort-Object Name)) {
            Import-WRATestModule -FilePath $f.FullName
        }
    }
}

# 2) Framework de testes.
Import-WRATestModule -FilePath (Join-Path $TestsRoot 'WRATest.psm1')

Reset-WRATestState
Set-WRATestOptions -Filter $Filter -Plain:$Plain

Write-Host ''
Write-Host ('Windows Resource Auditor - Testes  (raiz: {0})' -f $Root)
Write-Host ('Plataforma Windows: {0}' -f $script:WRATestIsWindows)

# 3) Descobre e executa os casos.
$casesDir = if ($Path) { $Path } else { Join-Path $TestsRoot 'Cases' }
if (-not (Test-Path -LiteralPath $casesDir)) {
    Write-Host ("Diretorio de casos nao encontrado: {0}" -f $casesDir) -ForegroundColor Red
    exit 1
}

$caseFiles = @(Get-ChildItem -LiteralPath $casesDir -Filter '*.Tests.ps1' -File | Sort-Object Name)
foreach ($cf in $caseFiles) {
    try { . $cf.FullName }
    catch {
        Write-Host ("ERRO ao carregar caso {0}: {1}" -f $cf.Name, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-WRATestSummary
exit (Get-WRATestExitCode)
