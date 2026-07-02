# Changelog

Todas as mudanças relevantes deste projeto são documentadas neste arquivo.
O formato segue, de modo simplificado, o estilo *Keep a Changelog*.

## [4.1.0] — Primeira versão pública

Primeira versão completa do Windows Resource Auditor: ferramenta somente leitura
de auditoria, monitoramento, inventário, diagnóstico e relatório do Windows.

O WRA v4.1.0 representa a quarta grande evolução da ferramenta. As versões
anteriores foram desenvolvidas e utilizadas exclusivamente em ambiente local.
Esta é a primeira versão disponibilizada publicamente no GitHub.

### Corrigido (revisão de qualidade)

- **Falsos positivos em serviços:** serviços "Automático (Início Atrasado)"
  que concluem sua tarefa e param por design não são mais tratados como o
  mesmo problema de um serviço automático travado; a lista distingue o tipo de
  início e sinaliza com severidade contextual.
- **Falso positivo de reinicialização pendente:** `PendingFileRenameOperations`
  deixou de disparar sozinho o alerta (entradas transitórias de instaladores
  causavam ruído); permanecem os sinais confiáveis (CBS e Windows Update).
- **Windows Update sem histórico:** quando não há dados de hotfix, o estado
  agora é "Desconhecido"/indeterminável em vez de "Atenção" por suposição, e a
  recomendação correspondente só é emitida quando o achado é confirmável.
- **Contadores de assinatura de processos:** formatos não assináveis
  ("Não aplicável") passaram a contar como "não verificada" — os cards agora
  batem com a tabela.
- **Exportação CSV:** os indicadores de ordenação (▲/▼) não vazam mais para o
  arquivo exportado; espaços normalizados.
- **Interface:** valores ausentes exibem "n/d" (sem unidade solta), scores
  não numéricos não corrompem mais os anéis, rótulos de ativação traduzidos, e
  comparação de nulos corrigida no gerenciador CIM (StrictMode).
- **Testes:** suíte de Scoring ampliada para cobrir a confiabilidade
  indeterminada e o teto quando eventos não podem ser lidos.

### Removido (revisão pós-entrega)

- **Seção de Drivers.** A coleta, a exibição no dashboard e a exportação
  `drivers.csv` foram removidas por não serem mais necessárias. A remoção não
  afeta os demais coletores do módulo Inventory (hardware, firmware, SO,
  software, impressoras e adaptadores de rede) nem qualquer outra
  funcionalidade já validada.

### Adicionado (revisão pós-entrega)

- **Menu interativo no `Launcher.bat`.** Ao executar o Launcher sem argumentos
  (duplo clique ou `Launcher.bat`), é exibido um menu numerado para escolher a
  operação sem digitar comandos do PowerShell: auditoria completa, cada módulo
  isolado (Inventário, Monitoramento, Rede, Processos, Segurança), listar
  módulos, abrir o último dashboard e agendar execução automática. Quando o
  Launcher é chamado com argumentos explícitos, a execução continua direta (para
  uso em scripts e no Agendador de Tarefas).
- **Barra de progresso.** Durante a auditoria, o conjunto de operações exibe uma
  barra de progresso nativa (`Write-Progress`) indicando o módulo em execução e
  o percentual concluído. É suprimida automaticamente no modo `-Quiet`.

### Corrigido (revisão pós-entrega)

- **Deteccao do host PowerShell no `Launcher.bat` (codigo 12 indevido).** A
  captura da versao via `for /f` com aspas aninhadas podia falhar (e o `where
  pwsh` pode retornar um stub do WindowsApps que nao responde), fazendo o
  Launcher rejeitar PS 5.1/7 validos. A deteccao passou a usar um probe primario
  sem aspas internas mais um fallback via arquivo temporario em ASCII, com
  diagnostico dos caminhos detectados em caso de falha.
- **`Invoke-WRAOperationSet` retornava com operador vírgula (`, $arr`).** Isso
  fazia chamadores que usam `@(...)` direto receberem um único elemento (o array
  inteiro) em vez dos envelopes. Removida a vírgula para um contrato previsível.

