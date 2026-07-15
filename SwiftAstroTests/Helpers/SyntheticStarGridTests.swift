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
import Testing

/// Tests for the ``SyntheticStarGrid`` fixture generator: a grid of stars that
/// grow in size (with matching halos) down the rows and grow in eccentricity
/// across the columns, with the brightest, largest stars saturating.
struct SyntheticStarGridTests
{
    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// The value of a pixel at a column/row in a single-channel buffer.
    private func value( _ image: PixelBuffer, x: Int, y: Int ) -> Double
    {
        image.pixels[ ( y * image.width ) + x ]
    }

    /// The ground truth has exactly one star per grid cell.
    @Test
    func groundTruthHasOneStarPerCell() throws
    {
        let grid = SyntheticStarGrid( columns: 4, rows: 3, spacing: 40 )

        #expect( grid.stars.count == 12 )
    }

    /// The generated image spans `columns × spacing` by `rows × spacing`.
    @Test
    func imageDimensionsMatchGridAndSpacing() throws
    {
        let grid  = SyntheticStarGrid( columns: 4, rows: 3, spacing: 40 )
        let image = try grid.image()

        #expect( image.width == 160 )
        #expect( image.height == 120 )
        #expect( image.channels == 1 )
    }

    /// Star size grows from the top row to the bottom row (Y axis = size).
    @Test
    func sizeIncreasesFromTopToBottomRow() throws
    {
        let grid    = SyntheticStarGrid( columns: 3, rows: 5, spacing: 60 )
        let byRow   = Dictionary( grouping: grid.stars ) { $0.row }
        let medians = ( 0 ..< 5 ).compactMap { row in byRow[ row ]?.first?.fwhm }

        #expect( medians.count == 5 )
        #expect( zip( medians, medians.dropFirst() ).allSatisfy { $0 < $1 } )
    }

    /// Eccentricity grows from the left column to the right column (X axis), and
    /// the leftmost column is round.
    @Test
    func eccentricityIncreasesFromLeftToRightColumn() throws
    {
        let grid          = SyntheticStarGrid( columns: 5, rows: 3, spacing: 60 )
        let topRow        = grid.stars.filter { $0.row == 0 }.sorted { $0.column < $1.column }
        let eccentricities = topRow.map { $0.eccentricity }

        #expect( eccentricities.count == 5 )
        #expect( try #require( eccentricities.first ) < 0.01 )
        #expect( zip( eccentricities, eccentricities.dropFirst() ).allSatisfy { $0 < $1 } )
    }

    /// Along a single row, size is constant — only eccentricity varies across it.
    @Test
    func sizeIsConstantAcrossARow() throws
    {
        let grid   = SyntheticStarGrid( columns: 5, rows: 3, spacing: 60 )
        let widths = Set( grid.stars.filter { $0.row == 1 }.map { ( $0.fwhm * 1000 ).rounded() } )

        #expect( widths.count == 1 )
    }

    /// The brightest, largest stars saturate to a flat top clipped at the
    /// saturation level, while the small stars stay below it.
    @Test
    func bigBrightStarsSaturateToAFlatTop() throws
    {
        let grid  = SyntheticStarGrid( columns: 2, rows: 2, spacing: 80, saturationLevel: 40000, minPeak: 1500, maxPeak: 120000 )
        let image = try grid.image()

        let big   = try #require( grid.stars.max { $0.fwhm < $1.fwhm } )
        let small = try #require( grid.stars.min { $0.fwhm < $1.fwhm } )

        #expect( big.saturated )
        #expect( small.saturated == false )

        let bigCenter   = self.value( image, x: Int( big.x ), y: Int( big.y ) )
        let smallCenter = self.value( image, x: Int( small.x ), y: Int( small.y ) )

        // The big star's core is clipped exactly at the saturation level, and the
        // clip forms a flat top of several pixels; the small star peaks below it.
        #expect( abs( bigCenter - 40000 ) < 0.001 )
        #expect( smallCenter < 40000 )

        let flatTop = ( -3 ... 3 ).flatMap { dy in ( -3 ... 3 ).map { dx in self.value( image, x: Int( big.x ) + dx, y: Int( big.y ) + dy ) } }

        #expect( flatTop.filter { abs( $0 - 40000 ) < 0.001 }.count >= 5 )
    }

    /// A high-eccentricity star is elongated: it extends farther along the x axis
    /// than the y axis.
    @Test
    func eccentricStarsAreElongatedAlongOneAxis() throws
    {
        // A two-cell row, large and unsaturated so the clip does not mask the
        // shape; the rightmost cell reaches the maximum eccentricity.
        let wide  = SyntheticStarGrid( columns: 2, rows: 1, spacing: 120, saturationLevel: 60000, minSigma: 5, maxSigma: 5, minPeak: 8000, maxPeak: 8000, maxEccentricity: 0.85 )
        let image = try wide.image()
        let star  = try #require( wide.stars.max { $0.eccentricity < $1.eccentricity } )

        let half        = ( self.value( image, x: Int( star.x ), y: Int( star.y ) ) + 200 ) / 2
        let xExtent     = ( -40 ... 40 ).filter { self.value( image, x: Int( star.x ) + $0, y: Int( star.y ) ) > half }.count
        let yExtent     = ( -40 ... 40 ).filter { self.value( image, x: Int( star.x ), y: Int( star.y ) + $0 ) > half }.count

        #expect( xExtent > yExtent )
    }

    /// A bright star carries a halo: flux well beyond the core, above what the
    /// core Gaussian alone would leave there.
    @Test
    func brightStarsCarryAHaloBeyondTheCore() throws
    {
        let withHalo    = SyntheticStarGrid( columns: 1, rows: 1, spacing: 160, saturationLevel: 200000, noiseAmplitude: 0, minSigma: 4, maxSigma: 4, minPeak: 20000, maxPeak: 20000, haloFraction: 0.05 )
        let withoutHalo = SyntheticStarGrid( columns: 1, rows: 1, spacing: 160, saturationLevel: 200000, noiseAmplitude: 0, minSigma: 4, maxSigma: 4, minPeak: 20000, maxPeak: 20000, haloFraction: 0.0 )

        let haloImage = try withHalo.image()
        let coreImage = try withoutHalo.image()
        let star      = try #require( withHalo.stars.first )

        // Sample well outside the core (≈ 4σ), where the halo dominates.
        let x = Int( star.x ) + 16
        let y = Int( star.y )

        #expect( self.value( haloImage, x: x, y: y ) > self.value( coreImage, x: x, y: y ) + 50 )
    }

    /// Generation is deterministic: the same configuration yields identical
    /// pixels, so fixtures are reproducible across runs.
    @Test
    func generationIsDeterministic() throws
    {
        let grid = SyntheticStarGrid( columns: 3, rows: 3, spacing: 50, seed: 42 )

        let first  = try grid.image()
        let second = try grid.image()

        #expect( first.pixels == second.pixels )
    }
}
