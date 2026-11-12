## The GPU half of the Graph docker: the scope, without the window.
##
## `graph.gmacs` bins the composited output into a buffer of counts and draws
## that buffer into a picture. This class owns the buffer, the picture and the
## three dispatches, and answers with a `Texture2DRD` the docker shows.
## Nothing comes back to the CPU except in a test, which reads the counts to
## check that the bins landed where they should.
##
## Separate from `graph_docker.gd` because a `Window` added to the tree maps a
## real OS window and blocks the headless suite, which is a known engine trap. The scope is the part worth testing,
## so it is the part that is not a Window.
##
## In the door rather than beside the docker, because the base module's Levels
## histogram and Curves graph draw the same pass and a module sees the door
## only. It names nothing in `ui/`.
class_name SaGraphPlot
extends RefCounted

const SHADER_NAME := "graph"

## The five graphs, each as the id a scenario and a stored choice name it by,
## the title the dropdown shows, and the number `graph.gmacs` knows it as.
##
## The kernel's number is written down rather than inferred from the position,
## because this list is the order a painter reads and the kernel's is the order
## the modes were built in. Putting the waveform first would otherwise
## renumber every branch in the shader.
const MODES: Array = [
    ["waveform", "Waveform", SaGraphParams.MODE_WAVEFORM],
    ["waveform_white", "Waveform (W)", SaGraphParams.MODE_WAVEFORM_WHITE],
    ["histogram", "Histogram", SaGraphParams.MODE_HISTOGRAM],
    ["parade", "RGB Parade", SaGraphParams.MODE_PARADE],
    ["vectorscope", "Vectorscope", SaGraphParams.MODE_VECTORSCOPE],
    ["cloud", "Oklab Cloud", SaGraphParams.MODE_CLOUD],
]

## The two readings of one graph, which the docker offers as a toggle rather
## than as two rows of the dropdown. The note asked for "rgbw toggle", and a
## toggle is what a painter flicks while looking at the picture: a dropdown
## costs a click, a read and a second click to compare the two. They are still
## two entries above, because the shader reaches them by mode number and a
## scenario and a stored choice reach them by id.
const WAVEFORM_MODES := ["waveform", "waveform_white"]

## The kernel numbers of the three modes drawn as traces rather than as a
## filled shape, which is what `gain_for` brightens.
const TRACE_KERNEL_MODES := [SaGraphParams.MODE_PARADE, SaGraphParams.MODE_WAVEFORM, SaGraphParams.MODE_WAVEFORM_WHITE]

## What a docker with no stored choice opens on. First in `MODES`, so an id
## nothing recognises falls back to the same graph.
const DEFAULT_MODE := "waveform"

## Value bins, and columns along the fixed bin grid. The histogram, the
## vectorscope and the cloud bin into it, and a capture of the waveform or the
## parade bins into it a second time, because a scope has to report the same
## numbers at every docker size. What the waveform and the parade draw is the
## live grid of `live_grid`, which follows the picture instead.
##
## These and the layout below are the kernel's, written down once in
## `SaGraphParams` beside the push constant, because the door's
## `SaNodeHistogram` bins with the same kernel and must read the same buffer.
const BINS := SaGraphParams.BINS
const COLUMNS := SaGraphParams.COLUMNS

## How many texels of the picture a cloud cell is across, mirroring
## `CLOUD_CELL_TEXELS` in `shaders/compute/graph.gmacs`. The picture is asked
## for in physical pixels, so a cell is two logical pixels at UI scale 1 and one
## at scale 2, and the cloud reads as many small points at any scale.
const CLOUD_CELL_TEXELS := 2.0

## The cells a capture bins the cloud into whatever the panel measures,
## mirroring `CLOUD_FIXED_CELLS`, so the counts `read_counts` answers for the
## cloud are the 96 by 96 they always were.
const CLOUD_FIXED_CELLS := 96

## The most cells the cloud's grid has either way, the plane's own side,
## mirroring `CLOUD_MAX_CELLS`.
const CLOUD_MAX_CELLS := 256

## How far a cell's mark reaches, in cells, mirroring `CLOUD_MARK_MIN` and
## `CLOUD_MARK_SPAN` in the same kernel. The floor is what a cell holding one
## sample gets and the span is what the log of its count adds, so the largest a
## mark ever reaches is the two added.
##
## Here for the same reason `CLOUD_CELL_TEXELS` is: the dump has to be able to say
## how many texels a lone point is drawn at, a number no screenshot carries.
const CLOUD_MARK_MIN := 0.9
const CLOUD_MARK_SPAN := 2.5

## The grey every graph is drawn over, mirroring `BACKGROUND` in the same
## kernel. Here because the picture is cleared to it before the first draw, so a
## docker opening does not flash black before the scope arrives.
const BACKGROUND := 0.1

