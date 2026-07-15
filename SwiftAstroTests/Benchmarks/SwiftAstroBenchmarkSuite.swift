/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2026, Jean-David Gadina - www.xs-labs.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the Software), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

import Foundation
@testable import SwiftAstro
import SwiftFITS
import SwiftPixel

/// Assembles and runs the SwiftAstro benchmark matrix — star detection, SNR and
/// sky-background estimation, Bayer→grayscale conversion, FITS decoding, and the
/// ephemeris models — into a single report.
///
/// Every result is passed through ``keep(_:)`` so an optimized build cannot elide
/// the work as dead code.
struct SwiftAstroBenchmarkSuite
{
    private let runner: BenchmarkRunner
    private let inputs: AstroBenchmarkInputs
    private let allocations: Bool

    /// The number of timed iterations each measurement summarizes.
    var iterations: Int
    {
        self.runner.iterations
    }

    /// Creates a suite.
    ///
    /// - Parameters:
    ///   - inputs:      The inputs the cases run over.
    ///   - iterations:  The number of timed iterations per case. Defaults to
    ///                  `20`.
    ///   - warmup:      The number of untimed warmup iterations. Defaults to `3`.
    ///   - allocations: Whether to measure peak allocation. Defaults to `true`;
    ///                  the smoke test disables it to stay fast.
    init( inputs: AstroBenchmarkInputs, iterations: Int = 20, warmup: Int = 3, allocations: Bool = true )
    {
        self.inputs      = inputs
        self.runner      = BenchmarkRunner( iterations: iterations, warmup: warmup )
        self.allocations = allocations
    }

    /// Runs the full matrix and packages it with run metadata.
    ///
    /// - Returns: The complete report.
    /// - Throws: Any error raised while running a case.
    func report() throws -> BenchmarkReport
    {
        BenchmarkReport(
            metadata:     BenchmarkEnvironment.metadata( module: "SwiftAstro", iterations: self.iterations ),
            measurements: try self.measurements()
        )
    }

    /// Extends the lifetime of a benchmarked result so the optimizer cannot
    /// discard the computation that produced it.
    private func keep< T >( _ value: T )
    {
        withExtendedLifetime( value ) {}
    }

    /// A placeholder descriptor for cases with no image input (the ephemeris
    /// models).
    private static let scalarFrame = BenchmarkFrameDescriptor( name: "n/a", width: 1, height: 1, channels: 1, layout: "scalar (no image)", isNormalized: false, notes: "Positional astronomy — no image input." )

    /// Builds every measurement in the matrix.
    private func measurements() throws -> [ BenchmarkMeasurement ]
    {
        let detection = self.inputs.detection
        let mosaic    = self.inputs.mosaic

        var results = [ BenchmarkMeasurement ]()

        func record( _ algorithm: String, category: String, frame: BenchmarkFrameDescriptor, _ body: () throws -> Void ) throws
        {
            if let measurement = try self.runner.measure( algorithm: algorithm, category: category, frame: frame, allocations: self.allocations, body )
            {
                results.append( measurement )
            }
        }

        // MARK: Star detection

        try record( "MatchedFilterStarDetector.detectStars", category: "Detection", frame: detection.descriptor )
        {
            self.keep( try MatchedFilterStarDetector().detectStars( in: detection.buffer ) )
        }

        // MARK: Signal-to-noise

        try record( "SignalToNoise.estimate", category: "SignalToNoise", frame: detection.descriptor )
        {
            self.keep( SignalToNoise.estimate( in: detection.buffer ) )
        }

        try record( "SkyBackground.estimate", category: "SignalToNoise", frame: detection.descriptor )
        {
            self.keep( SkyBackground.estimate( in: detection.buffer ) )
        }

        // MARK: Preprocessing

        try record( "BayerGrayscaleConverter.grayscale", category: "Preprocessing", frame: mosaic.descriptor )
        {
            self.keep( try BayerGrayscaleConverter( pattern: .rggb ).grayscale( from: mosaic.buffer ) )
        }

        // MARK: FITS decoding

        try self.inputs.decoding.forEach
        {
            decode in

            try record( "FITSImageDecoder.linearImage", category: "Decode", frame: decode.descriptor )
            {
                self.keep( try FITSImageDecoder.linearImage( from: decode.file ) )
            }

            try record( "FITSImageDecoder.detectionImage", category: "Decode", frame: decode.descriptor )
            {
                self.keep( try FITSImageDecoder.detectionImage( from: decode.file ) )
            }
        }

        // MARK: Ephemeris

        let date     = Date()
        let location = GeographicLocation( latitude: 46.2044, longitude: 6.1432 )
        let scalar   = Self.scalarFrame

        try record( "PlanetPosition.position (Mars)", category: "Ephemeris", frame: scalar )
        {
            self.keep( PlanetPosition.position( of: .mars, at: date ) )
        }

        try record( "SolarPosition.position", category: "Ephemeris", frame: scalar )
        {
            self.keep( SolarPosition.position( at: date ) )
        }

        try record( "LunarPosition.position", category: "Ephemeris", frame: scalar )
        {
            self.keep( LunarPosition.position( at: date ) )
        }

        try record( "TwilightEvents.compute", category: "Ephemeris", frame: scalar )
        {
            self.keep( TwilightEvents.compute( date: date, location: location ) )
        }

        try record( "MoonPhase(date:)", category: "Ephemeris", frame: scalar )
        {
            self.keep( MoonPhase( date: date ) )
        }

        return results
    }
}
