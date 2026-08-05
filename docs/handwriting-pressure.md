# Human handwriting pressure & motion (Quill)

## Assumptions

| Topic | Assumption |
|-------|------------|
| Hardware | Bachin T-A4 class plotter; primary path is **motor Z** (GRBL). Servo heads use the same normalized pressure after calibration. |
| Pressure actuator | Normalized pressure `0…1` maps to Z via `MachineProfile.z(forPressure:)` (higher Z = lighter). Soft floor prevents dig-in. |
| Coordinates | Millimetres, machine XY, Y-up, absolute (`G21`/`G90`). |
| Path data | Pre-existing `PlotJob` polylines (text stick font, ink, SVG). Planning is **offline** (not closed-loop real-time). |
| Language / output | Swift (`CNCCore`). Output is G-code with varying `Z` and `F`, plus optional `MotionPoint` JSON for tooling. |
| Variation | Deterministic given a seed — reproducible jobs, not per-point white noise. |

## Architecture

```
PlotJob (geometry)
  → StrokeAnalyzer          (stroke types, curvature, direction)
  → HumanVariationGenerator (path jitter, baseline drift, glyph scale — optional)
  → VelocityPlanner         (accel/decel, curve slowdown, pauses)
  → PressurePlanner         (pen profile + envelopes + effects + LF variation)
  → MotionPointGenerator    (time-sampled motion points)
  → ServoPressureFilter     (rate limit + low-pass)
  → GCodeExporter           (Z/F G-code with safety clamps)
```

Facade: `HandwritingSimulator`.

## Pressure model

```
raw = base
    + speed_effect          // slow → slightly higher
    + curvature_effect      // controlled curves → slightly higher
    + direction_effect      // downward/load-bearing → higher; up/connect → lower
    + stroke_type_effect
    + smooth_human_variation  // LF targets every ~10–30 mm, smoothstep between

p = stroke_start_envelope(raw)
  × stroke_end_envelope(...)
→ rate_limit → low_pass → clamp(pen.min…pen.maxSafety)
```

## Calibration (normalized → Z / servo)

1. Mount the instrument; set pen-up clear of paper.
2. Command pressure `0.0` — tip should just kiss or float lightly (`pressureMinZ`).
3. Command pressure `1.0` — darkest safe line; must not scrape or stall (`pressureMaxZ`, soft floor).
4. For **ballpoint**, verify mid-range (~0.55) lays ink without skipping.
5. For **fountain**, keep `maxPressure` ≤ ~0.35 and soft floor shallow — nibs damage easily.
6. Servo: map `0…1` → `penUpAngle…penDownAngle` with the same envelopes; never exceed mechanical stops.
7. Re-run Calibration wizard accuracy + a 100 mm stroke after changing pens.

## Safety

- Per-pen `maxPressure` / `maxPressureDeltaPerMm`
- Machine soft Z floor (`MachineProfile.clampPressureRange`)
- Filter cut-off and rate limit to avoid servo buzz
- No independent random pressure per point

## Acceptance (smoke)

- Stroke start: pressure rises smoothly over first 10–25% of stroke length  
- Stroke end: pressure falls on finishing tails  
- Identical text twice with same seed → same G-code; different seed → small differences  
- No Z oscillation above ~8 Hz equivalent in filtered samples  
- Fountain job never exceeds fountain `maxPressure`  

## Staged rollout

1. **Done** — Pressure attack/release, direction/speed/curvature, LF variation, servo filter, pen profiles, Compose wiring (XY-stable).  
2. **Next (UI)** — Pen & Layer Studio picker for `WritingInstrument` + “geometry variation” toggle.  
3. **Next (ink)** — Optional `HandwritingSimulator.enrich` on ink export (stylus pressure as bias).  
4. **Hardware** — Calibrate Z band per instrument; confirm no Z buzz at `filterLengthMm`.  
5. **Optional** — Explicit pause tokens between words in G-code (`G4`) from motion timeline.  
