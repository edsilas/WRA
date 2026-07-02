#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Common.psm1
#  Versao  : 4.1.0
#  Camada  : Contratos (utilitarios compartilhados)
#
#  Responsabilidade unica:
#    Funcoes utilitarias puras e sem estado, reutilizadas pelo framework e
#    pelos modulos de dominio (Defensive Programming + DRY).
#
#  Exposto:
#    Get-WRAProp -Object -Path [-Default]    Acesso seguro por caminho pontilhado.
#    Test-WRAPayload -Object                 Detecta um payload de modulo.
#    ConvertTo-WRAArray -InputObject         Normaliza valor em array.
# ============================================================================

Set-StrictMode -Version 2.0

function Get-WRAProp {
    [CmdletBinding()]
    param(
        [Parameter()] $Object,
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter()] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $node = $Object
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $node) { return $Default }
        if ($node -is [System.Collections.IDictionary]) {
            if ($node.Contains($segment)) { $node = $node[$segment]; continue }
            return $Default
        }
        $prop = $node.PSObject.Properties[$segment]
        if ($null -eq $prop) { return $Default }
        $node = $prop.Value
    }
    if ($null -eq $node) { return $Default }
    return $node
}

function Test-WRAPayload {
    [CmdletBinding()]
    param([Parameter()] $Object)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        return ($Object.Contains('__WRAPayload') -and [bool]$Object['__WRAPayload'])
    }
    $prop = $Object.PSObject.Properties['__WRAPayload']
    return ($null -ne $prop -and [bool]$prop.Value)
}

function ConvertTo-WRAArray {
    [CmdletBinding()]
    param([Parameter()] $InputObject)
    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [string]) { return , @($InputObject) }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $arr = @()
        foreach ($i in $InputObject) { $arr += $i }
        return , $arr
    }
    return , @($InputObject)
}

function Get-WRANum {
    # Conversao numerica segura: retorna double ou o valor padrao em falha.
    [CmdletBinding()]
    param(
        [Parameter()] $Object,
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter()][double] $Default = 0
    )
    $value = Get-WRAProp -Object $Object -Path $Name -Default $Default
    if ($null -eq $value) { return $Default }
    try { return [double]$value } catch { return $Default }
}

Export-ModuleMember -Function @('Get-WRAProp', 'Test-WRAPayload', 'ConvertTo-WRAArray', 'Get-WRANum')
