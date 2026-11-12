## A layer's picture in its row, drawn on the GPU and never read back.
##
## The chunks are already in VRAM, so `thumbnail.gmacs` samples them into a
## texture of a few hundred texels and this shows that through a `Texture2DRD`,
## the way `minimap_docker.gd` shows the easel's output. Hard rule 1 (no CPU-GPU ping-pong) holds: no
## pixel makes the trip back to the CPU for a picture this small.
##
## A layer's picture frames the paint on it rather than the canvas, because a
## small mark on a wide canvas is a speck or bare checker. The box round the
## paint is found on the card by `thumb_bounds` and read there by the kernel
## that draws, so the CPU never learns it. The texture keeps the document's
## proportions and the kernel widens the frame to them, so the slot, the rim and
## the empty row's checker are the ones the canvas framing gives. A mask's
## picture, a ground's and a group's frame the whole canvas.
##
## A layer's picture is drawn over a two-tone checker, so paint too dark for the
## row's own ground to set off, black above all, still reads, and so a square
## says "nothing painted here" the way it does on the canvas. A layer with no
## paint at all has no picture to draw it over, so its row draws the same checker
## itself, which costs no texture. A mask's picture is coverage and carries none.
##
## A group has no chunks of its own, so its row shows a folder mark instead.
## A ground has none either, and its picture is its two colours, split on the
## diagonal, drawn from its parameters with no texture at all.
##
## The same control draws a layer mask's picture, the second one on a masked
## layer's row, bound through `bind_mask` rather than `bind_layer`: coverage as
## grey, white shown and black hidden.
class_name SaLayerThumbnail
extends TextureRect

## Texels along the longer edge. The box below is twenty-odd logical pixels
## tall, so anything larger is thrown away scaling down to it.
const MAX_EDGE := 32

## The smallest interval between two redraws, in seconds. A stroke marks the
## thumbnail dirty on every dab and a painter cannot read four pictures a
## second, let alone sixty.
const REFRESH_SECONDS := 0.25
## How long the pictures may spend redrawing in one frame, in microseconds. The
## first picture a frame takes is drawn whatever it costs, one picture after it
## waits for the next frame once the rest would not pay for it, and an
## adjustment layer's walk stops drawing positions when the share runs out, so
## a change that dirties every row of a stack of hundreds is drawn over the
## frames after it rather than in one.
const FRAME_BUDGET_USEC := 10000

## The box the picture is fitted into, in logical units.
const BOX := Vector2(32.0, 22.0)

const SHADER_NAME := "thumbnail"

## The kernel that finds the box round the paint, `thumbnail_bounds.gmacs`.
const BOUNDS_SHADER_NAME := "thumbnail_bounds"

## How many chunks one dispatch of `thumb_bounds` reads, one sampler each. The
## kernel declares this many and its push constant this many origins.
const BOUNDS_BATCH: int = 8

## How many floats [method _display_tail] writes. Six more sit in front of it, so
## the block is 24 floats and the 96 bytes `thumbnail.gmacs` declares.
const DISPLAY_TAIL_FLOATS: int = 18

## The two greys of the checker a layer's picture is drawn over, as display
## values, which is what the kernel leaves in the texture. Light enough that
## black paint and dark blue read on both, and close enough to each other that
## the squares do not fight the picture.
const CHECKER_LIGHT: float = 0.86
const CHECKER_DARK: float = 0.66

## How many squares of the checker fit along the picture's longer edge, before
## the floor of one texel a square. A 32 texel picture gets squares four texels
## across, eight to a row, where the box shows at least four whatever the
## document's shape.
const CHECKER_ACROSS: int = 8

## The folder a group's row carries instead of a picture.
const COLOR_MARK := Color(1.0, 1.0, 1.0, 0.55)

## How thick the rim around the picture's slot is, in logical units.
const RIM_WIDTH: float = 1.0

## How thick the rim is on the picture the brush is painting, the layer's or its
## mask's. Twice the plain rim, in the accent, so the pick reads at a glance
## from the row beside it.
const PICKED_WIDTH: float = 2.0

## The format the picture is kept in. Half floats, because this is a view of
## the paint rather than the paint: nothing is stored back from it, and a
## thumbnail of a 4K document is 8 KB rather than 16.
const FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT

## Past any document pixel, where the box round the paint starts its minimum
## and, negated, its maximum. `thumbnail_bounds.gmacs` holds the same number.
const FRAME_WIDE: int = 1 << 30

var _layer: SaLayer = null
var _document: SaDocument = null
var _texture: SaTexture = null
var _shown: Texture2DRD = null
var _compute: SaCompute = null

## The compute of `thumbnail_bounds.gmacs`, a layout of its own beside the
## picture's, so its eight chunk samplers never enter the picture's sets.
var _bounds: SaCompute = null

## What draws an adjustment layer's picture, made on its first redraw.
var _adjustment: SaBackdropThumbnail = null
## Whether the last redraw left its walk unfinished, so the next frame takes
## the rest without waiting out [constant REFRESH_SECONDS].
var _continuing: bool = false
## The deadline [method _settle] hands the redraw it takes, nought outside it,
## so a [method refresh] from anywhere else draws a walk whole.
var _until_usec: int = 0
## The frame the pictures last spent in, by `Engine.get_process_frames`, and
## the microseconds they spent there.
static var _spent_frame: int = -1
static var _spent_usec: int = 0
## Whether this frame is the rest after a frame that spent the whole share.
static var _resting := false

