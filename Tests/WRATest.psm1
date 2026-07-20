#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : WRATest.psm1  (framework de testes nativo)
#  Versao  : 1.1.0
#
#  Framework minimo de testes, sem Pester e sem PowerShell Gallery. Oferece
#  Describe/It, asserts e um sumario com codigo de saida. As asserts lancam
#  excecao; It captura, registra e segue. Nenhuma dependencia externa.
# ============================================================================

Set-StrictMode -Version 2.0

$script:WRAT = [ordered]@{
    Total = 0; Passed = 0; Failed = 0; Skipped = 0
    Group = ''
    Failures = (New-Object System.Collections.Generic.List[string])
    Filter = ''
    Plain = $false
}

function Reset-WRATestState {
    $script:WRAT.Total = 0; $script:WRAT.Passed = 0; $script:WRAT.Failed = 0; $script:WRAT.Skipped = 0
    $script:WRAT.Group = ''
    $script:WRAT.Failures = New-Object System.Collections.Generic.List[string]
}

function Set-WRATestOptions {
    param([string] $Filter = '', [switch] $Plain)
    $script:WRAT.Filter = $Filter
    $script:WRAT.Plain = [bool]$Plain
}

function Write-WRATLine {
    param([string] $Text, [string] $Color = 'Gray')
    if ($script:WRAT.Plain) { Write-Host $Text }
    else { Write-Host $Text -ForegroundColor $Color }
}

function Describe {
    param([Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][scriptblock] $Body)
    $script:WRAT.Group = $Name
    Write-WRATLine ''
    Write-WRATLine ("== {0}" -f $Name) 'Cyan'
    & $Body
}

function It {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Body,
        [switch] $Skip
    )
    $full = ('{0} > {1}' -f $script:WRAT.Group, $Name)
    if ($script:WRAT.Filter -and ($full -notlike ('*' + $script:WRAT.Filter + '*'))) { return }

    $script:WRAT.Total++
    if ($Skip) {
        $script:WRAT.Skipped++
        Write-WRATLine ("  [SKIP] {0}" -f $Name) 'DarkYellow'
        return
    }
    try {
        & $Body
        $script:WRAT.Passed++
        Write-WRATLine ("  [PASS] {0}" -f $Name) 'Green'
    }
    catch {
        $script:WRAT.Failed++
        $msg = ('{0} :: {1}' -f $full, $_.Exception.Message)
        [void]$script:WRAT.Failures.Add($msg)
        Write-WRATLine ("  [FAIL] {0}" -f $Name) 'Red'
        Write-WRATLine ("         {0}" -f $_.Exception.Message) 'Red'
    }
}

# --------------------------------------------------------------------- Asserts
function Assert-True {
    param([Parameter(Mandatory = $true)] $Condition, [string] $Message = 'condicao falsa')
    if (-not $Condition) { throw ("Assert-True: {0}" -f $Message) }
}

function Assert-False {
    param([Parameter(Mandatory = $true)] $Condition, [string] $Message = 'condicao verdadeira')
    if ($Condition) { throw ("Assert-False: {0}" -f $Message) }
}

function Assert-Equal {
    param([Parameter()] $Expected, [Parameter()] $Actual, [string] $Message = '')
    $eq = $false
    if ($null -eq $Expected -and $null -eq $Actual) { $eq = $true }
    elseif ($null -eq $Expected -or $null -eq $Actual) { $eq = $false }
    elseif (($Expected -is [System.Array]) -and ($Actual -is [System.Array])) {
        if ($Expected.Count -eq $Actual.Count) {
            $eq = $true
            for ($i = 0; $i -lt $Expected.Count; $i++) { if ($Expected[$i] -ne $Actual[$i]) { $eq = $false; break } }
        }
    }
    else { $eq = ($Expected -eq $Actual) }
    if (-not $eq) { throw ("Assert-Equal: esperado <{0}>, obtido <{1}> {2}" -f $Expected, $Actual, $Message) }
}

