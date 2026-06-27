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
import SwiftFITS
import SwiftPixel

/// Loads a FITS file's image HDU into a single-channel, linear
/// ``SwiftPixel/PixelBuffer`` suitable for star detection.
///
/// FITS stores image samples big-endian, with optional `BZERO`/`BSCALE` linear
/// rescaling the reader must apply itself. This composes `SwiftFITS` (header
/// geometry + raw data segment) with `SwiftPixel` (`PixelUtilities.readRawPixels`
/// decoding) and applies that rescaling, yielding physical linear samples.
///
/// For one-shot-colour (Bayer CFA) frames, ``detectionImage(from:)`` additionally
/// demosaics and combines the mosaic to a single luminance channel via
/// ``BayerGrayscaleConverter`` — feeding a raw mosaic to a detector injects a
/// high-frequency checkerboard that inflates the noise estimate and fragments
/// stars.
public enum FITSImageDecoder
{
    /// Loads the file's image HDU as a single-channel, linear pixel buffer.
    ///
    /// For a one-shot-colour frame this is the raw, undebayered mosaic; use
    /// ``detectionImage(from:)`` for a detection-ready single channel.
    ///
    /// - Parameter file: The parsed FITS file.
    /// - Returns: The image HDU's linear samples as a single-channel buffer.
    /// - Throws: ``SwiftAstro/Error`` if the file has no usable 2D image HDU, or
    ///   any error raised while decoding.
    public static func linearImage( from file: FITSFile ) throws -> PixelBuffer
    {
        let hdu = try self.imageHDU( in: file )

        guard let bitpix = hdu.header.bitpix, let format = BitsPerPixel.from( value: bitpix )
        else
        {
            throw Error( message: "FITS image HDU has a missing or unsupported BITPIX" )
        }

        guard let width  = hdu.header.naxis( 1 ).map( Int.init ), width  > 0,
              let height = hdu.header.naxis( 2 ).map( Int.init ), height > 0
        else
        {
            throw Error( message: "FITS image HDU is not a 2D image with positive dimensions" )
        }

        // The data segment is padded to whole 2880-byte FITS blocks; readRawPixels
        // wants exactly the sample bytes, so trim the trailing block padding.
        let expectedBytes = format.size( numberOfPixels: width * height )
        let raw           = Data( hdu.data.prefix( expectedBytes ) )

        guard raw.count == expectedBytes
        else
        {
            throw Error( message: "FITS data segment is smaller than its geometry implies" )
        }

        let stored = try PixelUtilities.readRawPixels( data: raw, width: width, height: height, bitsPerPixel: format )
        let bzero  = self.numericValue( of: hdu.header[ "BZERO"  ]?.value ) ?? 0
        let bscale = self.numericValue( of: hdu.header[ "BSCALE" ]?.value ) ?? 1

        // readRawPixels intentionally skips BZERO/BSCALE; apply the linear
        // rescaling so the samples are physical linear values. Skip the per-sample
        // work in the common identity case.
        let pixels = ( bzero == 0 && bscale == 1 ) ? stored : stored.map { bzero + ( bscale * $0 ) }

        return try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// Loads the file's image HDU as a detection-ready single-channel image.
    ///
    /// A one-shot-colour (Bayer CFA) frame — a header carrying `BAYERPAT` — is
    /// demosaiced and combined to a single luminance channel via
    /// ``BayerGrayscaleConverter``; a monochrome frame is returned as its linear
    /// single channel.
    ///
    /// - Parameter file: The parsed FITS file.
    /// - Returns: A detection-ready single-channel pixel buffer.
    /// - Throws: ``SwiftAstro/Error`` on an unusable image HDU or an unsupported
    ///   `BAYERPAT`, or any error raised while decoding or demosaicing.
    public static func detectionImage( from file: FITSFile ) throws -> PixelBuffer
    {
        let hdu    = try self.imageHDU( in: file )
        let linear = try self.linearImage( from: file )

        guard let pattern = try self.bayerPattern( in: hdu.header )
        else
        {
            return linear
        }

        return try BayerGrayscaleConverter( pattern: pattern ).grayscale( from: linear )
    }

    /// Maps an image HDU header's `BAYERPAT` keyword to a debayer pattern.
    ///
    /// - Parameter header: The image HDU's header section.
    /// - Returns: The colour-filter-array pattern, or `nil` when the header has
    ///   no `BAYERPAT` keyword (i.e. the frame is monochrome).
    /// - Throws: ``SwiftAstro/Error`` when `BAYERPAT` holds an unsupported value.
    public static func bayerPattern( in header: FITSSection ) throws -> Processors.Debayer.Pattern?
    {
        guard let pattern = header[ "BAYERPAT" ]?.value.string
        else
        {
            return nil
        }

        switch pattern
        {
            case "BGGR": return .bggr
            case "RGBG": return .rgbg
            case "GRBG": return .grbg
            case "RGGB": return .rggb
            default:     throw Error( message: "Unsupported BAYERPAT value \( pattern )" )
        }
    }

    /// Selects the file's image HDU: the first data section paired with its
    /// preceding header section.
    ///
    /// - Parameter file: The parsed FITS file.
    /// - Returns: The image HDU's header section and raw data bytes.
    /// - Throws: ``SwiftAstro/Error`` when the file contains no image HDU.
    private static func imageHDU( in file: FITSFile ) throws -> ( header: FITSSection, data: Data )
    {
        let sections = file.sections

        guard let dataIndex = sections.firstIndex( where: { $0.kind == .data } ), dataIndex > 0
        else
        {
            throw Error( message: "FITS file contains no image HDU" )
        }

        return ( header: sections[ dataIndex - 1 ], data: sections[ dataIndex ].data )
    }

    /// Reads a numeric FITS header value as a `Double`, whether it was parsed as
    /// an integer or a float (e.g. `BZERO = 32768` vs `BSCALE = 1.0`).
    ///
    /// - Parameter value: The header value to read.
    /// - Returns: The value as a `Double`, or `nil` if it is not numeric.
    private static func numericValue( of value: FITSValue? ) -> Double?
    {
        if let integer = value?.integer
        {
            return Double( integer )
        }

        return value?.float
    }
}
