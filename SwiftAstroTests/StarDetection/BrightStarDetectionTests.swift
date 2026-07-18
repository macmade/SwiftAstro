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

    /// A frame whose large, bright sources include one *cluster blend*: several
    /// stars crammed into one blob, measured together as a single broad source with
    /// inflated metrics — the synthetic analogue of the M12 globular-core outlier (a
    /// dense knot of stars read as one giant "star"). Two genuinely large single
    /// bright stars and a scale-setting lattice sit around it.
    private func blendField( seed: UInt64 ) throws -> PixelBuffer
    {
        var field = SyntheticStarField( width: 360, height: 360, background: 200 )

        for row in 0 ..< 5
        {
            for column in 0 ..< 5
            {
                field = field.addingStar( cx: 45 + Double( column ) * 65, cy: 45 + Double( row ) * 65, peak: 5000, sigma: 3 )
            }
        }

        field = field.addingStar( cx: 100, cy: 300, peak: 90000, sigma: 5.0 ) // genuine large, saturated, kept
        field = field.addingStar( cx: 300, cy: 100, peak: 30000, sigma: 4.5 ) // genuine large, kept

        // The cluster: several unsaturated stars in a tight knot, each a distinct
        // peak, merging into one broad blob (many peaks → dropped as a blend).
        let cluster: [ ( x: Double, y: Double ) ] =
            [
                ( 189, 189 ), ( 201, 190 ), ( 194, 198 ), ( 204, 201 ),
                ( 188, 202 ), ( 197, 207 ), ( 208, 194 ),
            ]

        field = cluster.reduce( field ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: 8000, sigma: 3 ) }

        return try field.addingNoise( seed: seed, amplitude: 8 ).saturating( at: 40000 ).image()
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

    /// The bright-pass threshold is honoured, isolated from the other knobs: at the
    /// default it recovers the big stars the matched filter misses, but raised far
    /// above any blob's peak it admits nothing, so the pass contributes nothing and
    /// the result collapses to the matched filter alone — a change versus the
    /// default that the threshold parameter alone drives.
    @Test
    func honorsBrightPassThreshold() throws
    {
        let image  = try self.reproductionField( seed: 21 )
        let off     = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )
        let normal = try MatchedFilterStarDetector().detectStars( in: image )
        let strict = try MatchedFilterStarDetector( configuration: .init( brightStarThresholdSigma: 100000 ) ).detectStars( in: image )

        // The default bright pass recovers the big stars, so it finds strictly more
        // than the matched filter alone...
        #expect( normal.count > off.count )
        Self.bigStars.forEach
        {
            #expect( self.hasStar( normal, nearX: $0.x, y: $0.y ), "missing big star at (\( $0.x ), \( $0.y ))" )
        }

        // ...while an unreachable threshold admits no blob, collapsing the result to
        // exactly the matched filter alone.
        #expect( strict.count == off.count )
    }

    /// `saturationLevel` is honoured by the bright pass too, not only the
    /// matched-filter pass (CR-6): with it set, a saturated big star (flat-topped
    /// at the level) is dropped by *both* paths rather than silently re-added by
    /// the bright pass, while an unsaturated big star of the same size is still
    /// recovered.
    @Test
    func honorsSaturationLevelInTheBrightPass() throws
    {
        let image = try self.reproductionField( seed: 21 )
        let field = try MatchedFilterStarDetector( configuration: .init( saturationLevel: 40000 ) ).detectStars( in: image )

        // The two saturated big stars (peak clipped to the 40000 level) are now
        // excluded — the bright pass no longer defeats the saturation gate.
        #expect( self.hasStar( field, nearX: 130, y: 130 ) == false, "saturated big star at (130, 130) should be dropped" )
        #expect( self.hasStar( field, nearX: 270, y: 270 ) == false, "saturated big star at (270, 270) should be dropped" )

        // The two unsaturated big stars (peaks 22000 / 30000, below the level) are
        // still recovered, so the gate drops only what is actually saturated.
        #expect( self.hasStar( field, nearX: 270, y: 130 ), "unsaturated big star at (270, 130) should be kept" )
        #expect( self.hasStar( field, nearX: 130, y: 270 ), "unsaturated big star at (130, 270) should be kept" )
    }

    /// The bright-pass peak-count discriminator drops a crowded cluster measured as
    /// one broad source (the M12 globular-core outlier), while still recovering the
    /// genuinely large *single* bright stars the pass exists for — regardless of how
    /// broad they are.
    @Test
    func dropsAClusterBlendButKeepsGenuineLargeStars() throws
    {
        let image = try self.blendField( seed: 21 )

        // With the discriminator disabled, the crowded cluster leaks through as one
        // spurious broad "star" — the pre-fix behaviour.
        let undiscriminated = try MatchedFilterStarDetector( configuration: .init( brightStarMaxPeaks: 100000 ) ).detectStars( in: image )

        #expect( undiscriminated.stars.contains { abs( $0.x - 195 ) < 20 && abs( $0.y - 195 ) < 20 && $0.fwhm > 14 }, "the un-discriminated cluster should leak through as one broad artefact" )

        // The default discriminator drops that multi-peak cluster...
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.stars.contains { abs( $0.x - 195 ) < 20 && abs( $0.y - 195 ) < 20 && $0.fwhm > 14 } == false, "the multi-peak cluster should be dropped" )

        // ...while still recovering the two genuinely large single bright stars.
        #expect( self.hasStar( field, nearX: 100, y: 300, tolerance: 4 ), "genuine large star at (100, 300) should be kept" )
        #expect( self.hasStar( field, nearX: 300, y: 100, tolerance: 4 ), "genuine large star at (300, 100) should be kept" )
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
