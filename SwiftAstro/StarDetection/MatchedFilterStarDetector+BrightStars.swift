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
import SwiftPixel

/// The augmenting bright / large-star pass.
///
/// A zero-sum matched filter cannot see a bright star's saturated, flat-topped
/// core — a flat region convolves to zero — and its size band drops stars far
/// larger than the auto-estimated scale. On a frame dominated by small stars,
/// which tune that scale small, the large, bright stars a human notices first are
/// therefore missed. This pass recovers them directly from the raw image: it
/// thresholds high, grows the bright connected blobs, keeps those that are
/// star-shaped (a bounded, round footprint rather than sprawling nebulosity), and
/// appends any the matched filter did not already find.
///
/// It is deliberately purity-oriented, like the matched-filter pass: it only adds
/// large, bright, round blobs, so it augments the detections without inventing
/// stars from nebulosity or disturbing the faint-star path.
extension MatchedFilterStarDetector
{
    /// Detects the bright, large stars the matched-filter pass misses, deduplicated
    /// against the stars it already found.
    ///
    /// - Parameters:
    ///   - image:         The single-channel linear image.
    ///   - background:    The frame's background map, supplying the local level and
    ///                    noise the bright threshold stands on.
    ///   - fwhm:          The matched-filter FWHM, setting the blob size band.
    ///   - minSeparation: The minimum separation, in pixels, below which a bright
    ///                    candidate is treated as the same source as an existing
    ///                    detection.
    ///   - existing:      The stars the matched filter already found.
    /// - Returns: The additional bright stars to append.
    func brightStars( in image: PixelBuffer, background: LocalBackground, fwhm: Double, minSeparation: Double, excluding existing: [ Star ] ) -> [ Star ]
    {
        guard background.noises.contains( where: { $0 > 0 } )
        else
        {
            return []
        }

        let minRadius = self.configuration.brightStarMinRadiusFactor * fwhm
        let maxRadius = self.configuration.brightStarMaxRadiusFactor * fwhm
        let minArea   = Double.pi * minRadius * minRadius
        let maxArea   = Double.pi * maxRadius * maxRadius

        // Grow the blobs above the *local* level. Against a single global level a
        // flat patch of bright nebulosity clears the threshold everywhere at once,
        // and the noise riding on it fragments that patch into round, PSF-sized
        // blobs that pass every remaining purity cut — the nebulosity false
        // positives this pass is otherwise prone to. Measured against the local
        // level, the same gas is background and only what genuinely stands above its
        // own surroundings survives to be measured.
        let candidates = Self.brightComponents( in: image, maxSamples: Int( maxArea.rounded( .up ) ) )
        {
            background.threshold( atX: Double( $0 % image.width ), y: Double( $0 / image.width ), sigmas: self.configuration.brightStarThresholdSigma )
        }
        .compactMap
        {
            self.measureBright( component: $0, in: image, background: background, fwhm: fwhm, minArea: minArea )
        }

        return self.merge( candidates, into: existing, minSeparation: minSeparation )
    }