## Four ints on the card, the box round the layer's paint that `thumb_bounds`
## reduces and `thumb_chunk` frames the picture by. One buffer for the life of
## the row, so the uniform set built against it stays valid.
var _frame: SaCompute.Buffer = null
var _dirty: bool = true
var _waited: float = 0.0

## Whether the picture has been drawn since it was bound. Written by the two
## binds, which clear it, and by `refresh`.
var _drawn: bool = false
var _is_group: bool = false

## Whether the last redraw found the layer holding nothing, so that `_draw` puts
## the checker in the slot itself where there is no texture to carry it. Written
## by `refresh` and by the two binds, which clear it.
var _bare: bool = false

## A ground's two colours as the screen shows them, first and second, which
## `_draw` splits the slot between. Empty for every other layer. Written by
## `refresh` and by the two binds, which clear it.
var _ground: PackedColorArray = PackedColorArray()

## The mask this picture shows, or null for a layer's picture.
var _mask: SaMask = null

## What the slot was last drawn from, as [method _drawing] answers it. Written
## by `_draw` alone, so [method stale] can say a redraw is still queued.
var _drew: Array = []

## Whether this is the picture the brush paints into just now, which the rim
## says. Written by `show_picked` alone.
var picked: bool = false


func _init() -> void:
    custom_minimum_size = Vector2(SaUI.pxf(BOX.x), SaUI.pxf(BOX.y))
    expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size_flags_vertical = Control.SIZE_SHRINK_CENTER
    set_process(true)
    # The rim reads the palette every time it is drawn, and a theme swap moves
    # no pixel of this control on its own, so nothing would ask for that read.
    if EventBus:
        EventBus.theme_changed.connect(func(_id: String) -> void: queue_redraw())


## The side of one checker square, in texels of a picture of *picture* size: an
## eighth of the longer edge, never less than one texel. Static, like
## [method thumbnail_size], so the fit can be checked without a GPU.
static func checker_side(picture: Vector2i) -> int:
    return maxi(floori(float(maxi(picture.x, picture.y)) / float(CHECKER_ACROSS)), 1)


## The light squares of the checker over *rim*, the slot a picture of *picture*
## texels is fitted into, for the row to draw when a layer has no texture to carry
## the kernel's. The squares are the kernel's own: [method checker_side] texels a
## side, counted from the slot's corner, the light ones where the two coordinates
## of a square add to an even number. The dark ground is the rim itself. Clipped
## to the slot, so the last row and column of a picture that is not a whole
## number of squares stop at its edge.
static func checker_squares(rim: Rect2, picture: Vector2i) -> Array[Rect2]:
    var squares: Array[Rect2] = []
    if picture.x <= 0 or picture.y <= 0 or rim.size.x <= 0.0 or rim.size.y <= 0.0:
        return squares
    var side := checker_side(picture)
    var texel := Vector2(rim.size.x / float(picture.x), rim.size.y / float(picture.y))
    var across := ceili(float(picture.x) / float(side))
    var down := ceili(float(picture.y) / float(side))
    for j in down:
        for i in across:
            if (i + j) % 2 != 0:
                continue
            var square := Rect2(rim.position + Vector2(i, j) * float(side) * texel, Vector2(side, side) * texel)
            squares.append(square.intersection(rim))
    return squares


## The texture size for a document, longer edge first. Static so the fit can be
## checked without a GPU.
static func thumbnail_size(document_size: Vector2i) -> Vector2i:
    var longest := maxi(document_size.x, document_size.y)
    if longest <= 0:
        return Vector2i.ZERO
    if longest <= MAX_EDGE:
        return document_size
    var factor := float(MAX_EDGE) / float(longest)
    return Vector2i(maxi(int(round(document_size.x * factor)), 1), maxi(int(round(document_size.y * factor)), 1))


## Points the thumbnail at a layer. A group takes the folder mark and stops
## processing, because it holds no chunks to draw.
func bind_layer(layer: SaLayer, document: SaDocument) -> void:
    # The row redraws itself for a lock, a rename or a selection, and none of
    # those moved a pixel. Rebinding the same layer must not put the picture
    # back at the front of the queue, or a docker that refreshes often redraws
    # every thumbnail every time it does.
    if layer == _layer and document == _document and _mask == null:
        return
    _mask = null
    _layer = layer
    _document = document
    _drop_walk()
    _bare = false
    _ground = PackedColorArray()
    _is_group = layer != null and layer.is_group
    if _is_group:
        _release()
        set_process(false)
        queue_redraw()
        return
    texture = null
    queue_redraw()
    _dirty = true
    _drawn = false
    _waited = REFRESH_SECONDS
    set_process(true)


# A walk drawn for the layer bound before, unfinished or not, is no plate for
# the one bound now.
func _drop_walk() -> void:
    _adjustment = null
    _continuing = false


## Points the thumbnail at a layer's mask rather than at its paint. The picture
## is the coverage in grey, and it is drawn whatever the mask's `enabled` says,
## because a mask that is switched off still holds what it will hide when it
## comes back. The row dims it for that.
func bind_mask(mask: SaMask, document: SaDocument) -> void:
    if mask == _mask and document == _document:
        return
    _mask = mask
    _layer = null
    _document = document
    _drop_walk()
    _bare = false
    _ground = PackedColorArray()
    _is_group = false
    texture = null
    queue_redraw()
    _dirty = true
    _drawn = false
    _waited = REFRESH_SECONDS
    set_process(true)


