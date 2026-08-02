# LibreHardwareMonitor-Linux

**Read Linux hardware sensors with LibreHardwareMonitor clients.**

[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) (LHM) is
Windows-only — it depends on a Ring-0 kernel driver and WMI. But a whole ecosystem of clients
speaks its simple HTTP/JSON protocol: Elgato Stream Deck plugins, yasb, Home Assistant,
Grafana dashboards, and more.

This project does not port the application. It re-implements the **protocol** on top of native
Linux sensor sources, so any existing LHM client can read a Linux machine exactly as if it were
a Windows PC. Point the client at the host and port — nothing else changes.

```
┌─────────────────┐   HTTP GET /data.json   ┌──────────────────────────────┐
│  LHM client     │ ──────────────────────► │  lhm-linux (Linux host)      │
│  Stream Deck    │                         │                              │
│  Grafana        │ ◄────────────────────── │  nvidia-smi · lm-sensors     │
│  Home Assistant │   LHM-compatible JSON   │  ipmitool  · smartctl · proc │
└─────────────────┘                         └──────────────────────────────┘
```

- **Zero dependencies** — Python 3.9+ standard library only. No pip install, no venv.
- **Byte-compatible output** — verified field by field against a live LHM 0.9.x instance.
- **Servers included** — reads BMC/IPMI board temperatures, fans, voltages and PSU wattage,
  not just CPU and GPU.
- **Prometheus built in** — `/metrics.txt` with the same `lhm_*` metric names as upstream.
- Lightweight: ~22 MB RSS and well under 1 %.

## Why this exists

Monitoring a Windows PC from a Stream Deck is a solved problem. Doing the same for the Linux
box in the rack is not — the clients only speak LHM. Rather than writing a
new client for every panel, lhm-linux makes the Linux server speak the protocol the panels
already understand.

## Quick start

```bash
git clone https://github.com/insight-it-gmbh/LibreHardwareMonitor-Linux.git
cd LibreHardwareMonitor-Linux
sudo python3 lhmlinux/server.py
```

Then open `http://<host>:8085/` in a browser, or point your LHM client at that address.

Port 8085 is LHM's default, so most clients need only the hostname.

Check what is detected without starting a server:

```bash
sudo python3 lhmlinux/server.py --list-sensors
```

### Install as a service

```bash
sudo ./install.sh          # installs to /opt/lhm-linux + enables systemd unit
systemctl status lhm-linux
```

Uninstall with `sudo ./install.sh --uninstall`.

## Why root?

| Source | Provides | Root required |
|---|---|---|
| `nvidia-smi` | GPU temperature, load, VRAM, power, clocks, fan | no |
| `sensors` (lm-sensors) | CPU package and per-core temperatures | no |
| `/proc` | Memory usage, load average | no |
| `ipmitool` | Board/DIMM/VRM temperatures, fans, voltages, PSU watts | **yes** (`/dev/ipmi0`) |
| `smartctl` | Disk temperatures | **yes** (ATA passthrough) |

Without root you still get GPU, CPU and memory readings; IPMI and SMART sensors are skipped
with a note on startup. Every source is optional — a desktop without a BMC simply reports no
mainboard node.

Install whichever tools you want to use:

```bash
# Debian/Ubuntu
sudo apt install lm-sensors ipmitool smartmontools
# Fedora/RHEL
sudo dnf install lm_sensors ipmitool smartmontools
```

## Client setup

Any client that talks to LibreHardwareMonitor's web server works. Replace
`http://localhost:8085` with `http://<linux-host>:8085`.

| Client | Where to set it |
|---|---|
| Stream Deck "System Vitals" | Plugin settings → *Libre Webserver* URL |
| yasb `libre_monitor` widget | `libre_monitor_url` in the widget config |
| Home Assistant | *LibreHardwareMonitor* integration → host + port |
| Prometheus | Scrape `http://<host>:8085/metrics.txt` |

Sensor IDs follow upstream conventions, so existing client configs keep working:

