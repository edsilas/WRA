# Windows Resource Auditor v1.1.0 — Solução de Problemas

## Códigos de saída

### Launcher (`Launcher.bat`)

| Código | Significado | Ação sugerida |
|---|---|---|
| 0 | Sucesso (ou repassa o código do Core) | — |
| 10 | Sistema não é x64 | Execute em um host x64 |
| 11 | Nenhum host PowerShell encontrado | Instale o PowerShell 5.1+ ou 7+ |
| 12 | Versão do PowerShell muito antiga | Atualize para 4.0+ (idealmente 5.1/7+) |
| 13 | `Core.ps1` ausente ou corrompido | Restaure os arquivos da suíte |

### Core (`Core.ps1`)

| Código | Significado | Ação sugerida |
|---|---|---|
| 0 | Execução concluída com sucesso | — |
| 30 | Falha de bootstrap | Verifique permissões e integridade dos arquivos |
| 31 | Configuração indisponível | Valide o `Config.json`; o Core usa defaults se possível |
| 33 | Framework de módulos indisponível | Verifique a pasta `Modules\` |
| 34 | Nenhum módulo executado | Cheque `Modules.Enabled` e a seleção `-Run` |
| 35 | Falha ao gerar relatório | Verifique permissões em `Reports\` e `Templates\`/`Assets\` |
| 36 | Concluído com falhas em um ou mais módulos | Consulte os avisos/erros no log e no dashboard |
| 37 | Argumentos inválidos | Revise os parâmetros (`-Help`) |
| 38 | Outra instância já em execução | Aguarde a anterior ou ajuste `General.PreventMultipleInstances` |
| 39 | Falha ao instalar/remover tarefa agendada | Execute como administrador; verifique o `schtasks` |
| 40 | Exceção não tratada | Consulte o log mais recente em `Logs\` |

## Problemas comuns

**A elevação (UAC) foi recusada e a coleta veio incompleta.**
O Launcher continua sem elevação (Fail Safe). Módulos como Security marcam itens
não acessíveis com avisos. Execute como administrador para a auditoria completa.

**`Security.Audit` retorna muitos itens "não aplicáveis".**
É esperado em hardware/edições sem o recurso (ex.: sem TPM ou sem Secure Boot).
Esses itens são **excluídos** do Security Score, sem penalizar a pontuação.

**O dashboard abre, mas algumas seções estão vazias.**
A seção só é renderizada quando o módulo correspondente foi executado e retornou
dados. Verifique a seleção `-Run` e a lista `Modules.Enabled`.

**`-InstallSchedule` falha (código 39).**
Criar tarefas exige privilégios administrativos. Abra o terminal como
administrador e tente novamente. Confirme que `schtasks.exe` está acessível.

**O modo `-Watch` parece não disparar.**
Os disparos exigem que a métrica viole o limite por `ForSeconds` contínuos e
respeitam `Triggers.CooldownSeconds` após cada disparo. Reduza `ForSeconds` ou
ajuste os limites em `Triggers.Rules` para testar.

**Os contadores de desempenho retornam zero ou erro.**
A suíte usa classes CIM `Win32_PerfFormattedData_*`. Se o repositório de
performance estiver corrompido, reconstrua-o com `lodctr /R` (ação do sistema,
fora do escopo da ferramenta) e tente novamente.

**A sessão CIM compartilhada não foi criada.**
Em ambientes restritos, a ferramenta cai automaticamente para consultas diretas
(`Get-CimInstance` sem sessão). Para forçar, ajuste
`Performance.UseSharedCimSession` e `Performance.CimProtocol`.

**Logs não aparecem.**
Verifique `Logging.Directory` e permissões de escrita. O log nunca lança exceção
ao chamador; falhas de escrita são silenciosas por design.

## Onde investigar

- **Logs**: `Logs\WRA_<data>.log` (rotacionados; arquivados em `Logs\Archive\`).
- **Dados brutos**: `Reports\Latest\data.json`.
- **Diagnóstico de configuração**: o Core registra um diagnóstico de
  configuração no início (chaves inválidas caem para o default sem interromper).
- **Testes**: `powershell -File Tests\Invoke-Tests.ps1` para validar o ambiente.
