# Native LXC on Synology DSM (experimental)

Dieses Repository untersucht klassischen LXC-Support direkt unter Synology DSM. Zielplattform ist zunaechst eine **Synology DS224+ mit DSM 7.3.2-86009 Update 4**; Entwicklung und riskante Tests finden zuerst in Virtual DSM statt.

> **Status:** Phase 1 - read-only Machbarkeitsanalyse. Es wird noch nichts installiert und kein Container gestartet.

## Analyse ausfuehren

```sh
sudo sh scripts/analyze-dsm.sh
```

Das Skript veraendert keine DSM-Einstellungen, Mounts, Module oder Netzwerke. Es liest Systeminformationen und schreibt nur nach `./artifacts` beziehungsweise in das explizit gewaehlte Ausgabeverzeichnis:

```sh
sudo sh scripts/analyze-dsm.sh --output /volume1/lxc-analysis
```

Den Bericht vor einer Veroeffentlichung auf Geraetekennungen und Pfade pruefen. Anschliessend dieselbe Analyse auf Virtual DSM und der physischen DS224+ ausfuehren und die entpackten Berichte vergleichen:

```sh
sh scripts/compare-reports.sh HARDWARE_REPORT_DIR VDSM_REPORT_DIR
```

Wenn der Vergleich keine relevanten Unterschiede zeigt, bewertet der Preflight den Bericht gegen die LXC-Mindestanforderungen:

```sh
sh scripts/evaluate-report.sh HARDWARE_REPORT_DIR
sh scripts/evaluate-report.sh VDSM_REPORT_DIR --output artifacts/vdsm-preflight.md
```

## Roadmap

1. Kernel, Namespaces, Cgroups, Dateisysteme und Sicherheitsfunktionen inventarisieren.
2. LXC-Userspace reproduzierbar und isoliert von DSM-Systembibliotheken bauen.
3. Einen minimalen, bevorzugt unprivilegierten Container in Virtual DSM starten.
4. Kernel- und Modulunterschiede zur physischen DS224+ pruefen.
5. Installation, Konfiguration, Backup und Reparatur nach DSM-Updates paketieren.

Siehe [Kompatibilitaets-Gate](docs/compatibility.md), [Sicherheitsmodell](docs/safety.md), [Architektur](docs/architecture.md) und [Recovery-Plan](docs/recovery.md).
