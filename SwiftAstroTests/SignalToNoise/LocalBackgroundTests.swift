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

/// Tests for ``LocalBackground``.
struct LocalBackgroundTests
{
    /// Builds a single-channel buffer from a generator.
    private func image( width: Int, height: Int, _ value: ( Int, Int ) -> Double ) throws -> PixelBuffer
    {
        let pixels = ( 0 ..< ( width * height ) ).map { value( $0 % width, $0 / width ) }

        return try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// An image with no pixels yields no estimate.
    @Test
    func emptyImageHasNoEstimate() throws
    {
        let image = try PixelBuffer( width: 0, height: 0, channels: 1, pixels: [], isNormalized: false )

        #expect( LocalBackground.estimate( in: image ) == nil )
    }

    /// An image whose samples are all non-finite yields no estimate: there is no
    /// tile anywhere that can be measured.
    @Test
    func allBlankImageHasNoEstimate() throws
    {
        let image = try self.image( width: 32, height: 32 ) { _, _ in Double.nan }

        #expect( LocalBackground.estimate( in: image ) == nil )
    }

    /// A flat image reads its flat level everywhere, with zero noise.
    @Test
    func flatImageReadsItsLevelEverywhere() throws
    {
        let image      = try self.image( width: 128, height: 128 ) { _, _ in 42 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        #expect( background.level( atX: 0,   y: 0   ) == 42 )
        #expect( background.level( atX: 63,  y: 63  ) == 42 )
        #expect( background.level( atX: 127, y: 127 ) == 42 )
        #expect( background.noise( atX: 63,  y: 63  ) == 0 )
    }

    /// A tile larger than the image degenerates to the single global estimate: one
    /// tile whose level and noise are the whole image's median and robust MAD.
    @Test
    func tileLargerThanTheImageIsTheGlobalEstimate() throws
    {
        let pixels     = [ 0.0, 1, 2, 3, 4, 5, 6 ]
        let image      = try PixelBuffer( width: 7, height: 1, channels: 1, pixels: pixels, isNormalized: false )
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 4096 ) )

        #expect( background.columns == 1 )
        #expect( background.rows    == 1 )
        #expect( background.level( atX: 3, y: 0 ) == 3 )
        #expect( Swift.abs( background.noise( atX: 3, y: 0 ) - ( 1.4826 * 2.0 ) ) < 1e-9 )
    }

