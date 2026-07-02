# Windows Resource Auditor — Arquitetura Geral

**Projeto:** Windows Resource Auditor
**Versão:** 4.1.0
**Etapa:** 1 de 20 — Arquitetura Geral
**Documento de referência (`\Docs\01-Arquitetura-Geral.md`)**

---

## 1. Visão e princípios fundadores

O Windows Resource Auditor (WRA) é uma suíte **read-only** de auditoria, monitoramento, inventário, diagnóstico e correlação de eventos para Windows Cliente e Server. A arquitetura é orientada por três invariantes que **nunca** são violadas:

1. **Inviolabilidade do sistema operacional.** O WRA observa, mede, correlaciona e recomenda. Ele **nunca** altera estado do SO (Registro, Firewall, Defender, Serviços, Drivers, GPO, BitLocker, TPM, Secure Boot, arquivos de sistema). Ações corretivas existem apenas como *recomendações* ou como execução *manual explicitamente autorizada* pelo operador.
2. **Comunicação centralizada.** Módulos **nunca** se comunicam diretamente. Toda interação ocorre através do Core, que atua como mediador/orquestrador. Isso garante baixo acoplamento e torna cada módulo substituível.
3. **Contrato único de resultado.** Todo módulo retorna o mesmo envelope de objeto estruturado, tornando orquestração, logging, relatórios e dashboard agnósticos quanto à origem dos dados.

Princípios de engenharia aplicados de forma contínua: SOLID, DRY, KISS, Clean Architecture, Separation of Concerns, Defensive Programming, Fail Fast (na inicialização) + Fail Safe (em execução), Idempotência, Alta Coesão e Baixo Acoplamento.

---

## 2. Modelo em camadas

O WRA é organizado em quatro camadas com dependências sempre apontando "para dentro" (Clean Architecture). Camadas externas conhecem as internas; o inverso nunca acontece.

```
┌──────────────────────────────────────────────────────────────────────┐
│  CAMADA 0 — BOOTSTRAP (Batch)                                          │
│  Launcher.bat                                                          │
│   • Detecta privilégios, valida ambiente mínimo, escolhe o host        │
│     PowerShell adequado e entrega o controle ao Core. Nada de lógica   │
│     de negócio aqui.                                                    │
└───────────────┬──────────────────────────────────────────────────────┘
                │ invoca
┌───────────────▼──────────────────────────────────────────────────────┐
│  CAMADA 1 — ORQUESTRAÇÃO (Core.ps1)                                    │
│   • Configuração   • Logger      • Registro/descoberta de módulos      │
│   • Dispatcher     • Eventos     • Scheduler   • Triggers              │
│   • Pipeline de relatórios       • Pool de runspaces                   │
│  Único ponto que conhece TODOS os módulos. Ninguém conhece o Core      │
│  exceto através de contratos.                                          │
└───────────────┬──────────────────────────────────────────────────────┘
                │ carrega dinamicamente e invoca via contrato
┌───────────────▼──────────────────────────────────────────────────────┐
│  CAMADA 2 — MÓDULOS DE DOMÍNIO (\Modules)                              │
│   Monitor · Process Analyzer · Network · Security · Inventory          │
│   Cada módulo: responsabilidade única, sem conhecimento dos demais.    │
│   Recebe Config + serviços de infraestrutura (Logger) por injeção.     │
└───────────────┬──────────────────────────────────────────────────────┘
                │ produz dados normalizados (JSON)
┌───────────────▼──────────────────────────────────────────────────────┐
│  CAMADA 3 — APRESENTAÇÃO (\Reports + Dashboard)                        │
│   Dashboard HTML5/CSS3/JS ES2022 autocontido. Consome o JSON           │
│   produzido pelo Core. Zero dependência de framework, zero rede.       │
└──────────────────────────────────────────────────────────────────────┘
```

**Regra de dependência:** o Dashboard depende do formato de dados, os Módulos dependem dos contratos de infraestrutura, o Core depende das interfaces dos módulos, o Launcher depende apenas da existência do Core. Nenhuma seta aponta para fora.

---

## 3. Contrato universal de resultado

Todo módulo (e toda operação dentro de um módulo) retorna **obrigatoriamente** este envelope. Ele é a fronteira de integração de todo o sistema.

| Campo          | Tipo               | Significado                                                        |
|----------------|--------------------|-------------------------------------------------------------------|
| `Success`      | `[bool]`           | A operação concluiu sem erros não tratados.                       |
| `Module`       | `[string]`         | Nome do módulo emissor (ex.: `Network`).                          |
| `Operation`    | `[string]`         | Operação executada (ex.: `Get-TcpConnections`).                  |
| `Duration`     | `[timespan]`/`ms`  | Tempo de execução medido pelo Core.                              |
| `Timestamp`    | `[datetime]` (UTC) | Instante de conclusão, padronizado em ISO 8601.                  |
| `ComputerName` | `[string]`         | Host auditado.                                                    |
| `Data`         | `[object]`         | Carga normalizada, sempre serializável em JSON.                 |
| `Warnings`     | `[object[]]`       | Avisos não fatais (ex.: contador indisponível, sem elevação).   |
| `Errors`       | `[object[]]`       | Erros tratados, cada um com mensagem, categoria e stack trace.  |

