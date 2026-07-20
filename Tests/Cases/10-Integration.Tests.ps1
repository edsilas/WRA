# Desenvolvido por Edsilas
# Testes: integracao ao vivo (somente Windows). Executa os modulos de dominio
# reais contra o sistema e compoe os scores.
Describe 'Integration (live)' {

    $skip = -not $script:WRATestIsWindows

    It 'Registra os modulos de dominio em disco' -Skip:$skip {
        [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $script:WRATestConfig)
        $cfgObj = Get-WRAConfiguration
        [void](Initialize-WRAModuleRegistry -Config $cfgObj -Root $script:WRATestRoot)
        $domain = Join-Path (Join-Path $script:WRATestRoot 'Modules') 'Domain'
        [void](Register-WRAModules -Path $domain -Config $cfgObj)
        $reg = @(Get-WRAModuleRegistry)
        Assert-True ($reg.Count -ge 1) 'nenhum modulo de dominio registrado'
    }

    It 'Executa a auditoria All e compoe os scores' -Skip:$skip {
        [void](Initialize-WRAConfiguration -Root $script:WRATestRoot -ConfigPath $script:WRATestConfig)
        $cfgObj = Get-WRAConfiguration
        [void](Initialize-WRAModuleRegistry -Config $cfgObj -Root $script:WRATestRoot)
        [void](Register-WRAModules -Path (Join-Path (Join-Path $script:WRATestRoot 'Modules') 'Domain') -Config $cfgObj)

        $context = [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Elevated     = $false
            Config       = $cfgObj
            Root         = $script:WRATestRoot
        }
        $results = @(Invoke-WRAOperationSet -Selection @('All') -Context $context)
        Assert-True ($results.Count -ge 1) 'nenhum envelope produzido'
        foreach ($r in $results) {
            Assert-NotNull ($r.PSObject.Properties['Module']) 'envelope sem Module'
            Assert-NotNull ($r.PSObject.Properties['Success']) 'envelope sem Success'
        }

    }
}
