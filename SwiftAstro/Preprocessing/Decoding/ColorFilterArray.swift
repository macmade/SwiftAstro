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

/// The one mapping from a colour-filter-array pattern name to a debayer pattern,
/// shared by every format that can carry a mosaic.
///
/// FITS names its pattern in `BAYERPAT`, XISF in the image's colour-filter-array
/// element, camera RAW derives one from the sensor at the crop origin. All three
/// route through here, so a pattern accepted for one format is accepted for every
/// format — and, more importantly, a pattern *rejected* for one is rejected for
/// every one.
public enum ColorFilterArray
{
    /// Maps a colour-filter-array pattern name to its debayer pattern.
    ///
    /// Only the four 2 × 2 Bayer arrangements are supported; anything else — a
    /// four-character name that is not one of them, an X-Trans pattern, an empty
    /// string — throws rather than returning `nil`. That distinction matters:
    /// `nil` means "this frame is monochrome", and answering it for a mosaic whose
    /// pattern simply was not recognised would feed the raw mosaic to star
    /// detection as though it were a monochrome frame, injecting the Bayer grid as
    /// false structure.
    ///
    /// - Parameter name: The pattern name (e.g. `"RGGB"`).
    /// - Returns: The matching debayer pattern.
    /// - Throws: ``Error`` when the name is not a supported pattern.
    public static func pattern( named name: String ) throws -> Processors.Debayer.Pattern
    {
        switch name
        {
            case "BGGR": return .bggr
            case "GRBG": return .grbg
            case "RGGB": return .rggb
            case "GBRG": return .gbrg
            default:     throw Error( message: "Unsupported colour-filter-array pattern \( name )" )
        }
    }
}
