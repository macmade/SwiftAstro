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

/// Tests for ``MatchedFilterStarDetector``.
struct MatchedFilterStarDetectorTests
{
    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// Whether a star was detected within one pixel of an expected position.
    private func hasStar( _ field: StarField, nearX x: Double, y: Double ) -> Bool
    {
        field.stars.contains { abs( $0.x - x ) < 1 && abs( $0.y - y ) < 1 }
    }

    /// Every planted star is detected at its position, and nothing spurious is.
    @Test
    func detectsPlantedStars() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingStar( cx: 40, cy: 40, peak: 3000, sigma: 2 )
            .addingStar( cx: 120, cy: 50, peak: 2500, sigma: 2.2 )
            .addingStar( cx: 80, cy: 120, peak: 4000, sigma: 1.8 )
            .addingNoise( seed: 1, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 3 )
        #expect( self.hasStar( field, nearX: 40, y: 40 ) )
        #expect( self.hasStar( field, nearX: 120, y: 50 ) )
        #expect( self.hasStar( field, nearX: 80, y: 120 ) )
    }

    /// A smooth brightness gradient (extended-nebulosity proxy) produces no
    /// detections: the zero-sum matched filter has no response to it.
    @Test
    func findsNothingOnASmoothGradient() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingGradient( scaleX: 6, scaleY: 4 )
            .addingNoise( seed: 2, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// A pure-noise field produces no detections.
    @Test
    func findsNothingInPureNoise() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingNoise( seed: 3, amplitude: 12 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// Single hot pixels are rejected — they are not point-spread-shaped.
    @Test
    func rejectsHotPixels() throws
    {
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 30, cy: 30, peak: 6000, sigma: 0.01 )
            .addingStar( cx: 80, cy: 80, peak: 8000, sigma: 0.01 )
            .addingNoise( seed: 4, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// A star's measured centroid is accurate to well under a pixel, including its
    /// sub-pixel position — so an overlay can register a marker on the star.
    @Test
    func measuresSubPixelCentroids() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingStar( cx: 60.3,  cy: 90.7,  peak: 4000, sigma: 2 )
            .addingStar( cx: 110.8, cy: 40.2,  peak: 3500, sigma: 2 )
            .addingNoise( seed: 15, amplitude: 6 )
            .image()

        let field = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )
        let first  = try #require( field.stars.first { abs( $0.x - 60.3 ) < 1 && abs( $0.y - 90.7 ) < 1 } )
        let second = try #require( field.stars.first { abs( $0.x - 110.8 ) < 1 && abs( $0.y - 40.2 ) < 1 } )

        #expect( abs( first.x - 60.3 ) < 0.15 )
        #expect( abs( first.y - 90.7 ) < 0.15 )
        #expect( abs( second.x - 110.8 ) < 0.15 )
        #expect( abs( second.y - 40.2 ) < 0.15 )
    }

    /// The reported metrics of a detected star match the planted profile.
    @Test
    func measuresDetectedStarMetrics() throws
    {
        let sigma = 2.0
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 60, cy: 60, peak: 4000, sigma: sigma )
            .addingNoise( seed: 5, amplitude: 6 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )
        let star  = try #require( field.stars.first )

        #expect( field.count == 1 )
        #expect( abs( star.x - 60 ) < 0.3 )
        #expect( abs( star.y - 60 ) < 0.3 )
        #expect( abs( star.fwhm - Self.fwhmPerSigma * sigma ) < 0.15 * Self.fwhmPerSigma * sigma )
        #expect( star.eccentricity < 0.2 )
    }

    /// The auto-estimated FWHM is close to the planted profile's FWHM.
    @Test
    func autoEstimatesFWHMNearThePlantedValue() throws
    {
        let sigma = 2.5
        let image = try SyntheticStarField( width: 200, height: 200, background: 200 )
            .addingStar( cx: 50, cy: 50, peak: 5000, sigma: sigma )
            .addingStar( cx: 150, cy: 60, peak: 4500, sigma: sigma )
            .addingStar( cx: 100, cy: 150, peak: 6000, sigma: sigma )
            .addingNoise( seed: 6, amplitude: 8 )
            .image()

        let estimated = try #require( MatchedFilterStarDetector.estimateFWHM( in: image ) )

        #expect( abs( estimated - Self.fwhmPerSigma * sigma ) < 0.25 * Self.fwhmPerSigma * sigma )
    }

    /// On a dense field of small stars, the estimate tracks the true small scale
    /// rather than blowing up: sizing a bright star's footprint that has merged its
    /// crowded neighbours would read several times too large, which is what made a
    /// dense, drizzled master under-detect (the size-band cut then rejected the
    /// whole real population). The merge-aware estimate sizes the isolated stars.
    @Test
    func autoEstimatesFWHMOnADenseSmallStarField() throws
    {
        let sigma  = 1.2
        let places: [ ( x: Double, y: Double, peak: Double ) ] = ( 0 ..< 30 ).flatMap
        {
            row -> [ ( x: Double, y: Double, peak: Double ) ] in

            ( 0 ..< 30 ).map
            {
                column -> ( x: Double, y: Double, peak: Double ) in

                let x = 12.0 + ( Double( column ) * 6.0 )
                let y = 12.0 + ( Double( row ) * 6.0 )

                return ( x: x, y: y, peak: ( ( row + column ) % 5 == 0 ) ? 9000 : 2600 )
            }
        }

        let base  = SyntheticStarField( width: 200, height: 200, background: 200 )
        let image = try places.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: $1.peak, sigma: sigma ) }
            .addingNoise( seed: 9, amplitude: 8 )
            .image()

        let estimated = try #require( MatchedFilterStarDetector.estimateFWHM( in: image ) )

        // Near the true small FWHM, not the several-fold blow-up a merged footprint
        // would produce on this crowding.
        #expect( estimated < 2.0 * Self.fwhmPerSigma * sigma )
    }

    /// A manual FWHM override bypasses auto-estimation and still detects stars.
    @Test
    func honorsAManualFWHMOverride() throws
    {
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 60, cy: 60, peak: 4000, sigma: 2 )
            .addingNoise( seed: 7, amplitude: 6 )
            .image()

        let detector = MatchedFilterStarDetector( configuration: .init( expectedFWHM: 4.7 ) )
        let field    = try detector.detectStars( in: image )

        #expect( field.count == 1 )
    }

    /// A multi-channel image is rejected.
    @Test
    func rejectsMultiChannelInput() throws
    {
        let image = try PixelBuffer( width: 4, height: 4, channels: 3, pixels: [ Double ]( repeating: 0, count: 48 ), isNormalized: false )

        #expect( throws: SwiftAstro.Error.self )
        {
            try MatchedFilterStarDetector().detectStars( in: image )
        }
    }
}