    /// The map tracks a spatial step: a bright left half and a dark right half are
    /// each read at their own level, not at a single global compromise.
    @Test
    func tracksASpatialStepInTheBackground() throws
    {
        let image      = try self.image( width: 256, height: 64 ) { x, _ in x < 128 ? 1000 : 100 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        // Well inside each half — away from the interpolated seam.
        #expect( Swift.abs( background.level( atX: 16,  y: 32 ) - 1000 ) < 1e-9 )
        #expect( Swift.abs( background.level( atX: 240, y: 32 ) -  100 ) < 1e-9 )

        // A single global median would sit halfway between the two.
        #expect( background.level( atX: 16, y: 32 ) > 900 )
    }

    /// The interpolated level is continuous: sampling across a step produces a
    /// smooth ramp, never a jump larger than one tile's worth of change.
    @Test
    func interpolatesContinuouslyAcrossTiles() throws
    {
        let image      = try self.image( width: 256, height: 64 ) { x, _ in x < 128 ? 1000 : 100 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )
        let profile    = ( 0 ..< 256 ).map { background.level( atX: Double( $0 ), y: 32 ) }

        let biggestStep = zip( profile, profile.dropFirst() ).reduce( 0.0 ) { Swift.max( $0, Swift.abs( $1.1 - $1.0 ) ) }

        // Over a 32 px tile a 900-unit step interpolates at ~28 units per pixel.
        #expect( biggestStep < 40 )
        #expect( profile.first ?? 0 > 900 )
        #expect( profile.last  ?? 0 < 200 )
    }

    /// Sampling outside the image clamps to the edge tiles rather than
    /// extrapolating or trapping.
    @Test
    func clampsSamplesOutsideTheImage() throws
    {
        let image      = try self.image( width: 256, height: 64 ) { x, _ in x < 128 ? 1000 : 100 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        #expect( background.level( atX: -1000, y: -1000 ) == background.level( atX: 0,   y: 0  ) )
        #expect( background.level( atX:  1000, y:  1000 ) == background.level( atX: 255, y: 63 ) )
    }

    /// A compact source does not move its tile's level: the per-tile median is
    /// robust, which is what lets the map describe *sky* rather than the objects
    /// sitting on it.
    @Test
    func compactSourcesDoNotMoveTheTileLevel() throws
    {
        let plain = try self.image( width: 128, height: 128 ) { _, _ in 500 }
        let withStar = try self.image( width: 128, height: 128 )
        {
            x, y in

            let dx = Double( x ) - 64
            let dy = Double( y ) - 64

            return 500 + ( 50_000 * Foundation.exp( -( ( dx * dx ) + ( dy * dy ) ) / 8 ) )
        }

        let plainBackground = try #require( LocalBackground.estimate( in: plain,    tileSize: 64 ) )
        let starBackground  = try #require( LocalBackground.estimate( in: withStar, tileSize: 64 ) )

        #expect( starBackground.level( atX: 64, y: 64 ) == plainBackground.level( atX: 64, y: 64 ) )
    }

    /// Non-finite blanks are ignored, so a frame carrying them is measured from
    /// its finite samples exactly as if they were absent.
    @Test
    func ignoresNonFiniteBlanks() throws
    {
        let clean  = try self.image( width: 64, height: 64 ) { x, _ in Double( x % 8 ) }
        let blanks = try self.image( width: 64, height: 64 ) { x, y in y == 0 ? Double.nan : Double( x % 8 ) }

        let cleanBackground = try #require( LocalBackground.estimate( in: clean,  tileSize: 32 ) )
        let blankBackground = try #require( LocalBackground.estimate( in: blanks, tileSize: 32 ) )

        #expect( blankBackground.level( atX: 32, y: 32 ) == cleanBackground.level( atX: 32, y: 32 ) )
        #expect( blankBackground.noise( atX: 32, y: 32 ) == cleanBackground.noise( atX: 32, y: 32 ) )
    }

    /// A tile with no measurable spread inherits the typical tile noise, so a
    /// locally-flat patch cannot collapse a detection threshold to its own level.
    @Test
    func flatTilesInheritTheTypicalNoise() throws
    {
        // The left half carries spread; the right half is perfectly flat.
        let image = try self.image( width: 256, height: 64 )
        {
            x, y in

            x < 128 ? Double( ( x + y ) % 16 ) : 0
        }

        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        #expect( background.noise( atX: 240, y: 32 ) > 0 )
        #expect( Swift.abs( background.noise( atX: 240, y: 32 ) - background.noise( atX: 16, y: 32 ) ) < 1e-9 )
    }

    /// A wholly flat image keeps zero noise: there is no typical noise to inherit,
    /// and the detector's own "no measurable noise" guard must still fire.
    @Test
    func whollyFlatImageKeepsZeroNoise() throws
    {
        let image      = try self.image( width: 128, height: 128 ) { _, _ in 7 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        #expect( background.noise( atX: 64, y: 64 ) == 0 )
    }

    /// A non-positive tile size is clamped rather than trapping or dividing by
    /// zero, degenerating to a per-pixel mesh.
    @Test
    func clampsANonPositiveTileSize() throws
    {
        let image      = try self.image( width: 8, height: 8 ) { _, _ in 3 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 0 ) )

        #expect( background.tileSize == 1 )
        #expect( background.columns  == 8 )
        #expect( background.rows     == 8 )
        #expect( background.level( atX: 4, y: 4 ) == 3 )
    }

    /// A non-finite or astronomically large coordinate is clamped, not converted to
    /// an `Int` it cannot represent — which would trap.
    @Test
    func clampsNonFiniteAndUnrepresentableCoordinates() throws
    {
        let image      = try self.image( width: 256, height: 64 ) { x, _ in x < 128 ? 1000 : 100 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        let corner = background.level( atX: 0, y: 0 )
        let far    = background.level( atX: 255, y: 63 )

        // A NaN has no position to clamp, so it reads the first tile; an infinity
        // clamps to the mesh edge it points at.
        #expect( background.level( atX: Double.nan,       y: 0  ) == corner )
        #expect( background.level( atX: 0,                y: Double.nan ) == corner )
        #expect( background.level( atX: -Double.infinity, y: 0  ) == corner )
        #expect( background.level( atX: -1e300,           y: 0  ) == corner )
        #expect( background.level( atX: Double.infinity,  y: 63 ) == far )
        #expect( background.level( atX: 1e300,            y: 63 ) == far )
        #expect( background.noise( atX: 1e300, y: 1e300 ).isFinite )
        #expect( background.threshold( atX: Double.nan, y: 1e300, sigmas: 5 ).isFinite )
    }

    /// A multi-channel buffer yields no estimate: the mesh geometry assumes one
    /// sample per pixel, so an interleaved buffer would be silently misread.
    @Test
    func multiChannelImageHasNoEstimate() throws
    {
        let image = try PixelBuffer( width: 8, height: 8, channels: 3, pixels: [ Double ]( repeating: 5, count: 8 * 8 * 3 ), isNormalized: false )

        #expect( LocalBackground.estimate( in: image ) == nil )
    }

    /// A degenerate geometry is rejected, not trapped on — including one whose cell
    /// count overflows.
    @Test
    func rejectsADegenerateGeometry() throws
    {
        #expect( LocalBackground( tileSize: 1, columns: Int.max, rows: 3, levels: [], noises: [] ) == nil )
        #expect( LocalBackground( tileSize: 1, columns: 2, rows: 2, levels: [ 1, 2, 3 ], noises: [ 1, 2, 3, 4 ] ) == nil )
        #expect( LocalBackground( tileSize: 0, columns: 2, rows: 2, levels: [ 1, 2, 3, 4 ], noises: [ 1, 2, 3, 4 ] ) == nil )
    }

    /// A mesh carrying a non-finite value or a negative noise is rejected: it would
    /// silently disable every threshold built on it, and would make the map unequal
    /// to itself.
    @Test
    func rejectsANonFiniteOrNegativeMesh() throws
    {
        let ok = [ 1.0, 2, 3, 4 ]

        #expect( LocalBackground( tileSize: 8, columns: 2, rows: 2, levels: [ 1, .nan, 3, 4 ], noises: ok ) == nil )
        #expect( LocalBackground( tileSize: 8, columns: 2, rows: 2, levels: [ 1, .infinity, 3, 4 ], noises: ok ) == nil )
        #expect( LocalBackground( tileSize: 8, columns: 2, rows: 2, levels: ok, noises: [ 1, .nan, 3, 4 ] ) == nil )
        #expect( LocalBackground( tileSize: 8, columns: 2, rows: 2, levels: ok, noises: [ 1, -2, 3, 4 ] ) == nil )
        #expect( LocalBackground( tileSize: 8, columns: 2, rows: 2, levels: ok, noises: ok ) != nil )
    }

    /// A source large enough to fill its own tile does not poison that tile's
    /// statistics: the mesh is median-filtered against its neighbours, so the cell
    /// under a broad star still reports sky, not the star.
    @Test
    func aSourceFillingATileDoesNotPoisonItsCell() throws
    {
        let sky       = 300.0
        let plain     = try self.image( width: 384, height: 384 ) { _, _ in sky }
        let defocused = try self.image( width: 384, height: 384 )
        {
            x, y in

            let dx = Double( x ) - 192
            let dy = Double( y ) - 192

            return sky + ( 20000 * Foundation.exp( -( ( dx * dx ) + ( dy * dy ) ) / ( 2 * 14 * 14 ) ) )
        }

        let plainBackground = try #require( LocalBackground.estimate( in: plain,     tileSize: 64 ) )
        let starBackground  = try #require( LocalBackground.estimate( in: defocused, tileSize: 64 ) )

        // At the star's centre the map still reads sky, not the star's core.
        #expect( Swift.abs( starBackground.level( atX: 192, y: 192 ) - plainBackground.level( atX: 192, y: 192 ) ) < 1 )

        // And the noise there is not inflated by the star's own gradient. This
        // fixture is noiseless, so the sky's own MAD is exactly zero and the filtered
        // mesh reads zero here; an unfiltered mesh reads ~38.8, which as a `3σ`
        // footprint level would sit above the star itself.
        #expect( starBackground.noise( atX: 192, y: 192 ) < 10 )
    }

    /// The mesh covers a partial trailing tile: an image that is not a whole
    /// number of tiles wide still measures its rightmost column.
    @Test
    func coversAPartialTrailingTile() throws
    {
        let image      = try self.image( width: 70, height: 70 ) { x, _ in x < 64 ? 10 : 900 }
        let background = try #require( LocalBackground.estimate( in: image, tileSize: 32 ) )

        #expect( background.columns == 3 )
        #expect( background.rows    == 3 )
        #expect( background.level( atX: 69, y: 35 ) > 100 )
    }
}
