# Sensor Battery

Garmin Connect IQ data field showing battery levels for connected ANT+ and BLE sensors.

## Supported sensors

Power meter, Di2/shifting, Varia rear light, front light, heart rate, cadence, speed, and device battery.

## Build & run

Use the [Monkey C](https://developer.garmin.com/connect-iq/) extension in VS Code:

1. Open this folder in VS Code
2. **Monkey C: Build for Device** (or Run) — pick your device
3. Sideload via Garmin Express or copy the `.prg` to `GARMIN/APPS/` on the device

Keep `developer_key` local only — it is gitignored and must not be committed.

## CI

Pull requests run a compile check on GitHub Actions (`fenix847mm`, `edge1050`, `edge530`). No signing key is used in CI.

## Docs

- [CLAUDE.md](CLAUDE.md) — project overview for contributors and AI tools
- [docs/](docs/) — architecture, detailed specs, and advanced build notes
