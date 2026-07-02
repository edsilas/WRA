# Windows Resource Auditor v4.1.0 — Otimização

Esta etapa consolida as decisões de desempenho da suíte e introduz as
otimizações de maior impacto, mantendo o princípio do *Fail Safe*: toda
otimização degrada com segurança para o caminho não otimizado quando o recurso
não está disponível.

## Metas do contrato

- Uso de CPU em ociosidade do modo de vigilância: **< 1%**.
- Pegada de memória: **< 150 MB**.
- Coleta sem dependências externas, priorizando CIM.

## 1. Sessão CIM compartilhada (nova)

A coleta executa dezenas de consultas WMI/CIM por execução (Monitor, Network,
Security, Inventory, ProcessAnalyzer e o laço de Triggers). Sem otimização, cada
`Get-CimInstance` paga o custo de estabelecer a conexão local.

O módulo `CimManager.psm1` cria **uma única sessão CIM** no início da coleta
(`Initialize-WRACimSession`), reutilizada por todos os módulos, e a encerra no
shutdown (`Close-WRACimSession`). Todos os seis invólucros CIM dos módulos foram
adaptados de forma uniforme para anexar `-CimSession` quando a sessão existe:

```powershell
if (Get-Command -Name 'Get-WRACimSession' -ErrorAction SilentlyContinue) {
    $__cs = Get-WRACimSession
    if ($null -ne $__cs) { $params['CimSession'] = $__cs }
}
```

Verificou-se que **100% do tráfego CIM** passa por esses invólucros (não há
nenhuma chamada `Get-CimInstance` avulsa), então a otimização cobre toda a
coleta. O protocolo padrão é **DCOM** (`Performance.CimProtocol`), evitando
dependência de WinRM e respeitando a restrição de operação puramente local. Se a
sessão não puder ser criada, `Get-WRACimSession` retorna nulo e cada invólucro
recai no `Get-CimInstance` direto — sem falha.

No modo `-Watch`, a sessão vive por todo o processo de longa duração, eliminando
reconexões a cada ciclo de *polling* — o principal contribuinte para manter a
CPU em ociosidade abaixo de 1%.

## 2. Memoização com TTL (nova)

`CimManager.psm1` também expõe um cache em memória com expiração
(`Get-WRACacheValue`/`Set-WRACacheValue`/`Clear-WRACache`, TTL padrão de
`Performance.CacheTtlSeconds`). Destina-se a dados estáveis consultados mais de
uma vez na mesma execução, complementando o cache em disco de assinaturas do
ProcessAnalyzer (que sobrevive entre execuções).

## 3. Otimizações já incorporadas nas etapas anteriores

- **CIM em vez de WMI clássico**: classes `Win32_PerfFormattedData_*` em vez de
  `Get-Counter` (que sofre com nomes de contadores localizados) e em vez do WMI
  legado, mais lento.
- **Projeção de propriedades**: as consultas pedem apenas as colunas necessárias
  via `-Property`, reduzindo o *marshaling*.
- **`Win32_Product` evitado**: o inventário de programas lê as chaves de
  desinstalação do Registro (somente leitura), evitando o custoso *self-repair*
  do MSI disparado por `Win32_Product`.
- **`DISM` evitado** para recursos do Windows: usa `Win32_OptionalFeature`/
  `Win32_ServerFeature`.
- **Hashing paralelo**: o cálculo de SHA-256 e a verificação de assinatura no
  ProcessAnalyzer usam o pool de *runspaces* (`Invoke-WRAParallel`), limitado por
  `General.MaxParallelism`.
- **Janela de amostragem única**: o Monitor compartilha uma única janela de
  amostragem entre CPU, disco e rede em vez de medir cada um separadamente.
- **Cache de assinaturas em disco** com invalidação por tamanho/data/TTL.
- **Instância única** por mutex: evita auditorias concorrentes que dobrariam o
  consumo de recursos.

## 4. Controles de configuração (sem valores mágicos)

Nova seção `Performance` no `Config.json` (espelhada no schema):

| Chave | Padrão | Efeito |
|---|---|---|
| `UseSharedCimSession` | `true` | Liga/desliga a sessão CIM compartilhada |
| `CimProtocol` | `Dcom` | Protocolo da sessão (`Dcom` ou `Wsman`) |
| `CacheTtlSeconds` | `300` | TTL padrão da memoização em memória |

Parâmetros relacionados já existentes: `General.MaxParallelism`,
`General.PreferRunspaces`, `Cache.*`, `Timeouts.CimSeconds`.

## 5. Como as metas são atendidas

- **< 1% em ociosidade**: o laço de Triggers faz poucas consultas CIM por ciclo
  (intervalo configurável, padrão 15 s) sobre uma sessão reutilizada, com
  `Start-Sleep` entre ciclos — sem espera ativa.
- **< 150 MB**: nenhuma biblioteca externa é carregada; os conjuntos de dados são
  projetados (apenas colunas necessárias) e os relatórios são gravados em disco
  em vez de mantidos integralmente em memória; *runspaces* são fechados após o
  uso. O modo de vigilância não acumula histórico em memória entre disparos.

A validação final em host real (Etapa 19) deve confirmar essas medidas com a
suíte de testes (Etapa 16) e medição de tempos por fase, já registrados pelo
Core no log de cada operação.
