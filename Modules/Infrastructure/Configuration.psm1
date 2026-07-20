#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Configuration.psm1
#  Versao  : 1.1.0
#  Camada  : 1 - Infraestrutura
#
#  Responsabilidade unica:
#    Carregar, validar e resolver a configuracao da suite a partir de
#    Config.json (valores) + Config.schema.json (tipos, faixas e defaults),
#    produzindo um objeto de configuracao imutavel para o restante do sistema.
#
#  Contrato exposto (consumido pelo Core - Etapa 4):
#    Initialize-WRAConfiguration -Root <string> -ConfigPath <string> [-SchemaPath <string>]
#    Get-WRAConfiguration
#    Get-WRAConfigValue -Path 'A.B.C' [-Default <obj>]
#    Get-WRAConfigurationDiagnostics
#
#  Principios: fonte unica da verdade, zero valores magicos no codigo,
#  Defensive Programming, Fail Safe (defaults restauram chaves ausentes).
# ============================================================================

Set-StrictMode -Version 2.0

# Estado do modulo (cache).
$script:WRAConfig = $null
$script:WRAConfigDiagnostics = New-Object System.Collections.Generic.List[object]

# ------------------------------------------------------------------ Privados

function New-WRADiag {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Info', 'Warn', 'Error')][string] $Level,
        [Parameter(Mandatory = $true)][string] $Message
    )
    return [PSCustomObject]@{ Level = $Level; Message = $Message }
}

function ConvertTo-WRAHashtable {
    # Converte PSCustomObject/array (saida de ConvertFrom-Json) em arvore de
    # OrderedDictionary/array, permitindo deep-merge e indexacao seguros.
    param([Parameter()] $InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = [ordered]@{ }
        foreach ($key in $InputObject.Keys) {
            $h[[string]$key] = ConvertTo-WRAHashtable -InputObject $InputObject[$key]
        }
        return $h
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{ }
        foreach ($prop in $InputObject.PSObject.Properties) {
            $h[$prop.Name] = ConvertTo-WRAHashtable -InputObject $prop.Value
        }
        return $h
    }

    if ($InputObject -is [string]) { return $InputObject }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$list.Add((ConvertTo-WRAHashtable -InputObject $item))
        }
        return $list.ToArray()
    }

    return $InputObject
}

function ConvertTo-WRAObject {
    # Converte a arvore de hashtables de volta para PSCustomObject (saida final).
    param([Parameter()] $InputObject)

    if ($InputObject -is [System.Collections.IDictionary]) {
        $o = [ordered]@{ }
        foreach ($key in $InputObject.Keys) {
            $o[[string]$key] = ConvertTo-WRAObject -InputObject $InputObject[$key]
        }
        return [PSCustomObject]$o
    }

    if ($InputObject -is [string]) { return $InputObject }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $arr = @()
        foreach ($item in $InputObject) { $arr += , (ConvertTo-WRAObject -InputObject $item) }
        return , $arr
    }

    return $InputObject
}

function Get-WRASchemaDefaults {
    # Extrai recursivamente os valores 'default' de um no de schema.
    param([Parameter()] $SchemaNode)

    if ($null -eq $SchemaNode -or -not ($SchemaNode -is [System.Collections.IDictionary])) {
        return $null
    }

    if ($SchemaNode.Contains('properties')) {
        $obj = [ordered]@{ }
        $props = $SchemaNode['properties']
        if ($props -is [System.Collections.IDictionary]) {
            foreach ($key in $props.Keys) {
                $obj[[string]$key] = Get-WRASchemaDefaults -SchemaNode $props[$key]
            }
        }
        return $obj
    }

    if ($SchemaNode.Contains('default')) {
        return ConvertTo-WRAHashtable -InputObject $SchemaNode['default']
    }

    $type = $null
    if ($SchemaNode.Contains('type')) { $type = $SchemaNode['type'] }
    switch ($type) {
        'object' { return [ordered]@{ } }
        'array' { return @() }
        default { return $null }
    }
}

