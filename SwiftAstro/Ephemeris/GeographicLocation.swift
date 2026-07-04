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

/// An observer's location on Earth, in decimal degrees.
///
/// The low-precision ephemeris ignores elevation (its effect on rise/set times
/// and altitude is far below the method's accuracy), so only latitude and
/// longitude are carried here.
public struct GeographicLocation: Sendable, Equatable
{
    /// The latitude, in decimal degrees (positive north).
    public let latitude: Double

    /// The longitude, in decimal degrees (positive east).
    public let longitude: Double

    /// Creates a location.
    ///
    /// - Parameters:
    ///   - latitude:  The latitude, in decimal degrees (positive north).
    ///   - longitude: The longitude, in decimal degrees (positive east).
    public init( latitude: Double, longitude: Double )
    {
        self.latitude  = latitude
        self.longitude = longitude
    }
}
