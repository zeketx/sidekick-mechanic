# TelemetrySource

Swappable live readings for the readings screen. The truck is not here, so the only source that runs today is a simulator. OBD protocol, donor year, and dongle compatibility stay `TBD` in [TRUCK.md](../vehicle/TRUCK.md).

`docs/vehicle/ECU.md` (issue #7) is not on `main`. This protocol does not assume an OBD-II PID list or an OBD1 serial protocol. Those would be vehicle facts, and they are not confirmed.

## Protocol

`TelemetrySource` in `app/SidekickCore`:

- `start()` opens one session and returns an `AsyncStream<TelemetryReading>`.
- `stop()` ends that session and finishes the stream. Calling it while idle is safe.
- A second `start()` before `stop()` throws `alreadyRunning`.

Each `TelemetryReading` has a channel id, a numeric value, a unit, an origin, and a timestamp. The timestamp is milliseconds since the session started, taken from the script. It is not the wall clock.

`origin` is `simulated`, `elm327`, or `obd1`. This package only produces `simulated`.

## Simulator

`SimulatedTelemetrySource` replays a JSON scenario from `Sources/SidekickCore/Resources/Scenarios/`.

| File | Scenario |
|---|---|
| `fake-cold-start.json` | Cold start |
| `fake-warm-idle.json` | Warm idle |

Channel ids, display names, and units are `FAKE-` placeholders. The scenario note must say the values are not a spec. Decode rejects anything else, including a bare name like a real sensor and a real unit string.

`seed` is a `UInt64` on the scenario. Replay is a pure function of the script plus the seed: scripted values do not change, and each reading gets a `sequenceStamp` from SplitMix64(seed + index). Tests pass `ImmediateTelemetryClock` so they do not sleep. The readings screen uses `WallClockTelemetryClock`, which waits the scripted gap between frames.

Every simulated row shows the label `Simulated`. The screen banner is `Simulated readings. Not engine specs.`

## ELM327 seam

`TelemetrySources.elm327()` throws `seamNotImplemented(.elm327)`.

A later ELM327 source (issue #44) adopts `TelemetrySource` with `origin == .elm327` and `isSimulated == false`. Build it only if `TRUCK.md` confirms OBD-II. Bluetooth, AT commands, and PID maps stay out of this package. The readings screen already hides the simulated banner when `origin` is not `simulated`, so that source can reuse the view without a protocol change.

## OBD1 seam

`TelemetrySources.obd1()` throws `seamNotImplemented(.obd1)`.

A later OBD1 source (issue #45) adopts the same `TelemetrySource`. What that ECU can emit is `TBD`. This seam does not invent a Toyota serial protocol, connector, pinout, or part number. If M5 records OBD1, that source still emits `TelemetryReading` values and the screen does not change shape.

## Not in this package

- CoreBluetooth, ELM327 commands, or a dongle transport
- SAE J1979 PIDs presented as channels on this truck
- Torque, wire colors, connector IDs, or part numbers
- Sensor ranges presented as specs for the 2JZ-GE
