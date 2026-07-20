#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : Security.psm1
#  Versao  : 1.1.0
#  Camada  : 2 - Dominio
#
#  Responsabilidade unica:
#    Auditar a postura de seguranca (Defender, Firewall, SmartScreen, UAC, TPM,
#    Secure Boot, BitLocker, Credential Guard, Device Guard, Memory Integrity,
#    Windows Update, eventos criticos) e gerar Security Score, Risk Score,
#    Health Score (dominio de seguranca) e recomendacoes.
#
#  Fontes: CIM (namespaces de Defender/DeviceGuard/TPM/BitLocker), cmdlets
#  nativos quando disponiveis, e Registro SOMENTE LEITURA.
#
#  RESTRICAO: nunca altera qualquer configuracao. Toda correcao e recomendacao.
#
#  Operacao: Audit  ->  Invoke-WRASecurityAudit -Context
# ============================================================================

Set-StrictMode -Version 2.0

# --------------------------------------------------------------- Utilitarios

function Invoke-WRASecCim {
    param(
        [Parameter(Mandatory = $true)][string] $ClassName,
        [Parameter()][string] $Namespace,
        [Parameter()][string[]] $Property,
        [Parameter()][int] $TimeoutSec = 30,
        [Parameter()] $Warnings,
        [Parameter()][switch] $Quiet
    )
    if (Get-Command -Name 'Invoke-WRACimQuery' -ErrorAction SilentlyContinue) {
        return @(Invoke-WRACimQuery -ClassName $ClassName -Namespace $Namespace -Property $Property -TimeoutSec $TimeoutSec -Warnings $Warnings -Quiet:$Quiet)
    }
    try {
        $params = @{ ClassName = $ClassName; ErrorAction = 'Stop' }
        if ($Namespace) { $params['Namespace'] = $Namespace }
        if ($Property) { $params['Property'] = $Property }
        return @(Get-CimInstance @params)
    }
    catch {
        if (-not $Quiet -and $null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar {0}: {1}" -f $ClassName, $_.Exception.Message)) }
        return @()
    }
}

function Get-WRARegValue {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Name, [Parameter()] $Default = $null)
    try {
        if (Test-Path -LiteralPath $Path) {
            $p = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
            $v = Get-WRAProp -Object $p -Path $Name
            if ($null -ne $v) { return $v }
        }
    }
    catch { }
    return $Default
}

function New-WRASecCheck {
    param([string] $Name, [string] $Status, [string] $Detail, [double] $SubScore, [string] $Severity, [bool] $Applicable = $true, [bool] $Determinable = $true)
    return [PSCustomObject]@{ Name = $Name; Status = $Status; Detail = $Detail; SubScore = $SubScore; Severity = $Severity; Applicable = $Applicable; Determinable = $Determinable }
}

function Add-WRARec {
    param($List, [string] $Area, [string] $Severity, [string] $Finding, [string] $Recommendation)
    [void]$List.Add([PSCustomObject]@{ Area = $Area; Severity = $Severity; Finding = $Finding; Recommendation = $Recommendation })
}

# ----------------------------------------------------------- Verificacoes

