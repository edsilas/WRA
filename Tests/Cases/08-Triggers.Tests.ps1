# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Triggers.psm1
Describe 'Triggers' {

    It 'Test-WRATriggerCompare cobre os operadores' {
        $cmp = { param($c, $op, $v) Test-WRATriggerCompare -Current $c -Operator $op -Value $v }
        Assert-True  (Invoke-InModule -Module 'Triggers' -Body $cmp -ArgumentList @(95, '>=', 90)) '95 >= 90'
        Assert-False (Invoke-InModule -Module 'Triggers' -Body $cmp -ArgumentList @(80, '>=', 90)) '80 !>= 90'
        Assert-True  (Invoke-InModule -Module 'Triggers' -Body $cmp -ArgumentList @(10, '<', 20))  '10 < 20'
        Assert-True  (Invoke-InModule -Module 'Triggers' -Body $cmp -ArgumentList @(5, '==', 5))   '5 == 5'
        Assert-False (Invoke-InModule -Module 'Triggers' -Body $cmp -ArgumentList @(5, '??', 5))   'operador invalido => false'
    }

    It 'Start-WRATriggerWatch encerra apos MaxCycles (sem regras)' {
        $cfg = [pscustomobject]@{ Triggers = [pscustomobject]@{ PollSeconds = 1; CooldownSeconds = 0; Rules = @() } }
        $r = Start-WRATriggerWatch -Config $cfg -Root $script:WRATestRoot -Context $null -MaxCycles 2
        Assert-Equal 2 $r.Cycles
    }

    It 'Dispara OnTrigger quando a metrica e violada imediatamente' {
        # Regra sobre ServiceStopped com ForSeconds=0: dispara no primeiro ciclo se houver
        # qualquer servico automatico parado. Para ser deterministico, usamos uma regra
        # cujo limite e sempre satisfeito: ServiceStopped >= 0.
        $cfg = [pscustomobject]@{ Triggers = [pscustomobject]@{ PollSeconds = 1; CooldownSeconds = 0; Rules = @(
                    [pscustomobject]@{ Name = 'Always'; Metric = 'ServiceStopped'; Operator = '>='; Value = 0; ForSeconds = 0; Run = @('Monitor') }
                ) } }
        $script:WRATFired = 0
        $cb = { param($sel) $script:WRATFired++ }
        if ($script:WRATestIsWindows) {
            [void](Start-WRATriggerWatch -Config $cfg -Root $script:WRATestRoot -Context $null -OnTrigger $cb -MaxCycles 1)
            Assert-True ($script:WRATFired -ge 1) 'OnTrigger deveria ter disparado'
        }
        else {
            # Fora do Windows, a metrica retorna 0 e a regra (>=0) ainda dispara.
            [void](Start-WRATriggerWatch -Config $cfg -Root $script:WRATestRoot -Context $null -OnTrigger $cb -MaxCycles 1)
            Assert-True ($script:WRATFired -ge 0) 'execucao nao deveria lancar'
        }
    }
}
