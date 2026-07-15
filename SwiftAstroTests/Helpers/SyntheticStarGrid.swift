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
import SwiftPixel

/// A synthetic grid of stars for detector tests, laid out so the two axes vary
/// one property each:
///
/// - **Down the rows (Y): size.** Each star's FWHM ramps from `minSigma` at the
///   top to `maxSigma` at the bottom, and its peak brightness ramps from
///   `minPeak` to `maxPeak` in step — so the largest stars are also the brightest
///   and clip to a flat, saturated top, reproducing the case a matched filter
///   alone misses. Every star carries a **matching halo**: a fainter, broader
///   Gaussian whose scale tracks the core, so big stars get big halos.
/// - **Across the columns (X): eccentricity.** Each star's eccentricity ramps
///   from `0` (round) on the left to `maxEccentricity` on the right, holding its
///   overall size constant along the row, so a column changes only shape.
///
/// The fixture reports its **ground truth** (``stars``) — each star's true
/// centre, FWHM, eccentricity, peak and whether it saturates — so a test can
/// assert recall, position and the size/eccentricity trends against known
/// inputs. Reproducible seeded noise is added on top.
struct SyntheticStarGrid
{
    /// A ground-truth star: the exact parameters it was generated from.
    struct Star
    {
        /// The grid column (0 = leftmost, least eccentric).
        let column: Int

        /// The grid row (0 = topmost, smallest).
        let row: Int

        /// The centre column, in pixels.
        let x: Double

        /// The centre row, in pixels.
        let y: Double

        /// The core's geometric-mean full width at half maximum, in pixels.
        let fwhm: Double

        /// The shape eccentricity: `0` round, approaching `1` as it elongates.
        let eccentricity: Double

        /// The core's peak value above the background, before saturation clipping.
        let peak: Double

        /// Whether the star's centre clips at the saturation level.
        let saturated: Bool
    }

    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// The number of columns (the eccentricity axis).
    let columns: Int

    /// The number of rows (the size axis).
    let rows: Int

    /// The spacing between star centres, in pixels; also the cell size, so the
    /// image is `columns * spacing` by `rows * spacing`.
    let spacing: Int

    /// The flat background level the stars sit on.
    let background: Double

    /// The level at which pixels clip, modelling sensor / ADC saturation.
    let saturationLevel: Double

    /// The magnitude of the reproducible noise added on top.
    let noiseAmplitude: Double

    /// The seed for the deterministic noise source.
    let seed: UInt64

    /// The core Gaussian sigma of the smallest (top-row) stars, in pixels.
    let minSigma: Double

    /// The core Gaussian sigma of the largest (bottom-row) stars, in pixels.
    let maxSigma: Double

    /// The peak above background of the faintest (top-row) stars.
    let minPeak: Double

    /// The peak above background of the brightest (bottom-row) stars, before
    /// clipping.
    let maxPeak: Double

    /// The eccentricity of the rightmost column; the leftmost is `0`.
    let maxEccentricity: Double

    /// The halo's Gaussian sigma as a multiple of the core sigma.
    let haloScale: Double

    /// The halo's peak as a fraction of the core peak.
    let haloFraction: Double

    /// Creates a grid fixture. The defaults produce the headline 50×50 field with
    /// small round stars at the top-left grading to large, saturated, eccentric
    /// stars at the bottom-right.
    init(
        columns:         Int    = 50,
        rows:            Int    = 50,
        spacing:         Int    = 100,
        background:      Double  = 200,
        saturationLevel: Double  = 60000,
        noiseAmplitude:  Double  = 8,
        seed:            UInt64  = 1,
        minSigma:        Double  = 1.2,
        maxSigma:        Double  = 6.0,
        minPeak:         Double  = 1500,
        maxPeak:         Double  = 120000,
        maxEccentricity: Double  = 0.85,
        haloScale:       Double  = 2.0,
        haloFraction:    Double  = 0.03
    )
    {
        self.columns         = columns
        self.rows            = rows
        self.spacing         = spacing
        self.background      = background
        self.saturationLevel = saturationLevel
        self.noiseAmplitude  = noiseAmplitude
        self.seed            = seed
        self.minSigma        = minSigma
        self.maxSigma        = maxSigma
        self.minPeak         = minPeak
        self.maxPeak         = maxPeak
        self.maxEccentricity = maxEccentricity
        self.haloScale       = haloScale
        self.haloFraction    = haloFraction
    }

    /// The image width, in pixels.
    var width: Int
    {
        self.columns * self.spacing
    }

    /// The image height, in pixels.
    var height: Int
    {
        self.rows * self.spacing
    }

