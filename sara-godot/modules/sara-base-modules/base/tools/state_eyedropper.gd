## Tool state for picking colours from the view or the active layer.
##
## A sample size, the side of a square centred on the pointer and averaged,
## and the Sample row that says what is read. The square is
## copied into a small readback texture in one or a few `texture_copy` calls
## and read back once, so the only readback on the paint path stays a handful
## of texels rather than a chunk.
##
## The view's read goes through the easel's sample merged door:
## `SaEasel.snapshot_merged` hands back a [SaMergedSnapshot] of the composite
## under the square, one GPU to GPU copy per chunk cell under it, and the
## readback is of that snapshot, still the square's texels and nothing more.
## The eyedropper is the door's first reader, so the door the smudge stage
## will read its pickup from is proved by a tool a painter uses.
extends ToolState

## The narrowest and the widest square a pick averages, in texels. The side
## is odd, so the texel under the pointer is always the square's centre.
const MIN_SAMPLE_SIZE := 1
const MAX_SAMPLE_SIZE := 25

## What a pick reads, the Sample row's two choices.
##
## **VIEW is the composite**, every layer with its attached filters, every
## group's filters, masks and clips, the picture the view is drawn from. It is
## not what the canvas's own shader then does to that picture on the way to the
## screen, the highlight tone map, the gamut mapping, proofing, False Colour, the
## shape check and the relief's light: those are how Sara shows a colour rather
## than the colour, and a pick painted back is shown through them again, so a
## pick that took them would take them twice. A diagnostic view such as False
## Colour is never a colour a painter meant to pick at all.
##
## **LAYER is the active layer as painted**, before its filters, its mask and
## the layers above.
enum SampleFrom { VIEW, LAYER }

## The key the choice is kept under, in the base module's own preferences.
const SAMPLE_FROM_KEY := &"eyedropper_sample_from"
## The key the sample size is kept under, beside it.
const SAMPLE_SIZE_KEY := &"eyedropper_sample_size"

## The base module's context while the module is registered, held weakly, the
## door to its own preferences. A tool state is built by the tool machine with
## no argument, so the module hands the context to the script at `register` and
## takes it back at `unregister`, through [method keep_choice_in].
static var _preferences: WeakRef = null

## What a pick reads, one of [enum SampleFrom].
##
## A view of the module's preference while the module is registered, so the
## choice outlives the session and every surface's eyedropper reads the one the
## painter made on any of them, the way the wand's Feather is a view of
## `SaSettings.selection_feather`. A state with no module behind it, a suite's,
## keeps it in [member _sample_from] and remembers nothing, the way a gradient's
## ends without a context open opaque.
var sample_from: SampleFrom:
    set(value):
        _sample_from = value
        var context := _live_preferences()
        if context != null:
            context.set_preference(SAMPLE_FROM_KEY, int(value))
    get:
        var context := _live_preferences()
        if context == null:
            return _sample_from
        var stored: Variant = context.preference(SAMPLE_FROM_KEY, int(SampleFrom.VIEW))
        # A hand-edited profile is not a promise, so anything but one of the
        # two is read as the default.
        if not stored is int or not SampleFrom.values().has(stored):
            return SampleFrom.VIEW
        return stored as SampleFrom

## The side of the square a pick averages, in texels, an odd number from
## [constant MIN_SAMPLE_SIZE] to [constant MAX_SAMPLE_SIZE] read through
## [method side_of]. A view of the module's preference the way [member
## sample_from] is, so the 1, 3, 5 or 9 the old choice list wrote opens at the
## same side.
var sample_size: int:
    set(value):
        _sample_size = side_of(value)
        var context := _live_preferences()
        if context != null:
            context.set_preference(SAMPLE_SIZE_KEY, _sample_size)
    get:
        var context := _live_preferences()
        if context == null:
            return _sample_size
        return side_of(context.preference(SAMPLE_SIZE_KEY, MIN_SAMPLE_SIZE))

## The choice of a state with no module behind it.
var _sample_from: SampleFrom = SampleFrom.VIEW
## The sample size of a state with no module behind it.
var _sample_size: int = MIN_SAMPLE_SIZE
var _pixel_readback: SaTexture
var _last_sample_pos := Vector2i(-1, -1)
var _last_sample_color := SaFieldSpec.NO_PAINT
var _last_sample_from: SampleFrom = SampleFrom.VIEW
var _last_sample_size: int = 1