## A picture for a mask, which takes the mouse unlike the layer's, only so
## that its tooltip shows: a tooltip on a control that ignores the pointer
## never does. PASS hands the press on to the row, which is where the list
## reads which picture it landed on.
static func for_mask() -> SaLayerThumbnail:
    var made := SaLayerThumbnail.new()
    made.name = "MaskThumbnail"
    made.mouse_filter = Control.MOUSE_FILTER_PASS
    made.add_child(SaMaskOffMark.new())
    return made


## Shows *mask* of *document*, with the picked rim when the brush paints it,
## veiled and crossed out by its `SaMaskOffMark` when it is switched off, and
## the tooltip saying what a Shift click does.
func show_mask(mask: SaMask, document: SaDocument, is_picked: bool) -> void:
    bind_mask(mask, document)
    show_picked(is_picked)
    _off_mark().show_off(not mask.enabled)
    tooltip_text = TranslationServer.translate(
        (
            "Layer mask. Click to paint the mask, Shift+click to switch it off. Click the thumbnail beside it to paint the layer."
            if mask.enabled
            else "Layer mask, switched off: it hides nothing. Shift+click to switch it on again."
        )
    )


## Whether the picture is veiled and crossed out, a mask switched off.
func is_dimmed() -> bool:
    return _off_mark() != null and _off_mark().visible


## The mark `for_mask` gave this picture, and null on a layer's.
func _off_mark() -> SaMaskOffMark:
    return get_node_or_null(^"MaskOffMark") as SaMaskOffMark


## Draws the rim as the picked one or as the plain one. The row asks, because
## only the document knows what the brush is painting into.
func show_picked(on: bool) -> void:
    if picked == on:
        return
    picked = on
    queue_redraw()


## Says the layer's pixels may have moved. Cheap: the redraw itself waits for
## the interval to pass.
func mark_dirty() -> void:
    _dirty = true
    wake()


## Asks each frame again whether a picture still owed is shown, which the list
## does after a scroll. One owed nothing or out of sight stops asking, which on
## a stack of 300 rows was 300 calls a frame during a stroke.
func wake() -> void:
    set_process(_dirty and not _is_group)


func _process(delta: float) -> void:
    if not _dirty:
        set_process(false)
        return
    if not _continuing:
        _waited += delta
        if _waited < REFRESH_SECONDS:
            return
    # The painter's Thumbnails while painting may ask for the pen to lift or
    # the painter to stop first. The interval has run out, so the frame the
    # button comes up or the idle clock speaks is the frame the picture is drawn.
    var shown := _in_view()
    if _held() or SaSadFile.opening() or not shown:
        set_process(shown)
        return
    var traced := SaFrameTrace.now()
    _settle_in_budget()
    SaFrameTrace.spent("layer rows", traced)


## Whether the row shows inside the list's scrolled view. A picture below the
## fold waits, dirty, until it is scrolled to, because a change marks every row
## and 540 rows each redrew after an eye's or a stroke's, a second of frames
## each a share longer for a door step to wait through. A list with no
## size yet, as in a suite, shows all of it.
func _in_view() -> bool:
    var clip := get_parent_control()
    while clip != null and not clip is ScrollContainer:
        clip = clip.get_parent_control()
    if clip == null or clip.size == Vector2.ZERO:
        return true
    return clip.get_global_rect().intersects(get_global_rect())


## Draws the picture when the frame's share has room, and answers whether it
## did. A walk under way waits for a frame with room for its next position,
## and one left over draws in a later frame, from [method _process].
func _settle_in_budget() -> bool:
    var left := _share_left(Engine.get_process_frames())
    var next := _adjustment.next_usec() if _continuing and _adjustment != null else 0
    if left < FRAME_BUDGET_USEC and next >= left:
        return false
    var start := Time.get_ticks_usec()
    _settle(start + maxi(left, 1))
    _spend(Engine.get_process_frames(), Time.get_ticks_usec() - start)
    return true


## Counts *usec* the rows took in this frame against the pictures' share, so
## the frame that built a deep file's rows draws no picture on top of them.
static func spend(usec: int) -> void:
    _spend(Engine.get_process_frames(), usec)


## What is left of this frame's share for the pictures, in microseconds, the
## whole of [constant FRAME_BUDGET_USEC] in a frame no picture has spent in,
## and nothing in the frame after one that spent all of it. A picture's walk
## leaves the device more to do than its microseconds here say, and the frame
## after one that spent the share drew 140 to 200 ms later on a large test document
## when it walked again, so it rests and the device catches up.
## Counted from what the pictures spent and not from the frame's start, so a
## suite that drives the pictures inside one long frame of its own is never
## starved by the time the frame took before it.
static func _share_left(frame: int) -> int:
    if frame != _spent_frame:
        var heavy := _spent_frame == frame - 1 and _spent_usec >= FRAME_BUDGET_USEC and not _resting
        _resting = heavy
        _spent_frame = frame
        _spent_usec = FRAME_BUDGET_USEC if heavy else 0
    return FRAME_BUDGET_USEC - _spent_usec