## The buffer's planes, its largest bin, the gamut wireframe after it and the
## live grid after that, as `SaGraphParams` lays them out.
const PLANE := SaGraphParams.PLANE
const COUNT_SIZE := SaGraphParams.COUNT_SIZE
const MAX_SLOT := SaGraphParams.MAX_SLOT
const FRAME_VERTICES := SaGraphParams.FRAME_VERTICES
const FRAME_STRIDE := SaGraphParams.FRAME_STRIDE
const FRAME_SLOT := SaGraphParams.FRAME_SLOT
const LIVE_SLOT := SaGraphParams.LIVE_SLOT

## Where 1.0 sits on a waveform, mirroring `VALUE_TOP`, and so how many of the
## picture's rows are levels.
const VALUE_TOP := 8.0 / 9.0

## The most samples a pass takes, both ways. A pass takes one per pixel the
## view shows, which is darktable's waveform, so its cost
## follows the screen and never the document, and no pass runs over the whole
## canvas, because what it reads is the composited view. The ceiling is the cloud's:
## its colour sums are fixed point at `CLOUD_QUANT` in the kernel, and 4096 by
## 4096 samples in one cell is the most a uint holds at that. A 4K view is
## under it on both axes.
const MAX_SAMPLES := Vector2i(4096, 4096)

## How far under one texel a pixel still counts as one, the view's own
## `SaCanvas.FILTER_EPSILON`, for the same float round trip.
const FILTER_EPSILON := 1.0e-4

## The map a pass with no view hands the kernel: every document point to the
## middle of the screen, so every sample is shown.
const EVERY_POINT_SHOWN := [0.0, 0.0, 0.0, 0.0, 0.5, 0.5]

## The picture, when nobody says otherwise: what a scope of a layer gets, and
## what the docker draws before it has been laid out.
const PLOT := Vector2i(256, 256)

## What the picture may be asked to become. The floor is a docker squeezed to
## its minimum and the ceiling is a docker pulled across a 4K screen. There is
## no step between them: a picture rounded to eight texels was stretched over a
## rect up to seven pixels off it, so no texel met a pixel of the screen, and a
## cloud of two-texel points was resampled into smudges. Dragging an
## edge now makes a texture a frame, which a pass that frame redraws anyway.
const MIN_PLOT := 64
const MAX_PLOT := 2048

## How bright a bin at the maximum is drawn, on the kernel's log scale. One is
## the scale as it stands, which already lifts a small population off the floor.
const GAIN := 1.0

## What the parade and the waveform use instead.
##
## The note of 14:07 said the parade "needs more contrast to be visible", and it
## does: `largest` is the largest bin anywhere in the pass, and on a document
## with a flat background one column of that background holds a count no stroke
## comes near, so every trace in the picture was drawn against it and came out
## nearly black. The clamp in `level_of` is what makes a gain above one safe: it
## raises everything and flattens the top rather than overflowing.
const TRACE_GAIN := 2.6

## Where the cloud is looked at from, in radians: turned three quarters round
## and tipped down, which is the angle that shows all three axes at once.
## Where the cloud is looked at from when nothing has turned it, in radians.
const CLOUD_YAW := 0.7
const CLOUD_PITCH := 0.5

## How far the pitch may go before the projection degenerates into a line and
## there is nothing left to read. The browser's gamut solid clamps at the same
## place and for the same reason.
const CLOUD_PITCH_LIMIT := 1.3

## What a zoom of one is, and how far either way it may go. A tenth is the whole
## gamut with room round it and four is one corner filling the panel.
const CLOUD_ZOOM_MIN := 0.25
const CLOUD_ZOOM_MAX := 4.0

## The count axis of the histogram and the radius of the vectorscope: `log`,
## which is darktable's default, or `linear` on the toggle. One bit of the flags
## word, beside the passthrough, because the push constant is the 128 bytes it
## declares and has no word to spare.
const SCALES: Array[String] = ["log", "linear"]
var scale: String = "log"

## Which rows of the histogram are drawn, and therefore what its count axis is
## normalised against. Empty is the Graph docker's own picture: the three
## channels overlaid at half strength, and the count axis against the largest
## bin of all four rows including the luma one nothing draws.
##
## The Levels dialog names one of these instead, because its Channel dropdown
## has to reach the graph for the graph to be about the channel the painter is
## moving.
##
## **Master is the luma row, drawn grey**, which is what Photoshop and Krita
## both show for a composite. Three channels overlaid is a scope's picture, and
## on paint where one
## channel holds still, a gradient's constant blue for instance, that channel
## piles into one bin and the linear axis scales the other two down to the
## floor. The composite has no such bin, so it is the row that reads.
##
## **Lightness is the same row counted as Oklab L**, the kernel's
## `FLAG_ROW_OKLAB_L` beside the luma bit, so Master and Lightness are two
## graphs rather than one drawn twice. The three colour rows count the same
## either way.
##
## The bits are the kernel's `FLAG_ROW_*`, above the passthrough and the scale,
## in the same flags word, because the push constant is the 128 bytes it
## declares and has no word to spare. `SaGraphParams` holds them, since the
## door's `SaNodeHistogram` asks for a channel's rows the same way.
const HISTOGRAM_ROW_FLAGS := SaGraphParams.ROW_FLAGS
var histogram_channel: String = ""

