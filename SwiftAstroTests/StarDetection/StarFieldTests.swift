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
import Testing

/// Tests for ``StarField``.
struct StarFieldTests
{
    /// Builds a star carrying the given metrics; its centroid and flux are irrelevant to these aggregate tests.
    private func star( fwhm: Double, hfr: Double, eccentricity: Double ) -> Star
    {
        Star( x: 0, y: 0, flux: 1, hfr: hfr, fwhm: fwhm, eccentricity: eccentricity )
    }

    /// An empty field reports no stars and `nil` aggregates.
    @Test
    func emptyFieldHasNoStarsOrAggregates() throws
    {
        let field = StarField( stars: [] )

        #expect( field.count              == 0 )
        #expect( field.medianFWHM         == nil )
        #expect( field.medianHFR          == nil )
        #expect( field.medianEccentricity == nil )
    }

    /// The aggregate medians use the middle value for an odd star count.
    @Test
    func medianOfOddCountIsTheMiddleValue() throws
    {
        let field = StarField( stars:
            [
                self.star( fwhm: 6, hfr: 3, eccentricity: 0.6 ),
                self.star( fwhm: 2, hfr: 1, eccentricity: 0.2 ),
                self.star( fwhm: 4, hfr: 2, eccentricity: 0.4 ),
            ]
        )

        #expect( field.count              == 3 )
        #expect( field.medianFWHM         == 4 )
        #expect( field.medianHFR          == 2 )
        #expect( field.medianEccentricity == 0.4 )
    }

    /// The aggregate medians average the two middle values for an even star count.
    @Test
    func medianOfEvenCountAveragesTheTwoMiddleValues() throws
    {
        let field = StarField( stars:
            [
                self.star( fwhm: 2, hfr: 1, eccentricity: 0.1 ),
                self.star( fwhm: 4, hfr: 2, eccentricity: 0.2 ),
                self.star( fwhm: 6, hfr: 3, eccentricity: 0.3 ),
                self.star( fwhm: 8, hfr: 4, eccentricity: 0.4 ),
            ]
        )

        #expect( field.medianFWHM == 5 )
        #expect( field.medianHFR  == 2.5 )
    }
}
