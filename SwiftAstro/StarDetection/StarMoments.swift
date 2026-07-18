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
/// This is the shared measurement math: a flux-weighted centroid, the second
/// moments and the FWHM / eccentricity derived from them, plus a static half-flux
/// radius (HFD/2) measurement. It is robust to noise and hot pixels without the
/// cost of full PSF fitting.
///
/// The matched-filter detector reuses it to seed its Gaussian-fit initial guess
/// (centroid and scale from the second moments) and to size the detection scale
/// from the geometric-mean FWHM. The half-flux radius a detected ``Star`` reports
/// is measured separately — about the fit centre, over a bounded aperture — with
/// the static ``halfFluxRadius(samples:background:aroundX:y:withinRadius:)``.
public struct StarMoments: Sendable
{
    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ, where σ is the geometric mean
    /// √(σ_major·σ_minor) of the principal-axis widths.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// The radius, in units of the source's FWHM, of the circular aperture over
    /// which the half-flux radius is measured — the analogue of NINA's `Radius × 1.2`.
    /// Bounding the integration (≈ 3σ) stops a neighbouring star or a noisy sky
    /// pedestal in a wide measurement window from dragging the flux-weighted mean
    /// outward, while staying wide enough to capture a clean stellar profile.
    public static let hfrApertureRadiusFactor = 1.3

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

    /// The full width at half maximum, in pixels, from the geometric-mean axis
    /// width √(σ_major·σ_minor) of the second-moment ellipse.
    public let fwhm: Double

    /// The shape eccentricity: `0` for a round source, approaching `1` as it
    /// elongates.
    public let eccentricity: Double

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

        let mxx       = moments.xx / flux
        let myy       = moments.yy / flux
        let mxy       = moments.xy / flux
        let principal = Self.principalMoments( mxx: mxx, myy: myy, mxy: mxy )

        self.x            = cx
        self.y            = cy
        self.flux         = flux
        self.mxx          = mxx
        self.myy          = myy
        self.mxy          = mxy
        self.fwhm         = Self.fwhmPerSigma * Self.geometricMeanSigma( principal )
        self.eccentricity = Self.eccentricity( principal )
    }

    /// The principal second moments of the moment ellipse: the eigenvalues
    /// `major ≥ minor` of `[[Mxx, Mxy], [Mxy, Myy]]` (each `≈ σ²` for a Gaussian).
    ///
    /// - Parameters:
    ///   - mxx: The second moment about the x axis.
    ///   - myy: The second moment about the y axis.
    ///   - mxy: The mixed second moment.
    /// - Returns: The larger and smaller eigenvalues.
    private static func principalMoments( mxx: Double, myy: Double, mxy: Double ) -> ( major: Double, minor: Double )
    {
        let mean         = ( mxx + myy ) / 2
        let difference   = ( mxx - myy ) / 2
        let discriminant = ( ( difference * difference ) + ( mxy * mxy ) ).squareRoot()

        return ( major: mean + discriminant, minor: mean - discriminant )
    }

    /// The geometric-mean axis width `√(σ_major · σ_minor)` of the moment ellipse —
    /// the single "equivalent circular" σ the FWHM is built from, matching the
    /// Gaussian-fit path so both report the same convention. A non-positive-definite
    /// ellipse (a `minor ≤ 0` from noise or below-background samples) collapses to
    /// `0`.
    ///
    /// - Parameter principal: The principal moments (eigenvalues).
    /// - Returns: The geometric-mean standard deviation.
    private static func geometricMeanSigma( _ principal: ( major: Double, minor: Double ) ) -> Double
    {
        let sigmaMajor = Swift.max( principal.major, 0 ).squareRoot()
        let sigmaMinor = Swift.max( principal.minor, 0 ).squareRoot()

        return ( sigmaMajor * sigmaMinor ).squareRoot()
    }

    /// The eccentricity of the moment ellipse: `√(1 − minor/major)`, `0` for a
    /// round source and approaching `1` as it elongates.
    ///
    /// Clamped to `[0, 1]`: a non-positive-definite ellipse (`minor < 0`, reachable
    /// with below-background/negative sample weights) would otherwise drive the
    /// argument above `1`.
    ///
    /// - Parameter principal: The principal moments (eigenvalues).
    /// - Returns: The eccentricity in `0 ... 1`.
    private static func eccentricity( _ principal: ( major: Double, minor: Double ) ) -> Double
    {
        guard principal.major > 0
        else
        {
            return 0
        }

        return Swift.max( 0, Swift.min( 1, 1 - ( principal.minor / principal.major ) ) ).squareRoot()
    }

    /// The half-flux radius (HFD/2) of a source measured about an explicit centre —
    /// typically a Gaussian-fit centre rather than the moment centroid.
    ///
    /// - Parameters:
    ///   - samples:    The source's samples: each a pixel position and its raw
    ///                 (not background-subtracted) value.
    ///   - background: The background level subtracted to form the flux weights.
    ///   - cx:         The centre column to measure radii from.
    ///   - cy:         The centre row to measure radii from.
    ///   - aperture:   The radius, in pixels, of the circular aperture the radius is
    ///                 measured within — samples beyond it are ignored, bounding the
    ///                 flux-weighted mean (see ``hfrApertureRadiusFactor``).
    /// - Returns: The half-flux radius, in pixels.
    public static func halfFluxRadius( samples: [ ( x: Double, y: Double, value: Double ) ], background: Double, aroundX cx: Double, y cy: Double, withinRadius aperture: Double ) -> Double
    {
        let weighted = samples.map { ( x: $0.x, y: $0.y, w: $0.value - background ) }

        return self.halfFluxRadius( samples: weighted, aroundX: cx, y: cy, withinRadius: aperture )
    }

    /// The half-flux radius (HFD/2): the flux-weighted mean distance of the
    /// above-background samples from the centre — the radius acquisition software
    /// (NINA, SGP, Ekos) reports, `≈ σ√(π/2)` for a Gaussian.
    ///
    /// Only samples within `aperture` of the centre contribute, matching NINA's
    /// bounded measurement circle; samples below the background carry no flux (their
    /// weight is clamped to zero), so a noisy skirt or a neighbour outside the
    /// aperture cannot drag the radius outward. When no sample carries positive flux
    /// it falls back to `√2 ·` the outermost in-aperture radius — NINA's sentinel for
    /// an unmeasurable source.
    ///
    /// - Parameters:
    ///   - samples:  The source's background-subtracted samples.
    ///   - cx:       The centre column to measure radii from.
    ///   - cy:       The centre row to measure radii from.
    ///   - aperture: The radius, in pixels, beyond which samples are ignored.
    /// - Returns: The half-flux radius, in pixels.
    private static func halfFluxRadius( samples: [ ( x: Double, y: Double, w: Double ) ], aroundX cx: Double, y cy: Double, withinRadius aperture: Double ) -> Double
    {
        let radial = samples.compactMap
        {
            sample -> ( r: Double, w: Double )? in

            let dx = sample.x - cx
            let dy = sample.y - cy
            let r  = ( ( dx * dx ) + ( dy * dy ) ).squareRoot()

            return r <= aperture ? ( r: r, w: Swift.max( 0, sample.w ) ) : nil
        }

        let flux = radial.reduce( 0 ) { $0 + $1.w }

        guard flux > 0
        else
        {
            let outer = radial.reduce( 0 ) { Swift.max( $0, $1.r ) }

            return 2.0.squareRoot() * outer
        }

        let sumDistance = radial.reduce( 0 ) { $0 + ( $1.w * $1.r ) }

        return sumDistance / flux
    }
}
