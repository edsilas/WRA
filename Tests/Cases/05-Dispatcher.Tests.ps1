# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Dispatcher.psm1
function global:WRATestFakeHandler {
    param($Context)
    New-WRAModulePayload -Data ([pscustomobject]@{ Hit = $true })
}
function global:WRATestFailHandler {
    param($Context)
    throw 'falha proposital'
}

Describe 'Dispatcher' {

    It 'Registra modulo falso e despacha com envelope de sucesso' {
        [void](Initialize-WRAModuleRegistry)
        $op = New-WRAOperation -Name 'Do' -Handler 'WRATestFakeHandler'
        $manifest = New-WRAModuleManifest -Module 'Fake' -Operations @($op) -Description 'modulo de teste'
        Assert-True (Register-WRAModule -Manifest $manifest) 'registro deveria retornar true'

        $env = Invoke-WRAOperation -Module 'Fake' -Operation 'Do' -Context ([pscustomobject]@{ ComputerName = 'TESTBOX'; Elevated = $true })
        Assert-Equal $true $env.Success
        Assert-Equal 'Fake' $env.Module
        Assert-Equal $true (Get-WRAProp -Object $env -Path 'Data.Hit')
        Assert-Equal 'TESTBOX' $env.ComputerName
    }

    It 'Invoke-WRAOperationSet com All inclui o modulo habilitado' {
        [void](Initialize-WRAModuleRegistry)
        $op = New-WRAOperation -Name 'Do' -Handler 'WRATestFakeHandler'
        [void](Register-WRAModule -Manifest (New-WRAModuleManifest -Module 'Fake' -Operations @($op)))
        $set = @(Invoke-WRAOperationSet -Selection @('All') -Context ([pscustomobject]@{ ComputerName = 'T' }))
        Assert-True ($set.Count -ge 1) 'deveria executar ao menos uma operacao'
        Assert-Equal 'Fake' $set[0].Module
    }

    It 'Selecao explicita Modulo.Operacao resolve' {
        [void](Initialize-WRAModuleRegistry)
        [void](Register-WRAModule -Manifest (New-WRAModuleManifest -Module 'Fake' -Operations @(New-WRAOperation -Name 'Do' -Handler 'WRATestFakeHandler')))
        $set = @(Invoke-WRAOperationSet -Selection @('Fake.Do') -Context $null)
        Assert-Equal 1 $set.Count
    }

    It 'Modulo inexistente produz envelope de falha (nao lanca)' {
        [void](Initialize-WRAModuleRegistry)
        $env = Invoke-WRAOperation -Module 'Ghost' -Operation 'Nope' -Context $null
        Assert-Equal $false $env.Success
        Assert-True ($env.Errors.Count -ge 1) 'deveria conter erro'
    }

    It 'Excecao no handler vira envelope de falha' {
        [void](Initialize-WRAModuleRegistry)
        [void](Register-WRAModule -Manifest (New-WRAModuleManifest -Module 'Boom' -Operations @(New-WRAOperation -Name 'Go' -Handler 'WRATestFailHandler')))
        $env = Invoke-WRAOperation -Module 'Boom' -Operation 'Go' -Context $null
        Assert-Equal $false $env.Success
        Assert-True ($env.Errors.Count -ge 1) 'erro do handler deveria ser capturado'
    }
}