## Counts *usec* the pictures spent in *frame* against its share.
static func _spend(frame: int, usec: int) -> void:
    _share_left(frame)
    _spent_usec += usec


## Takes a redraw that is still waiting on the interval, now, and does nothing
## to a picture that is current or to one Thumbnails while painting holds, so a
## shot shows the picture the painter sees.
func settle() -> void:
    if _dirty and not _held():
        _settle()


## Draws the pictures under *root*, a row just built, at once while the
## frame's budget lasts, so a row is not bare for the interval. The rest have
## waited it out already and draw over the next frames, so a rebuild of
## hundreds of rows, which an open of a deep file is, does not draw every
## picture in its one frame.
static func settle_new(root: Node) -> void:
    for found: Node in root.find_children("*", "SaLayerThumbnail", true, false):
        (found as SaLayerThumbnail).settle_new_one()


## This picture's part of [method settle_new]: drawn now while the frame's
## budget lasts, and otherwise in a frame after, its interval taken as waited.
func settle_new_one() -> void:
    if _dirty and not _held() and not _settle_in_budget():
        _waited = REFRESH_SECONDS


## Whether the slot on screen is older than what it would draw now: a picture
## allocated or let go, the checker or a ground come or gone, or the rim moved,
## with the redraw that draws it still queued. A shot settles the pictures and
## then forces a frame, and a forced frame draws what the last redraw left, which
## after a crop or a rotation can name a texture the settle has just let go.
## The engine draws a freed texture as plain white, so the shot waits a frame
## while this holds. A slot that is not shown is never stale, because no frame
## draws it.
func stale() -> bool:
    return is_visible_in_tree() and _drawing() != _drew


## Settles every picture under *root*, and answers whether one shown is still
## to be drawn, so the shot is taken a frame later rather than of the frame a
## forced draw would make of the last redraw's leavings.
static func settle_all(root: Node) -> bool:
    if root == null:
        return false
    var stale_one := false
    for found: Node in root.find_children("*", "SaLayerThumbnail", true, false):
        var thumbnail := found as SaLayerThumbnail
        thumbnail.settle()
        stale_one = thumbnail.stale() or stale_one
    return stale_one


## What `_draw` draws from. The picture by its id rather than itself, because a
## reference kept here would hold a `Texture2DRD` past the texture it shows,
## which [method _release] lets go of in that order for a reason.
func _drawing() -> Array:
    var shown := texture.get_instance_id() if texture != null else 0
    return [shown, _bare, _ground, rim_rect(), picked, _is_group]


## Whether Thumbnails while painting holds the redraw now, or an adjustment's
## walk waits for the painter to stop, [method SaBackdropThumbnail.waits]. A
## picture not drawn since its bind is never held: a rebuild of the list binds
## every row afresh, and holding there would leave each slot empty until the
## painter stopped rather than showing the picture as it was a moment ago.
func _held() -> bool:
    if _adjustment != null and _adjustment.waits(_document, _layer):
        return true
    return _drawn and SaSettingsPerformance.holds_redraw(SaSettings.thumbnails_while_painting)


## The redraw a `mark_dirty` asked for, taken now, and the interval started again
## from it. With *until_usec*, a `Time.get_ticks_usec` deadline, an adjustment
## layer's walk stops when it passes and the picture stays dirty for the next
## frame to go on with.
func _settle(until_usec: int = 0) -> void:
    _waited = 0.0
    _dirty = false
    _until_usec = until_usec
    refresh()
    _until_usec = 0
    _continuing = _adjustment != null and _adjustment.pending()
    _dirty = _dirty or _continuing


## Redraws the picture now, whatever the interval says. The capture harness and
## the tests want the answer without waiting a quarter of a second for it.
func refresh() -> void:
    _drawn = true
    if _mask != null:
        _refresh_mask()
        return
    if _layer == null or _document == null or _layer.is_group:
        return
    _bare = false
    _ground = PackedColorArray()
    var wanted := thumbnail_size(_document.canvas_size)
    if wanted.x <= 0 or wanted.y <= 0:
        _release()
        return

    # A ground stores nothing, so there is no chunk to sample and none is
    # allocated for a picture (hard rule 3, sparse chunks). Its two colours are parameters on
    # the CPU already, so drawing them reads nothing back either.
    if _layer.is_generated():
        _release()
        _ground = ground_colors(_layer, _document.color_space)
        queue_redraw()
        return

    if SaBackdropThumbnail.takes(_layer):
        _refresh_adjustment(wanted, _until_usec)
        return

    # A layer with nothing painted on it has nothing to sample, and stopping here
    # is also what keeps the sampler binding below from having no texture. Its
    # picture is the checker alone, which `_draw` lays down without a texture,
    # so an empty layer still costs nothing and still reads as transparent.
    var source := _first_albedo()
    if source == null:
        _release()
        _bare = true
        queue_redraw()
        return

    var compute := _target(wanted)
    if compute == null:
        return
    var doc := Vector2(_document.canvas_size)
    var groups_x := SaCompute.groups_for(wanted.x)
    var groups_y := SaCompute.groups_for(wanted.y)

    var tail := _display_tail(_document.color_space, checker_side(wanted))

    _find_frame(doc)
    compute.set_sampled_texture(1, source.rid)
    compute.set_push_constant_float_array(_params(doc, Vector2.ZERO, Vector2.ONE, tail))
    # Its own list, so the barrier `list_end` inserts orders the clear before
    # every chunk that writes over part of it.
    compute.dispatch_kernel("thumb_clear", groups_x, groups_y, 1)

    # The document pixels a chunk covers, whatever texels it stores them at:
    # the kernel samples, so a chunk at 2.0 averages in.
    var extent := Vector2(SaChunk.SIZE, SaChunk.SIZE)
    if _layer.is_effect():
        _draw_result(compute, doc, extent, Vector2i(groups_x, groups_y), tail)
    else:
        compute.list_begin(compute.index_of_kernel("thumb_chunk"))
        for grid_pos: Vector2i in _layer.chunks:
            var chunk: SaChunk = _layer.chunks[grid_pos]
            var albedo := chunk.albedo() if chunk != null else null
            if albedo == null or not albedo.rid.is_valid():
                continue
            compute.set_sampled_texture(1, albedo.rid)
            compute.set_push_constant_float_array(_params(doc, Vector2(grid_pos * SaLayer.CHUNK_SIZE), extent, tail))
            compute.list_dispatch(groups_x, groups_y, 1)
        compute.list_end()

    if _shown != null:
        texture = _shown
    # Asked for by name, because the setter above returns early on the same
    # object and the kernel rewrote the texture underneath it. The engine draws
    # a frame only when something asked, so a refresh that asks for nothing
    # shows the old picture until the pointer moves.
    queue_redraw()