    /// The ground-truth stars, one per cell, computed purely from the
    /// configuration (independent of the pixels and the noise).
    var stars: [ Star ]
    {
        ( 0 ..< self.rows ).flatMap
        {
            row in

            ( 0 ..< self.columns ).map
            {
                column in

                let sigma = self.sigma( forRow: row )
                let peak  = self.peak( forRow: row )
                let ecc   = self.eccentricity( forColumn: column )

                return Star(
                    column:       column,
                    row:          row,
                    x:            ( Double( column ) + 0.5 ) * Double( self.spacing ),
                    y:            ( Double( row ) + 0.5 ) * Double( self.spacing ),
                    fwhm:         Self.fwhmPerSigma * sigma,
                    eccentricity: ecc,
                    peak:         peak,
                    saturated:    ( self.background + ( peak * ( 1 + self.haloFraction ) ) ) >= self.saturationLevel
                )
            }
        }
    }

    /// Renders the fixture to a single-channel linear pixel buffer: the stars and
    /// their halos stamped over the background, then reproducible noise, then
    /// saturation clipping.
    ///
    /// Each star is stamped only over its own bounded window, so generation stays
    /// fast even for a full 50×50 field.
    ///
    /// - Returns: The synthetic single-channel image.
    /// - Throws: An error if the geometry is inconsistent.
    func image() throws -> PixelBuffer
    {
        var pixels = [ Double ]( repeating: self.background, count: self.width * self.height )

        self.stars.forEach { self.stamp( $0, into: &pixels ) }

        var noise = DeterministicNoise( seed: self.seed )

        pixels = pixels.map
        {
            let noisy = $0 + ( noise.next() * self.noiseAmplitude )

            return Swift.min( Swift.max( noisy, 0 ), self.saturationLevel )
        }

        return try PixelBuffer( width: self.width, height: self.height, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// The core sigma for a row, ramping `minSigma` → `maxSigma` top to bottom.
    private func sigma( forRow row: Int ) -> Double
    {
        self.minSigma + ( ( self.maxSigma - self.minSigma ) * self.fraction( row, of: self.rows ) )
    }

    /// The core peak for a row, ramping `minPeak` → `maxPeak` top to bottom.
    private func peak( forRow row: Int ) -> Double
    {
        self.minPeak + ( ( self.maxPeak - self.minPeak ) * self.fraction( row, of: self.rows ) )
    }

    /// The eccentricity for a column, ramping `0` → `maxEccentricity` left to
    /// right.
    private func eccentricity( forColumn column: Int ) -> Double
    {
        self.maxEccentricity * self.fraction( column, of: self.columns )
    }

    /// The `0 ... 1` position of an index within `count` steps; `0` when there is
    /// only one step, so a single-row or single-column grid is well defined.
    private func fraction( _ index: Int, of count: Int ) -> Double
    {
        count > 1 ? Double( index ) / Double( count - 1 ) : 0
    }

    /// Stamps a star's core and halo into the pixel buffer over a bounded window.
    private func stamp( _ star: Star, into pixels: inout [ Double ] )
    {
        let sigma = Self.fwhmPerSigma == 0 ? 1 : star.fwhm / Self.fwhmPerSigma

        // Split the round sigma into major / minor axes that preserve the overall
        // size (their geometric mean stays `sigma`) while realising the target
        // eccentricity, elongating along the x axis.
        let q          = ( 1 - ( star.eccentricity * star.eccentricity ) ).squareRoot()
        let sigmaX     = sigma / q.squareRoot()
        let sigmaY     = sigma * q.squareRoot()
        let haloX      = sigmaX * self.haloScale
        let haloY      = sigmaY * self.haloScale
        let haloPeak   = star.peak * self.haloFraction
        let reach      = Int( ( Swift.max( haloX, haloY ) * 3.5 ).rounded( .up ) )
        let cx         = Int( star.x )
        let cy         = Int( star.y )

        ( -reach ... reach ).forEach
        {
            dy in

            let y = cy + dy

            guard y >= 0, y < self.height
            else
            {
                return
            }

            ( -reach ... reach ).forEach
            {
                dx in

                let x = cx + dx

                guard x >= 0, x < self.width
                else
                {
                    return
                }

                let fx       = Double( x ) - star.x
                let fy       = Double( y ) - star.y
                let core     = star.peak * exp( -( ( ( fx * fx ) / ( 2 * sigmaX * sigmaX ) ) + ( ( fy * fy ) / ( 2 * sigmaY * sigmaY ) ) ) )
                let halo     = haloPeak  * exp( -( ( ( fx * fx ) / ( 2 * haloX * haloX ) ) + ( ( fy * fy ) / ( 2 * haloY * haloY ) ) ) )

                pixels[ ( y * self.width ) + x ] += core + halo
            }
        }
    }
}
