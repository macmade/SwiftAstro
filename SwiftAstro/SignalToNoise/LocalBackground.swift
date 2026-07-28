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

/// A **spatially-varying** estimate of an image's background level and noise: a
/// coarse mesh of per-tile robust statistics, bilinearly interpolated back to
/// pixel resolution.
///
/// Where ``SkyBackground`` describes a frame with one level and one noise, this
/// describes how both *change across the frame*. That distinction decides whether
/// star detection works at all on a frame carrying large-area structure —
/// nebulosity, light-pollution gradients, vignetting. A single global
/// `median + k·MAD` treats every pixel of a bright nebula as "many sigma above
/// background", so a threshold meant to isolate a handful of stars instead admits
/// tens of thousands of noise ripples riding on the gas, which then poison every
/// statistic derived from them. Measured against the *local* level and the *local*
/// noise, the same nebula is simply background, and only genuine point sources
/// stand above it.
///
/// The estimator is deliberately the same robust pair used everywhere else in the
/// library — the median and `1.4826 × MAD` — just evaluated per tile, so the
/// meaning of "background" and "noise" does not change with the estimator, only
/// its support. Non-finite (NaN / ±Inf) blanks are ignored, as they are in
/// ``SkyBackground`` and ``SignalToNoise``, because the shared
/// ``SwiftPixel/PixelUtilities`` helpers filter them.
///
/// The tile works best when it is comfortably larger than the sources being
/// measured: the per-tile median is what keeps stars out of the background
/// estimate, and that only holds while stars occupy a small minority of a tile. A
/// source approaching a tile in size — a broad, defocused star — would otherwise
/// have its own tile describe *it* rather than the sky, both raising the level and
/// inflating the noise, so the mesh is median-filtered against its neighbours
/// before use (see ``estimate(in:tileSize:)``).
///
/// Two properties of the mesh are worth knowing before relying on a value near a
/// frame edge:
///
/// - It is **uniformly spaced**. A trailing partial tile is measured over the
///   pixels it actually has, but is sampled at the position a full tile *would*
///   occupy, so the last half-tile of a frame that is not a whole number of tiles
///   wide reads a blend weighted toward its neighbour.
/// - The median filter **clamps at the mesh border**, so a corner cell appears four
///   times in its own neighbourhood and an edge cell twice. Contamination that a
///   cell's eight true neighbours would outvote in the interior can therefore
///   carry the median at a corner — the filter's rescue of an over-large source
///   holds to roughly `0.7 ×` the tile in FWHM in the interior but only `0.5 ×` at
///   a corner. For the same reason a *diagonal* background gradient (vignetting is
///   the usual one) reads about one further tile-step off at the diagonal corners,
///   on top of the uniform-spacing offset above; an axis-aligned gradient passes
///   through the filter unchanged.
///
/// The two meshes are filtered independently, so at a mesh boundary a position can
/// take its level from one tile and its noise from another.
public struct LocalBackground: Sendable, Equatable
{
    /// The default tile edge, in pixels — large enough that stars stay a small
    /// minority of every tile, small enough to follow real sky structure.
    public static let defaultTileSize = 64

    /// The tile edge, in pixels.
    public let tileSize: Int

    /// The number of tile columns in the mesh.
    public let columns: Int

    /// The number of tile rows in the mesh.
    public let rows: Int

    /// The per-tile background levels, in row-major mesh order.
    public let levels: [ Double ]

    /// The per-tile background noises (`1.4826 × MAD`), in row-major mesh order.
    public let noises: [ Double ]