## Leaves the box round the layer's paint in the frame buffer, on the card, for
## `thumb_chunk` to frame the picture by. The seed goes up and nothing comes
## back: the CPU knows which chunks hold paint but not where in them, and asking
## would be the read back that hard rule 1, no CPU-GPU ping-pong, forbids for a picture.
##
## Every chunk inside the canvas is read, so the box is the paint's exactly
## whichever chunks hold it, an erased chunk at the edge of the grid included.
## Every thumbnail redraws on any change to the document, and a dispatch a
## chunk doubles a full layer's redraw on the CPU, so the chunks go
## [constant BOUNDS_BATCH] to a dispatch. A
## slot past the last chunk is bound to a chunk of the batch, because the
## layout wants every sampler, and the dispatch's depth stops short of it.
##
## The chunks go in a list of their own, ended before the picture's list
## begins, so the reduction is done before the picture reads it.
func _find_frame(doc: Vector2) -> void:
    _frame.update(PackedInt32Array([FRAME_WIDE, FRAME_WIDE, -FRAME_WIDE, -FRAME_WIDE]).to_byte_array())
    var bounds := _ensure_bounds()
    if bounds == null:
        return
    var canvas := Rect2i(Vector2i.ZERO, Vector2i(doc))
    var held: Array[SaChunk] = []
    var corners: Array[Vector2i] = []
    for grid_pos: Vector2i in _layer.chunks:
        var chunk: SaChunk = _layer.chunks[grid_pos]
        var albedo := chunk.albedo() if chunk != null else null
        if albedo == null or not albedo.rid.is_valid():
            continue
        var corner := grid_pos * SaLayer.CHUNK_SIZE
        if not Rect2i(corner, Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)).intersects(canvas):
            continue
        held.append(chunk)
        corners.append(corner)
    if held.is_empty():
        return

    bounds.set_storage("frame", _frame.rid)
    bounds.list_begin(0)
    for start in range(0, held.size(), BOUNDS_BATCH):
        var count := mini(BOUNDS_BATCH, held.size() - start)
        var widest := 0
        for slot in BOUNDS_BATCH:
            var chunk := held[start + mini(slot, count - 1)]
            bounds.set_sampled_texture(slot, chunk.albedo().rid)
            widest = maxi(widest, chunk.pixel_size())
        bounds.set_push_constant_float_array(_bounds_params(doc, corners, start, count))
        var groups := SaCompute.groups_for(widest)
        bounds.list_dispatch(groups, groups, count)
    bounds.list_end()


## The block `thumb_bounds` reads for the batch of *count* chunks from *start*:
## the document's size, a chunk's extent in document pixels, then where each of
## the batch's chunks sits, the x of every slot and then the y. Twenty floats,
## the 80 bytes `thumbnail_bounds.gmacs` declares, and a slot past *count* is
## nought, which the dispatch never reaches.
static func _bounds_params(document_size: Vector2, corners: Array[Vector2i], start: int, count: int) -> PackedFloat32Array:
    var packed := PackedFloat32Array([document_size.x, document_size.y, float(SaChunk.SIZE), float(SaChunk.SIZE)])
    packed.resize(4 + 2 * BOUNDS_BATCH)
    for slot in count:
        packed[4 + slot] = float(corners[start + slot].x)
        packed[4 + BOUNDS_BATCH + slot] = float(corners[start + slot].y)
    return packed