function Get-WRASecDefender {
    param([int] $TimeoutSec, $Warnings)
    $mp = @(Invoke-WRASecCim -ClassName 'MSFT_MpComputerStatus' -Namespace 'root/Microsoft/Windows/Defender' -TimeoutSec $TimeoutSec -Warnings $null -Quiet)
    $obj = $null
    if ($mp.Count -gt 0) { $obj = $mp[0] }
    elseif (Get-Command -Name 'Get-MpComputerStatus' -ErrorAction SilentlyContinue) {
        try { $obj = Get-MpComputerStatus -ErrorAction Stop } catch { }
    }
    if ($null -eq $obj) {
        return New-WRASecCheck -Name 'Microsoft Defender' -Status 'Unknown' -Detail 'Status do Defender indisponivel.' -SubScore 0 -Severity 'Medium' -Applicable $false -Determinable $false
    }
    $av = [bool](Get-WRAProp -Object $obj -Path 'AntivirusEnabled' -Default $false)
    $rtp = [bool](Get-WRAProp -Object $obj -Path 'RealTimeProtectionEnabled' -Default $false)
    $svc = [bool](Get-WRAProp -Object $obj -Path 'AMServiceEnabled' -Default $false)
    $score = 0.0
    if ($svc) { $score += 0.2 }
    if ($av) { $score += 0.3 }
    if ($rtp) { $score += 0.5 }
    $status = if ($rtp -and $av) { 'Enabled' } elseif ($av -or $svc) { 'Partial' } else { 'Disabled' }
    $sev = if ($rtp -and $av) { 'Info' } elseif ($av) { 'Medium' } else { 'High' }
    $detail = ('Antivirus={0}; RealTime={1}; Servico={2}' -f $av, $rtp, $svc)
    return New-WRASecCheck -Name 'Microsoft Defender' -Status $status -Detail $detail -SubScore $score -Severity $sev
}

function Get-WRASecFirewallProfiles {
    param($Warnings)
    $list = New-Object System.Collections.Generic.List[object]
    if (Get-Command -Name 'Get-NetFirewallProfile' -ErrorAction SilentlyContinue) {
        try {
            foreach ($fp in @(Get-NetFirewallProfile -ErrorAction Stop)) {
                $en = ([string](Get-WRAProp -Object $fp -Path 'Enabled' -Default '') -match '(?i)true|1')
                [void]$list.Add([PSCustomObject]@{ Name = [string](Get-WRAProp -Object $fp -Path 'Name' -Default ''); Enabled = $en })
            }
        }
        catch { }
    }
    if ($list.Count -eq 0) {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy'
        foreach ($prof in @('DomainProfile', 'StandardProfile', 'PublicProfile')) {
            $en = [int](Get-WRARegValue -Path (Join-Path $base $prof) -Name 'EnableFirewall' -Default 0)
            [void]$list.Add([PSCustomObject]@{ Name = $prof; Enabled = ($en -eq 1) })
        }
    }
    return $list.ToArray()
}

function Get-WRASecFirewall {
    param($Warnings)
    $profiles = Get-WRASecFirewallProfiles -Warnings $Warnings
    if (@($profiles).Count -eq 0) {
        return New-WRASecCheck -Name 'Firewall' -Status 'Unknown' -Detail 'Perfis de firewall indisponiveis.' -SubScore 0 -Severity 'Medium' -Applicable $false -Determinable $false
    }
    $enabled = @($profiles | Where-Object { $_.Enabled }).Count
    $total = @($profiles).Count
    $score = 0.0
    if ($total -gt 0) { $score = [double]$enabled / $total }
    $status = if ($enabled -eq $total) { 'Enabled' } elseif ($enabled -gt 0) { 'Partial' } else { 'Disabled' }
    $sev = if ($enabled -eq $total) { 'Info' } elseif ($enabled -gt 0) { 'Medium' } else { 'High' }
    $detail = ('{0}/{1} perfis habilitados.' -f $enabled, $total)
    $check = New-WRASecCheck -Name 'Firewall' -Status $status -Detail $detail -SubScore $score -Severity $sev
    $check | Add-Member -NotePropertyName 'Profiles' -NotePropertyValue @($profiles)
    return $check
}

function Get-WRASecSmartScreen {
    param($Warnings)
    $val = [string](Get-WRARegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'SmartScreenEnabled' -Default '')
    $enabled = ($val -match '(?i)RequireAdmin|Prompt|Warn|On')
    $score = if ($enabled) { 1.0 } else { 0.0 }
    $status = if ($enabled) { 'Enabled' } elseif ($val) { 'Disabled' } else { 'Unknown' }
    $sev = if ($enabled) { 'Info' } else { 'Low' }
    return New-WRASecCheck -Name 'SmartScreen' -Status $status -Detail ('Valor: {0}' -f $val) -SubScore $score -Severity $sev -Applicable ([bool]$val) -Determinable ([bool]$val)
}

