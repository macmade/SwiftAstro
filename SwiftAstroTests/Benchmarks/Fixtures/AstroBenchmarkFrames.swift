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

/// Builds the inputs the SwiftAstro benchmark suite runs over.
///
/// The representative set adapts the committed real FITS fixtures (reusing
/// ``FITSTestImage``, the same loader the detector's tests use): a centre crop of
/// the clean ESA M35 star field drives detection and SNR, and the raw
/// one-shot-colour light frame drives the Bayer and decode paths. The synthetic
/// set builds tiny buffers in code so the smoke test can exercise every case's
/// wiring in a fraction of a second, without touching disk.
enum AstroBenchmarkFrames
{
    /// The detection crop's square edge length, in pixels.
    ///
    /// The committed frames are tens of megapixels; running the full detector
    /// over one is slow because every star is Gaussian-fitted, so — like the
    /// detector's own real-frame tests — the benchmark crops to a representative
    /// region.
    static let detectionCropEdge = 1_024

    /// The representative inputs, adapted from the committed FITS fixtures.
    ///
    /// - Returns: The real-data inputs.
    /// - Throws: An error if a fixture is missing or cannot be decoded.
    static func representative() throws -> AstroBenchmarkInputs
    {
        let esa   = try FITSTestImage.esaM35BlueDetection()
        let edge  = min( Self.detectionCropEdge, min( esa.width, esa.height ) )
        let x     = ( esa.width - edge ) / 2
        let y     = ( esa.height - edge ) / 2
        let crop  = try FITSTestImage.crop( esa, x: x, y: y, width: edge, height: edge )

        let detection = Self.frame(
            name:   "esa-m35-\( edge )",
            layout: "mono",
            notes:  "ESA M35 blue reference frame (clean, non-mosaiced star field), centre \( edge )×\( edge ) crop. Drives detection and SNR.",
            buffer: crop
        )

        let rawMosaic = try FITSTestImage.realLightFrame()

        let mosaic = Self.frame(
            name:   "real-mosaic-\( rawMosaic.width )x\( rawMosaic.height )",
            layout: "cfa (RGGB mosaic)",
            notes:  "ZWO ASI585MC one-shot-colour light frame, raw RGGB mosaic. Drives the Bayer→grayscale conversion.",
            buffer: rawMosaic
        )

        let file       = try FITSFile( url: try FITSTestImage.url( resource: FITSTestImage.realLightFrameName ), options: .lenient )
        let decodeDesc = BenchmarkFrameDescriptor(
            name:         "real-fits-\( rawMosaic.width )x\( rawMosaic.height )",
            width:        rawMosaic.width,
            height:       rawMosaic.height,
            channels:     1,
            layout:       "FITS 16-bit RGGB",
            isNormalized: false,
            notes:        "On-disk 16-bit RGGB FITS file (ZWO ASI585MC). Drives the decode path."
        )

        return AstroBenchmarkInputs(
            detection: detection,
            mosaic:    mosaic,
            decoding:  [ AstroBenchmarkInputs.Decode( name: "real-light", descriptor: decodeDesc, file: file ) ]
        )
    }

    /// Tiny synthetic inputs with no on-disk decode cases, for the smoke test.
    ///
    /// - Parameter edge: The square edge length of the synthetic buffers. Must be
    ///                   even for the mosaic.
    /// - Returns: The synthetic inputs.
    /// - Throws: A `PixelBufferError` if the geometry is inconsistent.
    static func synthetic( edge: Int ) throws -> AstroBenchmarkInputs
    {
        let detection = Self.frame(
            name:   "synthetic-mono-\( edge )",
            layout: "mono",
            notes:  "Synthetic mono star-like field (smoke test only).",
            buffer: try Self.syntheticStarField( edge: edge )
        )

        let mosaic = Self.frame(
            name:   "synthetic-mosaic-\( edge )",
            layout: "cfa (RGGB mosaic)",
            notes:  "Synthetic single-channel mosaic (smoke test only).",
            buffer: try Self.syntheticMosaic( edge: edge )
        )

        return AstroBenchmarkInputs( detection: detection, mosaic: mosaic, decoding: [] )
    }

    /// Wraps a loaded buffer in a described frame.
    private static func frame( name: String, layout: String, notes: String, buffer: PixelBuffer ) -> BenchmarkFrame
    {
        let descriptor = BenchmarkFrameDescriptor(
            name:         name,
            width:        buffer.width,
            height:       buffer.height,
            channels:     buffer.channels,
            layout:       layout,
            isNormalized: buffer.isNormalized,
            notes:        notes
        )

        return BenchmarkFrame( descriptor: descriptor, buffer: buffer )
    }

    /// A synthetic single-channel star field: a flat background with a few
    /// Gaussian stars, in the raw ADU domain.
    private static func syntheticStarField( edge: Int ) throws -> PixelBuffer
    {
        let background = 200.0
        let sigma      = 2.0
        let stars      = [ ( x: edge / 4, y: edge / 4, amplitude: 3_000.0 ), ( x: edge / 2, y: ( edge * 3 ) / 4, amplitude: 2_000.0 ), ( x: ( edge * 3 ) / 4, y: edge / 3, amplitude: 4_000.0 ) ]

        var pixels = [ Double ]( repeating: background, count: edge * edge )

        stars.forEach
        {
            star in

            ( -6 ... 6 ).forEach
            {
                dy in

                ( -6 ... 6 ).forEach
                {
                    dx in

                    let px = star.x + dx
                    let py = star.y + dy

                    guard px >= 0, px < edge, py >= 0, py < edge
                    else
                    {
                        return
                    }

                    let squared = Double( ( dx * dx ) + ( dy * dy ) )

                    pixels[ ( py * edge ) + px ] += star.amplitude * exp( -squared / ( 2.0 * sigma * sigma ) )
                }
            }
        }

        return try PixelBuffer( width: edge, height: edge, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// A synthetic single-channel raw Bayer mosaic, in the 16-bit ADU domain.
    private static func syntheticMosaic( edge: Int ) throws -> PixelBuffer
    {
        let pixels = ( 0 ..< ( edge * edge ) ).map { Double( ( $0 &* 1_103_515_245 &+ 12_345 ) & 0xFFFF ) }

        return try PixelBuffer( width: edge, height: edge, channels: 1, pixels: pixels, isNormalized: false )
    }
}