    /// Creates a background map from an already-measured mesh.
    ///
    /// - Parameters:
    ///   - tileSize: The tile edge, in pixels.
    ///   - columns:  The number of tile columns.
    ///   - rows:     The number of tile rows.
    ///   - levels:   The per-tile levels, row-major, `columns * rows` entries.
    ///   - noises:   The per-tile noises, row-major, `columns * rows` entries.
    /// - Returns: The map, or `nil` when the geometry is degenerate, the mesh arrays
    ///   do not match it, or a mesh carries a non-finite value or a negative noise —
    ///   any of which would silently disable every threshold built on it, and would
    ///   make the map unequal to itself.
    public init?( tileSize: Int, columns: Int, rows: Int, levels: [ Double ], noises: [ Double ] )
    {
        // The cell count is computed with overflow reporting rather than `*`: this
        // initializer is failable precisely to reject a degenerate geometry, so an
        // adversarial one must come back `nil` instead of trapping.
        let ( cells, overflowed ) = columns.multipliedReportingOverflow( by: rows )

        guard tileSize >= 1, columns >= 1, rows >= 1, overflowed == false,
              levels.count == cells,
              noises.count == cells,
              levels.allSatisfy( \.isFinite ),
              noises.allSatisfy( { $0.isFinite && $0 >= 0 } )
        else
        {
            return nil
        }

        self.tileSize = tileSize
        self.columns  = columns
        self.rows     = rows
        self.levels   = levels
        self.noises   = noises
    }

    /// Measures the background map of an image.
    ///
    /// Each tile contributes the median and the robust `1.4826 × MAD` of its own
    /// samples. Two gaps are filled so a caller always reads a usable pair:
    ///
    /// - A tile whose samples are entirely non-finite has no median of its own and
    ///   inherits the median of the measurable tiles.
    /// - A tile with no measurable spread — a saturated or clipped patch, a
    ///   synthetic flat — inherits the median of the *positive* tile noises, so a
    ///   locally-flat patch cannot collapse a detection threshold onto its own
    ///   level. When no tile has any spread the frame is genuinely flat and the
    ///   noise stays `0`, leaving a caller's "no measurable noise" guard to fire.
    ///
    /// Both meshes are then **median-filtered against their 3×3 neighbourhood**. A
    /// source comparable to a tile — a broad, defocused star — makes its own tile
    /// measure the star rather than the sky, which raises that tile's level and can
    /// inflate its MAD by orders of magnitude; a threshold built on it then sits
    /// above the very source it was meant to find. The contaminated tiles are a
    /// small local cluster surrounded by sky, so replacing each cell with its
    /// neighbourhood median restores the sky value there while leaving genuine sky
    /// structure — which varies over many tiles, not one — intact.
    ///
    /// - Parameters:
    ///   - image:    The single-channel linear image to measure.
    ///   - tileSize: The tile edge, in pixels; values below `1` are clamped.
    /// - Returns: The map, or `nil` when the image is not single-channel, has no
    ///   pixels, or has not one finite sample.
    public static func estimate( in image: PixelBuffer, tileSize: Int = LocalBackground.defaultTileSize ) -> LocalBackground?
    {
        guard image.channels == 1, image.width > 0, image.height > 0
        else
        {
            return nil
        }

        // Bound the tile by the image before any arithmetic on it: a tile at the top
        // of `Int` would overflow the round-up below, and a tile past the image's
        // larger side already yields the single global cell it would anyway.
        let tile    = Swift.max( 1, Swift.min( tileSize, Swift.max( image.width, image.height ) ) )
        let columns = ( image.width  + tile - 1 ) / tile
        let rows    = ( image.height + tile - 1 ) / tile

        let measured = ( 0 ..< ( columns * rows ) ).map
        {
            Self.measure( tileAt: $0, columns: columns, tileSize: tile, in: image )
        }

        guard let typicalLevel = PixelUtilities.median( measured.compactMap { $0.level } )
        else
        {
            return nil
        }

        let typicalNoise = PixelUtilities.median( measured.compactMap { $0.noise }.filter { $0 > 0 } ) ?? 0

        let levels = measured.map { $0.level ?? typicalLevel }
        let noises = measured.map
        {
            let noise = $0.noise ?? 0

            return noise > 0 ? noise : typicalNoise
        }

        return LocalBackground(
            tileSize: tile,
            columns:  columns,
            rows:     rows,
            levels:   Self.medianFiltered( levels, columns: columns, rows: rows ),
            noises:   Self.medianFiltered( noises, columns: columns, rows: rows )
        )
    }