function Get-WRASecUac {
    param($Warnings)
    $lua = [int](Get-WRARegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Default 1)
    $enabled = ($lua -eq 1)
    $score = if ($enabled) { 1.0 } else { 0.0 }
    $status = if ($enabled) { 'Enabled' } else { 'Disabled' }
    $sev = if ($enabled) { 'Info' } else { 'High' }
    return New-WRASecCheck -Name 'UAC' -Status $status -Detail ('EnableLUA={0}' -f $lua) -SubScore $score -Severity $sev
}

function Get-WRASecTpm {
    param([int] $TimeoutSec, $Warnings)
    $tpm = @(Invoke-WRASecCim -ClassName 'Win32_Tpm' -Namespace 'root/cimv2/Security/MicrosoftTpm' -TimeoutSec $TimeoutSec -Warnings $null -Quiet)
    if ($tpm.Count -eq 0) {
        return New-WRASecCheck -Name 'TPM' -Status 'NotPresent' -Detail 'TPM ausente ou inacessivel.' -SubScore 0 -Severity 'Low' -Applicable $false
    }
    $t = $tpm[0]
    $en = [bool](Get-WRAProp -Object $t -Path 'IsEnabled_InitialValue' -Default $false)
    $act = [bool](Get-WRAProp -Object $t -Path 'IsActivated_InitialValue' -Default $false)
    $spec = [string](Get-WRAProp -Object $t -Path 'SpecVersion' -Default '')
    $score = if ($en -and $act) { 1.0 } elseif ($en) { 0.6 } else { 0.0 }
    $status = if ($en -and $act) { 'Enabled' } elseif ($en) { 'Partial' } else { 'Disabled' }
    $sev = if ($en) { 'Info' } else { 'Medium' }
    return New-WRASecCheck -Name 'TPM' -Status $status -Detail ('Enabled={0}; Activated={1}; Spec={2}' -f $en, $act, $spec) -SubScore $score -Severity $sev
}

function Get-WRASecSecureBoot {
    param($Warnings)
    if (-not (Get-Command -Name 'Confirm-SecureBootUEFI' -ErrorAction SilentlyContinue)) {
        return New-WRASecCheck -Name 'Secure Boot' -Status 'Unknown' -Detail 'Cmdlet indisponivel.' -SubScore 0 -Severity 'Low' -Applicable $false -Determinable $false
    }
    try {
        $r = Confirm-SecureBootUEFI -ErrorAction Stop
        $score = if ($r) { 1.0 } else { 0.0 }
        $status = if ($r) { 'Enabled' } else { 'Disabled' }
        $sev = if ($r) { 'Info' } else { 'Medium' }
        return New-WRASecCheck -Name 'Secure Boot' -Status $status -Detail ('Habilitado={0}' -f $r) -SubScore $score -Severity $sev
    }
    catch {
        return New-WRASecCheck -Name 'Secure Boot' -Status 'NotSupported' -Detail 'Plataforma legada (BIOS) ou sem suporte.' -SubScore 0 -Severity 'Low' -Applicable $false
    }
}