- **Quatro defeitos distintos por módulo (revelados após resolver o `@()`):**
  *Inventory* — uma substituição automática de `@()`→`.ToArray()` atingiu por
  engano `$features`, que em `Invoke-WRAInventoryCollect` guarda o retorno de uma
  função (não a lista); revertido para `@($features)`.
  *Network* — `Win32_Share.Type` vale `2147483648` ou mais para compartilhamentos
  administrativos (`C$`, `ADMIN$`, `IPC$`), estourando `[int]`; trocado para
  `[long]`. O valor de serviços por PID (indexado em dicionário) também usava
  `@(List)` e passou a `.ToArray()`.
  *ProcessAnalyzer* — `@($svcByPid[$thePid])` era novamente `@(List[object])`
  (acesso indexado, não capturado pela primeira varredura); corrigido para
  `.ToArray()`.
  *Security* — `Get-WRASecDeviceGuard` usava `(if (...) { } else { })` como
  expressão de argumento de `New-WRASecCheck`, sintaxe que o PowerShell 5.1
  rejeita; os valores passaram a ser pré-computados em variáveis.
- **`@()` sobre `List[object]` no Windows PowerShell 5.1 (causa das falhas de coleta).**
  No 5.1, o operador de subexpressão de array `@($lista)` aplicado a uma
  `System.Collections.Generic.List[object]` contendo objetos lança
  `System.ArgumentException: Argument types do not match` — comportamento ausente
  no PS7. Como os cinco módulos de domínio montam seus resultados com esse padrão
  (`@($cpu)`, `@($ram)`, `@($list)`, `@($ipv4)`, etc.), todos falhavam na coleta.
  Correção: as 42 ocorrências de `@($listaLocal)` foram trocadas por
  `$listaLocal.ToArray()`, que materializa a lista via chamada .NET direta, sem o
  operador `@()`. Também foi adicionado o registro do *stack trace* completo nas
  exceções de operação (facilita diagnóstico) e corrigida a contagem do resumo
  (consumo via `@()` de retorno com operador vírgula resultava em "1 operação").
- **Colisão de variável com parâmetro tipado em `Invoke-WRAOperationSet`.** A
  variável local `$selection` colidia (nomes são *case-insensitive* no PowerShell)
  com o parâmetro `[string[]] $Selection`. Ao atribuir os objetos de operação
  resolvidos (`PSCustomObject`) a essa variável com restrição de tipo `[string[]]`,
  o PowerShell os convertia para *string* (`"@{Module=...; Operation=...}"`). Em
  seguida `Get-WRAProp` não conseguia ler `Module`/`Operation` das strings, e
  **todas** as operações eram puladas — a auditoria terminava com 0 coletas
  ("1 operação | 1 com falha", sem `[ERROR]`). Correção: a variável local foi
  renomeada para `$resolvedOps`, eliminando a colisão; os objetos permanecem
  `PSCustomObject` e as 5 operações executam. Afetava PS 5.1 e PS 7.
- **`if` como valor de chave de hashtable no Windows PowerShell 5.1.** Construções
  `Chave = if (...) { ... } else { ... }` dentro de literais `[PSCustomObject]@{ }`
  disparavam *"Argument types do not match"* em runtime no 5.1 (válido no PS7).
  Afetava a coleta de hardware/firmware do Inventory, as interfaces do Network e o
  cálculo de confiabilidade do Scoring. Correção: eliminadas as 25 ocorrências —
  os valores passam a ser obtidos via `Get-WRAProp`/`Get-WRANum` (já null-safe) ou
  pré-calculados em variáveis antes do objeto. Atribuições `$var = if (...)` a
  variáveis simples são válidas no 5.1 e foram mantidas.
- **Visibilidade dos handlers no Windows PowerShell 5.1.** No 5.1, funções de um
  módulo de domínio não ficam visíveis ao `Get-Command` chamado de dentro de
  outro módulo (o Dispatcher), mesmo importadas com `-Global`. Resultado: todos
  os módulos falhavam imediatamente (envelope de falha, sem coleta). Correção:
  `Register-WRAModules` agora captura o `PSModuleInfo` de cada módulo importado
  (`-PassThru`) e `Invoke-WRAOperation` invoca o handler **dentro do escopo do
  módulo** (`& $moduleInfo { & $handler -Context $ctx }`), com fallback para
  `Get-Command`. Robusto no 5.1 e no 7.
