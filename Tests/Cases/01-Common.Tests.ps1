# Desenvolvido por Edsilas
# Testes: Modules/Contracts/Common.psm1
Describe 'Common' {

    It 'Get-WRAProp le caminho pontuado em PSCustomObject' {
        $o = [pscustomobject]@{ A = [pscustomobject]@{ B = [pscustomobject]@{ C = 42 } } }
        Assert-Equal 42 (Get-WRAProp -Object $o -Path 'A.B.C')
    }

    It 'Get-WRAProp le caminho pontuado em hashtable' {
        $o = @{ A = @{ B = 'x' } }
        Assert-Equal 'x' (Get-WRAProp -Object $o -Path 'A.B')
    }

    It 'Get-WRAProp retorna default quando ausente' {
        $o = [pscustomobject]@{ A = 1 }
        Assert-Equal 'def' (Get-WRAProp -Object $o -Path 'A.Z.Y' -Default 'def')
    }

    It 'Get-WRAProp nao lanca em objeto nulo' {
        Assert-NotThrows { [void](Get-WRAProp -Object $null -Path 'A.B' -Default $null) }
    }

    It 'Get-WRANum coage string numerica' {
        $o = [pscustomobject]@{ N = '12.5' }
        Assert-Equal 12.5 (Get-WRANum -Object $o -Name 'N')
    }

    It 'Get-WRANum retorna 0 para ausente' {
        $o = [pscustomobject]@{ }
        Assert-Equal 0 (Get-WRANum -Object $o -Name 'X')
    }

    It 'ConvertTo-WRAArray envolve escalar' {
        $a = ConvertTo-WRAArray -InputObject 'solo'
        Assert-True ($a -is [System.Array]) 'deveria ser array'
        Assert-Equal 1 $a.Count
    }

    It 'Test-WRAPayload reconhece payload e rejeita objeto comum' {
        $p = New-WRAModulePayload -Data @{ k = 1 }
        Assert-True (Test-WRAPayload -Object $p) 'payload valido'
        Assert-False (Test-WRAPayload -Object ([pscustomobject]@{ Data = 1 })) 'objeto comum nao e payload'
    }
}
