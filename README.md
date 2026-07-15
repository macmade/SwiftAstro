SwiftAstro
==========

[![Build Status](https://img.shields.io/github/actions/workflow/status/macmade/SwiftAstro/ci-mac.yaml?label=macOS&logo=apple)](https://github.com/macmade/SwiftAstro/actions/workflows/ci-mac.yaml)
[![Issues](http://img.shields.io/github/issues/macmade/SwiftAstro.svg?logo=github)](https://github.com/macmade/SwiftAstro/issues)
![Status](https://img.shields.io/badge/status-active-brightgreen.svg?logo=git)
![License](https://img.shields.io/badge/license-mit-brightgreen.svg?logo=open-source-initiative)  
[![Contact](https://img.shields.io/badge/follow-@macmade-blue.svg?logo=twitter&style=social)](https://twitter.com/macmade)
[![Sponsor](https://img.shields.io/badge/sponsor-macmade-pink.svg?logo=github-sponsors&style=social)](https://github.com/sponsors/macmade)

### About

Astrophotography Support Library for Swift.

SwiftAstro is a toolkit for building astrophotography capture and analysis tools.
It brings together three concerns behind one Swift module: a low-precision
**ephemeris** for planning and annotating observations, a **preprocessing**
pipeline that turns raw FITS frames into detection-ready images, and a **star
detector** with the frame-quality metrics used to grade and weight subframes.

It builds on two sibling libraries: [SwiftFITS](https://github.com/macmade/SwiftFITS)
for reading FITS files, and [SwiftPixel](https://github.com/macmade/SwiftPixel)
for pixel decoding, demosaicing and image math.

### Features

#### Ephemeris

Low-precision astronomical math after
[Paul Schlyter's method](https://stjarnhimlen.se/comp/ppcomp.html) — self-contained,
with no network access or ephemeris files. Positions are good to roughly an
arc-minute for the Sun and inner planets, which is ample for deciding whether a
target is up and where to point.

- **`SolarPosition` / `PlanetPosition`** — the Sun's and each planet's
  low-precision geocentric position, as an `EquatorialCoordinate` or, for an
  observer, a `HorizontalCoordinate`.
- **`Planet`** — every planet observable from Earth (all but Earth itself), with
  its name and astronomical symbol.
- **`TwilightEvents`** — sunrise, sunset and the civil / nautical / astronomical
  dawn and dusk times for a location on a given day, each `nil` at high latitudes
  when the Sun never crosses the threshold (polar day or night).
- **`MoonPhase`** — the Moon's age, illuminated fraction and named phase at an
  instant, from the mean synodic cycle.
- **`EquatorialCoordinate` / `HorizontalCoordinate` / `GeographicLocation`** —
  the coordinate systems the computations produce and consume, in decimal
  degrees.

#### Preprocessing

- **`FITSImageDecoder`** — loads a FITS file's image HDU into a single-channel,
  linear `PixelBuffer`, applying `BZERO` / `BSCALE` rescaling. `detectionImage(from:)`
  additionally demosaics a one-shot-colour (Bayer CFA) frame — recognized by its
  `BAYERPAT` keyword — to a single luminance channel ready for detection.
- **`BayerGrayscaleConverter`** — demosaics a raw Bayer mosaic (via `SwiftPixel`)
  and combines the channels with an **equal-weight mean** — not a perceptual
  luminance — so red- and blue-dominant stars are not suppressed relative to
  green ones.

#### Star detection

- **`StarDetecting`** — the protocol that lets the detection strategy vary; it
  takes a single-channel, *linear* image and returns a `StarField`.
- **`MatchedFilterStarDetector`** — a DAOFIND-style detector: a zero-sum Gaussian
  matched filter that responds to point sources while vanishing on smooth sky,
  gradients and nebulosity; **sharpness** and **roundness** purity cuts; and a
  per-star 2D elliptical Gaussian fit for measurement. The filter scale is
  auto-estimated from the brightest stars unless overridden. It optimizes for
  purity — it would rather miss a faint star than report a false one — and is
  tunable through its `Configuration`.
- **`Star` / `StarField`** — a detected star's centroid, flux, half-flux radius
  (HFR), FWHM and eccentricity, and the robust **median** aggregates and value
  ranges over a field of them (focus / tracking quality that outliers don't skew).
- **`StarMoments`** — the shared flux-weighted moment math (centroid, second
  moments, FWHM, eccentricity and empirical half-flux radius) that seeds the fit
  and reports the metrics.

#### Frame quality

- **`SignalToNoise`** — a relative, inverse-noise-variance frame weight (in the
  spirit of PixInsight's SubframeSelector "SNRWeight") for grading subframes of
  the same target against one another.
- **`SkyBackground`** — a robust sky-background level and noise estimate (image
  median and `1.4826 × MAD`), in native ADU and as a fraction of the image range.

### Requirements & Portability

SwiftAstro is written in Swift and depends on **Foundation**,
[SwiftFITS](https://github.com/macmade/SwiftFITS) and
[SwiftPixel](https://github.com/macmade/SwiftPixel) (both vendored as submodules
and resolved locally). SwiftPixel uses Apple's Accelerate framework, so the
package currently targets Apple platforms.

The library is developed, built and tested on macOS (deployment target macOS 15.0;
see the CI badge above).

### Swift Package Manager

SwiftAstro ships a `Package.swift` and can be consumed as a Swift package. Add it to your
dependencies:

```swift
.package( url: "https://github.com/macmade/SwiftAstro.git", branch: "main" )
```

The Xcode project (`SwiftAstro.xcodeproj`) is also provided for development.

### Cloning

This project uses submodules.  
To clone it, use the following command:

```bash
git clone --recursive https://github.com/macmade/SwiftAstro.git
```

### Example Usage

Detecting stars and grading a FITS frame:

```swift
import Foundation
import SwiftFITS
import SwiftAstro

do
{
    let file  = try FITSFile( url: URL( fileURLWithPath: "/path/to/frame.fits" ), options: .lenient )

    // Decode the image HDU to a detection-ready, single-channel linear buffer
    // (a Bayer frame is demosaiced to luminance automatically).
    let image = try FITSImageDecoder.detectionImage( from: file )

    // Detect stars and read the robust field metrics.
    let field = try MatchedFilterStarDetector().detectStars( in: image )

    print( "\( field.count ) stars, median FWHM \( field.medianFWHM ?? 0 ) px, median HFR \( field.medianHFR ?? 0 ) px" )

    // Grade the frame's sky background and relative signal-to-noise.
    if let snr = SignalToNoise.estimate( in: image )
    {
        print( "SNR weight: \( snr.weight )" )
    }
}
catch // SwiftAstro.Error
{
    print( error )
}
```

Computing an object's position and the day's twilight for an observer:

```swift
import Foundation
import SwiftAstro

let location = GeographicLocation( latitude: 46.2044, longitude: 6.1432 )
let now      = Date()

let sun      = SolarPosition.horizontal( at: now, location: location )
let mars     = PlanetPosition.horizontal( of: .mars, at: now, location: location )
let twilight = TwilightEvents.compute( date: now, location: location )
let moon     = MoonPhase( date: now )

print( "Sun above horizon: \( sun.isAboveHorizon )" )
print( "Mars altitude: \( mars.altitude )°" )
print( "Astronomical dusk: \( twilight.astronomicalDusk as Any )" )
print( "Moon: \( moon.phase.name ), \( moon.illumination * 100 )% illuminated" )
```

### Benchmarks

The test target includes an opt-in **benchmark & profiling harness** (under
`SwiftAstroTests/Benchmarks/`) that measures the runtime — and approximate peak
memory — of the SwiftAstro algorithms, and writes a committed baseline for
before/after comparison. It covers star detection
(`MatchedFilterStarDetector`), signal-to-noise and sky-background estimation,
the Bayer→grayscale conversion, FITS decoding, and the ephemeris models. Image
cases run over the committed FITS fixtures (an ESA M35 centre crop for detection
and SNR, the raw RGGB light frame for the Bayer and decode paths); the ephemeris
cases take no image input.

It is **excluded from ordinary test runs** — only the harness's own fast unit
tests run there — and executes only when the `RUN_BENCHMARKS` environment
variable is set. Because `xcodebuild test` does not forward the environment to
the test-host process, capture a baseline through SwiftPM, in an optimized build:

```bash
RUN_BENCHMARKS=1 swift test -c release --filter Test_SwiftAstroBenchmarks
```

Two files are written to `Docs/Benchmarks/` (override the directory with the
`FITSCOPE_BENCH_OUT` environment variable): `swiftastro-baseline.json` — the
machine-diffable source of truth — and `swiftastro-baseline.md` — a
human-readable table generated from it. Each measurement records min / median /
max wall-clock timing (the **min** is the least noisy estimate of intrinsic cost)
and a best-effort, approximate peak allocation. A baseline is a snapshot, not a
target: real timings vary between runs, so compare like for like — same host,
same Release build.

License
-------

Project is released under the terms of the MIT License.

Repository Infos
----------------

    Owner:          Jean-David Gadina - XS-Labs
    Web:            www.xs-labs.com
    Blog:           www.noxeos.com
    Twitter:        @macmade
    GitHub:         github.com/macmade
    LinkedIn:       ch.linkedin.com/in/macmade/
    StackOverflow:  stackoverflow.com/users/182676/macmade
