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

/// The one way to get from an opened image container to a detection image, and
/// to everything that can change that image's bytes along the way.
///
/// Every supported format — FITS, XISF, camera RAW and photographic — implements
/// this same set of operations, so a caller reaches a detection image the same
/// way regardless of which format it holds. The point is not the sharing itself:
/// it is that the library's star detection and the application's star detection
/// are then provably fed the *same* bytes, rather than agreeing by coincidence.
///
/// ## What belongs here
///
/// Anything that can change the decoded sample values: container structure,
/// header interpretation, sample formats and byte order, the crop that fixes a
/// mosaic's Bayer phase, the draw that fixes a bitmap's layout. Nothing that
/// exists because a consumer happens to have a user interface: no render
/// settings, no pipeline configuration, no progress, cancellation, presentation
/// or metadata vocabulary appears in this protocol or anything it names.
///
/// ## Uniform answers, not missing members
///
/// A format that has nothing to say still says it. Camera RAW enumerates exactly
/// one frame rather than omitting ``frames(in:)``; a photographic frame answers
/// ``cfaPattern(from:)`` with `nil` rather than not having the member. An absent
/// operation would be a partial surface, and a partial surface is how a caller
/// ends up special-casing formats again.
///
/// ## Concurrency
///
/// ``Properties`` is `Sendable`, as are the `Data` and `PixelBuffer` results, so
/// everything a decode *produces* can cross an isolation boundary. ``Container``
/// and ``Frame`` deliberately are not required to be: three of the four formats
/// hand back reference types that own parser or library state (`XISFImage`,
/// `RAWFile`, `CGImageSource`), and requiring `Sendable` would force
/// ``frames(in:)`` to eagerly crop, draw or decompress every frame just to
/// produce a value that could be sent. Enumerate frames cheaply, decode inside
/// one isolation domain, and send the results.
public protocol ImageDecoding
{
    /// The opened file the frames are enumerated from. The consumer parses it —
    /// container parsing is not part of the decode.
    associatedtype Container

    /// An opaque handle to one image within a ``Container``, carrying whatever
    /// that format needs to come back for the frame's bytes.
    associatedtype Frame

    /// The `Sendable` description of a frame's pixel layout — everything needed
    /// to interpret its bytes, and nothing else.
    associatedtype Properties: Sendable

    /// Enumerates the images the container holds, in display order.
    ///
    /// A format holding exactly one image answers with exactly one element. This
    /// is where a format's notion of "how many images is this really" lives — a
    /// FITS cube's planes are separate frames, an XISF file's images are separate
    /// frames, a multi-frame photographic container's indices are separate frames.
    ///
    /// - Parameter container: The opened container.
    /// - Returns: One frame per image, in display order.
    /// - Throws: ``Error`` when the container holds no decodable image, or its
    ///   structure cannot be read.
    static func frames( in container: Container ) throws -> [ Frame ]

    /// A frame's canonical bytes and the layout describing them.
    ///
    /// "Canonical" means the exact bytes every later operation and every consumer
    /// reads: the FITS block padding already trimmed, the RAW sensor buffer
    /// already cropped to the visible mosaic, the photographic image already
    /// drawn into a fixed interleaved layout. Producing them here — rather than
    /// leaving each consumer to produce its own — is what makes the detection
    /// image reproducible.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The canonical bytes and their layout.
    /// - Throws: ``Error`` when the frame's bytes cannot be produced.
    static func contents( of frame: Frame ) throws -> ( bytes: Data, properties: Properties )

    /// Decodes the bytes into linear samples — the stored values with the
    /// format's affine scaling applied, undemosaiced and unstretched.
    ///
    /// This is the domain the detection image is built in and the domain a
    /// consumer renders from, so both see the same numbers.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's canonical bytes.
    ///   - properties: The frame's layout.
    /// - Returns: The geometry and linear samples, or `nil` for an unsupported
    ///   sample format, an invalid geometry, or truncated bytes.
    static func linearImage( bytes: Data, properties: Properties ) -> ( width: Int, height: Int, samples: [ Double ] )?

    /// Decodes the bytes into one raw, unscaled sample array per channel.
    ///
    /// A single-channel frame — a monochrome image, or a colour-filter-array
    /// mosaic, which is one channel until it is demosaiced — answers with exactly
    /// one plane.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's canonical bytes.
    ///   - properties: The frame's layout.
    /// - Returns: One plane per channel, each `width × height` samples.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    static func planeSamples( bytes: Data, properties: Properties ) throws -> [ [ Double ] ]