## An effect layer's picture, drawn from what it shows rather than from its
## chunks, which cache the input before its records run, so a kaleidoscope's
## row drawn from them would show the plain photograph. One dispatch
## each rather than one list, because the records run on the filter chain's own
## computes between two of them, and a list cannot open while another is.
func _draw_result(compute: SaCompute, doc: Vector2, extent: Vector2, groups: Vector2i, tail: PackedFloat32Array) -> void:
    for grid_pos: Vector2i in SaEffectLayer.result_positions(_document, _layer):
        var shown := SaEffectLayer.result_at(_document, _layer, grid_pos)
        if shown == null or not shown.rid.is_valid():
            continue
        compute.set_sampled_texture(1, shown.rid)
        compute.set_push_constant_float_array(_params(doc, Vector2(grid_pos * SaLayer.CHUNK_SIZE), extent, tail))
        compute.dispatch_kernel("thumb_chunk", groups.x, groups.y, 1)


## An adjustment layer's picture, which holds no chunk: its records' output
## over the backdrop it reads, drawn into a plate by [SaBackdropThumbnail]
## and sampled here like one chunk over the whole canvas. Nothing below it is
## the checker alone, as on an empty layer. A walk *until_usec* stopped keeps
## the picture from before until it is done, and has the frame drawn all the
## same, for the reason [method SaBackdropThumbnail.pending] gives.
func _refresh_adjustment(wanted: Vector2i, until_usec: int) -> void:
    if _adjustment == null:
        _adjustment = SaBackdropThumbnail.new()
    var shown := _adjustment.drawn(_document, _layer, until_usec)
    if shown == null and _adjustment.pending():
        queue_redraw()
        return
    if shown == null or not shown.rid.is_valid():
        _release()
        _bare = true
        queue_redraw()
        return
    var compute := _target(wanted)
    if compute == null:
        return
    var doc := Vector2(_adjustment.drawn_canvas)
    var groups_x := SaCompute.groups_for(wanted.x)
    var groups_y := SaCompute.groups_for(wanted.y)
    var tail := _display_tail(_adjustment.drawn_space, checker_side(wanted))
    # The plate frames the whole canvas, which an empty box says.
    _frame.update(PackedInt32Array([FRAME_WIDE, FRAME_WIDE, -FRAME_WIDE, -FRAME_WIDE]).to_byte_array())
    var reach := float(SaBackdropThumbnail.PLATE * SaBackdropThumbnail.reduction(_adjustment.drawn_canvas))
    compute.set_sampled_texture(1, shown.rid)
    compute.set_push_constant_float_array(_params(doc, Vector2.ZERO, Vector2(reach, reach), tail))
    compute.dispatch_kernel("thumb_clear", groups_x, groups_y, 1)
    compute.dispatch_kernel("thumb_chunk", groups_x, groups_y, 1)
    texture = _shown
    queue_redraw()


## The mask's picture. Every texel starts at the mask's rest, which is what a
## position it holds nothing at reads as, and each chunk of coverage is drawn
## over it. A mask with no chunk at all is a white picture, never an empty slot,
## because the painter has just added it and the row has to say it is there.
func _refresh_mask() -> void:
    if _document == null:
        return
    var wanted := thumbnail_size(_document.canvas_size)
    if wanted.x <= 0 or wanted.y <= 0:
        _release()
        return
    var compute := _target(wanted)
    if compute == null:
        return
    var doc := Vector2(_document.canvas_size)
    var groups_x := SaCompute.groups_for(wanted.x)
    var groups_y := SaCompute.groups_for(wanted.y)
    # Coverage is not colour, so the tail is only there to fill the block, and the
    # checker's side of nought is the block saying there is none.
    var tail := _display_tail(null)

    compute.set_sampled_texture(1, _mask.absent().rid)
    compute.set_push_constant_float_array(_params(doc, Vector2.ZERO, Vector2.ONE, tail))
    compute.dispatch_kernel("thumb_mask_clear", groups_x, groups_y, 1)

    var positions := _mask.grid_positions()
    if not positions.is_empty():
        compute.list_begin(compute.index_of_kernel("thumb_mask"))
        for grid_pos: Vector2i in positions:
            var coverage := _mask.texture_for(grid_pos)
            if coverage == null or not coverage.rid.is_valid():
                continue
            compute.set_sampled_texture(1, coverage.rid)
            var extent := float(coverage.size.x)
            var origin := Vector2(grid_pos * SaLayer.CHUNK_SIZE)
            compute.set_push_constant_float_array(_params(doc, origin, Vector2(extent, extent), tail))
            compute.list_dispatch(groups_x, groups_y, 1)
        compute.list_end()

    if _shown != null:
        texture = _shown
    queue_redraw()


## The picture's texture at *wanted*, allocated when the size moved, bound as
## the kernels' target, and the compute that binds it. Null when either cannot
## be had, and the caller then draws nothing. Shared by the layer's picture and
## the mask's, which differ only in the kernels they run over it.
func _target(wanted: Vector2i) -> SaCompute:
    if _texture == null or _texture.size != wanted:
        _allocate(wanted)
    if _texture == null or not _texture.rid.is_valid():
        return null
    var compute := _ensure_compute()
    if compute == null:
        return null
    compute.use_storage_format(_texture.format)
    compute.set_texture(0, _texture.rid)
    # Every kernel of the file takes the frame in its layout, so a mask's
    # picture binds it as well and never reads it.
    if _frame == null:
        _frame = SaCompute.Buffer.new(PackedInt32Array([0, 0, -1, -1]).to_byte_array())
    compute.set_storage("frame", _frame.rid)
    return compute


