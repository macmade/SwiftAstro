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

/// Tests for the bright / large-star detection pass of ``MatchedFilterStarDetector``.
///
/// The reproduction is a frame dominated by small stars — which tune the
/// matched-filter scale small — with a few large, bright, round stars added. The
/// small-tuned filter plus its size band drops every large star, saturated or
/// not, which is exactly the case the pass must recover, without inventing stars
/// from bright nebulosity or double-counting the small ones.
struct BrightStarDetectionTests
{
    /// The planted large, round stars: two saturated, two not.
    private static let bigStars: [ ( x: Double, y: Double, peak: Double, sigma: Double ) ] =
        [
            ( x: 130, y: 130, peak: 90000,  sigma: 5.5 ),
            ( x: 270, y: 270, peak: 120000, sigma: 6.0 ),
            ( x: 270, y: 130, peak: 22000,  sigma: 5.0 ),
            ( x: 130, y: 270, peak: 30000,  sigma: 4.5 ),
        ]

    /// A 6×6 lattice of small stars.
    private static let smallStars: [ ( x: Double, y: Double, peak: Double ) ] =
        ( 0 ..< 6 ).flatMap
            {
                row in

                ( 0 ..< 6 ).map
                {
                    column -> ( x: Double, y: Double, peak: Double ) in

                    let x    = 40.0 + ( Double( column ) * 60.0 )
                    let y    = 40.0 + ( Double( row ) * 60.0 )
                    let peak = 2800.0 + ( Double( ( row + column ) % 3 ) * 300.0 )

                    return ( x: x, y: y, peak: peak )
                }
            }

    /// Whether a star was detected within a few pixels of an expected position.
    private func hasStar( _ field: StarField, nearX x: Double, y: Double, tolerance: Double = 3 ) -> Bool
    {
        field.stars.contains { abs( $0.x - x ) < tolerance && abs( $0.y - y ) < tolerance }
    }

    /// The reproduction frame: the small-star lattice plus the large stars, noise,
    /// then saturation clipping (so the saturated cores are flat, as on a sensor).
    private func reproductionField( seed: UInt64 ) throws -> PixelBuffer
    {
        let base       = SyntheticStarField( width: 400, height: 400, background: 200 )
        let withSmall  = Self.smallStars.reduce( base )      { $0.addingStar( cx: $1.x, cy: $1.y, peak: $1.peak, sigma: 2 ) }
        let withBig    = Self.bigStars.reduce( withSmall )   { $0.addingStar( cx: $1.x, cy: $1.y, peak: $1.peak, sigma: $1.sigma ) }

        return try withBig.addingNoise( seed: seed, amplitude: 8 ).saturating( at: 40000 ).image()
    }

    /// The default detector recovers every large star — saturated or not — that
    /// the matched filter alone drops, while still finding the small stars.
    @Test
    func detectsBigStarsTheMatchedFilterMisses() throws
    {
        let image = try self.reproductionField( seed: 21 )
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        Self.bigStars.forEach
        {
            #expect( self.hasStar( field, nearX: $0.x, y: $0.y ), "missing big star at (\( $0.x ), \( $0.y ))" )
        }

        #expect( self.hasStar( field, nearX: 40, y: 40 ) )

        // The pass adds exactly the large stars and nothing spurious, on top of
        // whatever the matched filter found on its own.
        let withoutPass = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )

