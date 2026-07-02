# Windows Resource Auditor v4.1.0 — Referência de Configuração

Documento gerado a partir de `Config/Config.schema.json` e do `Config/Config.json` distribuído. **Toda configuração operacional vive no `Config.json`**; o schema carrega os tipos, limites e valores padrão. Caminhos usam notação pontuada (ex.: `Thresholds.Cpu.Warning`).

> Acesso em código: `Get-WRAConfigValue -Path '<caminho>' -Default <valor>`.


## Version

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Version` | string | `4.1.0` | `4.1.0` | — |

## General

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `General.ComputerNameOverride` | string | `` | `` | — |
| `General.Culture` | string | `auto` | `auto` | — |
| `General.MaxParallelism` | integer | `4` | `4` | min 1; max 64 |
| `General.PreferRunspaces` | boolean | true | true | — |
| `General.PreventMultipleInstances` | boolean | true | true | — |
| `General.FailSafe` | boolean | true | true | — |

## Logging

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Logging.Level` | string | `Info` | `Info` | um de: `Trace`, `Debug`, `Info`, `Warn`, `Error` |
| `Logging.Directory` | string | `Logs` | `Logs` | — |
| `Logging.FileNamePattern` | string | `WRA_{date}.log` | `WRA_{date}.log` | — |
| `Logging.IncludeStackTrace` | boolean | true | true | — |
| `Logging.Encoding` | string | `utf8-no-bom` | `utf8-no-bom` | um de: `utf8-no-bom`, `utf8-bom` |
| `Logging.Console.Enabled` | boolean | true | true | — |
| `Logging.Console.UseColor` | boolean | true | true | — |
| `Logging.Rotation.Enabled` | boolean | true | true | — |
| `Logging.Rotation.MaxSizeMB` | integer | `10` | `10` | min 1; max 1024 |
| `Logging.Rotation.MaxAgeDays` | integer | `30` | `30` | min 1; max 3650 |
| `Logging.Rotation.MaxFiles` | integer | `60` | `60` | min 1; max 10000 |
| `Logging.Rotation.Compress` | boolean | true | true | — |
| `Logging.Rotation.ArchiveSubdir` | string | `Archive` | `Archive` | — |

