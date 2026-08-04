# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-08-03

### Added
- `install.sh --prefix DIR` for appliances with a read-only root filesystem, where
  `/opt` cannot be written (TrueNAS SCALE and other ZFS-on-root systems). The systemd
  unit follows the chosen path.
- `install.sh --port N` and `--help`; unknown options now fail with a clear message
  instead of being ignored.
- README section on platform quirks: what a VM can and cannot report, and how to
  install on a read-only root.

### Fixed
- `--uninstall` now reads the real install path out of the unit file, so a custom
  `--prefix` is removed too instead of being left behind.

## [1.1.0] - 2026-08-03

### Fixed
- **Slow sensor sources no longer stall fast ones.** Every source ran in one shared
  loop, so a BMC that takes 5-13 seconds to answer `ipmitool sdr` delayed CPU and GPU
  updates behind it — the whole cycle took ~9 s instead of the configured 2 s, which
  looks like a frozen display on a hardware panel. Each source now polls in its own
  thread at its own cadence: CPU, GPU and memory every 2 s, BMC/IPMI every 30 s, SMART
  every 300 s. Measured on a 6-GPU server, the number of values updating within a
  12-second window went from 22/143 to 48/143.

### Changed
- `SOURCES` entries are now `(function, key, interval)` tuples; `interval=None` means
  the fast interval from `--interval`.
- Readings are stored per source, so one slow or failing source no longer blanks the
  others between cycles.

## [1.0.0] - 2026-08-02

Initial public release.

### Added
- LibreHardwareMonitor-compatible `/data.json` endpoint, verified field by field against a
  live LHM 0.9.4 instance.
- Prometheus exposition at `/metrics.txt` using upstream `lhm_*` metric names.
- Self-contained HTML dashboard at `/`, plus a `/healthz` probe.
- Sensor sources: NVIDIA GPUs (`nvidia-smi`), CPU (`lm-sensors`), BMC board sensors, fans,
  voltages and PSU wattage (`ipmitool`), disk temperatures (`smartctl`), memory and load
  average (`/proc`).
- Min/max tracking per sensor for the lifetime of the process.
- CLI and environment configuration for port, bind address, poll interval, decimal separator
  and reported hostname; `--list-sensors` for inspection.
- `install.sh` and a hardened systemd unit.

Developed by Dominic Ballenthin at Insight-IT GmbH, Berlin.
