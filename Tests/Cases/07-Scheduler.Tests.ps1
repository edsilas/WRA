# Desenvolvido por Edsilas
# Testes: Modules/Infrastructure/Scheduler.psm1  (gera XML de tarefa, valida via [xml])
Describe 'Scheduler' {

    $make = {
        param($trigger)
        New-WRATaskXml -LauncherPath 'C:\Program Files\Acme & Co\WRA\Launcher.bat' `
            -RunSelection 'All' -Trigger $trigger -At '03:00' -IntervalMinutes 30 `
            -DaysOfWeek @('Monday', 'Friday') -RunHighest $true
    }

    foreach ($trg in @('Daily', 'Weekly', 'Startup', 'Logon', 'Interval', 'Hourly')) {
        It ("Gera XML bem-formado para gatilho {0}" -f $trg) {
            $xml = Invoke-InModule -Module 'Scheduler' -Body $make -ArgumentList @($trg)
            Assert-NotNull $xml
            Assert-NotThrows { [void]([xml]$xml) } 'XML malformado'
            Assert-Match $xml 'S-1-5-18' 'principal SYSTEM ausente'
            Assert-Match $xml 'IgnoreNew' 'politica de instancia ausente'
        }
    }

    It 'Escapa & nos argumentos e faz round-trip ao parsear' {
        $xml = Invoke-InModule -Module 'Scheduler' -Body $make -ArgumentList @('Daily')
        [xml]$doc = $xml
        $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
        $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
        $argNode = $doc.SelectSingleNode('//t:Actions/t:Exec/t:Arguments', $ns)
        Assert-NotNull $argNode 'no de Arguments ausente'
        Assert-Match $argNode.InnerText 'Acme & Co' 'ampersand nao sobreviveu ao parse'
    }

    It 'RunHighest false produz LeastPrivilege' {
        $xml = Invoke-InModule -Module 'Scheduler' -Body {
            New-WRATaskXml -LauncherPath 'C:\x\Launcher.bat' -RunSelection 'All' -Trigger 'Daily' -At '01:00' -IntervalMinutes 60 -DaysOfWeek @('Monday') -RunHighest $false
        } -ArgumentList @()
        Assert-Match $xml 'LeastPrivilege'
    }
}
