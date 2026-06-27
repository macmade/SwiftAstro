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

/// The flux-weighted moment measurements of a star from a set of background-
/// subtracted samples.
///
/// This is the shared "HFR-style" measurement math: a flux-weighted centroid,
/// the second moments and the FWHM / eccentricity derived from them, and the
/// empirical half-flux radius. It is robust to noise and hot pixels without the
/// cost of full PSF fitting.
///
/// It is the single source of truth for these metrics: the moment-based detector
/// measures sources with it directly, and the matched-filter detector reuses it
/// both to seed its Gaussian-fit initial guess (centroid and scale via the second
/// moments) and to report the empirical half-flux radius.
public struct StarMoments: Sendable
{
    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ, where σ = √((Mxx + Myy) / 2).
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// The flux-weighted centroid column, in pixels.
    public let x: Double

    /// The flux-weighted centroid row, in pixels.
    public let y: Double

    /// The total background-subtracted flux.
    public let flux: Double

    /// The flux-weighted second moment about the x axis (≈ σ² for a Gaussian).
    public let mxx: Double

    /// The flux-weighted second moment about the y axis (≈ σ² for a Gaussian).
    public let myy: Double

    /// The flux-weighted mixed second moment (the off-diagonal covariance term).
    public let mxy: Double

    /// The full width at half maximum, in pixels, from the mean second moment.
    public let fwhm: Double

    /// The shape eccentricity: `0` for a round source, approaching `1` as it
    /// elongates.
    public let eccentricity: Double

    /// The half-flux radius, in pixels.
    public let hfr: Double

    /// Measures the moments of a source from its samples and background.
    ///
    /// - Parameters:
    ///   - samples:    The source's samples: each a pixel position and its raw
    ///                 (not background-subtracted) value.
    ///   - background: The background level subtracted from each sample to form
    ///                 the flux weights.
    /// - Returns: The measured moments, or `nil` when the background-subtracted
    ///   flux is not positive (so a centroid is undefined).
    public init?( samples: [ ( x: Double, y: Double, value: Double ) ], background: Double )
    {
        let weighted = samples.map { ( x: $0.x, y: $0.y, w: $0.value - background ) }
        let flux     = weighted.reduce( 0 ) { $0 + $1.w }

        guard flux > 0
        else
        {
            return nil
        }

        let cx = weighted.reduce( 0 ) { $0 + ( $1.w * $1.x ) } / flux
        let cy = weighted.reduce( 0 ) { $0 + ( $1.w * $1.y ) } / flux

        let moments = weighted.reduce( ( xx: 0.0, yy: 0.0, xy: 0.0 ) )
        {
            let dx = $1.x - cx
            let dy = $1.y - cy

            return ( xx: $0.xx + ( $1.w * dx * dx ), yy: $0.yy + ( $1.w * dy * dy ), xy: $0.xy + ( $1.w * dx * dy ) )
        }

        let mxx = moments.xx / flux
        let myy = moments.yy / flux
        let mxy = moments.xy / flux

        self.x            = cx
        self.y            = cy
        self.flux         = flux
        self.mxx          = mxx
        self.myy          = myy
        self.mxy          = mxy
        self.fwhm         = Self.fwhmPerSigma * Swift.max( ( mxx + myy ) / 2, 0 ).squareRoot()
        self.eccentricity = Self.eccentricity( mxx: mxx, myy: myy, mxy: mxy )
        self.hfr          = Self.halfFluxRadius( samples: weighted, cx: cx, cy: cy, flux: flux )
    }

    /// The eccentricity of the moment ellipse: `√(1 − λ₂/λ₁)` for eigenvalues
    /// `λ₁ ≥ λ₂` of `[[Mxx, Mxy], [Mxy, Myy]]`. `0` for a round source.
    private static func eccentricity( mxx: Double, myy: Double, mxy: Double ) -> Double
    {
        let mean         = ( mxx + myy ) / 2
        let difference   = ( mxx - myy ) / 2
        let discriminant = ( ( difference * difference ) + ( mxy * mxy ) ).squareRoot()
        let major        = mean + discriminant
        let minor        = mean - discriminant

        guard major > 0
        else
        {
            return 0
        }

        return Swift.max( 0, 1 - ( minor / major ) ).squareRoot()
    }

    /// The empirical half-flux radius of a source measured about an explicit
    /// centre — typically a Gaussian-fit centre rather than the moment centroid.
    ///
    /// - Parameters:
    ///   - samples:    The source's samples: each a pixel position and its raw
    ///                 (not background-subtracted) value.
    ///   - background: The background level subtracted to form the flux weights.
    ///   - cx:         The centre column to measure radii from.
    ///   - cy:         The centre row to measure radii from.
    /// - Returns: The half-flux radius, in pixels, or `0` when there is no
    ///   positive flux.
    public static func halfFluxRadius( samples: [ ( x: Double, y: Double, value: Double ) ], background: Double, aroundX cx: Double, y cy: Double ) -> Double
    {
        let weighted = samples.map { ( x: $0.x, y: $0.y, w: $0.value - background ) }
        let flux     = weighted.reduce( 0 ) { $0 + $1.w }

        guard flux > 0
        else
        {
            return 0
        }

        return self.halfFluxRadius( samples: weighted, cx: cx, cy: cy, flux: flux )
    }

    /// The radius around the centroid containing half the source's flux, found by
    /// accumulating flux in order of increasing radius and interpolating to the
    /// 50% point.
    private static func halfFluxRadius( samples: [ ( x: Double, y: Double, w: Double ) ], cx: Double, cy: Double, flux: Double ) -> Double
    {
        let radial = samples.map
        {
            ( r: ( ( ( $0.x - cx ) * ( $0.x - cx ) ) + ( ( $0.y - cy ) * ( $0.y - cy ) ) ).squareRoot(), w: $0.w )
        }
        .sorted { $0.r < $1.r }

        let half       = flux / 2
        let cumulative = radial.reduce( into: [ Double ]() ) { $0.append( ( $0.last ?? 0 ) + $1.w ) }

        guard let crossing = cumulative.firstIndex( where: { $0 >= half } )
        else
        {
            return radial.last?.r ?? 0
        }

        // Interpolate within the crossing bin between the previous radius (where
        // the cumulative flux was `previousCumulative`) and this one.
        let previousRadius     = crossing > 0 ? radial[ crossing - 1 ].r : 0
        let previousCumulative = crossing > 0 ? cumulative[ crossing - 1 ] : 0
        let weight             = radial[ crossing ].w
        let fraction           = weight > 0 ? ( half - previousCumulative ) / weight : 0

        return previousRadius + ( fraction * ( radial[ crossing ].r - previousRadius ) )
    }
}
