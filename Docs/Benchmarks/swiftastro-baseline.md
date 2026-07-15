# SwiftAstro — Benchmark baseline

| Field | Value |
| --- | --- |
| Captured | 2026-07-15T19:33:04Z |
| Host | Mac16,12 |
| OS | Version 26.5.1 (Build 25F80) |
| Configuration | release |
| Iterations | 20 |
| Measurements | 11 |

Timings are wall-clock per iteration; **min** is the least noisy estimate of intrinsic cost. Peak allocation is an approximate, best-effort figure (see the harness README).

| Category | Algorithm | Frame | Min | Median | Max | Peak alloc. |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Decode | FITSImageDecoder.detectionImage | real-fits-3840x2160 | 352.19 ms | 398.43 ms | 418.21 ms | 332.28 MB |
| Decode | FITSImageDecoder.linearImage | real-fits-3840x2160 | 275.35 ms | 364.38 ms | 377.33 ms | 158.25 MB |
| Detection | MatchedFilterStarDetector.detectStars | esa-m35-1024 | 1.71 s | 1.73 s | 2.09 s | 37.42 MB |
| Ephemeris | LunarPosition.position | n/a | 208 ns | 250 ns | 334 ns | 336 B |
| Ephemeris | MoonPhase(date:) | n/a | 0 ns | 20 ns | 84 ns | 336 B |
| Ephemeris | PlanetPosition.position (Mars) | n/a | 208 ns | 229 ns | 375 ns | 272 B |
| Ephemeris | SolarPosition.position | n/a | 125 ns | 125 ns | 208 ns | 336 B |
| Ephemeris | TwilightEvents.compute | n/a | 833 ns | 875 ns | 1.04 µs | 336 B |
| Preprocessing | BayerGrayscaleConverter.grayscale | real-mosaic-3840x2160 | 33.96 ms | 38.92 ms | 134.39 ms | 253.16 MB |
| SignalToNoise | SignalToNoise.estimate | esa-m35-1024 | 84.57 ms | 85.28 ms | 92.80 ms | 21.59 MB |
| SignalToNoise | SkyBackground.estimate | esa-m35-1024 | 86.63 ms | 86.90 ms | 87.36 ms | 21.59 MB |