function Merge-WRAConfig {
    # Deep-merge: valores de $Override sobrepoem $Base. Objetos sao mesclados
    # recursivamente; arrays e escalares sao substituidos por inteiro.
    param([Parameter()] $Base, [Parameter()] $Override)

    if (($Base -is [System.Collections.IDictionary]) -and ($Override -is [System.Collections.IDictionary])) {
        $result = [ordered]@{ }
        foreach ($key in $Base.Keys) { $result[[string]$key] = $Base[$key] }
        foreach ($key in $Override.Keys) {
            $k = [string]$key
            if ($result.Contains($k) -and ($result[$k] -is [System.Collections.IDictionary]) -and ($Override[$k] -is [System.Collections.IDictionary])) {
                $result[$k] = Merge-WRAConfig -Base $result[$k] -Override $Override[$k]
            }
            else {
                $result[$k] = $Override[$k]
            }
        }
        return $result
    }

    if ($null -ne $Override) { return $Override }
    return $Base
}

function Test-WRAType {
    param([Parameter()] $Value, [Parameter()][string] $Type)
    switch ($Type) {
        'string' { return ($Value -is [string]) }
        'integer' { return (($Value -is [int]) -or ($Value -is [long])) }
        'number' { return (($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal])) }
        'boolean' { return ($Value -is [bool]) }
        'array' { return (($Value -is [array]) -or (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string]))) }
        'object' { return ($Value -is [System.Collections.IDictionary]) }
        default { return $true }
    }
}

function Test-WRAConfigAgainstSchema {
    # Validacao nao-fatal: registra avisos para tipos invalidos, valores fora do
    # enum ou fora das faixas. Os defaults ja preencheram chaves ausentes.
    param(
        [Parameter()] $Config,
        [Parameter()] $Schema,
        [Parameter()] $Diagnostics,
        [Parameter()] [string] $PathPrefix = ''
    )

    if ($null -eq $Schema -or -not ($Schema -is [System.Collections.IDictionary])) { return }
    if (-not $Schema.Contains('properties')) { return }
    $props = $Schema['properties']
    if (-not ($props -is [System.Collections.IDictionary])) { return }

    foreach ($key in $props.Keys) {
        $childSchema = $props[$key]
        if (-not ($childSchema -is [System.Collections.IDictionary])) { continue }

        if ($PathPrefix) { $path = ('{0}.{1}' -f $PathPrefix, $key) } else { $path = [string]$key }

        if (-not ($Config -is [System.Collections.IDictionary]) -or -not $Config.Contains($key)) { continue }
        $val = $Config[$key]

        $type = $null
        if ($childSchema.Contains('type')) { $type = $childSchema['type'] }

        if ($type -and -not (Test-WRAType -Value $val -Type $type)) {
            [void]$Diagnostics.Add((New-WRADiag -Level 'Warn' -Message ("Tipo invalido em '{0}' (esperado {1})." -f $path, $type)))
        }

        if ($childSchema.Contains('enum') -and ($val -isnot [System.Collections.IDictionary]) -and ($val -isnot [array])) {
            $enum = @($childSchema['enum'])
            if ($enum.Count -gt 0 -and ($val -notin $enum)) {
                [void]$Diagnostics.Add((New-WRADiag -Level 'Warn' -Message ("Valor fora do conjunto permitido em '{0}'." -f $path)))
            }
        }

        if (($type -eq 'number' -or $type -eq 'integer') -and (Test-WRAType -Value $val -Type 'number')) {
            if ($childSchema.Contains('minimum') -and ($val -lt $childSchema['minimum'])) {
                [void]$Diagnostics.Add((New-WRADiag -Level 'Warn' -Message ("Valor abaixo do minimo em '{0}'." -f $path)))
            }
            if ($childSchema.Contains('maximum') -and ($val -gt $childSchema['maximum'])) {
                [void]$Diagnostics.Add((New-WRADiag -Level 'Warn' -Message ("Valor acima do maximo em '{0}'." -f $path)))
            }
        }

        if (($type -eq 'object') -or $childSchema.Contains('properties')) {
            Test-WRAConfigAgainstSchema -Config $val -Schema $childSchema -Diagnostics $Diagnostics -PathPrefix $path
        }
    }
}