O Core é quem cronometra `Duration` e carimba `Timestamp`/`ComputerName`, garantindo consistência mesmo que um módulo se esqueça. Esse envelope é o que alimenta, sem transformação adicional, o Logger, o pipeline de relatórios e o Dashboard.

---

## 4. Modelo de comunicação (Mediator + Dispatcher)

```
   Operador / Scheduler / Trigger
              │
              ▼
        ┌───────────┐     1. resolve operação → módulo
        │   CORE    │     2. injeta Config + Logger
        │ Dispatcher│     3. cronometra execução
        └─────┬─────┘     4. captura envelope
              │           5. encaminha p/ Log + Report
   ┌──────────┼──────────┬──────────┬──────────┐
   ▼          ▼          ▼          ▼          ▼
 Monitor   Process    Network   Security   Inventory
           Analyzer
```

- O Core mantém um **registro de capacidades**: cada módulo declara quais operações expõe. O Dispatcher resolve `Module.Operation` para a função correta sem `if/switch` gigantes (Open/Closed: novos módulos não exigem alterar o Core).
- Quando o Network precisa correlacionar uma porta a um PID e a um processo, ele **não chama** o Process Analyzer. Ele emite seus próprios dados; a **correlação** é feita por um estágio de correlação no Core/Report, que cruza os envelopes. Isso preserva responsabilidade única.
- Eventos internos (ex.: "auditoria concluída", "limite excedido") trafegam por um barramento de eventos simples dentro do Core, do qual o Scheduler e os Triggers são assinantes.

---

## 5. Ciclo de vida dos módulos (carregamento dinâmico)

1. **Descoberta:** o Core varre `\Modules` e localiza os arquivos de módulo.
2. **Validação de contrato:** cada módulo precisa expor uma função de manifesto (nome, versão, operações, requisitos de privilégio). Módulos que não cumprem o contrato são rejeitados com aviso — o restante da suíte continua (Fail Safe).
3. **Registro:** as operações declaradas entram no registro do Dispatcher.
4. **Injeção de dependências:** no momento da invocação, o Core injeta a configuração já resolvida e o Logger. O módulo nunca lê `Config.json` diretamente nem instancia seu próprio logger (DRY + testabilidade).
5. **Execução isolada:** falha de um módulo é capturada, registrada e convertida em envelope com `Success = $false`. Nunca derruba a orquestração.

Adicionar um módulo novo = criar um arquivo que implementa o contrato e declarar suas operações. Zero alteração no Core.

---

## 6. Configuração — fonte única da verdade

- Todo comportamento configurável vive **exclusivamente** em `\Config\Config.json`: thresholds, timeouts, scheduler, política de logs, limites, pontuações (scores), severidades e triggers.
- **Nenhum valor mágico no código.** O Core carrega a configuração uma vez, valida o schema, aplica *defaults defensivos* para chaves ausentes e a expõe imutável aos módulos.
- Se o `Config.json` estiver ausente ou corrompido, o Core **falha rápido** com mensagem clara (na inicialização) ou cai para um perfil de defaults seguro (em execução não interativa), conforme política — decisão detalhada na Etapa 5.

---

## 7. Hierarquia de fontes de dados

A coleta segue uma ordem de preferência rígida, do mais moderno/leve para o legado:

```
1. CIM  ───────────► padrão. Get-CimInstance (WS-Man, sem DCOM pesado)
2. Win32 API ──────► P/Invoke via Add-Type quando o CIM não expõe o dado
3. Performance Counters ─► métricas contínuas de baixo custo
4. ETW ────────────► tracing de eventos de alta resolução (rede, processos)
5. Windows Event Log ─► histórico e correlação
6. Registro (RO) ──► apenas leitura, para configuração/estado declarado
7. WMI ────────────► último recurso, somente quando não há alternativa
```

**Por que CIM antes de WMI:** `Get-CimInstance` usa WS-Management, é mais leve, mais previsível entre versões e não arrasta o overhead de DCOM do antigo `Get-WmiObject`. O WMI clássico fica reservado para os raros dados sem equivalente em CIM.

---

## 8. Estratégia de compatibilidade multiversão

Alvos: Windows 10/11 x64, Server 2012 → 2025 (e futuras); PowerShell 4.0, 5.1 e 7+; arquitetura x64; **sem** dependências externas, **sem** PowerShell Gallery, **sem** Internet.

A compatibilidade é tratada por uma **camada de compatibilidade (shim)** dentro do Core, com duas diretrizes:

- **Detecção de recursos, não de versão.** Em vez de "se PS7 faça X", o shim testa a disponibilidade do recurso (cmdlet, contador, provider ETW) e degrada graciosamente. Quando um contador/provider não existe naquele SO, vira `Warning`, não erro fatal.
- **Subconjunto sintático seguro.** O código de produção evita construções exclusivas do PS7 (operador ternário, `??`, `&&`/`||` em pipeline, `ForEach-Object -Parallel`) nos caminhos que precisam rodar em PS 4.0/5.1; quando há ganho real no PS7, o recurso é acessado por trás de um wrapper detectado em runtime. CIM é preferido por estar disponível desde o PS 3.0.