function Get-WRASecBitLocker {
    param([int] $TimeoutSec, $Warnings)
    $vols = @(Invoke-WRASecCim -ClassName 'Win32_EncryptableVolume' -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -TimeoutSec $TimeoutSec -Warnings $null -Quiet)
    if ($vols.Count -eq 0) {
        return New-WRASecCheck -Name 'BitLocker' -Status 'Unknown' -Detail 'Volumes criptografaveis indisponiveis (requer privilegios).' -SubScore 0 -Severity 'Low' -Applicable $false -Determinable $false
    }
    $protected = 0
    $details = New-Object System.Collections.Generic.List[object]
    foreach ($v in $vols) {
        $ps = [int](Get-WRANum -Object $v -Name 'ProtectionStatus')
        $drv = [string](Get-WRAProp -Object $v -Path 'DriveLetter' -Default '')
        if ($ps -eq 1) { $protected++ }
        [void]$details.Add([PSCustomObject]@{ Drive = $drv; ProtectionStatus = $ps })
    }
    $total = $vols.Count
    $score = 0.0
    if ($total -gt 0) { $score = [double]$protected / $total }
    $status = if ($protected -eq $total) { 'Enabled' } elseif ($protected -gt 0) { 'Partial' } else { 'Disabled' }
    $sev = if ($protected -eq $total) { 'Info' } elseif ($protected -gt 0) { 'Medium' } else { 'High' }
    $check = New-WRASecCheck -Name 'BitLocker' -Status $status -Detail ('{0}/{1} volumes protegidos.' -f $protected, $total) -SubScore $score -Severity $sev
    $check | Add-Member -NotePropertyName 'Volumes' -NotePropertyValue $details.ToArray()
    return $check
}

function Get-WRASecDeviceGuard {
    param([int] $TimeoutSec, $Warnings)
    $dg = @(Invoke-WRASecCim -ClassName 'Win32_DeviceGuard' -Namespace 'root/Microsoft/Windows/DeviceGuard' -TimeoutSec $TimeoutSec -Warnings $null -Quiet)
    $cg = New-WRASecCheck -Name 'Credential Guard' -Status 'Unknown' -Detail 'DeviceGuard indisponivel.' -SubScore 0 -Severity 'Low' -Applicable $false -Determinable $false
    $mi = New-WRASecCheck -Name 'Memory Integrity' -Status 'Unknown' -Detail 'DeviceGuard indisponivel.' -SubScore 0 -Severity 'Low' -Applicable $false -Determinable $false
    if ($dg.Count -gt 0) {
        $running = @(Get-WRAProp -Object $dg[0] -Path 'SecurityServicesRunning' -Default @())
        $cgOn = ($running -contains 1)
        $miOn = ($running -contains 2)
        $cgStatus = if ($cgOn) { 'Enabled' } else { 'Disabled' }
        $cgScore = if ($cgOn) { 1.0 } else { 0.0 }
        $cgSev = if ($cgOn) { 'Info' } else { 'Low' }
        $cg = New-WRASecCheck -Name 'Credential Guard' -Status $cgStatus -Detail ('Running={0}' -f $cgOn) -SubScore $cgScore -Severity $cgSev
        $miStatus = if ($miOn) { 'Enabled' } else { 'Disabled' }
        $miScore = if ($miOn) { 1.0 } else { 0.0 }
        $miSev = if ($miOn) { 'Info' } else { 'Medium' }
        $mi = New-WRASecCheck -Name 'Memory Integrity' -Status $miStatus -Detail ('Running={0}' -f $miOn) -SubScore $miScore -Severity $miSev
    }
    return [PSCustomObject]@{ CredentialGuard = $cg; MemoryIntegrity = $mi }
}

