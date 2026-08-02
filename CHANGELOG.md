# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
