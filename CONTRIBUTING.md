# Contributing

Thanks for considering a contribution.

## Ground rules

**Standard library only.** lhm-linux must run with a bare `python3` on a freshly installed
server — no pip, no venv, no wheels. A pull request adding a third-party runtime dependency
will not be merged. Test-only tooling is fine.

**Do not break the wire format.** The whole point of this project is that unmodified
LibreHardwareMonitor clients work against it. Any change to `/data.json` must keep the field
names, types and formatting identical to upstream. Read the "Protocol notes" section of the
README before touching `build_data_json()` or `fmt()`.

**Sensor sources must degrade gracefully.** Every source is optional. If a tool is missing,
returns garbage or needs privileges we do not have, the source returns an empty list — it never
raises and never blocks the others.

**Never report a value you are not sure about.** Prefer omitting a sensor over publishing a
wrong number. See the SMART temperature parser for the reasoning: the obvious column in
`smartctl` output is a normalised health score, not a temperature, and reading it produced a
plausible-looking 139 °C for a disk actually running at 43 °C. Implausible readings are dropped.

## Running the tests

```bash
python3 tests/test_protocol.py
```

The tests validate the JSON tree against the documented LHM schema without needing any
hardware — they cover structure, field types, value formatting and the Prometheus output.

## Adding a sensor source

1. Write a `poll_<name>() -> list[Hardware]` function.
2. Use `Hardware(name, hwid, icon)` with an upstream-style ID (`/gpu-amd/0`, `/nvme/1`, ...).
3. Add sensors with `hw.add(label, sensor_type, value, index)`; `sensor_type` must be a key
   of `FORMATS`.
4. Register the function in `SOURCES`.
5. Verify with `--list-sensors`, then confirm a client still parses `/data.json`.

## Reporting a client incompatibility

Please include the client name and version, what it displays instead of the reading, and the
relevant slice of `curl -s http://<host>:8085/data.json`. If you can compare against a real
LibreHardwareMonitor instance, that diff is the single most useful thing you can attach.