## How many bins either side of its own the histogram draws a bin's bar over,
## nought for the docker's column a bin. Levels and Curves write it beside
## `scale` from [method bar_reach_for], because the picture they show is 256
## texels stretched across a dialog, where a painted layer's few levels would
## be columns a pixel or two wide.
var bar_reach: int = 0

## The narrowest a lone bin's bar may be drawn, in logical pixels. The row
## asked for three, and a bar that narrow is two outlines with a texel of fill
## between them, which read on screen as a pair of lines rather than a bar.
const BAR_MIN_WIDTH := 6.0

## Where the cloud is looked at from and how far, moved by the pointer. Held
## here rather than in the docker because the push constant is built here and
## the projection they feed is the kernel's.
var cloud_yaw: float = CLOUD_YAW
var cloud_pitch: float = CLOUD_PITCH
var cloud_pan: Vector2 = Vector2.ZERO
var cloud_zoom: float = 1.0

## Half floats: this is a picture of the paint rather than paint, so nothing is
## ever stored back from it.
const FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT

var _compute: SaCompute = null
var _counts: SaCompute.Buffer = null
## The view's parallelogram as `graph_sampling.gmacs` reads it, six floats.
var _shown_map: SaCompute.Buffer = null
var _plot: SaTexture = null
## The picture, once a pass has run. Null before that, which is what a docker
## with no document shows.
var shown: Texture2DRD = null
## The size the next pass draws at.
var plot_size: Vector2i = PLOT
## How many samples the last pass took, both ways.
var samples: Vector2i = Vector2i.ZERO
## The live grid of the last pass, columns by levels, and zero for a mode that
## bins into the fixed grid.
var live: Vector2i = Vector2i.ZERO
## What the last pass over a view was given, so a capture can bin the same
## samples into the fixed grid. Empty after a pass over a layer, which has no
## single view to bin again.
var _last_view: Dictionary = {}


## The mode id at *index*, or the default for an index nothing offers.
static func mode_at(index: int) -> String:
    if index < 0 or index >= MODES.size():
        return DEFAULT_MODE
    var mode_id: String = MODES[index][0]
    return mode_id


## Where *mode_id* sits in `MODES`, and zero for a word nothing knows, so a
## stored setting from another version opens on the default graph rather than
## on nothing.
static func index_of(mode_id: String) -> int:
    for index in range(MODES.size()):
        var listed: String = MODES[index][0]
        if listed == mode_id:
            return index
    return 0


## What `graph.gmacs` calls *mode_id*, which is not its place in the dropdown.
static func kernel_mode(mode_id: String) -> int:
    var number: int = MODES[index_of(mode_id)][2]
    return number


## Whether *mode_id* is one of the two waveforms, which is what decides whether
## the docker offers the RGB and W toggle at all.
static func is_waveform(mode_id: String) -> bool:
    return WAVEFORM_MODES.has(mode_id)


## How bright *mode* draws a bin at the maximum. The traced modes need more than
## the round ones, for the reason `TRACE_GAIN` gives.
static func gain_for(mode: int) -> float:
    return TRACE_GAIN if TRACE_KERNEL_MODES.has(mode) else GAIN


## Asks for a picture *size* texels across, held inside the two limits. The docker calls this with its own picture rect, so
## the graph fills the panel instead of being a square scaled up into it.
##
## Answers whether anything moved. A changed size drops the texture rather than
## resizing it, because a `SaTexture` owns an image whose extent is fixed at
## creation, and `_ensure_resources` makes the next one. The `Texture2DRD` goes
## first: it holds the RID the `SaTexture` is about to free.
func set_plot_size(size: Vector2i) -> bool:
    var wanted := round_size(size)
    if wanted == plot_size:
        return false
    plot_size = wanted
    shown = null
    _plot = null
    # The live grid is sized from the picture, so the buffer goes with it.
    _counts = null
    return true


## What `set_plot_size` would settle on for *size*. Public because the docker
## has to know whether a resize will drop the texture before it drops it: the
## `TextureRect` holds a reference of its own to the `Texture2DRD`, so it must
## let go first or it draws a RID that has been freed.
static func round_size(size: Vector2i) -> Vector2i:
    return Vector2i(_round_axis(size.x), _round_axis(size.y))