## The block both kernels read: where this chunk sits in the document, then what
## the numbers in it mean. The tail is built once per refresh, because it is the
## same for every chunk of one layer.
static func _params(
    document_size: Vector2, chunk_origin: Vector2, chunk_size: Vector2, tail: PackedFloat32Array
) -> PackedFloat32Array:
    var packed := PackedFloat32Array(
        [document_size.x, document_size.y, chunk_origin.x, chunk_origin.y, chunk_size.x, chunk_size.y]
    )
    packed.append_array(tail)
    return packed


## What the kernel needs to turn stored values into display ones: whether the
## document already is what the screen wants, which coordinate system its chunks
## hold, the way out to linear sRGB, and its transfer curve.
##
## The thumbnail is shown through a plain `Texture2DRD`, and Godot's 2D pipeline
## writes a canvas colour to the screen with no encode of its own, so the kernel
## has to leave display values behind. It did not, which is why an Oklab
## document's rows were red: L, a and b reached the screen as red, green and
## blue, and a near-neutral Oklab colour is a large first channel beside two
## small ones.
##
## The last three are the checker: the side of a square in texels, which is
## nought for a picture that has none, and its two greys.
##
## Eighteen floats, so the block ends at the 96 bytes the GLSL declares. Sending
## the matrix rather than generating it into the shader is the decision the
## compositor already took: a generated include is global to the compiler, and
## Sara runs more than one easel at a time.
static func _display_tail(space: SaColorSpace, checker: int = 0) -> PackedFloat32Array:
    var used := space if space != null else SaColorSpace.srgb()
    var transfer := used.transfer if used.transfer != null else SaTransferFunction.srgb()
    var packed := PackedFloat32Array([1.0 if used.is_display_ready() else 0.0, float(used.coordinates)])
    for column: Vector3 in SaColorSpace.basis_columns(used.to_linear_srgb_matrix()):
        packed.append(column.x)
        packed.append(column.y)
        packed.append(column.z)
    packed.append_array(transfer.to_params())
    packed.append_array(PackedFloat32Array([float(checker), CHECKER_LIGHT, CHECKER_DARK]))
    assert(packed.size() == DISPLAY_TAIL_FLOATS, "The thumbnail's colour tail is the wrong size")
    return packed


## *layer*'s two colours in display terms, the first and the second, which is
## what a ground's picture is split between. A ground with no second colour,
## the flat background, answers its first twice.
static func ground_colors(layer: SaLayer, space: SaColorSpace) -> PackedColorArray:
    var first: Color = layer.generator_params.get(SaGeneratedLayer.PARAM_COLOR, Color(0.5, 0.5, 0.5, 1.0))
    var second: Color = layer.generator_params.get(SaGeneratedLayer.PARAM_SECOND, first)
    if space != null:
        first = space.to_display(first)
        second = space.to_display(second)
    return PackedColorArray([first, second])


func _first_albedo() -> SaTexture:
    for grid_pos: Vector2i in _layer.chunks:
        var chunk: SaChunk = _layer.chunks[grid_pos]
        var albedo := chunk.albedo() if chunk != null else null
        if albedo != null and albedo.rid.is_valid():
            return albedo
    return null


func _ensure_compute() -> SaCompute:
    if _compute == null and not GlobalShaderCompiler.get_kernel_names(SHADER_NAME).is_empty():
        _compute = SaCompute.new(SHADER_NAME)
    return _compute


func _ensure_bounds() -> SaCompute:
    if _bounds == null and not GlobalShaderCompiler.get_kernel_names(BOUNDS_SHADER_NAME).is_empty():
        _bounds = SaCompute.new(BOUNDS_SHADER_NAME)
    return _bounds


func _allocate(wanted: Vector2i) -> void:
    _release()
    # A canvas resize changes the document's aspect without rebinding the layer,
    # and the rim is that aspect, so it has to be asked for again here.
    queue_redraw()
    _texture = SaTexture.new(wanted, FORMAT)
    if not _texture.rid.is_valid():
        _texture = null
        return
    # A fresh texture has undefined contents, and the first thing drawn over it
    # only covers the chunks that exist.
    _texture.clear(Color(0.0, 0.0, 0.0, 0.0))
    _shown = Texture2DRD.new()
    _shown.texture_rd_rid = _texture.rid


## The Texture2DRD goes first. It holds the RID the SaTexture is about to free,
## and a texture drawn from a freed RID is the crash this order exists to
## prevent.
func _release() -> void:
    texture = null
    _shown = null
    _texture = null


## Where the picture sits inside this control, in its own space, which is also
## what the rim frames. A `STRETCH_KEEP_ASPECT_CENTERED` TextureRect draws the
## document's aspect centred in whatever room it has, so the rim frames that
## rather than the whole control: a tall document gets a tall rim and not a wide
## one with the picture rattling inside it. Computed from the canvas size rather
## than from the texture, because an empty layer has no texture and is the case
## the rim exists for.
func rim_rect() -> Rect2:
    var box := Rect2(Vector2.ZERO, size)
    if box.size.x <= 2.0 or box.size.y <= 2.0:
        return Rect2()
    var doc := Vector2(_document.canvas_size) if _document != null else Vector2.ZERO
    var fitted := box.size
    if doc.x > 0.0 and doc.y > 0.0:
        fitted = doc * minf(box.size.x / doc.x, box.size.y / doc.y)
    return Rect2((box.size - fitted) * 0.5, fitted)


