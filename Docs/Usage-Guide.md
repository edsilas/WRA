# Windows Resource Auditor v4.1.0 — Guia de Uso

## Linha de comando

A forma recomendada de execução é pelo `Launcher.bat`, que prepara o ambiente e
repassa todos os argumentos ao `Core.ps1`. Os parâmetros abaixo são do Core.

| Parâmetro | Descrição | Padrão |
|---|---|---|
| `-Run <itens>` | Módulos/operações a executar (lista separada por vírgula). Aceita `All`, `<Modulo>` ou `<Modulo>.<Operacao>` | `All` |
| `-ConfigPath <arquivo>` | Caminho alternativo para o `Config.json` | `Config\Config.json` |
| `-LogLevel <nivel>` | `Trace`, `Debug`, `Info`, `Warn` ou `Error` | `Info` |
| `-Format <fmt>` | Formato(s) de relatório: `HTML`, `JSON`, `CSV` | do config |
| `-NoReport` | Não gera relatórios | desligado |
| `-ListModules` | Lista os módulos registrados e encerra | — |
| `-InstallSchedule` | Instala as tarefas agendadas do `Config.json` | — |
| `-RemoveSchedule` | Remove as tarefas agendadas do WRA | — |
| `-ListSchedule` | Lista as tarefas agendadas do WRA | — |
| `-Watch` | Modo de vigilância contínua (gatilhos) | — |
| `-Quiet` | Suprime a saída de console | desligado |
| `-Version` | Mostra a versão e encerra | — |
| `-Help` | Mostra a ajuda e encerra | — |

### Flags do Launcher

| Flag | Efeito |
|---|---|
| `--ps7` | Força o uso do PowerShell 7+ (`pwsh`) |
| `--ps5` | Força o Windows PowerShell |
| `--noelevate` | Não tenta elevar privilégios |
| `--help` | Ajuda do próprio launcher |

## Exemplos

```bat
REM Auditoria completa (todos os módulos), relatório conforme o config
Launcher.bat -Run All

REM Somente segurança, em JSON, com log detalhado
Launcher.bat -Run Security -Format JSON -LogLevel Debug

REM Uma operação específica
Launcher.bat -Run Network.Audit

REM Coleta sem relatório, saída silenciosa (uso em pipelines)
Launcher.bat -Run Monitor,Inventory -NoReport -Quiet

REM Config alternativo (ex.: perfil de servidor)
Launcher.bat -ConfigPath C:\WRA\Config\Server.json
```

## Seleção de módulos (`-Run`)

- `All` — executa todos os módulos habilitados em `Modules.Enabled`.
- `<Modulo>` — todas as operações daquele módulo (ex.: `Monitor`).
- `<Modulo>.<Operacao>` — uma operação específica (ex.: `Security.Audit`),
  ignorando o filtro de habilitação.

Operações disponíveis: `Monitor.Collect`, `ProcessAnalyzer.Analyze`,
`Network.Audit`, `Security.Audit`, `Inventory.Collect`.

## Relatórios

Cada execução cria `Reports\<RunId>\` (RunId = `yyyyMMdd_HHmmss_HOST`) contendo:

- `dashboard.html` — painel autocontido (offline), com scores, busca, filtros e
  exportação.
- `data.json` — conjunto de dados completo.
- `*.csv` — `processes`, `connections`, `programs`,
  `recommendations` (quando os dados existem).

Uma cópia da última execução fica em `Reports\Latest\`. A retenção é controlada
por `Reports.RetentionRuns`.

## Agendamento

As tarefas são definidas em `Scheduler.Tasks` no `Config.json`. Cada item aceita:

| Campo | Significado |
|---|---|
| `Name` | Sufixo do nome da tarefa (prefixo de `Scheduler.TaskNamePrefix`) |
| `Trigger` | `Daily`, `Weekly`, `Startup`, `Logon`, `Interval` ou `Hourly` |
| `At` | Horário `HH:mm` (para Daily/Weekly/Interval/Hourly) |
| `IntervalMinutes` | Intervalo em minutos (para `Interval`) |
| `DaysOfWeek` | Dias (para `Weekly`), ex.: `["Monday","Friday"]` |
| `Run` | Seleção de módulos/operações |

```bat
REM Instalar todas as tarefas definidas no config (requer privilégios)
Launcher.bat -InstallSchedule

REM Conferir o que está agendado
Launcher.bat -ListSchedule

REM Remover as tarefas do WRA
Launcher.bat -RemoveSchedule
```

As tarefas rodam como **SYSTEM** com nível mais alto disponível e política
`IgnoreNew` (não inicia uma segunda instância). Internamente, o Scheduler gera o
XML da tarefa e o registra via `schtasks /XML`, evitando problemas de aspas e
garantindo compatibilidade do Server 2012 em diante.

## Vigilância por gatilhos (`-Watch`)

No modo `-Watch`, o WRA monitora métricas continuamente e dispara uma auditoria
quando uma regra é violada por tempo suficiente, respeitando um período de
cooldown. As regras ficam em `Triggers.Rules`:

| Campo | Significado |
|---|---|
| `Name` | Identificação da regra |
| `Metric` | `Cpu`, `Memory`, `Disk`, `CriticalEvents` ou `ServiceStopped` |
| `Operator` | `>=`, `>`, `<=`, `<`, `==` |
| `Value` | Limite numérico |
| `ForSeconds` | Tempo contínuo de violação antes de disparar |
| `Run` | Seleção de módulos a auditar quando disparar |

Parâmetros globais: `Triggers.PollSeconds` (intervalo de amostragem) e
`Triggers.CooldownSeconds` (espera após um disparo). Encerre com `Ctrl+C`.

```bat
REM Vigilância contínua usando as regras do config
Launcher.bat -Watch
```

## Instância única

Para evitar auditorias concorrentes (ex.: uma agendada coincidindo com uma
manual), o Core adquire um mutex nomeado. Se outra auditoria já estiver em
execução, o processo encerra com o código **38**. Controle por
`General.PreventMultipleInstances`.