    /// Measures a bright blob and applies the star-shape purity cuts.
    ///
    /// The blob is measured with the same ``StarMoments`` used everywhere else, but
    /// over a circular aperture (which includes sky pixels), whereas the
    /// matched-filter path measures over the connected footprint above `bg + 3σ` —
    /// so its `flux`, `fwhm` and `hfr` share the same definitions but sit on a
    /// broadly similar, not identical, basis. Its `flux` is the aperture's
    /// background-subtracted sum (a lower bound), as for a fit-failed matched-filter
    /// star.
    ///
    /// - Returns: The measured star, or `nil` if the blob is too small, saturated
    ///   (when ``Configuration/saturationLevel`` is set), too elongated, or clipped
    ///   by the edge.
    private func measureBright( component: [ ( x: Double, y: Double, value: Double ) ], in image: PixelBuffer, background: LocalBackground, fwhm: Double, minArea: Double ) -> Star?
    {
        // Detection: decide star-or-not from the detection footprint against the
        // background map, read at the blob's own centre. Size and position are gated
        // here on the detection footprint; the roundness cut, however, is applied
        // after refinement to the refined eccentricity that is actually reported
        // (CR-5), so the emitted star can never be less round than its own limit.
        guard component.isEmpty == false
        else
        {
            return nil
        }

        let centreX = component.reduce( 0.0 ) { $0 + $1.x } / Double( component.count )
        let centreY = component.reduce( 0.0 ) { $0 + $1.y } / Double( component.count )
        let level   = background.level( atX: centreX, y: centreY )
        let noise   = background.noise( atX: centreX, y: centreY )

        guard Double( component.count ) >= minArea,
              let peak = component.map( { $0.value } ).max(),
              let base = StarMoments( samples: component, background: level )
        else
        {
            return nil
        }

        // Honour `saturationLevel` here too (CR-6). The bright pass exists to
        // recover a bright star's saturated, flat-topped core, so without this gate
        // it silently re-added exactly the saturated stars the matched-filter pass
        // drops — defeating the setting unless the caller also disabled the pass.
        // With it set, a blob whose peak sample is at or above the level is dropped
        // as saturated / bloomed, consistently across both detection paths.
        if let saturation = self.configuration.saturationLevel, peak >= saturation
        {
            return nil
        }

        let margin = self.configuration.edgeMargin

        guard base.x >= Double( margin ), base.y >= Double( margin ),
              base.x < Double( image.width - margin ), base.y < Double( image.height - margin )
        else
        {
            return nil
        }

        // Measure the star in an aperture centred on it, with the sky estimated
        // from a surrounding annulus — standard aperture photometry, keyed to the
        // PSF scale. The annulus sits *outside* the star, so it reads the true sky:
        // for a star on nebulosity that is the nebula pedestal (which would
        // otherwise inflate the size); for a saturated star it is real sky beyond
        // the flat core (which a centred window median would mistake for the core).
        let aperture = Swift.min( 40.0, Swift.max( 8.0, ( fwhm * 3.5 ).rounded() ) )
        let skyOuter = Swift.min( 60.0, aperture + Swift.max( 4.0, ( fwhm * 2.0 ).rounded() ) )
        let index    = ( Int( base.y ) * image.width ) + Int( base.x )
        let field    = MatchedFilterStarDetector.window( around: index, radius: Int( skyOuter ), in: image )

        let coreSamples = field.filter { Foundation.hypot( $0.x - base.x, $0.y - base.y ) <= aperture }
        let skySamples  = field.filter
        { let d = Foundation.hypot( $0.x - base.x, $0.y - base.y )
            return d > aperture && d <= skyOuter
        }
        let local       = PixelUtilities.median( skySamples.map { $0.value } ) ?? level

        // Optional local-contrast cut (disabled by default): reject a blob whose
        // peak does not stand above its local background — a knot of bright
        // nebulosity rather than a star. Off by default because in a cluster
        // embedded in nebulosity the real stars sit on bright nebulosity too.
        guard ( peak - local ) >= ( self.configuration.brightStarLocalContrastSigma * noise )
        else
        {
            return nil
        }

        // Size against the sky-annulus background so a nebula pedestal beneath the
        // star is not counted as its flux. Fall back to the mapped background level
        // if the annulus leaves no positive flux to measure, so a star on bright
        // nebulosity is re-sized, never dropped.
        let refined:           StarMoments
        let refinedBackground: Double

        if let localMoments = StarMoments( samples: coreSamples, background: local )
        {
            refined           = localMoments
            refinedBackground = local
        }
        else if let mappedMoments = StarMoments( samples: coreSamples, background: level )
        {
            refined           = mappedMoments
            refinedBackground = level
        }
        else
        {
            refined           = base
            refinedBackground = level
        }

        let hfr = StarMoments.halfFluxRadius( samples: coreSamples, background: refinedBackground, aroundX: refined.x, y: refined.y, withinRadius: StarMoments.hfrApertureRadiusFactor * refined.fwhm )

        // Count the distinct stellar peaks the blob is built from. A genuine star —
        // however large or bright — is a single peak; a blended pair or a crowded
        // cluster core (a globular, say) is several, measured together as one broad
        // source with inflated metrics. This discriminates on structure, not size, so
        // a genuinely large single star is kept however broad it is, while a
        // multi-star clump measured as one giant spurious "star" is dropped.
        //
        // The peaks are counted against the *mapped sky*, not the sky annulus that
        // sets the photometry. The two answer different questions, and conflating
        // them blinds this cut exactly where it is needed most: for a blob inside a
        // nebula core the annulus is itself on bright gas, so it lands the counting
        // level just under the saturation ceiling and no peak can be seen at all —
        // a cluster core then reports as one giant star. The annulus remains right
        // for photometry, where the gas pedestal genuinely is this source's
        // background; "how many stars are in here?" is asked relative to sky.
        let peakLevel = level + ( self.configuration.brightStarThresholdSigma * noise )
        let peaks     = MatchedFilterStarDetector.peakCount( around: refined.x, y: refined.y, radius: aperture, above: peakLevel, in: image )

        // Reject a degenerate or non-round measurement, or a multi-peak blend. A
        // near-flux-less patch of bright nebulosity can collapse the flux-weighted
        // moments to zero width and throw the centroid — and so the half-flux radius
        // — far outside the aperture, producing a spurious giant "star"; a real star
        // has a positive width and a radius no larger than the aperture it was
        // measured in. The roundness cut is applied here, on the refined eccentricity
        // that is reported, so the emitted star honours the stated purity contract
        // (CR-5).
        guard refined.fwhm > 0, hfr.isFinite, hfr > 0, hfr <= aperture,
              refined.eccentricity <= self.configuration.roundnessLimit,
              peaks <= self.configuration.brightStarMaxPeaks
        else
        {
            return nil
        }

        return Star( x: refined.x, y: refined.y, flux: refined.flux, hfr: hfr, fwhm: refined.fwhm, eccentricity: refined.eccentricity )
    }

