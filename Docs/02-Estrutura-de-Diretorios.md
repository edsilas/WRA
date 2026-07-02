# Windows Resource Auditor — Estrutura de Diretórios

**Projeto:** Windows Resource Auditor
**Versão:** 4.1.0
**Etapa:** 2 de 20 — Estrutura de Diretórios
**Documento de referência (`\Docs\02-Estrutura-de-Diretorios.md`)**

---

## 1. Objetivo da etapa

Materializar fisicamente a arquitetura em camadas definida na Etapa 1, atribuindo a cada pasta uma responsabilidade única, fixando convenções de nomenclatura, encoding e versionamento, e estabelecendo onde cada artefato (entrada, transitório, saída, documentação e teste) reside. Esta etapa **não** contém código — apenas o contrato físico do projeto, sobre o qual a Etapa 3 (`Launcher.bat`) começará a construir.

Princípio condutor: **Separation of Concerns aplicado ao disco.** A localização de um arquivo comunica sua camada e seu ciclo de vida (imutável de configuração, transitório de cache, gerado de relatório, etc.).

---

## 2. Árvore completa do projeto

```
WindowsResourceAuditor\
│
├─ Launcher.bat                      ← Camada 0: bootstrap (Etapa 3)
├─ Core.ps1                          ← Camada 1: orquestrador, entry point (Etapa 4)
│
├─ Config\                           ← Fonte única de configuração (Etapa 5)
│   ├─ Config.json                   ←   valores configuráveis (ÚNICO arquivo editável)
│   └─ Config.schema.json            ←   schema de validação + defaults (metadados, não valores de operação)
│
├─ Modules\                          ← Componentes carregáveis dinamicamente (Etapas 7–12)
│   │
│   ├─ Contracts\                    ←   contratos compartilhados (Camada de fronteira)
│   │   ├─ ResultEnvelope.psm1       ←     fábrica/validação do envelope universal
│   │   └─ ModuleContract.psm1       ←     contrato/manifesto que todo módulo implementa
│   │
│   ├─ Infrastructure\               ←   serviços internos do Core (injetáveis)
│   │   ├─ Configuration.psm1        ←     carga, validação e resolução de Config.json
│   │   ├─ Logger.psm1               ←     logging thread-safe + rotação
│   │   ├─ Compatibility.psm1        ←     shim de detecção de recursos (PS 4/5.1/7+, Server 2012→2025)
│   │   ├─ RunspaceManager.psm1      ←     pool de runspaces + throttling
│   │   ├─ Dispatcher.psm1           ←     registro e resolução Module.Operation
│   │   ├─ EventBus.psm1             ←     barramento de eventos interno
│   │   ├─ Scheduler.psm1            ←     tarefas agendadas (Etapa 14)
│   │   ├─ Triggers.psm1             ←     auditorias automáticas por limite/evento
│   │   ├─ Correlation.psm1          ←     cruzamento PID/porta/serviço/evento
│   │   ├─ Scoring.psm1              ←     Health/Security/Performance/Risk Score
│   │   └─ Reporting.psm1            ←     pipeline HTML/JSON/CSV
│   │
│   └─ Domain\                       ←   módulos de domínio (responsabilidade única)
│       ├─ Monitor.psm1              ←     CPU/RAM/GPU/Disco/Rede/Processos/Serviços/Eventos (Etapa 8)
│       ├─ ProcessAnalyzer.psm1      ←     auditoria completa de processos (Etapa 9)
│       ├─ Network.psm1              ←     pilha de rede e correlação (Etapa 10)
│       ├─ Security.psm1             ←     postura de segurança e scores (Etapa 11)
│       └─ Inventory.psm1            ←     hardware/firmware/SO/software (Etapa 12)
│
├─ Templates\                        ← Modelos de apresentação (Etapa 13)
│   ├─ Dashboard.template.html       ←   casca do dashboard (placeholders preenchidos no Reporting)
│   ├─ partials\                     ←   blocos reutilizáveis (cards, seções, gráficos)
│   │   ├─ card.html
│   │   ├─ timeline.html
│   │   └─ table.html
│   └─ report-fragments\             ←   fragmentos para relatórios derivados
│
├─ Assets\                           ← Recursos estáticos do dashboard (inlinados na geração)
│   ├─ css\
│   │   └─ dashboard.css             ←   CSS3 nativo, sem framework
│   ├─ js\
│   │   └─ dashboard.js              ←   JavaScript ES2022 nativo, sem framework
│   └─ img\
│       └─ icons.svg                 ←   sprites SVG (evita dependência de fontes de ícone)
│
├─ Reports\                          ← SAÍDA: relatórios gerados (Etapa 13)
│   ├─ <RunId>\                      ←   um snapshot completo por execução
│   │   ├─ dashboard.html            ←     dashboard autocontido
│   │   ├─ data.json                 ←     dataset normalizado da execução
│   │   ├─ inventory.csv
│   │   ├─ processes.csv
│   │   └─ network.csv
│   └─ Latest\                       ←   cópia do último RunId (ponteiro estável)
│
├─ Logs\                             ← SAÍDA: logs operacionais (Etapa 6)
│   ├─ WRA_<yyyyMMdd>.log            ←   log corrente do dia
│   └─ Archive\                      ←   logs rotacionados (comprimidos conforme Config)
│
├─ Cache\                            ← TRANSITÓRIO: seguro para apagar
│   ├─ baseline\                     ←   linhas de base de métricas (deltas/triggers)
│   ├─ signatures\                   ←   resultados de assinatura/hash já resolvidos (TTL)
│   └─ resolve\                      ←   resoluções auxiliares (ex.: nomes, GUIDs de serviço)
│
├─ Docs\                             ← Documentação do projeto (Etapa 18)
│   ├─ README.md
│   ├─ CHANGELOG.md
│   ├─ 01-Arquitetura-Geral.md
│   ├─ 02-Estrutura-de-Diretorios.md
│   └─ modules\                      ←   especificação por módulo
│
└─ Tests\                            ← Testes (Etapa 16) — harness nativo, sem PS Gallery
    ├─ Invoke-Tests.ps1              ←   runner próprio (não depende de Pester da Gallery)
    ├─ Unit\                         ←   testes por função/módulo
    ├─ Integration\                  ←   testes de integração via Core
    └─ Fixtures\                     ←   dados/respostas simuladas para testes determinísticos
```