function Get-WRASecWindowsUpdate {
    param([int] $MaxAgeDays, [int] $TimeoutSec, $Warnings)
    $hotfixes = @(Invoke-WRASecCim -ClassName 'Win32_QuickFixEngineering' -Property @('HotFixID', 'InstalledOn') -TimeoutSec $TimeoutSec -Warnings $Warnings)
    $count = $hotfixes.Count
    $last = $null
    foreach ($h in $hotfixes) {
        $d = Get-WRAProp -Object $h -Path 'InstalledOn'
        if ($null -ne $d) {
            try {
                $dt = [datetime]$d
                if ($null -eq $last -or $dt -gt $last) { $last = $dt }
            }
            catch { }
        }
    }
    $pending = Test-WRAPendingReboot
    $ageDays = $null
    $score = 0.5
    if ($null -ne $last) {
        $ageDays = [int]((Get-Date) - $last).TotalDays
        if ($ageDays -le $MaxAgeDays) { $score = 1.0 } else { $score = 0.4 }
    }
    if ($pending) { $score = [Math]::Max(0, $score - 0.2) }
    $svc = @(Invoke-WRASecCim -ClassName 'Win32_Service' -Property @('Name', 'State', 'StartMode') -TimeoutSec $TimeoutSec -Warnings $null -Quiet | Where-Object { (Get-WRAProp -Object $_ -Path 'Name') -eq 'wuauserv' })
    $svcState = if ($svc.Count -gt 0) { [string](Get-WRAProp -Object $svc[0] -Path 'State' -Default '') } else { 'Unknown' }

    # Sem nenhum dado de hotfix nao ha como avaliar a idade das atualizacoes:
    # o estado e indeterminado (nunca "Attention" nem "Healthy" por suposicao).
    if ($count -eq 0 -and $null -eq $last) {
        $detail = ('Historico de hotfixes indisponivel; PendingReboot={0}; wuauserv={1}' -f $pending, $svcState)
        $check = New-WRASecCheck -Name 'Windows Update' -Status 'Unknown' -Detail $detail -SubScore 0 -Severity 'Low' -Applicable $false -Determinable $false
        $check | Add-Member -NotePropertyName 'PendingReboot' -NotePropertyValue $pending
        $check | Add-Member -NotePropertyName 'LastUpdateAgeDays' -NotePropertyValue $null
        return $check
    }

    $status = if ($null -ne $ageDays -and $ageDays -le $MaxAgeDays -and -not $pending) { 'Healthy' } else { 'Attention' }
    $sev = if ($status -eq 'Healthy') { 'Info' } else { 'Medium' }
    $ageText = if ($null -ne $ageDays) { $ageDays } else { 'n/d' }
    $detail = ('Hotfixes={0}; UltimoDias={1}; PendingReboot={2}; wuauserv={3}' -f $count, $ageText, $pending, $svcState)
    $check = New-WRASecCheck -Name 'Windows Update' -Status $status -Detail $detail -SubScore $score -Severity $sev
    $check | Add-Member -NotePropertyName 'PendingReboot' -NotePropertyValue $pending
    $check | Add-Member -NotePropertyName 'LastUpdateAgeDays' -NotePropertyValue $ageDays
    return $check
}

function Test-WRAPendingReboot {
    # Sinais CONFIAVEIS de reinicializacao pendente (CBS e Windows Update).
    # PendingFileRenameOperations foi intencionalmente descartado como gatilho:
    # instaladores e antivirus criam entradas transitorias com frequencia,
    # tornando-o fonte classica de falsos positivos.
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($k in $keys) { if (Test-Path -LiteralPath $k) { return $true } }
    return $false
}

function Get-WRASecEvents {
    param([int] $LookbackHours, $Warnings)
    $result = [PSCustomObject]@{ Critical = 0; Error = 0 }
    try {
        $start = (Get-Date).AddHours(-1 * $LookbackHours)
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = @(1, 2); StartTime = $start } -MaxEvents 500 -ErrorAction Stop)
        $c = 0; $e = 0
        foreach ($ev in $events) {
            $lvl = [int](Get-WRANum -Object $ev -Name 'Level')
            if ($lvl -eq 1) { $c++ } elseif ($lvl -eq 2) { $e++ }
        }
        $result = [PSCustomObject]@{ Critical = $c; Error = $e }
    }
    catch {
        if ($null -ne $Warnings) { [void]$Warnings.Add(("Falha ao consultar eventos do sistema: {0}" -f $_.Exception.Message)) }
    }
    return $result
}

# ----------------------------------------------------------- Operacao

