# Native LXC on Synology DSM (experimental)

Dieses Repository untersucht klassischen LXC-Support direkt unter Synology DSM. Zielplattform ist zunaechst eine **Synology DS224+ mit DSM 7.3.2-86009 Update 4**; Entwicklung und riskante Tests finden zuerst in Virtual DSM statt.

> **Status:** Phase 6 in Virtual DSM erreicht: Phase-5-Lab-Lifecycle ist validiert; ein konservatives experimentelles `.spk` kann lokal gebaut und geprueft werden, wurde aber noch nicht installiert.

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

## Phase 2 starten

Nach `PASS WITH CAUTION` auf Hardware und Virtual DSM beginnt Phase 2 nur in Virtual DSM:

```sh
sh scripts/check-phase2-prereqs.sh
sh scripts/plan-entware-bootstrap.sh --volume /volume1
sh scripts/fetch-sources.sh --output /volume1/Dev/lxc-on-dsm/build/sources
sh scripts/build-pkgconf.sh --prefix /opt --install
sh scripts/build-lxc.sh --prefix /volume1/@lxc/lab/opt
sh scripts/build-lxc.sh --prefix /volume1/@lxc/lab/opt --install
sh scripts/verify-lxc-install.sh --prefix /volume1/@lxc/lab/opt
eval "$(sh scripts/print-lxc-env.sh --prefix /volume1/@lxc/lab/opt)"
sh scripts/create-lab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

Siehe [Kompatibilitaets-Gate](docs/compatibility.md), [Phase 2 Userspace](docs/phase2-userspace.md), [Phase 3 First Container](docs/phase3-first-container.md), [Phase 3 Results](docs/phase3-results.md), [Phase 4 Network](docs/phase4-network.md), [Phase 4 Results](docs/phase4-results.md), [Phase 5 Lifecycle](docs/phase5-lifecycle.md), [Phase 6 SPK](docs/phase6-spk.md), [Known Limitations](docs/known-limitations.md), [Entware Toolchain](docs/entware-build-toolchain.md), [Sicherheitsmodell](docs/safety.md), [Architektur](docs/architecture.md) und [Recovery-Plan](docs/recovery.md).

Der erste reproduzierbare Runtime-Test ist bewusst netzwerklos:

```sh
sh scripts/run-lab-smoke-test.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

Danach sammelt Phase 3.2 eine breitere Runtime-Evidence. `lxc-attach` wird
separat bewertet; die eigentliche Evidence nutzt weiterhin den bewährten
netzwerklosen Foreground-Start:

```sh
sh scripts/probe-lab-features.sh --prefix /volume1/@lxc/lab/opt --name alpine-lab
```

Der erste Phase-4-Schritt ist weiterhin read-only:

```sh
sh scripts/check-network-prereqs.sh
```

Der erste Runtime-Netzwerktest bleibt isoliert und nutzt einen separaten
Container:

```sh
sh scripts/create-netlab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-netlab
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-netlab
sh scripts/run-empty-network-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-netlab
```

Erst danach folgt ein separater veth-Test ohne Bridge:

```sh
sh scripts/create-netlab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-vethlab --network-type veth --host-veth lxcveth0
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-vethlab
sh scripts/run-veth-network-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-vethlab
```

Vor Bridge-Experimenten erst read-only pruefen:

```sh
sh scripts/check-bridge-prereqs.sh
```

Wenn keine geeignete Bridge existiert, nur einen manuellen isolierten
Bridge-Plan erzeugen:

```sh
sh scripts/plan-isolated-bridge-probe.sh
```

Der erste echte LAN-Test nutzt macvlan statt Host-Bridge-Umbau:

```sh
sh scripts/create-netlab-container.sh --prefix /volume1/@lxc/lab/opt --name alpine-macvlanlab --network-type macvlan --parent-if eth0
sh scripts/verify-lxc-runtime.sh --prefix /volume1/@lxc/lab/opt --name alpine-macvlanlab
sh scripts/run-macvlan-dhcp-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-macvlanlab
sh scripts/run-macvlan-host-reachability-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-macvlanlab
sh scripts/plan-macvlan-host-shim.sh --parent-if eth0
sh scripts/run-macvlan-host-shim-probe.sh --prefix /volume1/@lxc/lab/opt --name alpine-macvlanlab --host-cidr FREE_LAN_IP/CIDR
```

Danach wird ein lokales Lifecycle-Profil erzeugt und read-only geprueft:

```sh
sh scripts/write-macvlan-profile.sh --prefix /volume1/@lxc/lab/opt --name alpine-macvlanlab --parent-if eth0 --host-cidr FREE_LAN_IP/CIDR
sh scripts/verify-macvlan-profile.sh --profile config/lab-macvlan.env
sh scripts/doctor-macvlan-profile.sh --profile config/lab-macvlan.env
sh scripts/start-macvlan-profile.sh --profile config/lab-macvlan.env
sh scripts/stop-macvlan-profile.sh --profile config/lab-macvlan.env
sh scripts/doctor-macvlan-profile.sh --profile config/lab-macvlan.env
```

Der erste DSM-Paket-Schritt ist ein reines Skeleton-Gate:

```sh
sh scripts/check-spk-skeleton.sh
sh scripts/assemble-spk-payload.sh
sh scripts/check-spk-payload.sh
sh scripts/plan-spk-build.sh
sh scripts/build-spk.sh
sh scripts/check-spk-archive.sh --spk build/spk/lxc-on-dsm-0.1.0-lab.spk
sh scripts/plan-spk-install.sh
```
