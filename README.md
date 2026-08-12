# Native LXC on Synology DSM (experimental)

Dieses Repository untersucht klassischen LXC-Support direkt unter Synology DSM. Zielplattform ist zunächst eine **Synology DS224+ mit DSM 7.3.2-86009 Update 4**; Entwicklung und riskante Tests finden zuerst in Virtual DSM statt.

> **Status:** Phase 1 – read-only Machbarkeitsanalyse. Es wird noch nichts installiert und kein Container gestartet.

## Analyse ausführen

```sh
sudo sh scripts/analyze-dsm.sh
```

Das Skript verändert keine DSM-Einstellungen, Mounts, Module oder Netzwerke. Es liest Systeminformationen und schreibt nur nach `./artifacts` beziehungsweise in das explizit gewählte Ausgabeverzeichnis:

```sh
sudo sh scripts/analyze-dsm.sh --output /volume1/lxc-analysis
```

Den Bericht vor einer Veröffentlichung auf Gerätekennungen und Pfade prüfen. Anschließend dieselbe Analyse auf Virtual DSM und der physischen DS224+ ausführen und die entpackten Berichte vergleichen:

```sh
sh scripts/compare-reports.sh VDSM_REPORT_DIR HARDWARE_REPORT_DIR
```

## Roadmap

1. Kernel, Namespaces, Cgroups, Dateisysteme und Sicherheitsfunktionen inventarisieren.
2. LXC-Userspace reproduzierbar und isoliert von DSM-Systembibliotheken bauen.
3. Einen minimalen, bevorzugt unprivilegierten Container in Virtual DSM starten.
4. Kernel- und Modulunterschiede zur physischen DS224+ prüfen.
5. Installation, Konfiguration, Backup und Reparatur nach DSM-Updates paketieren.

Siehe [Kompatibilitäts-Gate](docs/compatibility.md), [Sicherheitsmodell](docs/safety.md), [Architektur](docs/architecture.md) und [Recovery-Plan](docs/recovery.md).