- **Despacho de operações no Windows PowerShell 5.1 (StrictMode).** Sob
  `Set-StrictMode -Version 2.0` no Windows PowerShell 5.1, a execução de
  `-Run All` falhava com *"The property 'Module' cannot be found on this
  object"*. A causa era a leitura direta de `$op.Module`/`$op.Operation` na
  resolução da seleção, combinada com o empacotamento por operador vírgula na
  fronteira de módulo. Correção: `Resolve-WRASelection` passa a devolver a lista
  diretamente; `Invoke-WRAOperationSet` força um array plano com `@(...)` e usa
  acesso seguro via `Get-WRAProp`; o caminho alternativo equivalente no Core foi
  igualmente blindado com `Get-CoreProp`. O PowerShell 7+ não era afetado.
- **Codificação dos scripts.** Adicionado BOM UTF-8 a todos os arquivos
  `.ps1`/`.psm1` e normalizados caracteres não-ASCII, garantindo leitura
  correta no Windows PowerShell 5.1/4.0.


### Adicionado

- **Bootstrap** (`Launcher.bat`): seleção de host (PowerShell 7+ preferido,
  Windows PowerShell como alternativa), validação de arquitetura x64 e versão,
  elevação única com continuidade sem elevação se recusada, verificação de
  integridade e de versão offline.
- **Orquestrador** (`Core.ps1`): *composition root* com detecção de capacidades
  em runtime, pipeline de inicialização → coleta → relatório → encerramento,
  códigos de saída padronizados e guarda de **instância única** por mutex.
- **Configuração**: `Config.json` (valores) + `Config.schema.json` (tipos,
  limites, defaults) com mesclagem profunda e validação não fatal.
- **Log**: thread-safe com mutex determinístico, rotação por tamanho/idade/
  contagem e compactação opcional; nunca lança ao chamador.
- **Framework de módulos**: envelope de resultado universal, contrato de módulo,
  auto-registro e despacho (Dispatcher), pool de runspaces para paralelismo
  interno.
- **Módulos de domínio**:
  - **Monitor** (`Collect`): CPU, memória, GPU, disco, rede, processos,
    serviços e eventos.
  - **ProcessAnalyzer** (`Analyze`): processos, relações, proprietário, hash
    SHA-256 e assinatura Authenticode (em paralelo, com cache em disco),
    correlação.
  - **Network** (`Audit`): conexões correlacionadas a processo, interfaces,
    rotas, firewall, shares, proxy, VPN e Hyper-V — **sem captura de pacotes**.
  - **Security** (`Audit`): Defender, Firewall, SmartScreen, UAC, TPM, Secure
    Boot, BitLocker, Credential Guard, Memory Integrity, Windows Update e
    eventos, com pontuação justa (itens não aplicáveis excluídos).
  - **Inventory** (`Collect`): hardware, SO, licenciamento, programas (via
    Registro, evitando `Win32_Product`), recursos, impressoras e NICs.
- **Indicadores** (`Scoring`): Health, Security, Performance, Risk e Reliability
  com renormalização quando módulos estão ausentes.
- **Relatórios** (`Reporting`): `dashboard.html` autocontido e offline (scores,
  busca, filtros, exportação), `data.json` e CSVs, por execução com cópia em
  `Latest` e retenção configurável. Injeção de dados com neutralização de
  `</script>`.
- **Agendamento** (`Scheduler`): tarefas para inicialização, logon, intervalo,
  diária e semanal via XML + `schtasks`, como SYSTEM, nível mais alto e política
  `IgnoreNew`.
- **Gatilhos** (`Triggers`): vigilância contínua (`-Watch`) com regras por CPU,
  memória, disco, eventos críticos e serviços parados, com tempo de violação e
  cooldown configuráveis.
- **Otimização** (`CimManager`): sessão CIM compartilhada e reutilizada por toda
  a coleta (DCOM por padrão), com cache de memoização por TTL. Degrada com
  segurança para consultas diretas.
- **Testes**: runner nativo (`Tests\Invoke-Tests.ps1`) sem Pester/Gallery, com
  casos para contratos, configuração, log, dispatcher, scoring, scheduler,
  triggers, reporting e integração ao vivo.
- **Documentação**: README, guias de uso e desenvolvimento, referência de
  módulos, referência de configuração gerada do schema, solução de problemas e
  notas de arquitetura, integração e otimização.

### Garantias de projeto

- Somente leitura: o sistema nunca é modificado automaticamente.
- Offline e sem dependências externas; apenas APIs nativas do Windows.
- Compatível com Windows 10/11 e Server 2012–2025 (inclui o Windows Server 2025); PowerShell 4.0/5.1/7+; x64.
- Fail Safe em todos os subsistemas.