        #expect( field.count == withoutPass.count + Self.bigStars.count )
    }

    /// With the pass disabled, the matched filter alone misses every large star —
    /// documenting the gap the pass closes — while still finding the small stars.
    @Test
    func matchedFilterAloneMissesBigStars() throws
    {
        let image    = try self.reproductionField( seed: 21 )
        let detector = MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) )
        let field    = try detector.detectStars( in: image )

        Self.bigStars.forEach
        {
            #expect( self.hasStar( field, nearX: $0.x, y: $0.y ) == false, "unexpectedly found big star at (\( $0.x ), \( $0.y ))" )
        }

        // Not everything is found: the large stars are dropped, so the count falls
        // short of the full planted population.
        #expect( field.count < Self.smallStars.count + Self.bigStars.count )
        #expect( field.count >= Self.smallStars.count - 2 )
    }

    /// Bright but extended nebulosity is not a star: it must not be detected, even
    /// though its raw values rise well above the bright-pass threshold.
    @Test
    func rejectsBrightExtendedNebulosity() throws
    {
        let image = try SyntheticStarField( width: 260, height: 260, background: 200 )
            .addingStar( cx: 130, cy: 130, peak: 3000, sigma: 40 )
            .addingNoise( seed: 12, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// A single normal, bright star is detected exactly once — the bright pass
    /// must not add a duplicate on top of the matched-filter detection.
    @Test
    func doesNotDoubleCountANormalBrightStar() throws
    {
        let image = try SyntheticStarField( width: 140, height: 140, background: 200 )
            .addingStar( cx: 70, cy: 70, peak: 6000, sigma: 2 )
            .addingNoise( seed: 13, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 1 )
    }

    /// On a field of only small stars, the pass adds nothing: enabling it leaves
    /// the detections identical to the matched filter alone.
    @Test
    func brightPassLeavesASmallStarFieldUnchanged() throws
    {
        let base  = SyntheticStarField( width: 400, height: 400, background: 200 )
        let image = try Self.smallStars.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: $1.peak, sigma: 2 ) }
            .addingNoise( seed: 22, amplitude: 8 )
            .image()

        let withPass    = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: true ) ).detectStars( in: image )
        let withoutPass = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )

        #expect( withPass.count == withoutPass.count )
    }

    /// The bright-pass parameters are honoured: a minimum-radius cut set larger
    /// than any real blob rejects every large star, collapsing the result to the
    /// matched filter alone.
    @Test
    func honorsBrightPassMinimumRadius() throws
    {
        let image  = try self.reproductionField( seed: 21 )
        let strict = try MatchedFilterStarDetector( configuration: .init( brightStarMinRadiusFactor: 100 ) ).detectStars( in: image )
        let off    = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )

        #expect( strict.count == off.count )
    }

    /// The bright-pass threshold is honoured: lowering it and the minimum radius
    /// only widens what the pass accepts, so it still recovers every large star.
    @Test
    func honorsBrightPassThreshold() throws
    {
        let image = try self.reproductionField( seed: 21 )
        let loose = try MatchedFilterStarDetector( configuration: .init( brightStarThresholdSigma: 6, brightStarMinRadiusFactor: 1.5 ) ).detectStars( in: image )

        Self.bigStars.forEach
        {
            #expect( self.hasStar( loose, nearX: $0.x, y: $0.y ), "missing big star at (\( $0.x ), \( $0.y ))" )
        }
    }

    /// The local-contrast cut is honoured: an impossibly high requirement rejects
    /// every bright candidate, collapsing the result to the matched filter alone.
    @Test
    func honorsBrightPassLocalContrast() throws
    {
        let image  = try self.reproductionField( seed: 21 )
        let strict = try MatchedFilterStarDetector( configuration: .init( brightStarLocalContrastSigma: 100000 ) ).detectStars( in: image )
        let off    = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )

        #expect( strict.count == off.count )
    }

    /// A large star sitting on a raised local background (a nebulosity pedestal) is
    /// sized against the sky *around* it, so the pedestal does not inflate its
    /// half-flux radius: the measured size matches the same star on flat sky.
    @Test
    func sizesABigStarOnRaisedBackgroundLikeOnFlatSky() throws
    {
        // A big star the matched filter drops (so the bright pass measures it), plus
        // small stars to keep the matched-filter scale small.
        let smalls: [ ( x: Double, y: Double ) ] = ( 0 ..< 4 ).flatMap
        {
            row -> [ ( x: Double, y: Double ) ] in

            ( 0 ..< 4 ).map
            {
                column -> ( x: Double, y: Double ) in

                ( x: 45.0 + ( Double( column ) * 75.0 ), y: 45.0 + ( Double( row ) * 75.0 ) )
            }
        }

        let field: ( Double ) -> SyntheticStarField =
        {
            pedestal in

            let base      = SyntheticStarField( width: 340, height: 340, background: 200 )
            let withSmall = smalls.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: 3000, sigma: 2 ) }
            let withStar  = withSmall.addingStar( cx: 190, cy: 190, peak: 24000, sigma: 5 )

            // A broad sub-star pedestal, standing in for local nebulosity.
            return pedestal > 0 ? withStar.addingStar( cx: 190, cy: 190, peak: pedestal, sigma: 14 ) : withStar
        }

        let flat = try field( 0 ).addingNoise( seed: 41, amplitude: 8 ).image()
        let neb  = try field( 1000 ).addingNoise( seed: 41, amplitude: 8 ).image()

        let onFlat = try #require( try MatchedFilterStarDetector().detectStars( in: flat ).stars.first { abs( $0.x - 190 ) < 3 && abs( $0.y - 190 ) < 3 } )
        let onNeb  = try #require( try MatchedFilterStarDetector().detectStars( in: neb ).stars.first  { abs( $0.x - 190 ) < 3 && abs( $0.y - 190 ) < 3 } )

        #expect( abs( onNeb.hfr - onFlat.hfr ) < 0.4 * onFlat.hfr )
    }
}
