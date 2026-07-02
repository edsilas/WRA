# Windows Resource Auditor v4.1.0 — Referência de Módulos

Cada módulo de domínio expõe uma operação e devolve um **payload**
(`New-WRAModulePayload`) que o Dispatcher encapsula no **envelope universal**
(`New-WRAResult`): `Success`, `Module`, `Operation`, `Duration`, `Timestamp`,
`ComputerName`, `Data`, `Warnings`, `Errors`.

Todos os módulos são **somente leitura** e seguem a prioridade de fontes
CIM › Win32 API › Performance Counters › ETW › Event Log › Registro › WMI.

---

## Monitor — `Monitor.Collect`

Coleta o estado de recursos em tempo quase real, usando uma única janela de
amostragem compartilhada entre CPU, disco e rede.

- **Coleta**: CPU (média e por núcleo), memória, GPU (gracioso se ausente),
  discos e I/O, rede e throughput, processos de maior consumo (CPU e memória),
  serviços (automáticos não em execução) e eventos críticos/erro recentes.
- **Fontes**: classes `Win32_PerfFormattedData_*` (evita nomes de contadores
  localizados do `Get-Counter`), `Win32_OperatingSystem`, Event Log.
- **Status de limites**: OK/Warning/Critical a partir de `Thresholds.*`.
- **Config**: `Modules.Monitor.*` (intervalo e duração de amostragem, top N,
  GPU, serviços, eventos, máximos).
- **Elevação**: não obrigatória (alguns eventos podem ser parciais sem ela).

## ProcessAnalyzer — `ProcessAnalyzer.Analyze`

Auditoria detalhada de processos e sua proveniência.

- **Coleta**: identidade, relação pai/filho, proprietário, linha de comando,
  threads/handles/working set, empresa/produto/versão do binário, **SHA-256** e
  estado da **assinatura Authenticode**, serviços relacionados, correlação com
  inicialização e sinalizações (flags) de anomalia.
- **Desempenho**: hash e verificação de assinatura em paralelo
  (`Invoke-WRAParallel`, limitado por `General.MaxParallelism`); cache de
  assinaturas em disco (`Cache\signatures\`) invalidado por tamanho/data/TTL.
- **Config**: `Modules.ProcessAnalyzer.*` (resolver proprietário, correlacionar
  inicialização, hashing paralelo, tamanho máximo de arquivo para hash).
- **Elevação**: recomendada para acessar metadados de processos de outros
  usuários (degrada com aviso).

## Network — `Network.Audit`

Auditoria completa da pilha de rede, **sem captura de pacotes**.

- **Regra de segurança**: nunca captura conteúdo de pacotes; o sinalizador
  `CapturePacketContent` é ignorado e gera aviso se verdadeiro.
- **Coleta**: conexões TCP/UDP **correlacionadas a processo/PID/porta/estado/
  serviços/interface** (via `Get-NetTCPConnection`/`Get-NetUDPEndpoint`, com
  fallback para `netstat -ano` usando tokens não localizados); interfaces,
  rotas, compartilhamentos, sessões, proxy (Registro, leitura), perfis de
  firewall, VPN (heurística) e switches Hyper-V.
- **Config**: `Modules.Network.*` (incluir conexões, sessões, VPN, switches
  Hyper-V, máximo de conexões).
- **Elevação**: recomendada para detalhes completos de propriedade de conexões.

## Security — `Security.Audit` (requer elevação)

Avaliação de postura de segurança, estritamente de leitura.

- **Verificações** (11): Defender (`MSFT_MpComputerStatus`), Firewall,
  SmartScreen, UAC, TPM (`Win32_Tpm`), Secure Boot
  (`Confirm-SecureBootUEFI`, protegido), BitLocker
  (`Win32_EncryptableVolume`), Credential Guard e Memory Integrity
  (`Win32_DeviceGuard`), Windows Update (QFE + reinício pendente) e eventos.
- **Pontuação justa**: cada verificação tem um sinalizador `Applicable`;
  verificações não aplicáveis são **excluídas do denominador** do Security Score
  (sem penalidade indevida).
- **Saídas**: `SecurityScore` (ponderado), `RiskScore` (pontos por severidade,
  com teto) e recomendações — **apenas recomendações, nunca correção
  automática**.
- **Config**: `Modules.Security.*` (verificar eventos, idade máxima de updates,
  janela de eventos).

## Inventory — `Inventory.Collect`

Inventário de hardware e software.

- **Coleta**: hardware (CPU/RAM/GPU/firmware), armazenamento e controladores,
  SO e licenciamento (`SoftwareLicensingProduct`), programas instalados (lidos
  das chaves de **desinstalação do Registro** — evita o `self-repair` do
  `Win32_Product`), recursos do Windows (`Win32_OptionalFeature`/
  `Win32_ServerFeature` — evita `DISM`), impressoras e adaptadores de rede.
- **Config**: `Modules.Inventory.*` (incluir recursos, controladores,
  adaptadores).
- **Elevação**: não obrigatória.

---

## Indicadores (Scoring)

O `Scoring.psm1` compõe os indicadores globais a partir de todos os envelopes,
renormalizando os pesos quando um módulo está ausente:

- **Performance** — de Monitor (utilização de CPU/memória/disco; menor uso =
  melhor), ponderado por `Scoring.Performance.Weights`.
- **Security** / **Risk** — diretamente do módulo Security.
- **Reliability** — derivado da contagem de eventos críticos/erro.
- **Health** — mistura ponderada de Performance, Security e Reliability
  (`Scoring.Health.Weights`).

## Como adicionar um módulo

Veja [`Developer-Guide.md`](Developer-Guide.md): basta criar um `.psm1` em
`Modules\Domain\` que se auto-registra via `Register-WRAModule` com um manifesto
e expõe um handler `function <Handler> { param($Context) ... }` retornando
`New-WRAModulePayload`.
