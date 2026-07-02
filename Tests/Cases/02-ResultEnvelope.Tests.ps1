# Desenvolvido por Edsilas
# Testes: Modules/Contracts/ResultEnvelope.psm1
Describe 'ResultEnvelope' {

    It 'New-WRAResult expoe os 9 campos do contrato' {
        $r = New-WRAResult -Success $true -Module 'M' -Operation 'Op' -Data @{ x = 1 } -DurationMs 5
        foreach ($f in @('Success', 'Module', 'Operation', 'Duration', 'Timestamp', 'ComputerName', 'Data', 'Warnings', 'Errors')) {
            Assert-NotNull ($r.PSObject.Properties[$f]) ("campo ausente: {0}" -f $f)
        }
        Assert-Equal $true $r.Success
        Assert-Equal 'M' $r.Module
        Assert-Equal 'Op' $r.Operation
    }

    It 'New-WRAResult normaliza Warnings/Errors como arrays' {
        $r = New-WRAResult -Success $true -Module 'M' -Operation 'Op'
        Assert-True ($r.Warnings -is [System.Array]) 'Warnings deve ser array'
        Assert-True ($r.Errors -is [System.Array]) 'Errors deve ser array'
    }

    It 'New-WRAModulePayload marca __WRAPayload' {
        $p = New-WRAModulePayload -Data 1 -Warnings @('w')
        Assert-Equal $true $p.__WRAPayload
        Assert-Equal 1 $p.Warnings.Count
    }

    It 'Test-WRAResult valida envelope correto' {
        $r = New-WRAResult -Success $true -Module 'M' -Operation 'Op'
        Assert-True (Test-WRAResult -Result $r) 'envelope valido'
    }
}
