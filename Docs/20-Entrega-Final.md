# Windows Resource Auditor v1.1.0 — Entrega Final

Pacote de entrega completo e revisado. Esta é a vigésima e última etapa do
plano: empacotamento, manifesto e checklist de aceitação.

## Resumo

Ferramenta **somente leitura** de auditoria, monitoramento, inventário,
diagnóstico e relatório do Windows, escrita em PowerShell + Batch + HTML/CSS/JS,
sem dependências externas, compatível com Windows 10/11 e Server 2012–2025,
PowerShell 4.0/5.1/7+, x64.

## Estrutura entregue

```
windows-resource-auditor/
├─ Launcher.bat                  Bootstrap (host, elevacao, validacao) — ASCII, sem BOM
├─ Core.ps1                      Orquestrador (composition root)
├─ README.md                     Visao geral e inicio rapido
├─ CHANGELOG.md                  Historico de versoes
├─ Config/
│  ├─ Config.json                Valores operacionais (unica fonte)
│  └─ Config.schema.json         Tipos, limites e defaults
├─ Modules/
│  ├─ Contracts/                 Common, ResultEnvelope, ModuleContract
│  ├─ Infrastructure/            Configuration, Logger, Dispatcher, RunspaceManager,
│  │                             CimManager, Reporting, Scheduler, Triggers
│  └─ Domain/                    Monitor, ProcessAnalyzer, Network, Security, Inventory
├─ Templates/Dashboard.template.html
├─ Assets/
│  ├─ css/dashboard.css
│  └─ js/dashboard.js
├─ Tests/
│  ├─ Invoke-Tests.ps1           Runner nativo (sem Pester/Gallery)
│  ├─ WRATest.psm1               Framework de testes
│  └─ Cases/                     10 casos (contratos → integracao)
├─ Docs/                         Documentacao completa (uso, config, modulos,
│                                desenvolvimento, troubleshooting, arquitetura,
│                                integracao, otimizacao, revisao)
├─ Reports/                      (runtime) saidas por execucao + Latest
├─ Logs/  └─ Archive/            (runtime) logs rotacionados
└─ Cache/ └─ signatures/         (runtime) cache em disco
```

48 arquivos versionáveis; 30 arquivos `.ps1`/`.psm1` (~6.000 linhas).

## Como executar

```bat
Launcher.bat                       REM auditoria completa + relatorio
Launcher.bat -ListModules          REM lista os modulos
Launcher.bat -Run Security         REM apenas seguranca (requer elevacao)
Launcher.bat -InstallSchedule      REM instala as tarefas agendadas
Launcher.bat -Watch                REM vigilancia continua por gatilhos
powershell -File Tests\Invoke-Tests.ps1   REM bateria de testes
```

Abra `Reports\Latest\dashboard.html` no navegador (autocontido, offline).

## Checklist de aceitação

| Item | Estado |
|---|---|
| Somente leitura; nunca auto-modifica o sistema | OK |
| Sem pseudocódigo / implementações parciais | OK |
| Sem bibliotecas externas / Internet / PS Gallery | OK |
| Configuração exclusiva no `Config.json` (+ schema) | OK |
| Envelope de retorno padronizado | OK |
| Prioridade CIM › Win32 › PerfCounters › ETW › EventLog › Registro › WMI | OK |
| Win10/11 + Server 2012–2025; PS 4.0/5.1/7+; x64 | OK |
| Nunca captura conteúdo de pacotes | OK |
| Correções apenas como recomendação | OK |
| Relatório HTML/JSON/CSV offline | OK |
| Agendamento (boot/logon/intervalo/diário/semanal) | OK |
| Gatilhos automáticos por limite | OK |
| Instância única (mutex) | OK |
| Otimização (sessão CIM compartilhada, cache TTL) | OK |
| Testes nativos (10 casos) | OK |
| Documentação completa | OK |
| Codificação: `.ps1`/`.psm1` UTF-8 com BOM; `.bat` ASCII sem BOM | OK |
| Balanceamento, integração e referências de config verificados | OK |
| Dashboard verificado fim-a-fim (jsdom) | OK |

## Verificações finais executadas

- Balanceamento de delimitadores: 30/30 arquivos OK.
- JSON válido; `Export-ModuleMember` em todos os módulos.
- Sem chamadas pendentes; 14/14 sondagens do Core resolvidas; 100% das
  referências de configuração resolvidas.
- Auto-registro + payload nos 5 módulos de domínio; envelope alinhado.
- Dashboard renderizado (8 seções, sem breakout `</script>`); XML de tarefas
  bem-formado nos 6 gatilhos.
- Codificação corrigida e revalidada (BOM UTF-8; scripts 100% ASCII).

## Observações para implantação

1. Execute a primeira auditoria como administrador para a cobertura completa de
   Security e correlação de processos/conexões.
2. Ajuste limites e regras em `Config.json` conforme o ambiente (servidores
   versus estações).
3. Para coleta periódica, use `-InstallSchedule`; para reação a picos, `-Watch`.
4. Os diretórios `Reports\`, `Logs\` e `Cache\` são populados em tempo de
   execução; trate os relatórios conforme sua política de dados.

**Projeto concluído — 20/20 etapas entregues.**
