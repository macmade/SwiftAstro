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

/// Seeds a Gaussian-fit initial guess from a moment measurement.
///
/// This is the astronomy-specific bridge between the generic ``SwiftPixel/GaussianFit``
/// fitter and the moment math in ``StarMoments``: the detector measures a source's
/// moments, builds the initial guess here, and refines it with the fit.
extension GaussianFit.Parameters
{
    /// Builds an initial guess from a moment measurement.
    ///
    /// The centre comes from the flux-weighted centroid; the axis widths and
    /// orientation come from the eigen-decomposition of the second-moment ellipse
    /// (the major axis is taken as `sigmaX`).
    ///
    /// - Parameters:
    ///   - moments:    The moment measurement of the source.
    ///   - amplitude:  The initial peak estimate above the background.
    ///   - background: The initial background estimate.
    public init( moments: StarMoments, amplitude: Double, background: Double )
    {
        let mean         = ( moments.mxx + moments.myy ) / 2
        let difference   = ( moments.mxx - moments.myy ) / 2
        let discriminant = ( ( difference * difference ) + ( moments.mxy * moments.mxy ) ).squareRoot()

        self.init(
            amplitude:  amplitude,
            x:          moments.x,
            y:          moments.y,
            sigmaX:     Swift.max( mean + discriminant, 1e-6 ).squareRoot(),
            sigmaY:     Swift.max( mean - discriminant, 1e-6 ).squareRoot(),
            theta:      0.5 * Foundation.atan2( 2 * moments.mxy, moments.mxx - moments.myy ),
            background: background
        )
    }
}