function Read-WRAJsonFile {
    # Le e desserializa um arquivo JSON. Lanca em caso de JSON invalido.
    param([Parameter(Mandatory = $true)][string] $Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

# ------------------------------------------------------------------ Publicos

function Initialize-WRAConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $ConfigPath,
        [Parameter()][string] $SchemaPath
    )

    $diag = New-Object System.Collections.Generic.List[object]

    if (-not $SchemaPath) {
        $SchemaPath = Join-Path (Split-Path -Parent $ConfigPath) 'Config.schema.json'
    }

    # 1) Defaults a partir do schema.
    $defaults = [ordered]@{ }
    if (Test-Path -LiteralPath $SchemaPath) {
        try {
            $schemaObj = Read-WRAJsonFile -Path $SchemaPath
            $schemaHt = ConvertTo-WRAHashtable -InputObject $schemaObj
            $defaults = Get-WRASchemaDefaults -SchemaNode $schemaHt
            if ($null -eq $defaults) { $defaults = [ordered]@{ } }
        }
        catch {
            $schemaHt = $null
            [void]$diag.Add((New-WRADiag -Level 'Warn' -Message ("Falha ao ler o schema; defaults indisponiveis: {0}" -f $_.Exception.Message)))
        }
    }
    else {
        $schemaHt = $null
        [void]$diag.Add((New-WRADiag -Level 'Warn' -Message ("Schema nao encontrado em '{0}'; validacao e defaults desabilitados." -f $SchemaPath)))
    }

    # 2) Configuracao do operador.
    $userHt = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $userObj = Read-WRAJsonFile -Path $ConfigPath
            if ($null -eq $userObj) {
                [void]$diag.Add((New-WRADiag -Level 'Warn' -Message 'Config.json vazio; utilizando apenas defaults.'))
            }
            else {
                $userHt = ConvertTo-WRAHashtable -InputObject $userObj
            }
        }
        catch {
            [void]$diag.Add((New-WRADiag -Level 'Error' -Message ("Config.json invalido; utilizando apenas defaults: {0}" -f $_.Exception.Message)))
        }
    }
    else {
        [void]$diag.Add((New-WRADiag -Level 'Warn' -Message ("Config.json nao encontrado em '{0}'; utilizando apenas defaults." -f $ConfigPath)))
    }

    # 3) Merge (operador sobre defaults).
    $merged = $defaults
    if ($null -ne $userHt) { $merged = Merge-WRAConfig -Base $defaults -Override $userHt }
    if ($null -eq $merged) { $merged = [ordered]@{ } }

    # 4) Validacao nao-fatal contra o schema.
    if ($null -ne $schemaHt) {
        Test-WRAConfigAgainstSchema -Config $merged -Schema $schemaHt -Diagnostics $diag -PathPrefix ''
    }

    # 5) Objeto final imutavel para consumo.
    $obj = ConvertTo-WRAObject -InputObject $merged

    $script:WRAConfig = $obj
    $script:WRAConfigDiagnostics = $diag
    return $obj
}

function Get-WRAConfiguration {
    return $script:WRAConfig
}

function Get-WRAConfigurationDiagnostics {
    return , @($script:WRAConfigDiagnostics.ToArray())
}

function Get-WRAConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter()] $Default = $null
    )

    if ($null -eq $script:WRAConfig) { return $Default }

    $node = $script:WRAConfig
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

Export-ModuleMember -Function @(
    'Initialize-WRAConfiguration',
    'Get-WRAConfiguration',
    'Get-WRAConfigValue',
    'Get-WRAConfigurationDiagnostics'
)
