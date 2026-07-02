#Requires -Version 4.0
# Desenvolvido por Edsilas
# ============================================================================
#  Windows Resource Auditor
#  Modulo  : RunspaceManager.psm1
#  Versao  : 4.1.0
#  Camada  : 1 - Infraestrutura
#
#  Responsabilidade unica:
#    Executar um mapeamento paralelo sobre uma colecao usando um pool de
#    runspaces (preferido a Jobs). Destinado ao paralelismo INTERNO dos modulos
#    onde ha ganho real (ex.: hashes/assinaturas de muitos arquivos).
#
#  Exposto:
#    Invoke-WRAParallel -Items -ScriptBlock [-Common] [-ImportModules]
#                       [-ThrottleLimit] [-TimeoutSeconds]
#
#  Retorno: array de objetos { Item; Output; HadErrors; Errors }, na mesma
#  ordem dos itens de entrada.
# ============================================================================

Set-StrictMode -Version 2.0

function Invoke-WRAParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]] $Items,
        [Parameter(Mandatory = $true)][scriptblock] $ScriptBlock,
        [Parameter()] $Common = $null,
        [Parameter()][string[]] $ImportModules = @(),
        [Parameter()][int] $ThrottleLimit = 4,
        [Parameter()][int] $TimeoutSeconds = 300
    )

    $results = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Items -or @($Items).Count -eq 0) { return , $results.ToArray() }
    if ($ThrottleLimit -lt 1) { $ThrottleLimit = 1 }

    $sbText = $ScriptBlock.ToString()
    $importList = @($ImportModules)

    # Wrapper executado em cada runspace: importa modulos necessarios e invoca
    # o scriptblock do usuario (recriado no runspace de destino).
    $wrapper = @'
param($__Item, $__Common, $__Imports, $__Sb)
foreach ($__m in @($__Imports)) {
    if ($__m -and (Test-Path -LiteralPath $__m)) {
        try { Import-Module -Name $__m -Force -DisableNameChecking -ErrorAction SilentlyContinue } catch { }
    }
}
$__block = [scriptblock]::Create($__Sb)
& $__block $__Item $__Common
'@

    $pool = $null
    try {
        # InitialSessionState completo: garante que os cmdlets nativos usados pelos
        # scriptblocks (ex.: Get-FileHash/Utility, Get-AuthenticodeSignature/Security,
        # Get-Item/Management) estejam disponiveis em cada runspace. Sem isto, o pool
        # carrega apenas Microsoft.PowerShell.Core e esses cmdlets ficam ausentes,
        # fazendo a computacao paralela falhar silenciosamente. Fallback preserva o
        # comportamento anterior caso a criacao do ISS nao seja suportada.
        $iss = $null
        try { $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault() } catch { $iss = $null }
        if ($null -ne $iss) { $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host) }
        else { $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit) }
        $pool.Open()

        $jobs = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Items) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($wrapper)
            [void]$ps.AddParameter('__Item', $item)
            [void]$ps.AddParameter('__Common', $Common)
            [void]$ps.AddParameter('__Imports', $importList)
            [void]$ps.AddParameter('__Sb', $sbText)
            $handle = $ps.BeginInvoke()
            [void]$jobs.Add([PSCustomObject]@{ PS = $ps; Handle = $handle; Item = $item })
        }

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        foreach ($job in $jobs) {
            $output = $null
            $hadErr = $false
            $errs = @()
            try {
                $remainingMs = ($deadline - (Get-Date)).TotalMilliseconds
                if ($remainingMs -lt 0) { $remainingMs = 0 }
                if ($remainingMs -gt [int]::MaxValue) { $remainingMs = [int]::MaxValue }
                $completed = $job.Handle.AsyncWaitHandle.WaitOne([int]$remainingMs)
                if ($completed) {
                    $output = $job.PS.EndInvoke($job.Handle)
                    if ($job.PS.HadErrors) {
                        $hadErr = $true
                        foreach ($e in $job.PS.Streams.Error) { $errs += $e }
                    }
                }
                else {
                    $hadErr = $true
                    $errs += ('Timeout apos {0} s' -f $TimeoutSeconds)
                    try { $job.PS.Stop() } catch { }
                }
            }
            catch {
                $hadErr = $true
                $errs += $_
            }
            finally {
                try { $job.PS.Dispose() } catch { }
            }
            [void]$results.Add([PSCustomObject]@{
                Item      = $job.Item
                Output    = $output
                HadErrors = $hadErr
                Errors    = $errs
            })
        }
    }
    catch {
        # Fail Safe: retorna o que foi coletado ate o erro.
    }
    finally {
        if ($null -ne $pool) {
            try { $pool.Close(); $pool.Dispose() } catch { }
        }
    }

    return , $results.ToArray()
}

Export-ModuleMember -Function @('Invoke-WRAParallel')
