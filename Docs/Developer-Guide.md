# Windows Resource Auditor v4.1.0 — Guia do Desenvolvedor

## Arquitetura

Quatro camadas, com dependências apenas para dentro:

```
Launcher (bootstrap) → Core (orquestrador) → Domínio (módulos) → Apresentação (dashboard)
                                    ↑ Infraestrutura (config, log, dispatcher, ...)
```

- **Launcher.bat** — seleciona o host PowerShell, valida arquitetura/versão,
  eleva uma vez quando necessário e repassa argumentos.
- **Core.ps1** — *composition root*: detecta capacidades em runtime, importa a
  infraestrutura, inicializa configuração/log/framework, executa o pipeline e
  encerra. Degrada graciosamente conforme os subsistemas presentes.
- **Infraestrutura** — Configuração, Log, Dispatcher, RunspaceManager,
  CimManager, Scoring, Reporting, Scheduler, Triggers.
- **Domínio** — Monitor, ProcessAnalyzer, Network, Security, Inventory.
- **Apresentação** — Reporting + Templates/Assets geram o dashboard offline.

Os módulos **nunca chamam uns aos outros**; toda coordenação passa pelo Core
(padrão Mediator). A comunicação usa o **envelope universal**.

## Contratos

### Envelope de resultado (`New-WRAResult`)

`Success`, `Module`, `Operation`, `Duration`, `Timestamp`, `ComputerName`,
`Data`, `Warnings`, `Errors`.

### Payload de módulo (`New-WRAModulePayload`)

`{ __WRAPayload = $true; Data; Warnings; Errors }`. O Dispatcher reconhece o
marcador e compõe o envelope com tempo, log e contagens.

### Handler de operação

```powershell
function Invoke-WRAExampleCollect {
    param($Context)
    # $Context expõe: ComputerName, Elevated, Config, Root, Paths
    $cfg = Get-WRAProp -Object $Context -Path 'Config'
    # ... coleta somente leitura ...
    return New-WRAModulePayload -Data $data -Warnings $warnings -Errors $errors
}
```

## Adicionando um módulo de domínio

1. Crie `Modules\Domain\Example.psm1`.
2. No topo do módulo (no import), auto-registre-se:

```powershell
$manifest = New-WRAModuleManifest -Module 'Example' -Operations @(
    New-WRAOperation -Name 'Collect' -Handler 'Invoke-WRAExampleCollect'
) -Description 'Exemplo'
[void](Register-WRAModule -Manifest $manifest)
```

3. Implemente o handler retornando `New-WRAModulePayload`.
4. Exporte o handler com `Export-ModuleMember`.
5. Adicione `Example` em `Modules.Enabled` e, se houver opções, um bloco
   `Modules.Example.*` no `Config.json` **e** no `Config.schema.json`.
6. Acrescente um caso em `Tests\Cases\`.

O Dispatcher descobre o arquivo, o importa com `-Global` (tornando os contratos
visíveis ao auto-registro) e passa a despachá-lo.

## Configuração

- **Toda** configuração operacional vive em `Config\Config.json`. Nenhum valor
  mágico em código.
- `Config.schema.json` carrega tipos, limites e **defaults**; a configuração do
  usuário é mesclada sobre os defaults (deep-merge). Acesso por
  `Get-WRAConfigValue -Path 'A.B.C' -Default <valor>`.
- Veja [`Configuration-Reference.md`](Configuration-Reference.md).

## Convenções

- Funções com prefixo `WRA` (públicas) / `Core` (privadas do Core).
- `Set-StrictMode -Version 2.0` em todos os módulos; acesso seguro a
  propriedades via `Get-WRAProp`/`Get-WRANum`.
- Subconjunto de sintaxe compatível com PS 4.0 (sem `?:`, `??`, `?.`,
  `-Parallel`). Detecção de recursos antes de usar APIs modernas.
- `.ps1`/`.psm1` em UTF-8; logs e dados sem BOM.
- Coleta sempre **somente leitura**; correções são recomendações.

## Concorrência

`RunspaceManager.psm1` (`Invoke-WRAParallel`) provê um *map* paralelo por pool de
runspaces para fan-out **interno** de um módulo (ex.: hashing no
ProcessAnalyzer), com import por runspace, timeout e resultados ordenados.
Limite por `General.MaxParallelism`.

## Otimização

`CimManager.psm1` mantém uma sessão CIM compartilhada (reutilizada por todos os
invólucros CIM dos módulos) e um cache de memoização com TTL. Veja
[`17-Otimizacao.md`](17-Otimizacao.md).

## Testes

Runner nativo, sem Pester/Gallery:

```bat
powershell -ExecutionPolicy Bypass -File Tests\Invoke-Tests.ps1
powershell -File Tests\Invoke-Tests.ps1 -Filter Scheduler -Plain
```

- `WRATest.psm1` — `Describe`/`It`, asserts, `Invoke-InModule` (acesso a
  internos), sumário e código de saída = nº de falhas.
- `Tests\Cases\*.Tests.ps1` — contratos, configuração, log, dispatcher, scoring,
  scheduler (XML), triggers, reporting (fim-a-fim) e integração ao vivo
  (protegida por verificação de Windows).

## Códigos de saída

Veja [`Troubleshooting.md`](Troubleshooting.md).