## A motion has moved the pointer since the last sample was taken: a tablet
## sends a motion every few milliseconds, and sampling each from `handle_input`
## is one GPU stall per event through [method pick_color_at_pos]'s synchronous
## readback. The motion only records where the pointer is, and [method tick]
## samples once a frame, the shape `state_gradient.gd` uses for its own
## preview.
var _sample_pending: bool = false
## The document position the pending sample is taken at, from the last motion.
var _pending_pos: Vector2 = Vector2.ZERO

## Whether the left button went down on this tool and has not come up.
##
## **The button mask is not enough on its own.** `InputEventMouseMotion` carries
## one only when whoever built the event filled it in, and the capture harness
## does not: `SaCaptureInput._inject_motion` sets the position, the pressure and
## the tilt and never the mask, so a scenario can press, move and release with
## this tool active and the motion branch never fire, which leaves a drag
## unprovable on the running app. `state_brush.gd` tracks its own `is_drawing`
## from the press, and this is the same thing under a name that says what it is
## for.
##
## The mask is still read beside it, because a motion can arrive with the button
## already down and no press this tool ever saw: ALT is `tool_eyedropper_quick`
## and swaps the tool under a held button.
var _dragging: bool = false

## The last colour this gesture picked, which the release commits as used.
##
## The recent row in the colour docker lists colours that were used, and a pick
## is a use, but only once the gesture ends: a drag samples once a frame, and
## noting each sample would fill the twelve places with one sweep across the
## picture. So the press and every sample only remember the colour here, and
## [method _commit_pick] hands the last one to `SaColors.note_used`, the door
## a module has to the colour store, the same call the picker makes when its
## own gesture ends.
var _picked: Color = SaFieldSpec.NO_PAINT
## Whether [member _picked] holds a pick the recent list has not been told of.
var _pick_uncommitted: bool = false
## Whether this press has said there was nothing painted under it, so a drag
## across empty canvas says it once rather than once a frame.
var _told_nothing_there: bool = false


## Hands *context*, the base module's, to every eyedropper as the door to the
## preferences [member sample_from] and [member sample_size] are kept in, or
## takes it back with null.
static func keep_choice_in(context: SaContext) -> void:
    _preferences = weakref(context) if context != null else null


## The side *stored* means. A whole odd number in range is itself, and anything
## else, a hand-edited profile's word or an even side whose centre falls between
## two texels, is the single texel. The bar's slider writes a float, so a whole
## one counts.
static func side_of(stored: Variant) -> int:
    if not (stored is int or stored is float):
        return MIN_SAMPLE_SIZE
    var side := int(stored)
    if float(side) != float(stored) or side % 2 == 0:
        return MIN_SAMPLE_SIZE
    if side < MIN_SAMPLE_SIZE or side > MAX_SAMPLE_SIZE:
        return MIN_SAMPLE_SIZE
    return side