function Assert-NotEqual {
    param([Parameter()] $NotExpected, [Parameter()] $Actual, [string] $Message = '')
    if ($NotExpected -eq $Actual) { throw ("Assert-NotEqual: valor inesperado <{0}> {1}" -f $Actual, $Message) }
}

function Assert-NotNull {
    param([Parameter()] $Value, [string] $Message = '')
    if ($null -eq $Value) { throw ("Assert-NotNull: valor nulo {0}" -f $Message) }
}

function Assert-Null {
    param([Parameter()] $Value, [string] $Message = '')
    if ($null -ne $Value) { throw ("Assert-Null: esperado nulo, obtido <{0}> {1}" -f $Value, $Message) }
}

function Assert-Contains {
    param([Parameter()] $Collection, [Parameter()] $Item, [string] $Message = '')
    $found = $false
    foreach ($e in @($Collection)) { if ($e -eq $Item) { $found = $true; break } }
    if (-not $found) { throw ("Assert-Contains: item <{0}> ausente {1}" -f $Item, $Message) }
}

function Assert-Match {
    param([Parameter()][string] $Text, [Parameter()][string] $Pattern, [string] $Message = '')
    if ($Text -notmatch $Pattern) { throw ("Assert-Match: '{0}' nao casa com /{1}/ {2}" -f $Text, $Pattern, $Message) }
}

function Assert-Throws {
    param([Parameter(Mandatory = $true)][scriptblock] $Body, [string] $Pattern = '', [string] $Message = '')
    $threw = $false
    try { & $Body }
    catch {
        $threw = $true
        if ($Pattern -and ($_.Exception.Message -notmatch $Pattern)) {
            throw ("Assert-Throws: excecao '{0}' nao casa com /{1}/ {2}" -f $_.Exception.Message, $Pattern, $Message)
        }
    }
    if (-not $threw) { throw ("Assert-Throws: nenhuma excecao lancada {0}" -f $Message) }
}

function Assert-NotThrows {
    param([Parameter(Mandatory = $true)][scriptblock] $Body, [string] $Message = '')
    try { & $Body }
    catch { throw ("Assert-NotThrows: excecao inesperada '{0}' {1}" -f $_.Exception.Message, $Message) }
}

# ----------------------------------------------- Acesso a internos de modulos
function Invoke-InModule {
    param([Parameter(Mandatory = $true)][string] $Module, [Parameter(Mandatory = $true)][scriptblock] $Body, [object[]] $ArgumentList = @())
    $m = Get-Module -Name $Module
    if ($null -eq $m) { throw ("Invoke-InModule: modulo '{0}' nao carregado" -f $Module) }
    return (& $m $Body @ArgumentList)
}

function Get-WRATestSummary { return [PSCustomObject]$script:WRAT }
function Get-WRATestExitCode { return [int]$script:WRAT.Failed }

function Write-WRATestSummary {
    Write-WRATLine ''
    Write-WRATLine '============================================================'
    Write-WRATLine ("Total: {0}  Passou: {1}  Falhou: {2}  Pulou: {3}" -f $script:WRAT.Total, $script:WRAT.Passed, $script:WRAT.Failed, $script:WRAT.Skipped) `
        $(if ($script:WRAT.Failed -gt 0) { 'Red' } else { 'Green' })
    if ($script:WRAT.Failed -gt 0) {
        Write-WRATLine ''
        Write-WRATLine 'Falhas:' 'Red'
        foreach ($f in $script:WRAT.Failures) { Write-WRATLine ("  - {0}" -f $f) 'Red' }
    }
    Write-WRATLine '============================================================'
}

Export-ModuleMember -Function @(
    'Reset-WRATestState', 'Set-WRATestOptions', 'Describe', 'It',
    'Assert-True', 'Assert-False', 'Assert-Equal', 'Assert-NotEqual', 'Assert-NotNull', 'Assert-Null',
    'Assert-Contains', 'Assert-Match', 'Assert-Throws', 'Assert-NotThrows',
    'Invoke-InModule', 'Get-WRATestSummary', 'Get-WRATestExitCode', 'Write-WRATestSummary'
)