    /// Combines decoded planes into a single linear luminance channel, with the
    /// format's affine scaling applied.
    ///
    /// The channels are combined with an **equal-weight mean** rather than a
    /// perceptual luminance, so red- and blue-dominant stars are not suppressed
    /// relative to green ones.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes, as returned by ``planeSamples(bytes:properties:)``.
    ///   - properties: The frame's layout.
    /// - Returns: The geometry and luminance samples, or `nil` when the planes do
    ///   not match the layout.
    static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: Properties ) -> ( width: Int, height: Int, samples: [ Double ] )?

    /// The affine transform taking a stored sample to its physical value.
    ///
    /// FITS reads it from `BSCALE` / `BZERO`; a format that stores physical values
    /// directly answers with the identity `(scale: 1, offset: 0)`.
    ///
    /// - Parameter properties: The frame's layout.
    /// - Returns: The multiplicative `scale` and additive `offset`.
    static func scaling( from properties: Properties ) -> ( scale: Double, offset: Double )

    /// The span of the sample format — the value a full-scale sample maps to,
    /// used to express a read-out as a `0...1` fraction and to bring samples into
    /// the native full-scale domain.
    ///
    /// This is the format's span applied *after* ``scaling(from:)``, which is why
    /// an integer format's answer is `2ⁿ − 1` even where the stored samples are
    /// signed: FITS has no unsigned 16- or 32-bit `BITPIX`, so unsigned data is
    /// stored signed with a compensating `BZERO`, putting the scaled range back at
    /// `0...2ⁿ − 1`.
    ///
    /// - Parameter properties: The frame's layout.
    /// - Returns: The full-scale value, or `nil` for a floating-point format,
    ///   which has no fixed span.
    static func fullScale( from properties: Properties ) -> Double?

    /// The sample format label for the frame's bytes.
    ///
    /// - Parameter properties: The frame's layout.
    /// - Returns: The sample format, or `nil` when the layout does not describe a
    ///   supported one.
    static func bitsPerPixel( from properties: Properties ) -> BitsPerPixel?

    /// The frame's colour-filter-array pattern, when it is a raw mosaic.
    ///
    /// All mosaic formats route through the one shared ``ColorFilterArray``
    /// mapping, so they accept identical patterns and reject identical ones. A
    /// format that never carries a colour-filter array answers `nil`.
    ///
    /// - Parameter properties: The frame's layout.
    /// - Returns: The pattern, or `nil` when the frame is not a mosaic.
    /// - Throws: ``Error`` when the layout names a pattern that is not a
    ///   supported 2 × 2 Bayer arrangement — never silently treated as "no
    ///   pattern", which would feed a raw mosaic to a detector as though it were
    ///   a monochrome frame.
    static func cfaPattern( from properties: Properties ) throws -> Processors.Debayer.Pattern?

    /// The frame's pixel dimensions.
    ///
    /// - Parameter properties: The frame's layout.
    /// - Returns: The width and height, or `nil` when either is missing or not
    ///   positive.
    static func dimensions( from properties: Properties ) -> ( width: Int, height: Int )?

    /// The number of meaningful channels the frame holds: `1` for a monochrome
    /// image or a colour-filter-array mosaic, `3` for colour.
    ///
    /// This is where "is this frame colour" lives for every format. A FITS
    /// three-plane colour cube answers `3` here; how many *images* a cube holds is
    /// ``frames(in:)``'s question, not this one.
    ///
    /// - Parameter properties: The frame's layout.
    /// - Returns: The channel count.
    static func channelCount( from properties: Properties ) -> Int

    /// Decodes the single sample stored at a byte index.
    ///
    /// Bounds-checked rather than trapping, so a consumer reading out a pixel
    /// under the cursor cannot crash on a truncated frame.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's canonical bytes.
    ///   - index:      The sample's index into `bytes`, in `bytes`' own index
    ///                 space (a `Data` slice may not start at zero).
    ///   - properties: The frame's layout.
    /// - Returns: The stored value, before ``scaling(from:)`` is applied, or `nil`
    ///   when a whole sample does not fit at that index.
    static func decodeSample( bytes: Data, at index: Data.Index, properties: Properties ) -> Double?

    /// The byte indices of the samples covering an image coordinate — one per
    /// channel, in channel order.
    ///
    /// Paired with ``decodeSample(bytes:at:properties:)`` this is the whole
    /// per-pixel read-out: the offset arithmetic is format vocabulary and lives
    /// here, while whatever a consumer *displays* for that sample does not.
    /// Coordinates use a top-left origin.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column, left to right.
    ///   - y:          The zero-based row, top to bottom.
    ///   - properties: The frame's layout.
    /// - Returns: One index per channel, or `nil` for an invalid geometry or
    ///   out-of-bounds coordinates.
    static func sampleByteOffsets( x: Int, y: Int, properties: Properties ) -> [ Data.Index ]?

    /// Builds the detection image from bytes a consumer already holds.
    ///
    /// The detection image is the single-channel linear image star detection and
    /// the sky-background measurement run on: a colour frame is combined to
    /// luminance, and a colour-filter-array mosaic is demosaiced to luminance
    /// (feeding a raw mosaic to a detector injects the Bayer grid as false
    /// structure). Best-effort by design — a consumer that cannot build one skips
    /// detection rather than failing to open the image.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's canonical bytes.
    ///   - properties: The frame's layout.
    /// - Returns: The detection image, or `nil` when it cannot be built.
    static func detectionImage( bytes: Data, properties: Properties ) -> PixelBuffer?

    /// Builds the detection image for a frame, end to end.
    ///
    /// The convenience a caller holding only a container reaches for, and the one
    /// that makes "can I get a detection image without knowing the format" true.
    /// Unlike ``detectionImage(bytes:properties:)`` this reports why it failed
    /// rather than answering `nil`.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when the frame's bytes cannot be produced or no
    ///   detection image can be built from them.
    static func detectionImage( of frame: Frame ) throws -> PixelBuffer
}

internal extension ImageDecoding
{
    /// The error an operation throws while its format's decoder body has not yet
    /// landed, naming the format and the operation so a partially-migrated build
    /// says which piece is missing.
    ///
    /// - Parameter operation: The operation's name.
    /// - Returns: The error to throw.
    static func unimplemented( _ operation: String ) -> Error
    {
        Error( message: "\( Self.self ).\( operation ) is not implemented yet" )
    }
}