    /// Replaces every mesh cell with the median of its 3×3 neighbourhood, clamping
    /// at the mesh edges.
    ///
    /// - Parameters:
    ///   - mesh:    The per-tile values, row-major.
    ///   - columns: The number of tile columns.
    ///   - rows:    The number of tile rows.
    /// - Returns: The filtered mesh, or the mesh unchanged when it is a single cell.
    private static func medianFiltered( _ mesh: [ Double ], columns: Int, rows: Int ) -> [ Double ]
    {
        guard columns > 1 || rows > 1
        else
        {
            return mesh
        }

        return mesh.indices.map
        {
            index in

            let column = index % columns
            let row    = index / columns

            let neighbourhood = ( -1 ... 1 ).flatMap
            {
                dy in

                ( -1 ... 1 ).map
                {
                    dx -> Double in

                    let x = Swift.min( Swift.max( column + dx, 0 ), columns - 1 )
                    let y = Swift.min( Swift.max( row    + dy, 0 ), rows    - 1 )

                    return mesh[ ( y * columns ) + x ]
                }
            }

            return PixelUtilities.median( neighbourhood ) ?? mesh[ index ]
        }
    }

    /// Measures one tile's robust level and noise.
    ///
    /// - Parameters:
    ///   - index:    The tile's row-major mesh index.
    ///   - columns:  The number of tile columns.
    ///   - tileSize: The tile edge, in pixels.
    ///   - image:    The single-channel image.
    /// - Returns: The tile's level and noise, each `nil` when its samples carry no
    ///   finite value to measure.
    private static func measure( tileAt index: Int, columns: Int, tileSize: Int, in image: PixelBuffer ) -> ( level: Double?, noise: Double? )
    {
        let x0 = ( index % columns ) * tileSize
        let y0 = ( index / columns ) * tileSize
        let x1 = Swift.min( image.width,  x0 + tileSize )
        let y1 = Swift.min( image.height, y0 + tileSize )

        let samples = ( y0 ..< y1 ).flatMap
        {
            y in

            image.pixels[ ( ( y * image.width ) + x0 ) ..< ( ( y * image.width ) + x1 ) ]
        }

        guard let level = PixelUtilities.median( Array( samples ) )
        else
        {
            return ( level: nil, noise: nil )
        }

        let mad = PixelUtilities.medianAbsoluteDeviation( Array( samples ), around: level )

        return ( level: level, noise: mad.map { $0 * PixelUtilities.madStandardDeviationScale } )
    }

    /// The interpolated background level at a pixel position.
    ///
    /// - Parameters:
    ///   - x: The column, in pixels.
    ///   - y: The row, in pixels.
    /// - Returns: The background level, in the image's native linear units.
    public func level( atX x: Double, y: Double ) -> Double
    {
        self.interpolate( self.levels, at: self.weights( atX: x, y: y ) )
    }

    /// The interpolated background noise at a pixel position.
    ///
    /// - Parameters:
    ///   - x: The column, in pixels.
    ///   - y: The row, in pixels.
    /// - Returns: The robust background noise, in the image's native linear units.
    public func noise( atX x: Double, y: Double ) -> Double
    {
        self.interpolate( self.noises, at: self.weights( atX: x, y: y ) )
    }

    /// The detection level a given number of noise sigmas above the local
    /// background — the form nearly every caller wants, evaluated in one call.
    ///
    /// - Parameters:
    ///   - x:      The column, in pixels.
    ///   - y:      The row, in pixels.
    ///   - sigmas: How many noise sigmas above the local background.
    /// - Returns: The threshold, in the image's native linear units.
    public func threshold( atX x: Double, y: Double, sigmas: Double ) -> Double
    {
        // One set of interpolation weights serves both meshes. This runs per pixel
        // over a whole frame, so resolving the position twice would double the cost
        // of the detector's hottest scans for no benefit.
        let weights = self.weights( atX: x, y: y )

        return self.interpolate( self.levels, at: weights ) + ( sigmas * self.interpolate( self.noises, at: weights ) )
    }

