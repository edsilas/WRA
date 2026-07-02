# Windows Resource Auditor — v4.1.0

**Ferramenta somente leitura de auditoria, monitoramento, inventário, diagnóstico e relatório de recursos do Windows.**

O Windows Resource Auditor (WRA) coleta o estado do sistema operacional, calcula indicadores de saúde, segurança e desempenho, e gera um **painel HTML autocontido** — sem nunca modificar o sistema. Correções e melhorias são apresentadas como **recomendações**, jamais aplicadas automaticamente.

> Desenvolvido por Edsilas.

---

## Sumário

1. [Apresentação e propósito](#1-apresentação-e-propósito)
2. [Objetivos e casos de uso recomendados](#2-objetivos-e-casos-de-uso-recomendados)
3. [Quando utilizar a ferramenta](#3-quando-utilizar-a-ferramenta)
4. [Limitações conhecidas e o que a ferramenta não faz](#4-limitações-conhecidas-e-o-que-a-ferramenta-não-faz)
5. [Requisitos mínimos e recomendados](#5-requisitos-mínimos-e-recomendados)
6. [Sistemas operacionais compatíveis](#6-sistemas-operacionais-compatíveis)
7. [Dependências e componentes nativos](#7-dependências-e-componentes-nativos)
8. [Estrutura completa do projeto](#8-estrutura-completa-do-projeto)
9. [Fluxo de execução](#9-fluxo-de-execução)
10. [Instalação e configuração](#10-instalação-e-configuração)
11. [Guia de utilização passo a passo](#11-guia-de-utilização-passo-a-passo)
12. [Funcionalidades disponíveis](#12-funcionalidades-disponíveis)
13. [O Dashboard e as seções do relatório](#13-o-dashboard-e-as-seções-do-relatório)
14. [Indicadores, métricas, tabelas e filtros](#14-indicadores-métricas-tabelas-e-filtros)
15. [Como interpretar os resultados](#15-como-interpretar-os-resultados)
16. [Onde os arquivos são armazenados](#16-onde-os-arquivos-são-armazenados)
17. [Estrutura dos relatórios gerados](#17-estrutura-dos-relatórios-gerados)
18. [FAQ e solução de problemas](#18-faq-e-solução-de-problemas)
19. [Boas práticas de utilização](#19-boas-práticas-de-utilização)
20. [Desempenho e compatibilidade](#20-desempenho-e-compatibilidade)
21. [Versionamento e histórico](#21-versionamento-e-histórico)
22. [Créditos](#22-créditos)

---

## 1. Apresentação e propósito

O **Windows Resource Auditor** é uma aplicação de linha de comando, escrita inteiramente em **Windows PowerShell** e **Batch**, que realiza uma fotografia detalhada e segura do estado de uma máquina Windows. Ele consolida, em um único relatório, informações de hardware, sistema operacional, software instalado, processos, rede, serviços, eventos e postura de segurança.

Seu propósito central é **diagnosticar sem interferir**. A ferramenta foi desenhada com um princípio inviolável: ela **lê** o sistema, nunca o altera. Não modifica Registro, Firewall, Windows Defender, Windows Update, drivers, serviços, GPO, BitLocker, TPM, Secure Boot ou arquivos. Quando identifica um problema, ela o registra e sugere uma recomendação — a decisão e a ação permanecem sempre com o operador.

O resultado final é um **dashboard HTML autocontido** (um único arquivo, sem dependências externas), acompanhado de exportações em **JSON** e **CSV**, que podem ser arquivados, comparados ao longo do tempo ou anexados a chamados e laudos técnicos.

### Princípios de projeto

- **Não invasiva (somente leitura):** diagnostica e recomenda, nunca aplica mudanças (`Safety.ReadOnly = true`, `Safety.NeverModifySystem = true`).
- **Offline e autossuficiente:** não usa Internet, PowerShell Gallery ou bibliotecas de terceiros. Apenas APIs nativas do Windows.
- **Prioridade de fontes de dados:** CIM → API Win32 → Performance Counters → ETW → Log de Eventos → Registro (leitura) → WMI (último recurso, para compatibilidade).
- **Fail Safe (degradação graciosa):** se um subsistema estiver indisponível, a coleta correspondente é registrada como aviso e a execução continua, em vez de abortar.

---

## 2. Objetivos e casos de uso recomendados

A ferramenta é indicada para profissionais e equipes de TI que precisam de uma visão consolidada e confiável de uma estação ou servidor Windows. Casos de uso típicos:

- **Diagnóstico de incidentes:** levantar rapidamente o estado de uma máquina lenta, instável ou com comportamento suspeito (processos não assinados, picos de CPU/memória, eventos críticos recentes).
- **Auditoria de segurança de baseline:** verificar a postura de Defender, Firewall, UAC, BitLocker, Secure Boot, Credential Guard, integridade de memória e atualizações.
- **Inventário técnico:** documentar hardware, firmware, sistema operacional, software instalado e impressoras de um parque de máquinas.
- **Preparação e fechamento de chamados:** anexar um relatório HTML/JSON ao ticket como evidência objetiva do estado da máquina.
- **Comparação ao longo do tempo:** executar periodicamente (manual ou agendado) e comparar relatórios para identificar regressões ou mudanças não planejadas.
- **Verificação pós-manutenção:** confirmar, após uma intervenção, que serviços e segurança estão como esperado.

---

## 3. Quando utilizar a ferramenta

A ferramenta é mais indicada nos seguintes cenários:

- **Ambientes em que não se pode alterar nada:** por ser estritamente somente leitura, é segura para rodar em produção, em máquinas de clientes ou em servidores críticos.
- **Diagnóstico rápido e pontual:** quando se precisa de um panorama completo em poucos minutos, sem instalar agentes.
- **Máquinas isoladas ou sem Internet:** funciona 100% offline, sem dependências externas.
- **Coleta padronizada por uma equipe:** o relatório tem formato consistente, facilitando a comparação entre máquinas e técnicos.
- **Execução recorrente:** pode ser agendada como tarefa diária (Agendador de Tarefas) para gerar relatórios automáticos.

Não é indicada como ferramenta de **monitoramento contínuo em tempo real** (ela faz coletas pontuais, não vigilância 24/7) nem como **ferramenta de correção/remediação** (ela não aplica mudanças).

---

## 4. Limitações conhecidas e o que a ferramenta não faz

Para uso correto, é importante entender os limites da ferramenta:

- **Não corrige nada.** Não aplica patches, não altera configurações, não inicia/para serviços, não modifica o Registro. Toda saída é informativa/recomendatória.
- **Não é antivírus nem EDR.** A análise de processos calcula hash SHA-256 e verifica a assinatura digital (Authenticode), mas **não** classifica malware, não consulta reputação online e não bloqueia nada.
- **Não monitora em tempo real por padrão.** A coleta é pontual. Existe um modo de observação por gatilhos (`-Watch`), porém ele é experimental, desativado por padrão e voltado a disparar coletas adicionais quando métricas locais ultrapassam limites — não substitui uma solução de monitoramento.
- **Profundidade depende de privilégios.** Sem elevação (Administrador), várias verificações ficam limitadas ou indisponíveis (BitLocker, TPM, alguns dados de Defender, certos eventos e a sessão CIM). Os itens indisponíveis aparecem como "Indisponível" ou geram avisos, sem derrubar a execução.
- **Disponibilidade de dados varia por versão do Windows.** Recursos como `Get-NetTCPConnection`, perfis de Firewall via cmdlet, status do Defender ou integridade de memória existem em versões mais novas; em sistemas antigos a ferramenta recorre a fontes alternativas (WMI) ou marca o item como indisponível.
- **A análise de eventos coleta apenas eventos relevantes.** O módulo de Eventos foca em níveis úteis ao diagnóstico (Crítico, Erro, Aviso), falhas de auditoria e uma amostra de Informação. O nível **Informação** tende a aparecer pouco — por design, para reduzir ruído.
- **Arquitetura suportada: x64.** O Launcher recusa execução fora de Windows x64.
- **Não envia dados para lugar nenhum.** Não há telemetria, upload ou conexão de rede de saída. Os relatórios ficam apenas na máquina, em disco.

---

## 5. Requisitos mínimos e recomendados

### Requisitos mínimos

| Item | Mínimo |
|------|--------|
| Arquitetura | Windows x64 |
| PowerShell | Windows PowerShell **4.0** |
| Privilégios | Usuário padrão (coleta parcial) |
| Memória livre | ~512 MB |
| Espaço em disco | ~50 MB para a ferramenta + relatórios |
| Navegador | Qualquer navegador moderno para abrir o dashboard HTML |

### Requisitos recomendados

| Item | Recomendado |
|------|-------------|
| PowerShell | Windows PowerShell **5.1** (runtime validado da ferramenta) |
| Privilégios | **Administrador** (elevado) — habilita todas as verificações |
| Memória livre | 1 GB ou mais |
| Navegador | Navegador atualizado (Edge, Chrome, Firefox) para a interatividade do dashboard |

> **Observação sobre privilégios:** sem elevação, a ferramenta ainda roda e produz relatório, mas verificações que exigem direitos administrativos (BitLocker, TPM, parte do Defender, sessão CIM compartilhada, certos eventos) ficam limitadas. O menu do Launcher exibe o nível de privilégio atual e o Launcher pode solicitar elevação automaticamente.

---

## 6. Sistemas operacionais compatíveis

- **Windows 10 / 11** (x64).
- **Windows Server 2012, 2012 R2, 2016, 2019, 2022, 2025** (x64).

### Hosts PowerShell

- **Windows PowerShell 5.1** — host **preferencial** (runtime validado).
- **Windows PowerShell 4.0** — suportado (piso mínimo, exigido pelo `#Requires -Version 4.0`).
- **PowerShell 7+ (pwsh)** — suportado como **fallback** (ou forçado com `--ps7`).

O `Launcher.bat` detecta os hosts disponíveis e seleciona automaticamente o Windows PowerShell; o pwsh 7 é usado apenas quando o Windows PowerShell não está presente ou quando explicitamente solicitado.

### Restrições

- Arquitetura **x64** obrigatória (o Launcher recusa outras).
- Em **versões mais antigas do Windows**, alguns dados são obtidos via WMI (compatibilidade) e certas verificações que dependem de cmdlets/recursos modernos podem aparecer como "Indisponível".
- A política de execução é contornada com segurança apenas para o processo da ferramenta (`-ExecutionPolicy Bypass` no chamado), sem alterar a política do sistema.

---

## 7. Dependências e componentes nativos

A ferramenta **não possui dependências externas**: nada de módulos da PowerShell Gallery, pacotes NuGet, bibliotecas de terceiros, fontes web ou Internet. Tudo o que ela usa já faz parte do Windows.

Componentes **nativos do Windows e do .NET** utilizados:

- **CIM / WMI** (`Get-CimInstance`, sessão CIM via DCOM, com fallback para `Get-WmiObject`) — coleta de hardware, SO, rede, segurança, processos.
- **Performance Counters** — amostragem de CPU, memória e disco.
- **Log de Eventos** (`Get-WinEvent`) — análise de eventos do Windows (System, Application, Security).
- **Assinatura digital Authenticode** (`Get-AuthenticodeSignature`) e **hash** (`Get-FileHash`, com fallback nativo via `System.Security.Cryptography.SHA256`) — verificação de processos.
- **Registro do Windows** (somente leitura) — verificações de segurança e configuração.
- **Agendador de Tarefas do Windows** — para agendamento opcional da execução.
- **.NET Framework / .NET** (`System.Management`, `System.Security.Cryptography`, `System.Threading.Mutex`, runspaces) — utilitários internos e paralelismo.

O **dashboard** (`dashboard.html`) é HTML + CSS + JavaScript **puro (vanilla)**, sem frameworks, sem CDNs e sem chamadas de rede — o arquivo abre e funciona offline, inclusive por duplo clique.

---

## 8. Estrutura completa do projeto

```
WRA/
├── Launcher.bat                  # Ponto de entrada (Batch). Detecta host PowerShell,
│                                 # valida x64, oferece menu interativo e chama o Core.
├── Core.ps1                      # Orquestrador (composition root). Inicializa o ambiente,
│                                 # carrega módulos, executa o pipeline e gera o relatório.
├── README.md                     # Esta documentação oficial.
├── CHANGELOG.md                  # Histórico de alterações.
│
├── Config/
│   ├── Config.json               # Configuração principal (módulos, limites, relatórios,
│   │                             # scoring, agendamento, gatilhos, segurança).
│   └── Config.schema.json        # Esquema de validação do Config.json.
│
├── Modules/
│   ├── Contracts/                # Camada 0 — contratos e utilitários base.
│   │   ├── Common.psm1           #   Helpers comuns (acesso seguro a propriedades, números, etc.).
│   │   ├── ResultEnvelope.psm1   #   Envelope padronizado de resultado (Success/Data/Warnings/Errors).
│   │   └── ModuleContract.psm1   #   Registro/validação de módulos e operações.
│   │
│   ├── Infrastructure/           # Camada 1 — infraestrutura.
│   │   ├── Configuration.psm1    #   Carga e validação da configuração.
│   │   ├── Logger.psm1           #   Log estruturado, rotação e arquivamento.
│   │   ├── Dispatcher.psm1       #   Execução de módulos/operações com o envelope de resultado.
│   │   ├── Scoring.psm1          #   Cálculo dos indicadores globais (Saúde, Segurança, Desempenho, Risco).
│   │   ├── Scheduler.psm1        #   Integração com o Agendador de Tarefas.
│   │   ├── Triggers.psm1         #   Regras de gatilho por métrica (modo observação).
│   │   ├── Reporting.psm1        #   Geração de HTML/JSON/CSV e cópia em "Latest".
│   │   ├── CimManager.psm1       #   Sessão CIM compartilhada (DCOM) + coleta CIM resiliente + cache.
│   │   └── RunspaceManager.psm1  #   Pool de runspaces para tarefas paralelas.
│   │
│   └── Domain/                   # Camada 2 — coletores de domínio.
│       ├── Inventory.psm1        #   Hardware, firmware, SO, software, impressoras, licenciamento.
│       ├── Monitor.psm1          #   CPU/Memória/Disco/GPU, serviços, top de processos, eventos.
│       ├── Network.psm1          #   Interfaces, conexões, portas, rotas, shares, sessões, firewall.
│       ├── ProcessAnalyzer.psm1  #   Processos: assinatura, hash, dono, correlação com serviços/inicialização.
│       └── Security.psm1         #   Defender, Firewall, UAC, TPM, Secure Boot, BitLocker, Update, etc.
│
├── Assets/
│   ├── css/dashboard.css         # Estilos do dashboard.
│   └── js/dashboard.js           # Lógica do dashboard (render, filtros, ordenação, interatividade).
│
├── Templates/
│   └── Dashboard.template.html   # Template do relatório; o Core injeta CSS, JS e dados.
│
├── Reports/                      # Saída dos relatórios (criada/usada em execução).
│   ├── <RunId>/                  #   Uma pasta por execução (ver seção 17).
│   └── Latest/                   #   Cópia do relatório mais recente.
│
├── Logs/                         # Logs de execução.
│   └── Archive/                  #   Logs rotacionados/compactados.
│
├── Cache/
│   └── signatures/               # Cache de verificações de assinatura (TTL configurável).
│
├── Docs/                         # Documentação técnica complementar (arquitetura, referências).
│
└── Tests/                        # Testes automatizados dos subsistemas.
    ├── Invoke-Tests.ps1
    ├── WRATest.psm1
    └── Cases/                    #   01-Common ... 10-Integration.
```

### Camadas da arquitetura

A aplicação é organizada em camadas com responsabilidades únicas:

- **Camada 0 — Contratos:** define o "vocabulário" (envelope de resultado, contrato de módulo, helpers comuns).
- **Camada 1 — Infraestrutura:** configuração, log, despacho, scoring, relatório, CIM, runspaces, agendamento e gatilhos.
- **Camada 2 — Domínio:** os cinco coletores que efetivamente obtêm os dados do Windows.
- **Orquestração (`Core.ps1`):** amarra tudo, da inicialização à geração do relatório, com detecção de capacidades em tempo de execução.

---

## 9. Fluxo de execução

Da inicialização até o relatório, a aplicação segue este fluxo:

1. **Launcher (`Launcher.bat`)** — detecta os hosts PowerShell disponíveis, valida a arquitetura x64, verifica a presença do `Core.ps1` e, se necessário, solicita elevação. Sem argumentos, exibe o **menu interativo**; com argumentos, executa diretamente (ideal para scripts e Agendador).
2. **Inicialização do Core** — resolve os caminhos relativos a si mesmo, monta o contexto (versão do PowerShell, máquina, privilégios) e carrega dinamicamente os subsistemas de infraestrutura disponíveis.
3. **Configuração** — carrega o `Config/Config.json` (ou o caminho indicado em `-ConfigPath`) e valida-o contra o esquema.
4. **Logging** — inicializa o log estruturado (nível, diretório, rotação).
5. **Sessão CIM** — se habilitada, cria uma sessão CIM compartilhada (DCOM) e a **valida com uma consulta de teste**; se a sessão não responder, ela é descartada e os módulos usam consulta direta/WMI.
6. **Resolução da seleção** — interpreta `-Run` (por exemplo, `All` ou módulos específicos) e monta a lista de operações.
7. **Execução dos módulos** — cada coletor roda dentro de um envelope de resultado (`Success/Data/Warnings/Errors`), com **barra de progresso** nativa (suprimida em `-Quiet`). Falhas pontuais viram avisos, não interrompem o conjunto.
8. **Scoring** — a partir dos dados coletados, calcula os indicadores globais (Saúde, Segurança, Desempenho, Risco).
9. **Relatório** — serializa os dados em JSON (com blindagem de caracteres de controle), monta o HTML autocontido a partir do template + CSS + JS, e grava as saídas habilitadas (HTML/JSON/CSV) em `Reports/<RunId>/`, atualizando a cópia em `Reports/Latest/`.
10. **Encerramento** — fecha a sessão CIM, libera recursos, aplica a retenção de relatórios e registra o resultado final.

---

## 10. Instalação e configuração

### Instalação

A ferramenta é **portátil** — não há instalador. Basta extrair os arquivos para uma pasta local.

1. Copie/extraia o conteúdo do pacote para um diretório, por exemplo:
   ```
   C:\WRA
   ```
2. Garanta que a estrutura (`Launcher.bat`, `Core.ps1`, `Modules\`, `Config\`, `Assets\`, `Templates\`) esteja preservada na mesma pasta.
3. (Opcional) Para execuções com todas as verificações, rode como **Administrador**.

> Não é necessário alterar a política de execução do sistema: o Launcher chama o PowerShell com `-ExecutionPolicy Bypass` apenas para o processo da ferramenta.

### Configuração

Toda a configuração fica em `Config/Config.json`. Os principais grupos:

- **`General`** — `MaxParallelism` (paralelismo, padrão 4), `PreferRunspaces`, `PreventMultipleInstances`, `FailSafe`.
- **`Logging`** — nível (`Info` por padrão), diretório, rotação (tamanho, idade, quantidade, compactação).
- **`Modules`** — habilita/ajusta cada coletor (ver detalhes na seção 12). `Modules.Enabled` define quais módulos rodam em `All`.
- **`Thresholds`** — limites de alerta de CPU (80/95%), Memória (80/92%), Disco (85/95%) e Rede (800 Mbps).
- **`Timeouts`** — limites de tempo por operação, módulo, CIM e processo.
- **`Reports`** — formatos (`HTML`, `JSON`, `CSV`), `KeepLatest`, `RetentionRuns` (30), título.
- **`Scoring`** — pesos dos indicadores (Saúde, Segurança, Desempenho).
- **`Severity`** — níveis e cores (Info, Low, Medium, High, Critical).
- **`Performance`** — `UseSharedCimSession`, `CimProtocol` (`Dcom`), `CacheTtlSeconds`.
- **`Cache`** — cache de assinaturas (`SignatureTtlHours`, padrão 168h = 7 dias).
- **`Scheduler`** / **`Triggers`** — agendamento e gatilhos (desativados por padrão).
- **`Safety`** — `ReadOnly`, `NeverModifySystem` (sempre verdadeiros; reforçam o caráter não invasivo).

Alterações são validadas contra `Config/Config.schema.json` na carga; um JSON inválido é rejeitado com mensagem de erro.

---

## 11. Guia de utilização passo a passo

### Modo 1 — Menu interativo (recomendado para uso manual)

1. Abra a pasta da ferramenta (ex.: `C:\WRA`).
2. Dê **duplo clique** em `Launcher.bat` (ou execute `Launcher.bat` sem argumentos no Prompt/Terminal).
3. O menu exibe o host PowerShell, o nível de privilégio e as opções:

   ```
   [1]  Auditoria completa (todos os modulos)
   [2]  Inventario      (hardware, SO, software)
   [3]  Monitoramento   (servicos, processos, eventos)
   [4]  Rede            (interfaces, conexoes, portas, shares)
   [5]  Processos       (analise detalhada e assinaturas)
   [6]  Seguranca       (firewall, BitLocker, contas, updates)

   [7]  Listar modulos disponiveis
   [8]  Abrir ultimo relatorio (dashboard HTML)
   [9]  Agendar execucao automatica (tarefa diaria)

   [0]  Sair
   ```
4. Digite o número desejado e tecle **ENTER**.
5. Ao final de uma auditoria (opções 1 a 6), escolha **8** para abrir o último `dashboard.html` no navegador.

### Modo 2 — Linha de comando (scripts e automação)

Quando o `Launcher.bat` recebe argumentos, ele os repassa ao `Core.ps1` e executa diretamente (sem menu). Você também pode chamar o `Core.ps1` diretamente.

Exemplos:

```bat
REM Auditoria completa com HTML/JSON/CSV (padrão)
Launcher.bat -Run All

REM Apenas Monitor e Rede, sem gerar relatório
Launcher.bat -Run Monitor,Network -NoReport

REM Apenas o relatório HTML, em modo silencioso
Launcher.bat -Run All -Format HTML -Quiet

REM Listar os módulos disponíveis
Launcher.bat -ListModules

REM Forçar o uso do Windows PowerShell 5.1
Launcher.bat --ps5 -Run All

REM Agendar / remover / listar a tarefa automática
Launcher.bat -InstallSchedule
Launcher.bat -RemoveSchedule
Launcher.bat -ListSchedule
```

### Parâmetros do `Core.ps1`

| Parâmetro | Descrição |
|-----------|-----------|
| `-Run <módulos>` | Módulos a executar: `All` (padrão) ou lista (`Inventory`, `Monitor`, `Network`, `ProcessAnalyzer`, `Security`). |
| `-ConfigPath <arquivo>` | Caminho alternativo para o `Config.json`. |
| `-LogLevel <nível>` | `Trace`, `Debug`, `Info`, `Warn` ou `Error`. |
| `-Format <formatos>` | `HTML`, `JSON` e/ou `CSV`. |
| `-NoReport` | Executa a coleta sem gerar relatório. |
| `-ListModules` | Lista os módulos/operações disponíveis. |
| `-InstallSchedule` / `-RemoveSchedule` / `-ListSchedule` | Gerencia a tarefa agendada. |
| `-Watch` | Modo observação por gatilhos (experimental). |
| `-Quiet` | Suprime saída de console e barra de progresso. |
| `-ShowVersion` (alias `-Version`) | Exibe a versão. |
| `-ShowHelp` (alias `-Help`, `-h`) | Exibe a ajuda. |

### Flags exclusivas do `Launcher.bat`

| Flag | Efeito |
|------|--------|
| `--ps5`, `--use-windows-powershell` | Força o Windows PowerShell. |
| `--ps7`, `--use-pwsh` | Força o PowerShell 7+. |

> Qualquer outro argumento é repassado tal e qual ao `Core.ps1`.

---

## 12. Funcionalidades disponíveis

A coleta é dividida em cinco módulos de domínio, configuráveis em `Config.json > Modules`.

### Inventory — Inventário

Levanta o "retrato" do equipamento: **hardware** (placa, CPU, memória), **firmware/BIOS**, **sistema operacional**, **software instalado**, **recursos/features**, **controladores**, **impressoras**, **adaptadores de rede** e **licenciamento/ativação**.

### Monitor — Monitoramento

Amostra **CPU, memória e disco** (e **GPU**, quando disponível) por uma janela curta (padrão: amostras a cada 2 s por 10 s), lista o **top de processos** por consumo, coleta o estado dos **serviços** (em execução/parados e automáticos que não estão rodando) e realiza a **análise de eventos** do Windows. A análise de eventos cobre os **últimos 7 dias**, agrupa eventos semelhantes, destaca críticos e recorrentes, e calcula estatísticas por nível, log, origem e dia. (Há também uma coleta resumida de eventos críticos/erro nas últimas 24 h, usada no card de visão geral.)

### Network — Rede

Coleta **interfaces**, **conexões** ativas, **portas em escuta (listeners)**, **rotas**, **compartilhamentos (shares)**, **sessões**, **perfis de Firewall**, **VPN** e **switches Hyper-V**, correlacionando conexões com os processos donos quando possível. A resolução de DNS é desativada por padrão (`ResolveDns = false`) por desempenho.

### ProcessAnalyzer — Processos

Faz a análise detalhada dos processos: **linha de comando**, **dono**, **correlação com serviços e itens de inicialização**, cálculo de **hash SHA-256** e verificação de **assinatura digital (Authenticode)** dos executáveis. O cálculo de hash pode ser paralelizado (`ParallelHashing`) e respeita um tamanho máximo de arquivo (`HashMaxFileSizeMB`, padrão 512 MB). A verificação de assinatura usa mecanismos nativos do Windows e classifica cada processo como assinatura válida, sem assinatura válida ou não verificada.

### Security — Segurança

Verifica a postura de segurança: **Windows Defender**, **Firewall**, **SmartScreen**, **UAC**, **TPM**, **Secure Boot**, **BitLocker**, **Credential Guard**, **integridade de memória**, **Windows Update** (idade máxima configurável, padrão 35 dias) e **eventos de segurança**. Produz uma lista de **recomendações** classificadas por severidade.

### Indicadores globais (Scoring)

A partir dos módulos, a ferramenta calcula quatro indicadores:

- **Saúde** — combinação ponderada de Desempenho, Segurança e Confiabilidade.
- **Segurança** — postura de segurança (Defender, Firewall, Update, BitLocker, Secure Boot, UAC).
- **Desempenho** — pressão de CPU, memória e disco.
- **Risco** — escala de risco consolidada.

### Recursos auxiliares

- **Relatórios** em HTML (dashboard), JSON (dados completos) e CSV (tabelas).
- **Agendamento** de execução diária via Agendador de Tarefas.
- **Modo observação** (`-Watch`) por gatilhos de métrica (experimental, desativado por padrão).
- **Log estruturado** com rotação e arquivamento.
- **Cache** de assinaturas com TTL para acelerar execuções repetidas.

---

## 13. O Dashboard e as seções do relatório

O `dashboard.html` é um **painel analítico interativo**. À esquerda há a navegação entre seções; ao topo, o título, a versão, e os botões **Exportar JSON** e **Imprimir**. **Cada indicador é um ponto de entrada**: ao clicar em um card, número ou barra, o painel rola até a lista detalhada correspondente, já filtrada.

As seções do relatório:

- **Visão geral** — os quatro anéis (**Saúde, Segurança, Desempenho, Risco**), um resumo de fatos (sistema, memória, ativação, CPU média, memória em uso, eventos críticos, recomendações) e o **status de cada módulo** (concluído/falha, duração, avisos e erros). Os fatos e os cards de módulo navegam para as seções correspondentes.
- **Inventário** — sistema operacional, hardware, **volumes** e **programas instalados** (com filtro por fabricante).
- **Processos** — cards de assinatura (válida / sem assinatura válida / não verificada / analisados) e a **tabela de processos** (nome, PID, PPID, usuário, working set, threads, handles, assinatura e SHA‑256, com o hash completo no tooltip). Inclui também a lista de processos sinalizados, quando houver.
- **Rede** — **interfaces** e a tabela de **conexões** (protocolo, estado, endereços/portas, processo, interface), com filtros combináveis.
- **Segurança** — cards das **verificações** (com status e severidade) e a lista de **recomendações** filtrável por severidade.
- **Eventos** — **análise dos últimos 7 dias**: indicadores por nível (Crítico, Erro, Aviso, Informação, Auditoria), totais e período; barras por dia, por origem e por log; e a **tabela de eventos agrupados** (nível, última ocorrência, quantidade, log, ID, origem, categoria e descrição), com destaque automático de críticos e recorrentes e exportação CSV.
- **Serviços** — cards (em execução / parados / total) e a tabela de serviços automáticos que não estão em execução.

---

## 14. Indicadores, métricas, tabelas e filtros

### Anéis (scores)

Os quatro anéis exibem valores de 0 a 100. A cor segue a faixa: **verde** (≥ 80), **amarelo** (≥ 50) e **vermelho** (< 50). Quanto maior, melhor — exceto **Risco**, em que valores maiores indicam mais exposição.

### Severidade

As cores de severidade são consistentes em todo o relatório:

| Severidade | Cor | Significado |
|-----------|-----|-------------|
| Info | Azul | Informativo |
| Low / OK | Verde | Normal/saudável |
| Medium | Amarelo | Atenção |
| High | Laranja | Importante |
| Critical | Vermelho | Crítico |

### Filtros correlacionados (sem busca textual)

Cada tabela traz uma **barra de filtros inteligentes**, gerada a partir dos próprios dados:

- Dimensões com poucos valores aparecem como **chips** (seleção múltipla — OR dentro da mesma dimensão).
- Dimensões com muitos valores aparecem como **lista suspensa**.
- Dimensões diferentes **combinam entre si** (E lógico), permitindo correlacionar (ex.: na Rede, filtrar por protocolo **e** estado **e** interface ao mesmo tempo).
- A atualização é **instantânea**, sem recarregar a página, com um contador "Mostrando X de Y" e o botão **Limpar filtros**.

Filtros típicos por seção: **Processos** (assinatura, usuário); **Rede** (protocolo, estado, interface); **Programas** (fabricante); **Eventos** (nível, log, origem, categoria).

### Ordenação

Toda tabela permite **ordenar por qualquer coluna**: clique no cabeçalho para alternar ascendente/descendente (indicado por ▲/▼). A ordenação convive com os filtros. Em Eventos, a ordenação é semântica onde faz sentido (nível por severidade, quantidade e ID numéricos, última ocorrência por data).

### Agrupamento de eventos

Para reduzir ruído, eventos semelhantes são **agrupados** por nível + log + ID + origem. Cada grupo mostra a contagem, a primeira/última ocorrência e uma descrição resumida; grupos recorrentes recebem um selo e os críticos são destacados.

### Exportação

- **Exportar JSON** (topo) — baixa o conjunto completo de dados.
- **Imprimir** (topo) — usa a impressão do navegador (inclusive para PDF).
- **CSV** (em tabelas que oferecem) — exporta a tabela corrente.

---

## 15. Como interpretar os resultados

Roteiro sugerido para diagnóstico:

1. **Comece pela Visão geral.** Os quatro anéis dão o panorama. Um Risco alto ou Segurança baixa pede atenção imediata; Desempenho baixo indica pressão de recursos.
2. **Confira o status dos módulos.** Se algum módulo aparecer "Com falha" ou com muitos avisos, parte dos dados pode estar incompleta (frequentemente por falta de privilégios) — rode como Administrador para uma leitura completa.
3. **Clique nos indicadores.** Use os cards como atalho: "Eventos críticos" leva à seção de Eventos já filtrada; "Recomendações" abre a lista de segurança; os cards de módulo levam às respectivas seções.
4. **Em Segurança,** priorize as recomendações por severidade (Crítica/Alta primeiro). Verifique Defender, Firewall, BitLocker, Secure Boot, UAC e a idade do Windows Update.
5. **Em Eventos,** filtre por Crítico/Erro e observe os grupos **recorrentes** — repetições frequentes costumam apontar a causa raiz. Use as barras por origem/log para localizar o componente.
6. **Em Processos,** observe processos **sem assinatura válida** ou em locais incomuns. A assinatura "Válida" indica binário assinado e confiável; "Não assinada"/"Não confiável"/"Hash divergente" merecem verificação; "Não verificada" significa que a checagem não pôde ser concluída (não é, por si só, um problema).
7. **Em Rede,** correlacione conexões/portas com os processos donos para identificar escutas inesperadas.
8. **Compare ao longo do tempo.** Guarde os relatórios (ou o `data.json`) e compare execuções para detectar mudanças.

> Lembre-se: a ferramenta **aponta**, não corrige. As recomendações são pontos de partida para uma decisão consciente do operador.

---

## 16. Onde os arquivos são armazenados

Por padrão, tudo é gravado **na própria pasta da ferramenta** (caminhos relativos):

- **Relatórios:** `Reports\` (configurável em `Reports.Directory`).
  - Cada execução cria `Reports\<RunId>\`.
  - O relatório mais recente também é copiado para `Reports\Latest\` (`KeepLatest`).
- **Logs:** `Logs\` (e `Logs\Archive\` para arquivos rotacionados/compactados).
- **Cache:** `Cache\` (assinaturas em `Cache\signatures\`).

A opção **8** do menu abre `Reports\Latest\dashboard.html`. A retenção de relatórios é controlada por `Reports.RetentionRuns` (padrão: manter as 30 execuções mais recentes).

---

## 17. Estrutura dos relatórios gerados

Cada execução gera uma pasta nomeada com **data, hora e nome da máquina**:

```
Reports/
├── 20260628_184500_NOME-DA-MAQUINA/
│   ├── dashboard.html      # Painel HTML autocontido (abre em qualquer navegador)
│   ├── data.json           # Conjunto completo de dados (JSON válido e compacto)
│   ├── processes.csv       # Processos
│   ├── connections.csv     # Conexões de rede
│   ├── programs.csv        # Programas instalados
│   └── recommendations.csv # Recomendações de segurança
└── Latest/                 # Cópia do relatório mais recente
```

- O `dashboard.html` embute CSS, JS e os dados — **um único arquivo**, sem dependências, que pode ser copiado e aberto em outra máquina.
- O `data.json` contém `meta` (produto, versão, máquina, datas, duração), `scores` (os quatro indicadores) e `modules` (saída de cada módulo, com `success`, `warnings`, `errors` e `data`).
- Os formatos gerados dependem de `Reports.Formats` (padrão: HTML, JSON e CSV). Os CSVs só são criados quando há dados correspondentes.

---

## 18. FAQ e solução de problemas

**O relatório abriu em branco / sem informações.**
Normalmente isso indicava JSON inválido embutido (a versão atual blinda a serialização contra caracteres de controle). Garanta que está usando a versão atual e gere um novo relatório. Para diagnosticar, abra o `data.json` da pasta da execução — ele deve ser um JSON válido. Se estiver vazio, veja o item abaixo.

**Os dados vieram zerados.**
Quase sempre é falta de privilégios ou indisponibilidade de coleta. Rode o `Launcher.bat` como **Administrador**. Em **Windows mais antigos**, a ferramenta recorre a WMI automaticamente; ainda assim, alguns itens podem ficar como "Indisponível". Verifique os avisos de cada módulo no card de status da Visão geral e no log em `Logs\`.

**Aparece "PowerShell compatível não disponível".**
É necessário Windows PowerShell 4.0+ (ou pwsh 7). Verifique com:
```
powershell -NoProfile -Command $PSVersionTable.PSVersion
```
Force um host específico com `--ps5` ou `--ps7`, se necessário.

**"Esta ferramenta requer Windows x64."**
A ferramenta só roda em arquitetura x64.

**A verificação de assinatura/hash dos processos não apareceu.**
Exige leitura dos executáveis e, em muitos casos, elevação. Rode como Administrador. Para forçar um recálculo limpo, é possível apagar a pasta `Cache\signatures\`.

**O nível "Informação" quase não aparece em Eventos.**
Isso é intencional: o módulo coleta apenas eventos relevantes ao diagnóstico para reduzir ruído.

**Quero apenas alguns módulos.**
Use `-Run`, por exemplo `Launcher.bat -Run Security,Network`.

**Como agendar?**
Use a opção **9** do menu ou `Launcher.bat -InstallSchedule` (cria uma tarefa diária; padrão 03:00, ajustável em `Config.json > Scheduler`). Remova com `-RemoveSchedule` e liste com `-ListSchedule`.

**Onde ficam os logs?**
Em `Logs\` (e `Logs\Archive\`). Aumente o detalhamento com `-LogLevel Debug`.

> Para troubleshooting avançado, consulte também `Docs\Troubleshooting.md`.

---

## 19. Boas práticas de utilização

- **Rode como Administrador** quando precisar do relatório completo (segurança, BitLocker, TPM, sessão CIM).
- **Use o menu** para uso pontual e a **linha de comando** para automação/scripts.
- **Arquive os relatórios** (ou o `data.json`) para comparar a evolução da máquina ao longo do tempo.
- **Limite os módulos** com `-Run` quando precisar de rapidez ou de um recorte específico.
- **Evite executar em paralelo** na mesma máquina — a ferramenta previne instâncias concorrentes por padrão (`PreventMultipleInstances`).
- **Mantenha a estrutura de pastas intacta**; a ferramenta resolve caminhos relativos a si mesma.
- **Não dependa dela para remediação** — ela diagnostica; a correção é decisão e ação do operador.

---

## 20. Desempenho e compatibilidade

- **Coleta otimizada:** uma **sessão CIM compartilhada** (DCOM) é reutilizada por todos os módulos, reduzindo o custo de conexão. A sessão é validada na criação; se não responder, a ferramenta usa consulta direta ou WMI.
- **Paralelismo controlado:** tarefas como o cálculo de hash usam um **pool de runspaces** com limite configurável (`General.MaxParallelism`, padrão 4), preservando a responsividade.
- **Cache com TTL:** verificações estáveis (ex.: assinaturas) são memoizadas, acelerando execuções repetidas (`Cache.SignatureTtlHours`, padrão 7 dias).
- **Janelas de amostragem curtas:** o monitoramento usa janelas breves (padrão 10 s) para um retrato representativo sem prender a máquina.
- **Compatibilidade ampla:** funciona de Windows PowerShell 4.0 ao 7+, em Windows 10/11 e Server 2012–2025. Em sistemas mais antigos, a coleta recai em WMI nativo quando a pilha CIM moderna não responde, e a serialização do relatório é blindada para permanecer válida independentemente do conteúdo coletado.
- **Tempo típico:** uma auditoria completa costuma levar de alguns segundos a poucos minutos, dependendo do volume de software, conexões e do hardware.

---

## 21. Versionamento e histórico

- **Versão atual:** 4.1.0.
- O histórico detalhado de alterações está em **`CHANGELOG.md`**.

O WRA v4.1.0 representa a quarta grande evolução da ferramenta. As versões anteriores foram desenvolvidas e utilizadas exclusivamente em ambiente local; esta é a primeira versão disponibilizada publicamente no GitHub.

Resumo do estado atual (4.1.0), além da coleta e do relatório base:

- Menu interativo no Launcher e barra de progresso na auditoria.
- Tradução completa do dashboard para pt‑BR.
- **Filtros dinâmicos correlacionados** (sem busca textual), com chips/listas combináveis, ordenação por coluna e **indicadores interativos** que abrem a lista detalhada correspondente.
- **Módulo de análise de Eventos do Windows** (últimos 7 dias) com agrupamento, destaque de críticos/recorrentes e estatísticas.
- Verificação de **assinatura digital e SHA‑256** de processos via mecanismos nativos, com indicadores claros de sucesso/falha/indisponibilidade.
- **Compatibilidade com Windows mais antigos** (fallback nativo para WMI) e **blindagem da serialização JSON** do relatório.

> O número de versão permanece **4.1.0**; as melhorias acima compõem revisões dessa versão, descritas no `CHANGELOG.md`.

---

## 22. Créditos

**Windows Resource Auditor v4.1.0**

**Desenvolvido por Edsilas.**

Ferramenta somente leitura de auditoria, monitoramento, inventário, diagnóstico e relatório de recursos do Windows — construída exclusivamente com tecnologias nativas do Windows e do PowerShell, sem dependências externas.
