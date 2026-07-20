#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : ModuleContract.psm1
#  Versao  : 1.1.0
#  Camada  : Contratos
#
#  Responsabilidade unica:
#    Definir e validar o contrato/manifesto que todo modulo de dominio publica
#    ao se auto-registrar no framework.
#
#  Forma do manifesto:
#    Module             [string]  Nome unico do modulo.
#    Version            [string]  Versao do modulo.
#    Description        [string]  Descricao curta.
#    RequiresElevation  [bool]    Indica se o modulo, em geral, exige elevacao.
#    Operations         [array]   Lista de operacoes, cada uma com:
#       Name             [string]  Nome unico da operacao no modulo.
#       Handler          [string]  Nome da funcao exportada que executa a operacao.
#                                  Assinatura: function <Handler> { param($Context) ... }
#       Description      [string]
#       RequiresElevation[bool]
#
#  Exposto:
#    New-WRAOperation / New-WRAModuleManifest / Test-WRAModuleContract
# ============================================================================

Set-StrictMode -Version 2.0

function New-WRAOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Handler,
        [Parameter()][string] $Description = '',
        [Parameter()][switch] $RequiresElevation
    )
    return [PSCustomObject]([ordered]@{
        Name              = $Name
        Handler           = $Handler
        Description       = $Description
        RequiresElevation = [bool]$RequiresElevation
    })
}

function New-WRAModuleManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Module,
        [Parameter(Mandatory = $true)][object[]] $Operations,
        [Parameter()][string] $Version = '1.1.0',
        [Parameter()][string] $Description = '',
        [Parameter()][switch] $RequiresElevation
    )
    return [PSCustomObject]([ordered]@{
        Module            = $Module
        Version           = $Version
        Description       = $Description
        RequiresElevation = [bool]$RequiresElevation
        Operations        = @($Operations)
    })
}

function Test-WRAModuleContract {
    [CmdletBinding()]
    param([Parameter()] $Manifest)

    if ($null -eq $Manifest) { return $false }

    $module = Get-WRAProp -Object $Manifest -Path 'Module'
    if (-not ($module -is [string]) -or [string]::IsNullOrWhiteSpace($module)) { return $false }

    $ops = Get-WRAProp -Object $Manifest -Path 'Operations'
    if ($null -eq $ops) { return $false }
    $opsArr = @($ops)
    if ($opsArr.Count -eq 0) { return $false }

    $seen = @{ }
    foreach ($op in $opsArr) {
        $name = Get-WRAProp -Object $op -Path 'Name'
        $handler = Get-WRAProp -Object $op -Path 'Handler'
        if (-not ($name -is [string]) -or [string]::IsNullOrWhiteSpace($name)) { return $false }
        if (-not ($handler -is [string]) -or [string]::IsNullOrWhiteSpace($handler)) { return $false }
        if ($seen.ContainsKey($name)) { return $false }
        $seen[$name] = $true
    }
    return $true
}

Export-ModuleMember -Function @('New-WRAOperation', 'New-WRAModuleManifest', 'Test-WRAModuleContract')