## What the rim is, for the capture harness. A photograph cannot say whether a
## one pixel line is a rim or the row behind it, or whether the row is empty,
## so the row says both. `space` is what the kernel was last told the stored
## numbers mean, so a dump can say the row converts and how.
##
## **The picture itself is not read back.** Hard rule 1 (no CPU-GPU ping-pong) allows export, the
## eyedropper and the `texel` capture step, and a fourth reader added to make a
## proof easier would be widening the rule rather than meeting it. The picture
## is drawn into the main window, so a shot carries it and `x`, `y`, `w` and `h`
## say exactly where, while what the canvas holds is the `texel` step's answer.
##
## **A redraw still waiting on the interval is taken first**. `empty` is whether
## the last redraw found paint, which waits a quarter of a second after
## `mark_dirty`, so a dump read ten frames after a fill read it as empty. The
## report answers the layer as it is now, and so does the picture drawn after.
func rim_report() -> Dictionary:
    settle()
    var box := rim_rect()
    return {
        "x": box.position.x,
        "y": box.position.y,
        "w": box.size.x,
        "h": box.size.y,
        "width": SaUI.pxf(RIM_WIDTH),
        "color": rim_color().to_html(false),
        "space": space_report(),
        "empty": _texture == null,
        "checker": _bare,
        "group": _is_group,
        # A ground's two colours as drawn, first then second, and nothing for
        # any other layer. The split is geometry on the CPU, so the report says
        # what it was drawn from rather than a photograph.
        "ground": Array(_ground).map(func(shown: Color) -> String: return shown.to_html(false)),
        # Whether this is a mask's picture, and whether the rim is the picked
        # one. Two pixels of accent are not something a scenario should have to
        # find in a photograph.
        "mask": _mask != null,
        "picked": picked,
    }


## What the kernel is told the stored numbers mean: whether the document is
## already what a screen wants, and which coordinate system its chunks hold.
##
## The first two floats of [method _display_tail], read from the document rather
## than from a copy of them, so the report cannot drift from what was sent. A
## row with no document answers the passthrough an sRGB one would.
func space_report() -> Dictionary:
    var space := _document.color_space if _document != null else null
    var used := space if space != null else SaColorSpace.srgb()
    return {
        "display_ready": used.is_display_ready(),
        "coordinates": SaColorSpace.coordinates_name(used.coordinates),
    }


## The rim's colour. The muted border of whatever palette is loaded, so a theme
## the painter picks moves the rim with the rest of the docker rather than
## leaving one hardcoded grey rectangle behind.
func rim_color() -> Color:
    return SaTheme.palette.border_secondary


## The rim every row carries, and the folder a group carries inside it.
##
## The rim marks where the picture goes, so an empty layer's row is no gap. It
## is drawn here rather than as a `StyleBoxFlat` panel, which would have to be a
## parent of this control, and the row builds it as a leaf.
##
## A group holds no chunks, so its row carries a folder inside the same rim.
## Drawn rather than loaded, for the reason the cursor ring is drawn: geometry
## cannot fail the way a missing icon file can, and the one icon in the set that
## reads as a frame is spent on the clip toggle beside it.
func _draw() -> void:
    _drew = _drawing()
    var rim := rim_rect()
    if rim.size.x <= 0.0 or rim.size.y <= 0.0:
        return
    if _bare and _document != null:
        draw_rect(rim, Color(CHECKER_DARK, CHECKER_DARK, CHECKER_DARK))
        for square: Rect2 in checker_squares(rim, thumbnail_size(_document.canvas_size)):
            draw_rect(square, Color(CHECKER_LIGHT, CHECKER_LIGHT, CHECKER_LIGHT))
    # A ground's picture, its first colour over the top left and its second
    # over the bottom right, so both of a paper's tones read in a slot this
    # small where its grain would not.
    if _ground.size() == 2:
        var corners := [rim.position, Vector2(rim.end.x, rim.position.y), rim.end, Vector2(rim.position.x, rim.end.y)]
        draw_colored_polygon(PackedVector2Array([corners[0], corners[1], corners[3]]), _ground[0])
        draw_colored_polygon(PackedVector2Array([corners[1], corners[2], corners[3]]), _ground[1])
    # Half the line width in, so the rim's outer edge lands on the picture's own
    # rather than half of it spilling into the row. An inset of a whole unit was
    # tried first and was wrong the other way: the fit already fills two of the
    # four edges, so the rim crossed the picture there and the capture showed a
    # doubled line down the right of every painted row.
    var line := SaUI.pxf(PICKED_WIDTH if picked else RIM_WIDTH)
    var color := SaTheme.palette.accent_primary if picked else rim_color()
    draw_rect(rim.grow(-line * 0.5), color, false, line)
    if not _is_group:
        return
    var box := rim.grow(-SaUI.pxf(3.0))
    if box.size.x <= 2.0 or box.size.y <= 2.0:
        return
    var lip := box.size.y * 0.28
    draw_rect(Rect2(box.position, Vector2(box.size.x * 0.5, lip * 2.0)), COLOR_MARK, false, 1.0)
    draw_rect(Rect2(box.position + Vector2(0.0, lip), box.size - Vector2(0.0, lip)), COLOR_MARK, false, 1.0)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _release()