    /// The bilinear interpolation weights for a pixel position: the mesh cell below
    /// and to the left of it, and the fractions along each axis.
    ///
    /// The position is expressed on the mesh's continuous tile-centre axis and
    /// clamped into the mesh, so a position beyond the image — or in the half-tile
    /// border before the first centre — reads its nearest tile rather than
    /// extrapolating. The clamp is applied *before* the conversion to `Int`, which
    /// would otherwise trap on a non-finite or astronomically large coordinate: an
    /// infinity clamps to the mesh edge it points at, and a `NaN` — which has no
    /// position to clamp — reads the first tile.
    ///
    /// - Parameters:
    ///   - x: The column, in pixels.
    ///   - y: The row, in pixels.
    /// - Returns: The cell coordinates and the fractional weights.
    private func weights( atX x: Double, y: Double ) -> ( ix: Int, iy: Int, dx: Double, dy: Double )
    {
        let size = Double( self.tileSize )
        let fx   = Self.meshCoordinate( x, tileSize: size, count: self.columns )
        let fy   = Self.meshCoordinate( y, tileSize: size, count: self.rows )
        let ix   = Int( Foundation.floor( fx ) )
        let iy   = Int( Foundation.floor( fy ) )

        return ( ix: ix, iy: iy, dx: fx - Double( ix ), dy: fy - Double( iy ) )
    }

    /// Maps a pixel coordinate onto the mesh's continuous tile-centre axis, bounded
    /// to `-1 ... count` so the surrounding cell indices stay representable and the
    /// cell clamp then resolves them to real cells.
    ///
    /// - Parameters:
    ///   - value:    The pixel coordinate.
    ///   - tileSize: The tile edge, in pixels.
    ///   - count:    The number of cells along this axis.
    /// - Returns: The bounded mesh coordinate; `0` for a `NaN` input.
    private static func meshCoordinate( _ value: Double, tileSize: Double, count: Int ) -> Double
    {
        guard value.isNaN == false
        else
        {
            return 0
        }

        return Swift.min( Swift.max( ( value - ( tileSize / 2 ) ) / tileSize, -1 ), Double( count ) )
    }

    /// Bilinearly interpolates a mesh from a set of weights.
    ///
    /// - Parameters:
    ///   - mesh:    The per-tile values, row-major.
    ///   - weights: The cell coordinates and fractional weights.
    /// - Returns: The interpolated value.
    private func interpolate( _ mesh: [ Double ], at weights: ( ix: Int, iy: Int, dx: Double, dy: Double ) ) -> Double
    {
        let top    = ( self.value( mesh, weights.ix, weights.iy )     * ( 1 - weights.dx ) ) + ( self.value( mesh, weights.ix + 1, weights.iy )     * weights.dx )
        let bottom = ( self.value( mesh, weights.ix, weights.iy + 1 ) * ( 1 - weights.dx ) ) + ( self.value( mesh, weights.ix + 1, weights.iy + 1 ) * weights.dx )

        return ( top * ( 1 - weights.dy ) ) + ( bottom * weights.dy )
    }

    /// Reads a mesh cell, clamping the coordinates into the mesh.
    ///
    /// - Parameters:
    ///   - mesh: The per-tile values, row-major.
    ///   - tx:   The tile column.
    ///   - ty:   The tile row.
    /// - Returns: The clamped cell's value.
    private func value( _ mesh: [ Double ], _ tx: Int, _ ty: Int ) -> Double
    {
        let column = Swift.min( Swift.max( tx, 0 ), self.columns - 1 )
        let row    = Swift.min( Swift.max( ty, 0 ), self.rows    - 1 )

        return mesh[ ( row * self.columns ) + column ]
    }
}
