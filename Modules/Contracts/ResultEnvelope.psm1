#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : ResultEnvelope.psm1
#  Versao  : 1.1.0
#  Camada  : Contratos (fronteira de integracao)
#
#  Responsabilidade unica:
#    Fabricar e validar o envelope universal de resultado (contrato da Etapa 1)
#    que todo modulo retorna, e o payload que os handlers de operacao produzem.
#
#  Exposto:
#    New-WRAResult         Constroi o envelope padronizado.
#    New-WRAModulePayload  Constroi o payload (Data/Warnings/Errors) de um handler.
#    Test-WRAResult        Valida se um objeto cumpre o contrato do envelope.
# ============================================================================

Set-StrictMode -Version 2.0

function New-WRAResult {
    [CmdletBinding()]
    param(
        [Parameter()][bool] $Success = $true,
        [Parameter(Mandatory = $true)][string] $Module,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter()][double] $DurationMs = 0,
        [Parameter()] $Data = $null,
        [Parameter()] $Warnings = @(),
        [Parameter()] $Errors = @(),
        [Parameter()][string] $ComputerName
    )
    if (-not $ComputerName) { $ComputerName = $env:COMPUTERNAME }

    return [PSCustomObject]([ordered]@{
        Success      = $Success
        Module       = $Module
        Operation    = $Operation
        Duration     = $DurationMs
        Timestamp    = (Get-Date).ToString('o')
        ComputerName = $ComputerName
        Data         = $Data
        Warnings     = @($Warnings)
        Errors       = @($Errors)
    })
}

function New-WRAModulePayload {
    [CmdletBinding()]
    param(
        [Parameter()] $Data = $null,
        [Parameter()] $Warnings = @(),
        [Parameter()] $Errors = @()
    )
    return [PSCustomObject]([ordered]@{
        __WRAPayload = $true
        Data         = $Data
        Warnings     = @($Warnings)
        Errors       = @($Errors)
    })
}

function Test-WRAResult {
    [CmdletBinding()]
    param([Parameter()] $Result)
    if ($null -eq $Result) { return $false }
    $required = @('Success', 'Module', 'Operation', 'Duration', 'Timestamp', 'ComputerName', 'Data', 'Warnings', 'Errors')
    foreach ($name in $required) {
        if ($Result -is [System.Collections.IDictionary]) {
            if (-not $Result.Contains($name)) { return $false }
        }
        else {
            if ($null -eq $Result.PSObject.Properties[$name]) { return $false }
        }
    }
    return $true
}

Export-ModuleMember -Function @('New-WRAResult', 'New-WRAModulePayload', 'Test-WRAResult')