## The live grid *mode_id* bins into at picture *size* from *sample_grid*
## samples, as columns by levels, mirroring `live_columns` and `live_levels` in
## the kernel: a column per texel across, a third of the width each for the
## parade, and never more columns than there are columns of samples, and a
## level per row below `VALUE_TOP`. Zero for the modes with no columns.
static func live_grid(size: Vector2i, mode_id: String, sample_grid: Vector2i) -> Vector2i:
    if not is_waveform(mode_id) and mode_id != "parade":
        return Vector2i.ZERO
    var across := int(size.x / 3.0) if mode_id == "parade" else size.x
    var columns := maxi(mini(across, sample_grid.x), 1)
    var levels := maxi(int(size.y * VALUE_TOP), 2)
    return Vector2i(columns, levels)


## How many counts the live grid of *grid* takes: three planes of it.
static func live_size(grid: Vector2i) -> int:
    return 3 * grid.x * grid.y


## The samples a pass over *span_x* by *span_y* takes when it is told the view
## shows *shown* pixels, or one per document texel when it is not told, held
## under `MAX_SAMPLES`.
static func samples_for(shown_pixels: Vector2i, span_x: Vector2, span_y: Vector2) -> Vector2i:
    var wanted := shown_pixels
    if wanted.x <= 0 or wanted.y <= 0:
        wanted = Vector2i(roundi(span_x.length()), roundi(span_y.length()))
    return Vector2i(clampi(wanted.x, 1, MAX_SAMPLES.x), clampi(wanted.y, 1, MAX_SAMPLES.y))


## The box along the document's axes that holds the parallelogram *origin*,
## *span_x* and *span_y*, clipped to a document *source_size* across. A
## parallelogram that misses the document answers the whole of it, whose
## samples the kernel then skips as unshown, so the pass bins nothing.
static func shown_box(origin: Vector2, span_x: Vector2, span_y: Vector2, source_size: Vector2i) -> Rect2:
    var box := Rect2(origin, Vector2.ZERO)
    for corner: Vector2 in [origin + span_x, origin + span_y, origin + span_x + span_y]:
        box = box.expand(corner)
    var document := Rect2(Vector2.ZERO, Vector2(source_size))
    var clipped := box.intersection(document)
    if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
        return document
    return clipped


## How many samples *box* takes when *view_samples* cover the parallelogram
## *span_x* and *span_y*: the same density, a sample a pixel at the view's
## zoom, over the box instead. The zoom is read as the root of the two axes'
## ratios, which a view that neither stretches nor shears holds equal.
static func samples_over(box: Rect2, view_samples: Vector2i, span_x: Vector2, span_y: Vector2) -> Vector2i:
    var across := maxf(span_x.length(), 1.0e-6)
    var down := maxf(span_y.length(), 1.0e-6)
    var zoom := sqrt(float(view_samples.x) / across * float(view_samples.y) / down)
    var wanted := Vector2i(roundi(box.size.x * zoom), roundi(box.size.y * zoom))
    return Vector2i(clampi(wanted.x, 1, MAX_SAMPLES.x), clampi(wanted.y, 1, MAX_SAMPLES.y))


## The affine map that takes a document point to where the parallelogram
## *origin*, *span_x* and *span_y* puts it, 0 to 1 both ways when it is shown,
## as the six floats `graph_sampling.gmacs` reads: the images of the two axes
## and of the origin. A parallelogram with no area shows every point, as a
## pass with no view does.
static func shown_map(origin: Vector2, span_x: Vector2, span_y: Vector2) -> PackedFloat32Array:
    var onto := Transform2D(span_x, span_y, origin)
    if absf(onto.determinant()) < 1.0e-9:
        return PackedFloat32Array(EVERY_POINT_SHOWN)
    var back := onto.affine_inverse()
    return PackedFloat32Array([back.x.x, back.x.y, back.y.x, back.y.y, back.origin.x, back.origin.y])


## Writes *edges* into the buffer the kernel's `shown` names and binds it.
## Updated in place, so a pass a frame allocates nothing.
func _bind_shown_map(compute: SaCompute, edges: PackedFloat32Array) -> void:
    var bytes := edges.to_byte_array()
    if _shown_map == null:
        _shown_map = SaCompute.Buffer.new(bytes)
    else:
        _shown_map.update(bytes)
    compute.set_buffer(3, _shown_map.rid)


## Nearest while a sample covers a texel or less, which is the texel the view
## shows, and linear once it covers more, which is what the kernel's taps are
## laid out for. The view switches its own sampler at the same place.
static func filter_for(span_x: Vector2, span_y: Vector2, sample_grid: Vector2i) -> RenderingDevice.SamplerFilter:
    var across := span_x.length() / float(maxi(sample_grid.x, 1))
    var down := span_y.length() / float(maxi(sample_grid.y, 1))
    if maxf(across, down) <= 1.0 + FILTER_EPSILON:
        return RenderingDevice.SAMPLER_FILTER_NEAREST
    return RenderingDevice.SAMPLER_FILTER_LINEAR


static func _round_axis(pixels: int) -> int:
    return clampi(pixels, MIN_PLOT, MAX_PLOT)