    /// Appends the bright candidates that do not coincide with an existing
    /// detection or a brighter candidate already kept — brighter wins — so the
    /// pass never duplicates a star the matched filter already found.
    private func merge( _ candidates: [ Star ], into existing: [ Star ], minSeparation: Double ) -> [ Star ]
    {
        let minSepSquared = minSeparation * minSeparation
        var kept          = [ Star ]()

        candidates.sorted { $0.flux > $1.flux }.forEach
        {
            candidate in

            let collides = ( existing + kept ).contains
            {
                let dx = $0.x - candidate.x
                let dy = $0.y - candidate.y

                return ( ( dx * dx ) + ( dy * dy ) ) < minSepSquared
            }

            guard collides == false
            else
            {
                return
            }

            kept.append( candidate )
        }

        return kept
    }

    /// Finds the connected components (8-connectivity) of the pixels above `level`.
    ///
    /// A component that grows past `maxSamples` is a sprawling structure, not a
    /// star; it is fully flood-filled so its pixels are not rescanned, but its
    /// samples are not collected and it is dropped, bounding the work and memory a
    /// large nebulosity costs.
    ///
    /// - Parameters:
    ///   - image:      The single-channel image.
    ///   - maxSamples: The largest component, in pixels, to collect; larger ones
    ///                 are discarded.
    ///   - level:      The value a pixel at a given index must exceed to belong to a
    ///                 component — position-dependent, so the threshold follows the
    ///                 local background rather than one global level.
    /// - Returns: The collected components, each a list of samples.
    private static func brightComponents( in image: PixelBuffer, maxSamples: Int, level: ( Int ) -> Double ) -> [ [ ( x: Double, y: Double, value: Double ) ] ]
    {
        let width   = image.width
        let height  = image.height
        var visited = [ Bool ]( repeating: false, count: image.pixels.count )
        var result  = [ [ ( x: Double, y: Double, value: Double ) ] ]()

        image.pixels.indices.forEach
        {
            start in

            guard visited[ start ] == false, image.pixels[ start ] > level( start )
            else
            {
                return
            }

            var stack     = [ start ]
            var samples   = [ ( x: Double, y: Double, value: Double ) ]()
            var oversized = false

            while let current = stack.popLast()
            {
                guard visited[ current ] == false, image.pixels[ current ] > level( current )
                else
                {
                    continue
                }

                visited[ current ] = true

                let x = current % width
                let y = current / width

                if oversized == false
                {
                    samples.append( ( x: Double( x ), y: Double( y ), value: image.pixels[ current ] ) )

                    if samples.count > maxSamples
                    {
                        oversized = true
                        samples   = []
                    }
                }

                Self.neighborOffsets.forEach
                {
                    let nx = x + $0.0
                    let ny = y + $0.1

                    guard nx >= 0, nx < width, ny >= 0, ny < height
                    else
                    {
                        return
                    }

                    stack.append( ( ny * width ) + nx )
                }
            }

            if oversized == false, samples.isEmpty == false
            {
                result.append( samples )
            }
        }

        return result
    }

    /// Counts the distinct stellar peaks within `radius` of a centre: the strict
    /// 8-connectivity local maxima whose value exceeds `level`.
    ///
    /// This tells a single star (one peak) from a blended pair or a crowded cluster
    /// core (several). A saturated star's flat-topped core has no *strict* maximum
    /// and so contributes no peak, which is correct here — it is still a single
    /// source; only genuinely separate peaks are counted.
    ///
    /// - Parameters:
    ///   - cx:     The centre column to search around.
    ///   - cy:     The centre row to search around.
    ///   - radius: The search radius, in pixels.
    ///   - level:  The value a pixel must exceed to be a candidate peak.
    ///   - image:  The single-channel image.
    /// - Returns: The number of strict local maxima above `level` within the radius.
    static func peakCount( around cx: Double, y cy: Double, radius: Double, above level: Double, in image: PixelBuffer ) -> Int
    {
        let width         = image.width
        let height        = image.height
        let px            = Int( cx.rounded() )
        let py            = Int( cy.rounded() )
        let r             = Int( radius.rounded() )
        let radiusSquared = radius * radius

        let offsets = ( -r ... r ).flatMap { dy in ( -r ... r ).map { dx in ( dx: dx, dy: dy ) } }

        return offsets.filter
        {
            let x = px + $0.dx
            let y = py + $0.dy

            guard x >= 1, y >= 1, x < width - 1, y < height - 1,
                  Double( ( $0.dx * $0.dx ) + ( $0.dy * $0.dy ) ) <= radiusSquared
            else
            {
                return false
            }

            let value = image.pixels[ ( y * width ) + x ]

            guard value > level
            else
            {
                return false
            }

            return MatchedFilterStarDetector.neighborOffsets.allSatisfy { image.pixels[ ( ( y + $0.1 ) * width ) + ( x + $0.0 ) ] < value }
        }
        .count
    }
}