static func _live_preferences() -> SaContext:
    return _preferences.get_ref() as SaContext if _preferences != null else null


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging = event.pressed
        if event.pressed:
            # A press is a new pick, so the last one's colour is not an answer
            # for it. The picture under the pointer may have changed since, a
            # filter attached or a stroke laid over it, and at a zoom where a
            # texel is many screen pixels wide the press lands on the texel the
            # last one did, which would hand the colour from before the change back.
            _last_sample_pos = Vector2i(-1, -1)
            _told_nothing_there = false
            _sample_color_at_mouse(get_document_mouse_position())
        else:
            # A motion since the last frame would otherwise be sampled by the
            # next tick, after the commit, and the foreground would end on a
            # colour the recent row never heard of.
            if _sample_pending:
                tick(0.0)
            _commit_pick()
        return

    if event is InputEventMouseMotion and (_dragging or (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
        _pending_pos = get_document_mouse_position()
        _sample_pending = true


## The frame's one sample, when a motion asked for one since the last.
func tick(_delta: float) -> void:
    if not _sample_pending:
        return
    _sample_pending = false
    _sample_color_at_mouse(_pending_pos)


## Whether there is any canvas under *pos* to sample.
##
## The sample square clipped to the document, which is the same rectangle
## [method _read_square] averages and, at a sample size of one, the same bounds
## the single-texel path checks. An empty intersection means the pointer is over
## the background beside the canvas.
##
## **A partly overlapping square still picks.** What a pointer beside the canvas
## must not do is pick the background, and that is the empty intersection above,
## not a nine by nine square at the canvas edge, whose average already leaves
## out the texels that are not there.
func has_sample_at(pos: Vector2) -> bool:
    var doc: SaDocument = document()
    if doc == null:
        return false
    var side := sample_size
    @warning_ignore("integer_division")
    var half := side / 2
    var centre := Vector2i(floor(pos.x), floor(pos.y))
    var square := Rect2i(centre - Vector2i(half, half), Vector2i(side, side))
    square = square.intersection(Rect2i(Vector2i.ZERO, doc.canvas_size))
    return square.size.x > 0 and square.size.y > 0


func _sample_color_at_mouse(pos: Vector2) -> void:
    # Off the canvas there is nothing to pick, so the colour is left alone.
    # Emitting what [method pick_color_at_pos] answers there sets the painter's
    # foreground to transparent black on every release outside the canvas.
    #
    # **The click and the drag both**, because `handle_input` sends both here:
    # a drag that leaves the canvas would otherwise wipe the colour it had just
    # picked.
    if not has_sample_at(pos):
        return
    var color := pick_color_at_pos(pos)
    # Inside the canvas a pick with no coverage is no colour either. Its rgb is
    # whatever the texel was cleared to, and once the document's colour space
    # read it as a colour the foreground held a triple nobody chose, which the
    # next stroke painted solid. The pick says so in the corner instead, once a
    # press. A partly covered pick keeps its colour.
    if color.a <= 0.0:
        if not _told_nothing_there:
            _told_nothing_there = true
            EventBus.corner_notice.emit(tr("Nothing painted there, so the colour stays as it was."))
        return
    # The canvas stores whatever the document declared and the colour wheel speaks
    # the document's gamut through sRGB's curve, so a texel handed over
    # unconverted is the brush's bug in the other direction: picking from a linear
    # document put a value on the wheel that the brush would then paint back
    # somewhere else. Exactly a passthrough for an RGB document on the sRGB curve.
    var doc: SaDocument = document()
    if doc != null and doc.color_space != null:
        color = doc.color_space.to_display(color)
    # A soft edge's colour, without the edge's coverage. The brush paints the
    # foreground at full alpha, so an alpha handed on here shows on the
    # swatch as a checker blend and is never painted. The store drops it from its
    # own copy, but the bus hands the swatch the colour as emitted, so the pick
    # drops it before it emits. A texel that is not a number is refused the way
    # the store refuses it, before the bus hands it to every tool.
    color = SaInHand.Pair.opaque(color)
    if not SaInHand.Pair.finite(color):
        return
    EventBus.color_picked.emit(color)
    _picked = color
    _pick_uncommitted = true


## Hands the gesture's last pick to the recent list, once.
func _commit_pick() -> void:
    if not _pick_uncommitted:
        return
    _pick_uncommitted = false
    SaInHand.Pair.note_used(_picked)


## The colour under *pos*, straight and in the document's own encoding, or
## [constant SaFieldSpec.NO_PAINT] where nothing is painted or there is no
## canvas.
##
## **Not `Color.TRANSPARENT`**, which is Godot's transparent white. On an RGB
## document its alpha hid that, and on the Oklab default it is lightness one
## with a and b at one, which the colour space carried to rgb (3.22, -1.79,
## -0.75) and handed the colour wheel.
func pick_color_at_pos(pos: Vector2) -> Color:
    var rd := GlobalShaderCompiler.get_rd()
    var doc: SaDocument = document()
    # The view is the composite the easel owns, read through its snapshot
    # door, which is the only readback on the whole paint path, and the
    # snapshot copies the square first so the readback is the square alone.
    var easel: SaEasel = surface.easel if surface != null else null
    if not rd or doc == null:
        return SaFieldSpec.NO_PAINT

    var pos_i := Vector2i(floor(pos.x), floor(pos.y))
    var doc_size: Vector2i = doc.canvas_size
    if pos_i.x < 0 or pos_i.x >= doc_size.x or pos_i.y < 0 or pos_i.y >= doc_size.y:
        return SaFieldSpec.NO_PAINT

    var from := sample_from
    var side := sample_size
    if pos_i == _last_sample_pos and from == _last_sample_from and side == _last_sample_size:
        return _last_sample_color

    if side > 1:
        return _read_square(pos_i, doc_size, easel, from)

    if from == SampleFrom.LAYER:
        var layer := doc.active_layer
        if not layer:
            return SaFieldSpec.NO_PAINT
        var chunk_x: int = int(floor(pos.x / float(layer.CHUNK_SIZE)))
        var chunk_y: int = int(floor(pos.y / float(layer.CHUNK_SIZE)))
        var grid_pos := Vector2i(chunk_x, chunk_y)
        # Colour comes from the albedo field. A layer whose albedo is derived
        # has already resolved it, so this reads the same pixels the compositor
        # does rather than the concentrations behind them.
        var albedo := layer.get_field(grid_pos)
        if albedo == null:
            return SaFieldSpec.NO_PAINT
        # A layer stored finer than the document holds several texels under
        # one pixel, so the pick is their mean, which is what the view draws.
        if albedo.size.x != layer.CHUNK_SIZE:
            return _read_square(pos_i, doc_size, easel, from, 1)
        var local_x: int = pos_i.x - chunk_x * layer.CHUNK_SIZE
        var local_y: int = pos_i.y - chunk_y * layer.CHUNK_SIZE
        return _read_pixel(albedo, Vector2i(local_x, local_y), pos_i, from)
    return _read_merged(easel, Rect2i(pos_i, Vector2i.ONE), pos_i, from)


func _read_pixel(source: SaTexture, source_pos: Vector2i, sample_pos: Vector2i, from: SampleFrom) -> Color:
    if source == null or not source.rid.is_valid():
        return SaFieldSpec.NO_PAINT
    if _pixel_readback == null or _pixel_readback.format != source.format:
        _pixel_readback = SaTexture.new(Vector2i.ONE, source.format)
    var rd := GlobalShaderCompiler.get_rd()
    (
        rd
        . texture_copy(
            source.rid,
            _pixel_readback.rid,
            Vector3(source_pos.x, source_pos.y, 0),
            Vector3.ZERO,
            Vector3.ONE,
            0,
            0,
            0,
            0,
        )
    )
    var data: PackedByteArray = rd.texture_get_data(_pixel_readback.rid, 0)
    # Both the width and the offsets come from the format. Decoding four bytes
    # per channel regardless would read an F16 texel as two halves glued
    # together and then past the end of the buffer, so an F16 document would
    # pick a colour that is not on the canvas and log two engine errors doing
    # it.
    var sampled := SaFieldSpec.decode_texel(data, source.format)
    if data.size() < SaFieldSpec.BYTES_PER_TEXEL.get(source.format, 16):
        return SaFieldSpec.NO_PAINT
    _last_sample_pos = sample_pos
    _last_sample_from = from
    _last_sample_size = sample_size
    _last_sample_color = sampled
    return _last_sample_color


## The view's read of *square*, through the easel's snapshot door.
##
## The snapshot is the composite under the square and nothing beyond it, so
## every texel of it counts and the readback is the square, one texel at a
## sample size of one. The snapshot is dropped on return, which frees its
## texture: RAII, the way the door promises.
func _read_merged(easel: SaEasel, square: Rect2i, centre: Vector2i, from: SampleFrom) -> Color:
    if easel == null:
        return SaFieldSpec.NO_PAINT
    var snapshot := easel.snapshot_merged(square)
    if snapshot == null or snapshot.texture == null:
        return SaFieldSpec.NO_PAINT
    var rd := GlobalShaderCompiler.get_rd()
    var format: int = snapshot.texture.format
    var data: PackedByteArray = rd.texture_get_data(snapshot.texture.rid, 0)
    var count: int = snapshot.rect.size.x * snapshot.rect.size.y
    if data.size() < count * int(SaFieldSpec.BYTES_PER_TEXEL.get(format, 16)):
        return SaFieldSpec.NO_PAINT
    var averaged := _mean(data, format, range(count))
    _last_sample_pos = centre
    _last_sample_from = from
    _last_sample_size = sample_size
    _last_sample_color = averaged
    return averaged


## The average of the [member sample_size] square around *centre*, clipped to the
## canvas, from the composite through its snapshot or from the active layer's
## chunks, as *from* says.
##
## On the layer, each source rectangle is copied into its place in one
## readback texture the size of the square in texels, and a coverage list says which
## texels were filled, so a square that runs off the canvas or into a chunk
## nobody painted averages only what is there rather than diluting the colour
## with nothing.
func _read_square(centre: Vector2i, doc_size: Vector2i, easel: SaEasel, from: SampleFrom, side: int = 0) -> Color:
    var doc: SaDocument = document()
    var rd := GlobalShaderCompiler.get_rd()
    if side <= 0:
        side = sample_size
    @warning_ignore("integer_division")
    var half := side / 2
    var square := Rect2i(centre - Vector2i(half, half), Vector2i(side, side))
    square = square.intersection(Rect2i(Vector2i.ZERO, doc_size))
    if square.size.x <= 0 or square.size.y <= 0:
        return SaFieldSpec.NO_PAINT

    if from == SampleFrom.VIEW:
        return _read_merged(easel, square, centre, from)

    var pieces: Array = []
    var layer := doc.active_layer
    if layer == null:
        return SaFieldSpec.NO_PAINT
    var chunk_size: int = layer.CHUNK_SIZE
    @warning_ignore("integer_division")
    var first := square.position / chunk_size
    @warning_ignore("integer_division")
    var last := (square.end - Vector2i.ONE) / chunk_size
    # A layer stored finer than the document has chunk.pixel_size() texels
    # across a chunk, so every rectangle is taken in texels: the document pixel
    # x starts at texel floor(x * density), the same on every chunk of the layer.
    var density := 1.0
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var grid_pos := Vector2i(gx, gy)
            var albedo := layer.get_field(grid_pos)
            if albedo == null:
                continue
            density = float(albedo.size.x) / float(chunk_size)
            var origin := grid_pos * chunk_size
            var part := Rect2i(origin, Vector2i(chunk_size, chunk_size)).intersection(square)
            pieces.append([albedo, origin, part])
    if pieces.is_empty():
        return SaFieldSpec.NO_PAINT

    var square_texels := texels_of(square, density)
    var span := square_texels.size.x
    var format: int = (pieces[0][0] as SaTexture).format
    if _pixel_readback == null or _pixel_readback.format != format or _pixel_readback.size != square_texels.size:
        _pixel_readback = SaTexture.new(square_texels.size, format)
    var covered: Dictionary = {}
    for piece: Array in pieces:
        var source: SaTexture = piece[0]
        var part: Rect2i = piece[2]
        var texels := texels_of(part, density)
        var origin: Vector2i = piece[1]
        var source_pos := texels.position - texels_of(Rect2i(origin, Vector2i.ONE), density).position
        var target := texels.position - square_texels.position
        rd.texture_copy(
            source.rid,
            _pixel_readback.rid,
            Vector3(source_pos.x, source_pos.y, 0),
            Vector3(target.x, target.y, 0),
            Vector3(texels.size.x, texels.size.y, 1),
            0,
            0,
            0,
            0
        )
        for y in range(target.y, target.y + texels.size.y):
            for x in range(target.x, target.x + texels.size.x):
                covered[y * span + x] = true

    var data: PackedByteArray = rd.texture_get_data(_pixel_readback.rid, 0)
    var averaged := _mean(data, format, covered.keys())
    _last_sample_pos = centre
    _last_sample_from = from
    _last_sample_size = side
    _last_sample_color = averaged
    return averaged


## *rect* in document pixels as the texels of a layer stored at *density*.
## White Point's averaged pick takes its squares the same way.
static func texels_of(rect: Rect2i, density: float) -> Rect2i:
    var start := Vector2i(floori(rect.position.x * density), floori(rect.position.y * density))
    var end := Vector2i(floori(rect.end.x * density), floori(rect.end.y * density))
    return Rect2i(start, end - start)


## The mean of the texels *indices* of *data*, its colour weighted by each
## texel's alpha and its alpha the plain mean. A texel is stored straight, so a
## transparent one inside a painted chunk still carries a colour, black for one
## nobody painted, and averaged as it stands it pulled the pick towards that
## colour at a stroke's soft edge. Weighted, it adds coverage and no hue,
## the way a chunk nobody painted already added nothing.
static func _mean(data: PackedByteArray, format: int, indices: Array) -> Color:
    if indices.is_empty():
        return SaFieldSpec.NO_PAINT
    var colour := Vector3.ZERO
    var alpha := 0.0
    for index: int in indices:
        var texel := SaFieldSpec.decode_texel(data, format, index)
        colour += Vector3(texel.r, texel.g, texel.b) * texel.a
        alpha += texel.a
    if alpha <= 0.0:
        return SaFieldSpec.NO_PAINT
    colour /= alpha
    return Color(colour.x, colour.y, colour.z, alpha / float(indices.size()))


func reset() -> void:
    # ALT borrows this tool, and letting go of ALT before the button hands the
    # tool back with the release still to come. The pick already set the
    # foreground, so it is a use, and it is committed here rather than lost.
    _commit_pick()
    _last_sample_pos = Vector2i(-1, -1)
    # A tool swapped away mid-drag would otherwise come back believing the
    # button is still down, and sample on the first hover.
    _dragging = false
    # A tool swapped away between a motion and the next tick would otherwise
    # sample once more on a frame this tool is no longer active for.
    _sample_pending = false