## Modules

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Modules.Enabled` | array | `["Monitor", "ProcessAnalyzer", "Network", "Security", "In…` | `["Monitor", "ProcessAnalyzer", "Network", "Security", "In…` | — |
| `Modules.Monitor.Enabled` | boolean | true | true | — |
| `Modules.Monitor.SampleIntervalSeconds` | integer | `2` | `2` | min 1; max 3600 |
| `Modules.Monitor.DurationSeconds` | integer | `10` | `10` | min 1; max 86400 |
| `Modules.Monitor.UseEtw` | boolean | true | true | — |
| `Modules.Monitor.UsePerformanceCounters` | boolean | true | true | — |
| `Modules.Monitor.TopProcesses` | integer | `10` | `10` | min 1; max 1000 |
| `Modules.Monitor.CollectGpu` | boolean | true | true | — |
| `Modules.Monitor.IncludeServices` | boolean | true | true | — |
| `Modules.Monitor.IncludeEvents` | boolean | true | true | — |
| `Modules.Monitor.EventsLookbackHours` | integer | `24` | `24` | min 1; max 8760 |
| `Modules.Monitor.EventsMaxItems` | integer | `25` | `25` | min 1; max 10000 |
| `Modules.Monitor.AutoStoppedServicesMax` | integer | `25` | `25` | min 1; max 10000 |
| `Modules.ProcessAnalyzer.Enabled` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.IncludeCommandLine` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.ComputeHashes` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.VerifySignatures` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.ResolveModules` | boolean | false | false | — |
| `Modules.ProcessAnalyzer.ResolveOwner` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.CorrelateServices` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.CorrelateStartup` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.ParallelHashing` | boolean | true | true | — |
| `Modules.ProcessAnalyzer.HashMaxFileSizeMB` | integer | `512` | `512` | min 0; max 1048576 |
| `Modules.ProcessAnalyzer.MaxProcesses` | integer | `0` | `0` | min 0; max 100000 |
| `Modules.Network.Enabled` | boolean | true | true | — |
| `Modules.Network.ResolveDns` | boolean | false | false | — |
| `Modules.Network.IncludeInterfaces` | boolean | true | true | — |
| `Modules.Network.IncludeConnections` | boolean | true | true | — |
| `Modules.Network.IncludeListeners` | boolean | true | true | — |
| `Modules.Network.IncludeRoutes` | boolean | true | true | — |
| `Modules.Network.IncludeShares` | boolean | true | true | — |
| `Modules.Network.IncludeSessions` | boolean | true | true | — |
| `Modules.Network.IncludeFirewallProfiles` | boolean | true | true | — |
| `Modules.Network.IncludeVpn` | boolean | true | true | — |
| `Modules.Network.IncludeHyperVSwitch` | boolean | true | true | — |
| `Modules.Network.CorrelateProcesses` | boolean | true | true | — |
| `Modules.Network.MaxConnections` | integer | `0` | `0` | min 0; max 1000000 |
| `Modules.Network.CapturePacketContent` | boolean | false | false | — |
| `Modules.Security.Enabled` | boolean | true | true | — |
| `Modules.Security.CheckDefender` | boolean | true | true | — |
| `Modules.Security.CheckFirewall` | boolean | true | true | — |
| `Modules.Security.CheckSmartScreen` | boolean | true | true | — |
| `Modules.Security.CheckUac` | boolean | true | true | — |
| `Modules.Security.CheckTpm` | boolean | true | true | — |
| `Modules.Security.CheckSecureBoot` | boolean | true | true | — |
| `Modules.Security.CheckBitLocker` | boolean | true | true | — |
| `Modules.Security.CheckCredentialGuard` | boolean | true | true | — |
| `Modules.Security.CheckMemoryIntegrity` | boolean | true | true | — |
| `Modules.Security.CheckWindowsUpdate` | boolean | true | true | — |
| `Modules.Security.CheckEvents` | boolean | true | true | — |
| `Modules.Security.UpdateMaxAgeDays` | integer | `35` | `35` | min 1; max 3650 |
| `Modules.Security.EventsLookbackHours` | integer | `24` | `24` | min 1; max 8760 |
| `Modules.Inventory.Enabled` | boolean | true | true | — |
| `Modules.Inventory.IncludeHardware` | boolean | true | true | — |
| `Modules.Inventory.IncludeFirmware` | boolean | true | true | — |
| `Modules.Inventory.IncludeOperatingSystem` | boolean | true | true | — |
| `Modules.Inventory.IncludeSoftware` | boolean | true | true | — |
| `Modules.Inventory.IncludeFeatures` | boolean | true | true | — |
| `Modules.Inventory.IncludeControllers` | boolean | true | true | — |
| `Modules.Inventory.IncludePrinters` | boolean | true | true | — |
| `Modules.Inventory.IncludeNetworkAdapters` | boolean | true | true | — |
| `Modules.Inventory.IncludeLicensing` | boolean | true | true | — |

## Thresholds

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Thresholds.Cpu.WarnPercent` | number | `80` | `80` | min 0; max 100 |
| `Thresholds.Cpu.CriticalPercent` | number | `95` | `95` | min 0; max 100 |
| `Thresholds.Cpu.SustainSeconds` | integer | `30` | `30` | min 0; max 86400 |
| `Thresholds.Memory.WarnPercent` | number | `80` | `80` | min 0; max 100 |
| `Thresholds.Memory.CriticalPercent` | number | `92` | `92` | min 0; max 100 |
| `Thresholds.Disk.WarnPercent` | number | `85` | `85` | min 0; max 100 |
| `Thresholds.Disk.CriticalPercent` | number | `95` | `95` | min 0; max 100 |
| `Thresholds.Disk.QueueLengthWarn` | number | `2` | `2` | min 0; max 1000 |
| `Thresholds.Network.WarnMbps` | number | `800` | `800` | min 0; max 1000000 |

## Timeouts

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Timeouts.OperationSeconds` | integer | `120` | `120` | min 1; max 86400 |
| `Timeouts.ModuleSeconds` | integer | `300` | `300` | min 1; max 86400 |
| `Timeouts.CimSeconds` | integer | `30` | `30` | min 1; max 3600 |
| `Timeouts.ProcessSeconds` | integer | `60` | `60` | min 1; max 3600 |

## Scheduler

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Scheduler.Enabled` | boolean | false | false | — |
| `Scheduler.TaskNamePrefix` | string | `WRA_` | `WRA_` | — |
| `Scheduler.RunAsHighest` | boolean | true | true | — |
| `Scheduler.PreventMultipleInstances` | boolean | true | true | — |
| `Scheduler.Tasks` | array | `[{"Name": "DailyAudit", "Trigger": "Daily", "At": "03:00"…` | `[{"Name": "DailyAudit", "Trigger": "Daily", "At": "03:00"…` | — |

## Triggers

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Triggers.Enabled` | boolean | false | false | — |
| `Triggers.PollSeconds` | integer | `15` | `15` | min 1; max 3600 |
| `Triggers.CooldownSeconds` | integer | `300` | `300` | min 0; max 86400 |
| `Triggers.Rules` | array | `[{"Name": "CpuSpike", "Metric": "Cpu", "Operator": ">=", …` | `[{"Name": "CpuSpike", "Metric": "Cpu", "Operator": ">=", …` | — |

## Reports

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Reports.Directory` | string | `Reports` | `Reports` | — |
| `Reports.Formats` | array | `["HTML", "JSON", "CSV"]` | `["HTML", "JSON", "CSV"]` | — |
| `Reports.KeepLatest` | boolean | true | true | — |
| `Reports.RetentionRuns` | integer | `30` | `30` | min 1; max 100000 |
| `Reports.EmbedAssets` | boolean | true | true | — |
| `Reports.Title` | string | `Windows Resource Auditor Report` | `Windows Resource Auditor Report` | — |

## Scoring

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Scoring.Health.Weights.Performance` | number | `0.4` | `0.4` | min 0; max 1 |
| `Scoring.Health.Weights.Security` | number | `0.4` | `0.4` | min 0; max 1 |
| `Scoring.Health.Weights.Reliability` | number | `0.2` | `0.2` | min 0; max 1 |
| `Scoring.Security.Weights.Defender` | number | `0.25` | `0.25` | min 0; max 1 |
| `Scoring.Security.Weights.Firewall` | number | `0.2` | `0.2` | min 0; max 1 |
| `Scoring.Security.Weights.WindowsUpdate` | number | `0.2` | `0.2` | min 0; max 1 |
| `Scoring.Security.Weights.BitLocker` | number | `0.15` | `0.15` | min 0; max 1 |
| `Scoring.Security.Weights.SecureBoot` | number | `0.1` | `0.1` | min 0; max 1 |
| `Scoring.Security.Weights.Uac` | number | `0.1` | `0.1` | min 0; max 1 |
| `Scoring.Performance.Weights.Cpu` | number | `0.34` | `0.34` | min 0; max 1 |
| `Scoring.Performance.Weights.Memory` | number | `0.33` | `0.33` | min 0; max 1 |
| `Scoring.Performance.Weights.Disk` | number | `0.33` | `0.33` | min 0; max 1 |
| `Scoring.Risk.Scale` | integer | `100` | `100` | min 1; max 1000 |

## Severity

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Severity.Levels` | array | `["Info", "Low", "Medium", "High", "Critical"]` | `["Info", "Low", "Medium", "High", "Critical"]` | — |
| `Severity.Colors.Info` | string | `#3b82f6` | `#3b82f6` | — |
| `Severity.Colors.Low` | string | `#22c55e` | `#22c55e` | — |
| `Severity.Colors.Medium` | string | `#eab308` | `#eab308` | — |
| `Severity.Colors.High` | string | `#f97316` | `#f97316` | — |
| `Severity.Colors.Critical` | string | `#ef4444` | `#ef4444` | — |

## Performance

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Performance.UseSharedCimSession` | boolean | true | true | — |
| `Performance.CimProtocol` | string | `Dcom` | `Dcom` | um de: `Dcom`, `Wsman` |
| `Performance.CacheTtlSeconds` | integer | `300` | `300` | min 0; max 86400 |

## Cache

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Cache.Enabled` | boolean | true | true | — |
| `Cache.Directory` | string | `Cache` | `Cache` | — |
| `Cache.SignatureTtlHours` | integer | `168` | `168` | min 0; max 100000 |
| `Cache.BaselineEnabled` | boolean | true | true | — |

## Safety

| Caminho | Tipo | Padrão | Distribuído | Restrições |
|---|---|---|---|---|
| `Safety.ReadOnly` | boolean | true | true | — |
| `Safety.AllowManualRecommendationsExport` | boolean | true | true | — |
| `Safety.NeverModifySystem` | boolean | true | true | — |

---

_141 chaves documentadas. Listas como `Modules.Enabled`, `Scheduler.Tasks` e `Triggers.Rules` são coleções; consulte o `Config.json` para a estrutura de cada item._
