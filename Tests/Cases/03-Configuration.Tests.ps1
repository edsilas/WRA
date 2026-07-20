# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Configuration.psm1
Describe 'Configuration' {

    It 'Initialize-WRAConfiguration carrega o Config.json real' {
        Assert-NotThrows { [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $script:WRATestConfig) }
    }

    It 'Get-WRAConfigValue resolve chave conhecida' {
        [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $script:WRATestConfig)
        Assert-Equal $true (Get-WRAConfigValue -Path 'General.PreventMultipleInstances' -Default $false)
    }

    It 'Get-WRAConfigValue retorna default para chave inexistente' {
        [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $script:WRATestConfig)
        Assert-Equal 'fallback' (Get-WRAConfigValue -Path 'Nao.Existe.Aqui' -Default 'fallback')
    }

    It 'Version e a lista de modulos habilitados estao presentes' {
        [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $script:WRATestConfig)
        Assert-NotNull (Get-WRAConfigValue -Path 'Version')
        $enabled = @(Get-WRAConfigValue -Path 'Modules.Enabled' -Default @())
        Assert-Contains $enabled 'Monitor'
        Assert-Contains $enabled 'Security'
    }

    It 'ConfigPath invalido degrada para defaults sem lancar (Fail Safe)' {
        $bogus = Join-Path $env:TEMP ('wra_nope_{0}.json' -f ([guid]::NewGuid().ToString('N')))
        Assert-NotThrows { [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $bogus -SchemaPath $script:WRATestSchema) }
        Assert-NotNull (Get-WRAConfigValue -Path 'Version')
    }
}