```
/gpu-nvidia/0/temperature/0     first NVIDIA GPU, core temperature
/intelcpu/0/temperature/1       first CPU socket, core 1
/lpc/bmc/fan/2                  third BMC fan
/hdd/0/temperature/0            first disk
/ram/load/0                     memory utilisation
```

## Endpoints

| Path | Content |
|---|---|
| `/` | HTML dashboard, auto-refreshing |
| `/data.json` | LHM-compatible sensor tree |
| `/metrics.txt` (`/metrics`) | Prometheus exposition |
| `/healthz` | `ok` — liveness probe |

## Configuration

Every option has a CLI flag and an environment variable.

| Flag | Environment variable | Default | Meaning |
|---|---|---|---|
| `-p, --port` | `LHM_PORT` | `8085` | Listen port |
| `-b, --bind` | `LHM_BIND` | `0.0.0.0` | Bind address |
| `-i, --interval` | `LHM_INTERVAL` | `2.0` | Poll interval in seconds |
| `--decimal` | `LHM_DECIMAL` | `comma` | `comma` or `dot` (see below) |
| `--hostname` | `LHM_HOSTNAME` | system hostname | Name of the computer node |
| `--list-sensors` | — | — | Print detected sensors and exit |

For the systemd unit, edit the `Environment=` lines in
`/etc/systemd/system/lhm-linux.service`, then
`systemctl daemon-reload && systemctl restart lhm-linux`.

### Decimal separator

LibreHardwareMonitor formats values using the Windows locale, so a German host emits
`"63,0 °C"` and an English host `"63.0 °C"`. Clients parse that string. The default here is a
comma; switch with `--decimal dot` if your client expects a point.

## Protocol notes

These cost real debugging time and are documented nowhere upstream. If you write your own
LHM-compatible server, save yourself the trouble:

1. **`RawMin` / `RawValue` / `RawMax` are formatted strings, not numbers.**
   Upstream emits `"RawValue": "1,288 V"`, not `"RawValue": 1.288`, despite the `Raw` prefix.
2. **The decimal separator comes from the host locale.** See above.
3. **The `Load` group node is singular.** Every other label is plural — `Temperatures`,
   `Fans`, `Powers`, `Voltages`, `Clocks`, `Controls` — but it is `Load`, not `Loads`.
4. **`Data` and `SmallData` share one node** labelled `Data`.
5. **`id` is a pre-order counter across the whole tree**, starting at `0` on the root.
6. **Leaf nodes still carry `"Children": []`.** Some clients break on `undefined`.
7. Sensors without a reading render as `"-"`; upstream also emits `"NaN %"` in some cases.
8. Responses set `Access-Control-Allow-Origin: *` and `Cache-Control: no-cache`.

The tree shape is:

```
root (Text: "Sensor", Version)
└── computer (Text: hostname)
    └── hardware (HardwareId: "/gpu-nvidia/0")
        └── type group (Text: "Temperatures")
            └── sensor (SensorId, Type, Value, Min, Max, Raw*)
```

## Compatibility

Tested on Ubuntu 26.04 with Python 3.14 (a dual-socket Xeon server with 6 NVIDIA GPUs, a
Supermicro BMC and 4 disks) and validated against LibreHardwareMonitor 0.9.4 running on
Windows 11. It should work on any Linux with Python 3.9 or newer; the sensor tooling is
distribution-independent.

## Security

The server serves **read-only** sensor data and has **no authentication**, matching
LibreHardwareMonitor's own web server. Bind it to a trusted network. Do not expose it to the
internet — put it behind a reverse proxy with authentication, or restrict it with
`--bind 127.0.0.1` plus an SSH tunnel.

## Contributing

Issues and pull requests are welcome. Useful additions: AMD GPU support via `amdgpu` hwmon,
Nouveau, network throughput sensors, and reports from clients not yet listed above.

Please keep the zero-dependency, standard-library-only constraint.

## License

MIT — see [LICENSE](LICENSE).

LibreHardwareMonitor-Linux is an independent, clean-room implementation of the LibreHardwareMonitor JSON
endpoint. It contains no upstream code. LibreHardwareMonitor itself is licensed under the
MPL-2.0 and is not affiliated with this project.