Matriz de privilégios: parte dos dados (ex.: certos eventos de segurança, ETW de kernel) exige elevação. Sem elevação, o módulo coleta o que puder e registra a limitação em `Warnings` — nunca aborta a suíte inteira.

---

## 9. Tratamento de erros, logging e resiliência

- **Fail Fast na borda:** o Launcher e a inicialização do Core abortam imediatamente diante de pré-condições inválidas (host incompatível, integridade comprometida).
- **Fail Safe no núcleo:** uma vez em operação, qualquer falha de módulo/operação é encapsulada no envelope e isolada.
- **Logger central** vive no Core, é injetado nos módulos e registra: data, hora, duração, módulo, operação, resultado, avisos, erros e stack trace quando houver. É **thread-safe** (sincronização por mutex) para suportar execução concorrente, e implementa **rotação automática** por tamanho/idade conforme `Config.json`.

---

## 10. Concorrência e desempenho

Metas de design: **CPU < 1% em espera**, **RAM < 150 MB**, baixo I/O de disco e rede.

- **Monitor orientado a eventos, não a polling agressivo.** O modo contínuo se apoia em Performance Counters e ETW com intervalos configuráveis, evitando laços apertados que queimam CPU. As metas de <1% CPU/<150 MB são atingíveis com esse desenho, mas dependem da disciplina de implementação (intervalos, coleta incremental, descarte de objetos) — isso será materializado e medido na Etapa 8 (Monitor) e na Etapa 17 (Otimização).
- **Runspaces, não Jobs.** Paralelismo via *runspace pool* (mais leve, mesmo espaço de processo, sem custo de serialização entre processos) e somente quando há ganho real — coletas independentes (ex.: Inventory de hardware × Network) paralelizam; coletas triviais permanecem sequenciais (KISS).
- **Throttling configurável** no pool, para não competir com a carga de produção da máquina auditada.

---

## 11. Fluxo de uma auditoria completa (end-to-end)

```
Launcher.bat
   └─► valida ambiente/privilégios ─► inicia Core.ps1
        └─► carrega Config.json ─► inicializa Logger ─► descobre Módulos
             └─► Dispatcher executa operações (sequencial/runspaces)
                  ├─ Monitor       ─┐
                  ├─ ProcessAnalyzer│
                  ├─ Network        ├─► envelopes normalizados
                  ├─ Security       │
                  └─ Inventory     ─┘
                       └─► estágio de Correlação (cruza PID/porta/serviço/evento)
                            └─► cálculo de Scores (Health/Security/Performance/Risk)
                                 └─► geração de Relatórios (HTML/JSON/CSV)
                                      └─► Dashboard consome o JSON autocontido
```

Scheduler e Triggers podem disparar esse fluxo automaticamente (logon, intervalos, limites excedidos), com guarda contra múltiplas instâncias.

---

## 12. Fronteiras tecnológicas (o que NÃO entra)

- Sem bibliotecas externas, sem módulos da PowerShell Gallery, sem instaladores adicionais, sem dependência de Internet.
- Apenas APIs públicas e recursos nativos do Windows.
- O Dashboard usa apenas HTML5 + CSS3 + JavaScript ES2022 nativo, sem frameworks, e funciona offline a partir de um único arquivo.
- A rede é auditada por metadados (interfaces, conexões, rotas, sessões) — **nunca** se captura conteúdo de pacotes.

---

## 13. Síntese das decisões de arquitetura

| Decisão | Escolha | Justificativa |
|--------|---------|---------------|
| Estilo arquitetural | Clean Architecture em camadas + Mediator | Baixo acoplamento, testabilidade, expansão sem tocar no Core |
| Comunicação | Tudo via Core (módulos isolados) | Responsabilidade única, substituibilidade |
| Contrato de saída | Envelope único padronizado | Orquestração/log/report/dashboard agnósticos |
| Config | `Config.json` como fonte única | Zero valores mágicos, comportamento 100% configurável |
| Coleta | CIM → Win32 → PerfCounters → ETW → EventLog → Registro(RO) → WMI | Mais leve e moderno primeiro; legado por último |
| Compatibilidade | Detecção de recurso + subconjunto sintático seguro | PS 4.0/5.1/7+ e Server 2012→2025 sem ramificações frágeis |
| Concorrência | Runspace pool, só com ganho real | Desempenho e metas de CPU/RAM |
| Segurança | Read-only absoluto | Correções apenas como recomendação/ação manual autorizada |
| Apresentação | HTML/CSS/JS nativo autocontido | Sem frameworks, offline, portável |

---

## 14. O que vem a seguir

A Etapa 2 (Estrutura de Diretórios) detalhará o propósito de cada pasta (`\Config`, `\Modules`, `\Reports`, `\Logs`, `\Assets`, `\Templates`, `\Cache`, `\Docs`, `\Tests`), convenções de nomenclatura, responsabilidade por arquivo e o layout físico que materializa esta arquitetura — sem antecipar código, que começa na Etapa 3 (`Launcher.bat`).