## Bins the whole of *source* and draws *mode_id*, a sample per texel. What a
## scope of a document with no view on it is, and what the test uses.
func run_over_document(source: SaTexture, source_size: Vector2i, space: SaColorSpace, mode_id: String) -> bool:
    var size := Vector2(source_size)
    return run(source, source_size, Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), space, mode_id, source_size)


## Bins every chunk of *layer* and draws *mode_id*: the layer's own histogram
## rather than the picture's, which is what a Levels dialog has to show.
##
## One clear, one compute list holding a dispatch per chunk, one draw. The
## counts accumulate across the list because the kernel adds atomically, so
## the chunks need no ordering between them, only the clear before and the
## draw after. Chunks are sparse, so this reads the paint and nothing else.
func run_over_layer(layer: SaLayer, space: SaColorSpace, mode_id: String) -> bool:
    if layer == null or layer.chunks.is_empty():
        return false
    var compute := _ensure_compute()
    if compute == null or not _ensure_resources():
        return false
    var first := _first_albedo(layer)
    if first == null:
        return false

    var mode := kernel_mode(mode_id)
    # A sample per texel of every chunk, which is every pixel of the layer.
    var edge := first.size.x
    samples = Vector2i(edge, edge)
    live = live_grid(plot_size, mode_id, samples)
    _last_view = {}
    compute.use_storage_format(_plot.format)
    compute.set_texture(0, _plot.rid)
    compute.set_sampled_texture(1, first.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
    compute.set_buffer(2, _counts.rid)
    _bind_shown_map(compute, PackedFloat32Array(EVERY_POINT_SHOWN))
    compute.set_push_constant_float_array(_square_params(edge, space, mode))
    compute.dispatch_kernel("graph_clear", _clear_groups(), 1, 1)
    _dispatch_frame(compute, mode_id)

    compute.list_begin(compute.index_of_kernel("graph_bin"))
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var albedo := chunk.albedo() if chunk != null else null
        if albedo == null or not albedo.rid.is_valid():
            continue
        var side := chunk.pixel_size()
        compute.set_sampled_texture(1, albedo.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
        compute.set_push_constant_float_array(_square_params(side, space, mode))
        compute.list_dispatch(SaCompute.groups_for(side), SaCompute.groups_for(side), 1)
    compute.list_end()

    compute.set_sampled_texture(1, first.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
    compute.set_push_constant_float_array(_square_params(first.size.x, space, mode))
    compute.dispatch_kernel("graph_draw", SaCompute.groups_for(plot_size.x), SaCompute.groups_for(plot_size.y), 1)
    return true


## Bins the square texture *source_at* answers for each of *positions* and
## draws *mode_id*: the histogram of a picture composited for the occasion
## rather than stored, which is what an attached Levels on a group or on the
## document's root equalizes from.
##
## A dispatch a texture rather than one list, because the caller composites
## each texture between two of them and may answer the same scratch every
## time: a compute list may not stay open across the composite, and the bin
## of one position is ordered before the composite of the next by the
## device's own barriers. A position *source_at* answers null for is passed
## over. It writes the plot's own buffer and picture and reads nothing back.
func run_over_sources(positions: Array[Vector2i], source_at: Callable, space: SaColorSpace, mode_id: String) -> bool:
    var compute := _ensure_compute()
    if compute == null or not _ensure_resources():
        return false
    var mode := kernel_mode(mode_id)
    var binned: SaTexture = null
    for grid_pos: Vector2i in positions:
        var source: SaTexture = source_at.call(grid_pos)
        if source == null or not source.rid.is_valid():
            continue
        var edge := source.size.x
        compute.use_storage_format(_plot.format)
        compute.set_texture(0, _plot.rid)
        compute.set_sampled_texture(1, source.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
        compute.set_buffer(2, _counts.rid)
        _bind_shown_map(compute, PackedFloat32Array(EVERY_POINT_SHOWN))
        compute.set_push_constant_float_array(_square_params(edge, space, mode))
        if binned == null:
            samples = Vector2i(edge, edge)
            live = live_grid(plot_size, mode_id, samples)
            _last_view = {}
            compute.dispatch_kernel("graph_clear", _clear_groups(), 1, 1)
            _dispatch_frame(compute, mode_id)
        compute.dispatch_kernel("graph_bin", SaCompute.groups_for(edge), SaCompute.groups_for(edge), 1)
        binned = source
    if binned == null:
        return false
    compute.dispatch_kernel("graph_draw", SaCompute.groups_for(plot_size.x), SaCompute.groups_for(plot_size.y), 1)
    return true


## The whole of a square texture *edge* across, which is what one chunk is,
## at a sample per texel.
func _square_params(edge: int, space: SaColorSpace, mode: int) -> PackedFloat32Array:
    return SaGraphParams.pack_square(edge, space, mode, gain_for(mode), flags_for(space), _cloud())


func _first_albedo(layer: SaLayer) -> SaTexture:
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var albedo := chunk.albedo() if chunk != null else null
        if albedo != null and albedo.rid.is_valid():
            return albedo
    return null


## Bins the part of the document the parallelogram *origin*, *span_x* and
## *span_y* shows, in document pixels, and draws *mode_id*.
##
## The parallelogram is the view's, turned and mirrored as the view is, but
## the samples lie on the document's own grid: the box of the parallelogram
## along the document's axes, clipped to the document, with every sample the
## parallelogram leaves out skipped in the kernel. So a waveform's column is a
## run of document x, left to right as the document is, and turning or
## mirroring the view leaves the graph alone. A view zoomed out to show
## the whole document graphs the whole document across the whole width, with
## no column for the surround.
##
## *shown_pixels* is how many pixels the view shows the parallelogram at, which
## sets the density, one sample a pixel shown. Left at zero it is one a
## document texel.
func run(
    source: SaTexture,
    source_size: Vector2i,
    origin: Vector2,
    span_x: Vector2,
    span_y: Vector2,
    space: SaColorSpace,
    mode_id: String,
    shown_pixels: Vector2i = Vector2i.ZERO
) -> bool:
    if source == null or not source.rid.is_valid() or source_size.x <= 0 or source_size.y <= 0:
        return false
    var compute := _ensure_compute()
    if compute == null:
        return false
    if not _ensure_resources():
        return false

    var box := shown_box(origin, span_x, span_y, source_size)
    samples = samples_over(box, samples_for(shown_pixels, span_x, span_y), span_x, span_y)
    live = live_grid(plot_size, mode_id, samples)
    _last_view = {
        "source": source,
        "source_size": source_size,
        "origin": box.position,
        "span_x": Vector2(box.size.x, 0.0),
        "span_y": Vector2(0.0, box.size.y),
        "shown_map": shown_map(origin, span_x, span_y),
        "space": space,
        "mode_id": mode_id,
    }
    _bind(compute, _last_view, 0)

    # Three dispatches, each its own list, because each needs what the one
    # before it wrote: the counts must be zero before anything adds to them,
    # and complete before anything reads them.
    compute.dispatch_kernel("graph_clear", _clear_groups(), 1, 1)
    _dispatch_frame(compute, mode_id)
    compute.dispatch_kernel("graph_bin", SaCompute.groups_for(samples.x), SaCompute.groups_for(samples.y), 1)
    compute.dispatch_kernel("graph_draw", SaCompute.groups_for(plot_size.x), SaCompute.groups_for(plot_size.y), 1)
    return true


## Binds the picture, *view*'s source and the counts, and pushes *view*'s
## parameters with *extra_flags* over its own.
##
## The source is read nearest while a sample covers a texel or less, because a
## scope reports values the picture holds and a filtered tap at an edge invents
## one in neither texel, and linear once a sample covers more, which is where
## the view blends texels too and the kernel spreads its taps over the pixel.
func _bind(compute: SaCompute, view: Dictionary, extra_flags: int) -> void:
    var span_x: Vector2 = view["span_x"]
    var span_y: Vector2 = view["span_y"]
    var source: SaTexture = view["source"]
    compute.use_storage_format(_plot.format)
    compute.set_texture(0, _plot.rid)
    compute.set_sampled_texture(1, source.rid, filter_for(span_x, span_y, samples))
    compute.set_buffer(2, _counts.rid)
    var edges: PackedFloat32Array = view["shown_map"]
    _bind_shown_map(compute, edges)
    var mode_id: String = view["mode_id"]
    var source_size: Vector2i = view["source_size"]
    var origin: Vector2 = view["origin"]
    var space: SaColorSpace = view["space"]
    var mode := kernel_mode(mode_id)
    var params := _params(source_size, origin, span_x, span_y, space, mode, samples)
    params[SaGraphParams.PARAM_FLAGS] = float(int(params[SaGraphParams.PARAM_FLAGS]) | extra_flags)
    compute.set_push_constant_float_array(params)


## Groups enough for the clear to reach the end of the live grid.
func _clear_groups() -> int:
    return ceili(float(LIVE_SLOT + live_size(live)) / 64.0)


## Bins the last pass's samples a second time into the fixed grid, for a
## capture of the waveform, the parade or the cloud, and draws nothing: the picture on
## screen stays the live one. Answers whether it ran. The live grid is left as
## it was, because the clear stops at `LIVE_SLOT` when the flag is set.
func _bin_fixed_grid() -> bool:
    if _last_view.is_empty():
        return false
    if live == Vector2i.ZERO and _last_view["mode_id"] != "cloud":
        return false
    var source: SaTexture = _last_view["source"]
    if source == null or not source.rid.is_valid() or _counts == null or _plot == null:
        return false
    var compute := _ensure_compute()
    if compute == null:
        return false
    _bind(compute, _last_view, SaGraphParams.FLAG_FIXED_GRID)
    compute.dispatch_kernel("graph_clear", int(ceil(float(LIVE_SLOT) / 64.0)), 1, 1)
    compute.dispatch_kernel("graph_bin", SaCompute.groups_for(samples.x), SaCompute.groups_for(samples.y), 1)
    return true


## The passthrough bit, the scale bit, the histogram's chosen rows and its
## bars' reach, packed the way `graph.gmacs` reads them.
func flags_for(space: SaColorSpace) -> int:
    return SaGraphParams.flags(space, scale == "linear", histogram_channel, bar_reach)


## The reach that draws a lone bin at least `BAR_MIN_WIDTH` logical pixels
## wide when the picture is shown *shown_width* logical pixels across: a bar
## is `2 * reach + 1` bins and a bin is `shown_width / BINS` pixels. One at the
## least, so a picture shown wide still draws bars rather than columns.
static func bar_reach_for(shown_width: float) -> int:
    if shown_width <= 0.0:
        return 1
    var bins := BAR_MIN_WIDTH * float(BINS) / shown_width
    return clampi(ceili((bins - 1.0) * 0.5), 1, SaGraphParams.BAR_MASK)


## How wide a lone bin's bar comes out at *reach* in a picture shown
## *shown_width* logical pixels across, the number a capture reports.
static func bar_width(reach: int, shown_width: float) -> float:
    return float(2 * reach + 1) * shown_width / float(BINS)


## The gamut wireframe, but only for the modes that draw one: the cloud and the
## vectorscope, whose hue ring is six of the same edges on the a and b plane.
##
## After the clear, which writes over the end of the buffer the vertices live
## in, and before the draw that reads them back. Every other mode is a flat
## picture with no wireframe, so it stays at the three dispatches the Info
## docker's counter shows for it.
func _dispatch_frame(compute: SaCompute, mode_id: String) -> void:
    if mode_id != "cloud" and mode_id != "vectorscope":
        return
    compute.dispatch_kernel("graph_frame", int(ceil(float(FRAME_VERTICES) / 64.0)), 1, 1)


## The counts a pass left in the fixed grid, as one array, whatever the panel
## measures. A waveform or a parade binned into the live grid, so for those the
## same samples are binned a second time into the fixed one first. A readback
## and a stall, so it is for a test and a capture rather than for the docker,
## which never asks.
func read_counts() -> PackedInt32Array:
    if _counts == null:
        return PackedInt32Array()
    _bin_fixed_grid()
    return _counts.read().to_int32_array().slice(0, LIVE_SLOT)


## The live grid the last pass drew, three planes of `live` columns by levels,
## channel first, then column, then level. A readback and a stall, like
## `read_counts`.
func read_live_counts() -> PackedInt32Array:
    if _counts == null or live == Vector2i.ZERO:
        return PackedInt32Array()
    return _counts.read().to_int32_array().slice(LIVE_SLOT, LIVE_SLOT + live_size(live))


## What a capture reports of the bins: the samples and the live grid of the
## last pass, and the fixed grid the same samples fill, as a total and a
## digest. The fixed grid is the part a scenario compares across panel sizes,
## so it is the part summarised, and a digest rather than the quarter of a
## million counts a dump has no room for.
func bins_report() -> Dictionary:
    if _counts == null or samples == Vector2i.ZERO:
        return {}
    var fixed := read_counts().slice(0, COUNT_SIZE)
    var total := 0
    for count in fixed:
        total += count
    return {
        "samples": [samples.x, samples.y],
        "live": [live.x, live.y],
        "fixed": [COLUMNS, BINS],
        "fixed_total": total,
        "fixed_digest": fixed.to_byte_array().hex_encode().sha256_text().left(16),
    }


## The gamut wireframe's vertices as the last pass projected them: one entry per
## vertex, `{"at": Vector2, "color": Color}`.
##
## A readback and a stall, so it is for a test rather than for the docker, which
## never asks. The floats are stored as their bits in a buffer of `uint`, which
## is what lets one buffer carry both the counts and this.
func read_frame() -> Array:
    if _counts == null:
        return []
    var raw := _counts.read()
    var out: Array = []
    for i in FRAME_VERTICES:
        var at := (FRAME_SLOT + i * FRAME_STRIDE) * 4
        if at + FRAME_STRIDE * 4 > raw.size():
            break
        (
            out
            . append(
                {
                    "at": Vector2(raw.decode_float(at), raw.decode_float(at + 4)),
                    "color": Color(raw.decode_float(at + 8), raw.decode_float(at + 12), raw.decode_float(at + 16)),
                }
            )
        )
    return out


## The largest bin the last pass wrote, which is what the picture is normalised
## against.
func read_largest() -> int:
    var all := read_counts()
    return all[MAX_SLOT] if all.size() > MAX_SLOT else 0


func _params(
    source_size: Vector2i,
    origin: Vector2,
    span_x: Vector2,
    span_y: Vector2,
    space: SaColorSpace,
    mode: int,
    sample_grid: Vector2i
) -> PackedFloat32Array:
    var gain := gain_for(mode)
    return SaGraphParams.pack(source_size, origin, span_x, span_y, sample_grid, space, mode, gain, flags_for(space), _cloud())


## Where the cloud is looked at from, laid out as `SaGraphParams.NO_CLOUD` is.
func _cloud() -> Array:
    return [cloud_yaw, cloud_pitch, cloud_pan, cloud_zoom]


func _ensure_compute() -> SaCompute:
    if _compute == null and not GlobalShaderCompiler.get_kernel_names(SHADER_NAME).is_empty():
        _compute = SaCompute.new(SHADER_NAME)
    return _compute


func _ensure_resources() -> bool:
    if _counts == null:
        # Room for the widest live grid this picture can have, which is the
        # waveform's with a sample column for every texel.
        var zeros := PackedInt32Array()
        zeros.resize(LIVE_SLOT + live_size(live_grid(plot_size, DEFAULT_MODE, MAX_SAMPLES)))
        _counts = SaCompute.Buffer.new(zeros.to_byte_array())
        if not _counts.rid.is_valid():
            _counts = null
            return false
    if _plot == null:
        _plot = SaTexture.new(plot_size, FORMAT)
        if not _plot.rid.is_valid():
            _plot = null
            return false
        _plot.clear(Color(BACKGROUND, BACKGROUND, BACKGROUND, 1.0))
        shown = Texture2DRD.new()
        shown.texture_rd_rid = _plot.rid
    return true


## The buffer, the picture and the kernel go in this order: the `Texture2DRD`
## holds the RID the `SaTexture` is about to free, so it goes first. Inline
## rather than through a `release()` of its own, because a method call on
## `self` inside `NOTIFICATION_PREDELETE` fails.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        shown = null
        _plot = null
        _counts = null
        _shown_map = null
        _compute = null


## A reference picture as a texture a pass can bin: *image* uploaded once, as
## floats, at most *longest* texels on its longer side. A reference is not the
## canvas, so this is the one upload the scope makes, and it is made when the
## reference changes rather than per frame. The picture is scaled down first
## because the pass takes a sample per texel of it, so a 6000 texel photograph
## would cost thirty-six times the samples of one at *longest* and show the
## panel nothing more.
static func upload_image(image: Image, longest: int = 1024) -> SaTexture:
    if image == null or image.get_width() <= 0 or image.get_height() <= 0:
        return null
    var copy := image.duplicate() as Image
    var size := copy.get_size()
    var side := maxi(size.x, size.y)
    if side > longest:
        var shrink := float(longest) / float(side)
        copy.resize(maxi(1, roundi(size.x * shrink)), maxi(1, roundi(size.y * shrink)), Image.INTERPOLATE_BILINEAR)
    copy.convert(Image.FORMAT_RGBAF)
    var texture := SaTexture.new(copy.get_size(), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    if not texture.rid.is_valid() or texture.rd == null:
        return null
    texture.rd.texture_update(texture.rid, 0, copy.get_data())
    return texture


## How many cells across the cloud's grid is in a picture *size*, mirroring
## `cloud_cells` in the kernel: the smaller side over `CLOUD_CELL_TEXELS`,
## rounded up to even, so a cell is never wider than that, between 2 and
## `CLOUD_MAX_CELLS`.
static func cloud_cells_for(size: Vector2i) -> int:
    var across := (ceili(float(mini(size.x, size.y)) / CLOUD_CELL_TEXELS) + 1) & ~1
    return clampi(across, 2, CLOUD_MAX_CELLS)


## The cloud's grid against the plot it is drawn in, for a dump.
##
## A cell is a point rather than a column, so how many texels wide it comes out
## is the whole of whether the samples read beside the wireframe. At 256 cells
## it was one texel and a painting's strokes drew as single texels while the
## frame drew as a continuous line, and at a fixed 96 a higher UI scale drew
## the same few logical pixels a cell. Reported rather than argued, because
## the number changes with the docker's size and no screenshot carries it.
## `fixed_cells` is the grid a capture's counts are read from.
##
## Through this node rather than a block in `harness/report/sa_state_report.gd`,
## because a new number is reported by whoever owns it.
func cloud_report() -> Dictionary:
    var side: int = mini(plot_size.x, plot_size.y)
    var cells := cloud_cells_for(plot_size)
    var per_cell := float(side) / float(cells)
    return {
        "cells": cells,
        "fixed_cells": CLOUD_FIXED_CELLS,
        "plot_side": side,
        "texels_per_cell": snappedf(per_cell, 0.01),
        "lone_mark_texels": snappedf(CLOUD_MARK_MIN * per_cell, 0.01),
        "busiest_mark_texels": snappedf((CLOUD_MARK_MIN + CLOUD_MARK_SPAN) * per_cell, 0.01),
    }
