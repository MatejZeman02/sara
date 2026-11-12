## What the `graph.gmacs` kernels read: the layout of their buffer of counts,
## the numbers they know each graph by, and the push constant every pass
## pushes, packed in one place.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In core rather than beside the Graph docker's plot, because two callers pack
## it: `SaGraphPlot` for the scopes it draws, and `SaNodeHistogram` for the
## counts an attached Levels equalizes from, which a module asks of the door
## and which must be the plot's counts bin for bin. Packing it twice would let
## the two drift, and a module could not reach it under `ui`. Every constant
## here mirrors one in the kernel, and changing one here alone means nothing.
class_name SaGraphParams
extends RefCounted

## The kernel's numbers for the six graphs, `MODE_*` in `graph.gmacs`. The
## plot's `MODES` gives each its id and title, in the order a painter reads.
const MODE_HISTOGRAM := 0
const MODE_PARADE := 1
const MODE_VECTORSCOPE := 2
const MODE_WAVEFORM := 3
const MODE_CLOUD := 4
const MODE_WAVEFORM_WHITE := 5

## Value bins, and columns along the fixed bin grid.
const BINS := 256
const COLUMNS := 256

## One plane of the buffer. Four of them: three are the parade's channels,
## which the waveform reads a second way, and the fourth is the cloud's, which
## uses one for its counts and three for the colour sums it averages back. The
## histogram's four rows sit in the first plane's spare room.
const PLANE := COLUMNS * BINS
const COUNT_SIZE := 4 * PLANE
const MAX_SLOT := COUNT_SIZE

## The gamut wireframe's vertices, at the end of the buffer. Twelve edges of the
## document's RGB cube at eight segments each, five floats a vertex: the
## projected point and the colour it stands for. `graph.gmacs` says why they are
## computed once a pass rather than per pixel.
const FRAME_EDGES := 12
const FRAME_SEGMENTS := 8
const FRAME_VERTICES := FRAME_EDGES * (FRAME_SEGMENTS + 1)
const FRAME_STRIDE := 5
const FRAME_SLOT := MAX_SLOT + 64
const BUFFER_SIZE := FRAME_SLOT + FRAME_VERTICES * FRAME_STRIDE

## Where the live grid starts, mirroring `LIVE_SLOT` in the kernel: after
## everything of a fixed size. A histogram has no live grid, so its buffer ends
## here.
const LIVE_SLOT := BUFFER_SIZE

## The bits of the flags word. The stored triple is already what a screen
## wants, the count axis is linear, and the waveform and the parade bin into the
## fixed grid, mirroring `FLAG_PASSTHROUGH`, `FLAG_LINEAR` and
## `FLAG_FIXED_GRID`.
const FLAG_PASSTHROUGH := 1
const FLAG_LINEAR := 2
const FLAG_FIXED_GRID := 64

## Which rows of the histogram are drawn, the kernel's `FLAG_ROW_*` in the same
## flags word. Master is the luma row, and Lightness is the same row counted as
## Oklab L, so the two are two graphs rather than one drawn twice.
const ROW_FLAGS := {
    "master": 32,
    "red": 4,
    "green": 8,
    "blue": 16,
    "lightness": 32 | 128,
}

## The histogram's bars, mirroring `BAR_SHIFT` and `BAR_MASK`
## in `graph_histogram.gmacs`: how many bins either side of its own a bin's
## bar spreads over, in four bits above every flag. Nought is the Graph
## docker's picture, a column a bin.
const BAR_SHIFT := 8
const BAR_MASK := 15

## Where the flags word sits in what `pack` answers, so a capture can add
## `FLAG_FIXED_GRID` to what the pass pushed.
const PARAM_FLAGS := 11

## Where the cloud is looked at from, as yaw, pitch, pan and zoom, for a pass
## that draws no cloud. Only the cloud and its wireframe read them.
const NO_CLOUD := [0.0, 0.0, Vector2.ZERO, 1.0]


## The flags word for *space*, with the linear count axis when *linear*, the
## histogram rows *channel* names, none for a word `ROW_FLAGS` does not hold,
## and bars *bar_reach* bins either side, held inside `BAR_MASK`.
static func flags(space: SaColorSpace, linear: bool, channel: String, bar_reach: int = 0) -> int:
    var packed := 0
    if space == null or space.is_display_ready():
        packed |= FLAG_PASSTHROUGH
    if linear:
        packed |= FLAG_LINEAR
    var rows: int = ROW_FLAGS.get(channel, 0)
    return packed | rows | (clampi(bar_reach, 0, BAR_MASK) << BAR_SHIFT)


## The push constant of a pass over the parallelogram of *source_size* that
## *origin*, *span_x* and *span_y* describe, in source texels, sampled
## *sample_grid* times both ways, for kernel *mode* drawn at *gain*, with the
## flags word *flag_word* and the cloud seen from *cloud*, laid out as
## `NO_CLOUD` is.
static func pack(
    source_size: Vector2i,
    origin: Vector2,
    span_x: Vector2,
    span_y: Vector2,
    sample_grid: Vector2i,
    space: SaColorSpace,
    mode: int,
    gain: float,
    flag_word: int,
    cloud: Array
) -> PackedFloat32Array:
    # What the kernel needs to turn a stored triple into the display value the
    # value modes bin and the light the round modes project. The picture's own
    # size is not here: `graph.gmacs` asks the image it writes, because the
    # block is already the 128 bytes Vulkan guarantees.
    var curve := space.transfer if space != null and space.transfer != null else SaTransferFunction.srgb()
    var yaw: float = cloud[0]
    var pitch: float = cloud[1]
    var pan: Vector2 = cloud[2]
    var zoom: float = cloud[3]
    var packed := PackedFloat32Array(
        [
            float(source_size.x),
            float(source_size.y),
            float(sample_grid.x),
            float(sample_grid.y),
            origin.x,
            origin.y,
            span_x.x,
            span_x.y,
            span_y.x,
            span_y.y,
            float(space.coordinates if space != null else SaColorSpace.Coordinates.RGB),
            float(flag_word),
            float(mode),
            gain,
            curve.slope,
            curve.threshold,
            curve.gain,
            curve.exponent,
            yaw,
            pitch,
            pan.x,
            pan.y,
            zoom
        ]
    )
    # The document's own gamut into linear sRGB, which is what makes the
    # wireframe this document's shape rather than sRGB's. Exactly the identity
    # for an sRGB-gamut document, so the common case is unchanged.
    var gamut: Basis = space.to_linear_srgb_matrix() if space != null else Basis.IDENTITY
    for column: Vector3 in SaColorSpace.basis_columns(gamut):
        packed.append(column.x)
        packed.append(column.y)
        packed.append(column.z)
    return packed


## The push constant of a pass over the whole of a square texture *edge*
## across, which is what one chunk is, at a sample per texel.
static func pack_square(
    edge: int, space: SaColorSpace, mode: int, gain: float, flag_word: int, cloud: Array
) -> PackedFloat32Array:
    var side := float(edge)
    var grid := Vector2i(edge, edge)
    return pack(grid, Vector2.ZERO, Vector2(side, 0.0), Vector2(0.0, side), grid, space, mode, gain, flag_word, cloud)