---

## 3. Responsabilidade de cada diretório

### Raiz
Contém apenas os dois pontos de entrada previstos na especificação: `Launcher.bat` (bootstrap em Batch) e `Core.ps1` (orquestrador em PowerShell). Nenhuma lógica de domínio reside na raiz. O Core é deliberadamente enxuto: ele *carrega* seus serviços a partir de `\Modules\Infrastructure`, mantendo-se como ponto de entrada de orquestração — coerente com "modular e facilmente expansível".

### `\Config`
Fonte única da verdade para todo comportamento configurável (thresholds, timeouts, scheduler, política de logs, limites, scores, severidades, triggers).
- **`Config.json`** é o **único** arquivo que o operador edita e o único lugar onde valores de operação existem — nada de valores mágicos no código.
- **`Config.schema.json`** não contém configuração de operação; é **metadado de validação**. Ele descreve o formato esperado e carrega os *defaults* (via `default` do JSON Schema). Assim conciliamos as duas regras da especificação: "configuração exclusivamente em Config.json" **e** "nenhum valor fixo no código" — os padrões de fallback vivem em metadado declarativo, não embutidos em `.ps1` nem competindo como segunda fonte de configuração.

### `\Modules`
Abriga **todos** os componentes carregados dinamicamente pelo Core, segregados por papel arquitetural:
- **`Contracts\`** — a fronteira de integração: a fábrica do envelope universal e o contrato/manifesto que todo módulo deve implementar (nome, versão, operações, requisitos de privilégio).
- **`Infrastructure\`** — os serviços internos do Core (configuração, logger, compatibilidade, dispatcher, runspaces, event bus, scheduler, triggers, correlação, scoring, reporting). São injetados nos módulos de domínio; nunca o contrário.
- **`Domain\`** — exatamente os cinco módulos de auditoria, cada um com responsabilidade única e sem conhecimento dos demais.

Adicionar um novo módulo de domínio = criar um `.psm1` em `Domain\` que implemente `ModuleContract.psm1`. O Core o descobre e registra sem qualquer alteração no próprio Core (Open/Closed).

### `\Templates`
Modelos de apresentação com marcadores de substituição (placeholders) que o `Reporting.psm1` preenche. Separar template de dados mantém a geração de relatórios livre de HTML embutido em strings de PowerShell. `partials\` guarda blocos reutilizáveis (DRY na camada de apresentação).

### `\Assets`
Recursos estáticos de origem do dashboard (CSS3, JS ES2022, ícones SVG). Como o dashboard final é **autocontido** e offline, estes assets são *inlinados* no HTML no momento da geração. Preferimos SVG e fontes do sistema a fontes/ícones externos para não violar "sem dependência de Internet" e "sem bibliotecas externas".

### `\Reports` (saída)
Cada execução produz um **snapshot completo** em `\Reports\<RunId>\` (dashboard HTML autocontido + `data.json` + CSVs). Manter tudo de uma execução junto facilita arquivamento e auditoria forense. `\Reports\Latest\` é uma cópia do snapshot mais recente, oferecendo um caminho estável para automações e atalhos.

### `\Logs` (saída)
Logs operacionais conforme a Etapa 6: data, hora, duração, módulo, operação, resultado, avisos, erros e stack trace. Rotação automática por tamanho/idade (parametrizada em `Config.json`); arquivos rotacionados vão para `Archive\`, opcionalmente comprimidos.

### `\Cache` (transitório)
Dados de apoio que **podem ser apagados a qualquer momento sem perda funcional**: linhas de base para cálculo de deltas e disparo de triggers, resultados de assinatura/hash já resolvidos (com TTL, para não recalcular SHA-256 de binários inalterados), e resoluções auxiliares. O Core sempre tolera cache ausente (Fail Safe).

### `\Docs`
Documentação viva do projeto, incluindo os documentos de cada etapa, `README.md`, `CHANGELOG.md` e a especificação por módulo em `modules\`.

### `\Tests`
Suíte de testes com **runner nativo** (`Invoke-Tests.ps1`), evitando dependência da PowerShell Gallery. `Unit\` cobre funções isoladas, `Integration\` exercita fluxos via Core, e `Fixtures\` fornece dados/respostas simuladas para testes determinísticos e reproduzíveis entre versões do Windows.

---

## 4. Convenções de nomenclatura

| Elemento | Convenção | Exemplo |
|---------|-----------|---------|
| Arquivos de módulo | PascalCase + `.psm1` | `ProcessAnalyzer.psm1` |
| Funções públicas | `Verbo-Substantivo` (verbo aprovado) + prefixo `WRA` | `Get-WRATcpConnection` |
| Funções privadas | mesmo padrão, **não exportadas** (escopo do módulo) | `Resolve-WRASignature` |
| Variáveis | camelCase para locais; PascalCase para parâmetros públicos | `$tcpRows`, `$ComputerName` |
| Chaves de `Config.json` | PascalCase (alinhado às propriedades do envelope) | `"Thresholds": { "CpuPercent": 85 }` |
| Identificador de execução (`RunId`) | `<yyyyMMdd_HHmmss>_<HOST>` | `20260626_142530_HOSTSRV01` |
| Arquivos de log | `WRA_<yyyyMMdd>.log` (+ índice ao rotacionar) | `WRA_20260626.log`, `WRA_20260626.1.log` |
| Arquivos de relatório | dentro de `\Reports\<RunId>\` com nome de domínio | `network.csv` |
| Documentos | `NN-Titulo-Kebab.md` | `02-Estrutura-de-Diretorios.md` |

**Prefixo `WRA` nas funções** evita colisão com cmdlets nativos e com módulos do sistema, e torna explícita a origem de qualquer função em rastreamentos e logs.

---

## 5. Encoding, versionamento e portabilidade

- **Encoding:** arquivos `.ps1`/`.psm1` em **UTF-8 com BOM** para que o Windows PowerShell 5.1 e o PowerShell 7+ interpretem corretamente caracteres acentuados; arquivos de log e dados em **UTF-8 sem BOM**. Essa distinção evita os problemas clássicos de encoding entre PS 5.1 (que assume ANSI sem BOM) e PS 7 (UTF-8 por padrão).
- **Versão:** a versão `4.1.0` é declarada em `Config.json` e ecoada no envelope/relatórios; o `CHANGELOG.md` registra a evolução. Nenhum número de versão é duplicado no código.
- **Caminhos:** o Core resolve todos os diretórios de forma **relativa à raiz do projeto** (a partir da própria localização de `Core.ps1`), nunca por caminhos absolutos fixos. Isso torna a ferramenta portável: copiar a pasta para qualquer máquina ou compartilhamento e executar, sem instalação.
- **Diretórios voláteis:** `\Reports`, `\Logs` e `\Cache` são criados sob demanda pelo Core caso não existam (idempotência), e podem ser limpos sem afetar o funcionamento.

---

## 6. Mapa pasta → camada → etapa

| Pasta/arquivo | Camada (Etapa 1) | Etapa de implementação |
|---------------|------------------|------------------------|
| `Launcher.bat` | 0 — Bootstrap | 3 |
| `Core.ps1` | 1 — Orquestração | 4 |
| `Config\` | transversal | 5 |
| `Infrastructure\Logger.psm1` | 1 — Orquestração | 6 |
| `Contracts\`, `Infrastructure\Dispatcher` | 1 — Orquestração | 7 |
| `Domain\Monitor.psm1` | 2 — Domínio | 8 |
| `Domain\ProcessAnalyzer.psm1` | 2 — Domínio | 9 |
| `Domain\Network.psm1` | 2 — Domínio | 10 |
| `Domain\Security.psm1` | 2 — Domínio | 11 |
| `Domain\Inventory.psm1` | 2 — Domínio | 12 |
| `Templates\`, `Assets\`, `Reporting.psm1` | 3 — Apresentação | 13 |
| `Infrastructure\Scheduler.psm1`, `Triggers.psm1` | 1 — Orquestração | 14 |
| `Tests\` | transversal | 16 |
| `Docs\` | transversal | 18 |

---

## 7. O que vem a seguir

A Etapa 3 implementará o **`Launcher.bat`** — o bootstrap em Batch que detecta privilégios administrativos, valida o ambiente mínimo (arquitetura x64, host PowerShell disponível e compatível), verifica a integridade da estrutura aqui definida, seleciona o interpretador adequado (Windows PowerShell 5.1 ou PowerShell 7+) e entrega o controle ao `Core.ps1`, registrando o início no sistema de logs. Será a primeira entrega de código totalmente funcional, sem pseudocódigo e sem omissões.