function Invoke-WRASecurityAudit {
    [CmdletBinding()]
    param([Parameter()] $Context)

    $warnings = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]
    $config = Get-WRAProp -Object $Context -Path 'Config'

    $cimTimeout = [int](Get-WRAProp -Object $config -Path 'Timeouts.CimSeconds' -Default 30)
    $updMaxAge = [int](Get-WRAProp -Object $config -Path 'Modules.Security.UpdateMaxAgeDays' -Default 35)
    $evHours = [int](Get-WRAProp -Object $config -Path 'Modules.Security.EventsLookbackHours' -Default 24)

    $checks = New-Object System.Collections.Generic.List[object]
    $recs = New-Object System.Collections.Generic.List[object]
    $weighted = @{ }

    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckDefender' -Default $true)) {
        $c = Get-WRASecDefender -TimeoutSec $cimTimeout -Warnings $warnings
        [void]$checks.Add($c); $weighted['Defender'] = $c
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'Defender' -Severity $c.Severity -Finding 'Protecao do Microsoft Defender incompleta.' -Recommendation 'Habilite o Antivirus e a Protecao em Tempo Real do Microsoft Defender.' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckFirewall' -Default $true)) {
        $c = Get-WRASecFirewall -Warnings $warnings
        [void]$checks.Add($c); $weighted['Firewall'] = $c
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'Firewall' -Severity $c.Severity -Finding 'Um ou mais perfis de firewall estao desabilitados.' -Recommendation 'Habilite o Windows Firewall em todos os perfis (Dominio, Privado e Publico).' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckSmartScreen' -Default $true)) {
        $c = Get-WRASecSmartScreen -Warnings $warnings
        [void]$checks.Add($c)
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'SmartScreen' -Severity $c.Severity -Finding 'SmartScreen desabilitado.' -Recommendation 'Habilite o SmartScreen para protecao contra aplicativos e arquivos maliciosos.' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckUac' -Default $true)) {
        $c = Get-WRASecUac -Warnings $warnings
        [void]$checks.Add($c); $weighted['Uac'] = $c
        if ($c.SubScore -lt 1) { Add-WRARec -List $recs -Area 'UAC' -Severity $c.Severity -Finding 'UAC desabilitado.' -Recommendation 'Reabilite o Controle de Conta de Usuario (EnableLUA=1).' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckTpm' -Default $true)) {
        $c = Get-WRASecTpm -TimeoutSec $cimTimeout -Warnings $warnings
        [void]$checks.Add($c)
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'TPM' -Severity $c.Severity -Finding 'TPM nao totalmente habilitado.' -Recommendation 'Habilite e ative o TPM no firmware (UEFI) se aplicavel.' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckSecureBoot' -Default $true)) {
        $c = Get-WRASecSecureBoot -Warnings $warnings
        [void]$checks.Add($c); $weighted['SecureBoot'] = $c
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'Secure Boot' -Severity $c.Severity -Finding 'Secure Boot desabilitado.' -Recommendation 'Habilite o Secure Boot no firmware UEFI.' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckBitLocker' -Default $true)) {
        $c = Get-WRASecBitLocker -TimeoutSec $cimTimeout -Warnings $warnings
        [void]$checks.Add($c); $weighted['BitLocker'] = $c
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'BitLocker' -Severity $c.Severity -Finding 'Volumes sem protecao BitLocker.' -Recommendation 'Considere habilitar o BitLocker nos volumes nao criptografados.' }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckCredentialGuard' -Default $true) -or [bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckMemoryIntegrity' -Default $true)) {
        $dg = Get-WRASecDeviceGuard -TimeoutSec $cimTimeout -Warnings $warnings
        if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckCredentialGuard' -Default $true)) {
            [void]$checks.Add($dg.CredentialGuard)
            if ($dg.CredentialGuard.SubScore -lt 1 -and $dg.CredentialGuard.Applicable) { Add-WRARec -List $recs -Area 'Credential Guard' -Severity $dg.CredentialGuard.Severity -Finding 'Credential Guard inativo.' -Recommendation 'Avalie habilitar o Credential Guard (VBS) conforme a politica corporativa.' }
        }
        if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckMemoryIntegrity' -Default $true)) {
            [void]$checks.Add($dg.MemoryIntegrity)
            if ($dg.MemoryIntegrity.SubScore -lt 1 -and $dg.MemoryIntegrity.Applicable) { Add-WRARec -List $recs -Area 'Memory Integrity' -Severity $dg.MemoryIntegrity.Severity -Finding 'Integridade de Memoria (HVCI) inativa.' -Recommendation 'Habilite a Integridade de Memoria em Isolamento de Nucleo, se compativel.' }
        }
    }
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckWindowsUpdate' -Default $true)) {
        $c = Get-WRASecWindowsUpdate -MaxAgeDays $updMaxAge -TimeoutSec $cimTimeout -Warnings $warnings
        [void]$checks.Add($c); $weighted['WindowsUpdate'] = $c
        if ($c.SubScore -lt 1 -and $c.Applicable) { Add-WRARec -List $recs -Area 'Windows Update' -Severity $c.Severity -Finding 'Atualizacoes desatualizadas ou reinicializacao pendente.' -Recommendation 'Instale as atualizacoes pendentes e reinicie se necessario.' }
    }

    $events = $null
    if ([bool](Get-WRAProp -Object $config -Path 'Modules.Security.CheckEvents' -Default $true)) {
        $events = Get-WRASecEvents -LookbackHours $evHours -Warnings $warnings
        $critCount = [int](Get-WRAProp -Object $events -Path 'Critical' -Default 0)
        if ($critCount -gt 0) { Add-WRARec -List $recs -Area 'Eventos' -Severity 'Medium' -Finding ('{0} eventos criticos recentes no log do Sistema.' -f $critCount) -Recommendation 'Investigue os eventos criticos recentes do sistema.' }
    }

    # ----- Controles-chave nao verificaveis -----
    # Sinaliza (como recomendacao) os controles de seguranca essenciais cujo
    # estado nao pode ser determinado, para que sejam verificados manualmente.
    $keyControls = @('Defender', 'Firewall', 'WindowsUpdate', 'BitLocker', 'SecureBoot', 'Uac')
    foreach ($k in $keyControls) {
        if ($weighted.ContainsKey($k)) {
            $chk = $weighted[$k]
            $determinable = [bool](Get-WRAProp -Object $chk -Path 'Determinable' -Default $true)
            if (-not $chk.Applicable -and -not $determinable) {
                Add-WRARec -List $recs -Area $chk.Name -Severity 'Low' `
                    -Finding ('Nao foi possivel determinar o estado de: {0}.' -f $chk.Name) `
                    -Recommendation 'Execute como Administrador para verificar este controle; ate la, considere-o nao confirmado.'
            }
        }
    }

    $data = [PSCustomObject]@{
        Checks          = $checks.ToArray()
        Recommendations = $recs.ToArray()
        Events          = $events
    }

    return New-WRAModulePayload -Data $data -Warnings $warnings.ToArray() -Errors $errors.ToArray()
}

# ----------------------------------------------------------- Auto-registro

$WRASecManifest = $null
if (Get-Command -Name 'New-WRAModuleManifest' -ErrorAction SilentlyContinue) {
    $ops = @(
        (New-WRAOperation -Name 'Audit' -Handler 'Invoke-WRASecurityAudit' -RequiresElevation `
            -Description 'Auditoria de postura de seguranca com Security/Risk/Health Score e recomendacoes.')
    )
    $WRASecManifest = New-WRAModuleManifest -Module 'Security' -Operations $ops -RequiresElevation `
        -Version '1.1.0' -Description 'Auditoria de seguranca somente leitura (nunca altera configuracoes).'
}
if ($null -ne $WRASecManifest -and (Get-Command -Name 'Register-WRAModule' -ErrorAction SilentlyContinue)) {
    [void](Register-WRAModule -Manifest $WRASecManifest)
}

Export-ModuleMember -Function @('Invoke-WRASecurityAudit')
