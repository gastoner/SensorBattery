# Sensor Battery

Garmin Connect IQ data field showing battery levels for connected ANT+ and BLE sensors.

## Supported sensors

Power meter, Di2/shifting, Varia rear light, front light, heart rate, cadence, speed, and device battery.

## Build & run

Requires [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 9.1.0 and a local `developer_key` (gitignored — never commit it).

### VS Code (recommended)

Use the [Monkey C](https://developer.garmin.com/connect-iq/) extension:

1. Open this folder in VS Code
2. **Monkey C: Build for Device** (or Run) — pick your device
3. Sideload via Garmin Express or copy the `.prg` to `GARMIN/APPS/` on the device

### Command line

```bash
monkeyc -f monkey.jungle -d edge1050 -o bin/SensorBattery.prg -y developer_key -O3pz -w
```

## Docs

- [CLAUDE.md](CLAUDE.md) — project overview for contributors and AI tools
- [docs/architecture.md](docs/architecture.md) — class design and data flow
- [docs/specs.md](docs/specs.md) — behavior, timings, and state machines
- [docs/development.md](docs/development.md) — conventions and local setup
