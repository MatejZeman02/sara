## The cover a picker wears for a mask shows each colour at the
## lightness it paints.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## When a mask layer is chosen, the colour picker goes greyscale and must use
## Oklab lightness for it. The cover weighed the display numbers by Rec. 709's
## luminance, which is neither the document's own lightness nor the grey
## [SaColorStore] hands a pick back, so a colour under the cover and the same
## colour picked through it were two different greys.
##
## Six saturated colours and a ramp of greys are drawn into a viewport, an
## [SaGreyVeil] following a store of this suite's own is laid over them, the
## frame is read back, and every covered pixel has to be the grey the store
## gives for the colour under it, to within one step of an 8-bit channel. Each
## colour space a document can be opened in is run, because every number the
## cover draws by comes from the document's space.
extends "res://tests/test_framework.gd"

## The cover is a shader and the frame it draws is read off a device.
const REQUIRES_GPU := true

static var scratch_path: String = SaDataRoot.path("test_colors.cfg")

## The row under the cover as 8-bit levels: red, yellow, green, cyan, blue and
## magenta, then a ramp from black to white. The levels are written out so the
## colour the store is asked about is exactly the colour the picture holds.
const SHOWN: Array[Vector3i] = [
    Vector3i(255, 0, 0),
    Vector3i(255, 255, 0),
    Vector3i(0, 255, 0),
    Vector3i(0, 255, 255),
    Vector3i(0, 0, 255),
    Vector3i(255, 0, 255),
    Vector3i(0, 0, 0),
    Vector3i(26, 26, 26),
    Vector3i(64, 64, 64),
    Vector3i(128, 128, 128),
    Vector3i(191, 191, 191),
    Vector3i(255, 255, 255),
]

## Each colour a block this many pixels square, read at its middle, so a half
## pixel anywhere in the cover's fit would show rather than hide.
const BLOCK := 4

## One step of an 8-bit channel, the clause's own slack.
const A_STEP := 1

var _hosts: Array[Node] = []


func after_each() -> void:
    for host: Node in _hosts:
        host.free()
    _hosts.clear()
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


## A document in *space* whose first layer has a mask that is the paint target,
## and a store of this suite's own following it, so the app's pair is left as
## the painter had it.
func _bench(space: SaColorSpace) -> SaColorStore:
    var host := Node.new()
    host.name = "TestHost"
    EventBus.add_child(host)
    _hosts.append(host)
    var easel := SaEasel.create_default(Vector2i(32, 32), null, space)
    host.add_child(easel)
    var document := easel.document
    var layer := document.active_layer
    assert_true(SaMaskOps.new(document).run(SaMaskOps.ADD, layer), "the layer takes a mask")
    var store := SaColorStore.new()
    store.path = scratch_path
    host.add_child(store)
    store.follow(document)
    document.mask_target = layer.mask
    assert_true(store.masking, "the mask as the target greys the store")
    return store


## [constant SHOWN] as a picture one texel a pixel, each colour a block wide.
func _row() -> Image:
    var image := Image.create(SHOWN.size() * BLOCK, BLOCK, false, Image.FORMAT_RGB8)
    for i in SHOWN.size():
        image.fill_rect(Rect2i(i * BLOCK, 0, BLOCK, BLOCK), _level(i))
    return image


static func _level(index: int) -> Color:
    var v := SHOWN[index]
    return Color8(v.x, v.y, v.z)


## The row drawn into a viewport with *store*'s cover over it, read back as the
## frame a painter sees.
##
## The cover is a real [SaGreyVeil] under a control of the row's size, so it
## fits itself and pushes the document's numbers into its material as it enters
## the tree, which is what a docker built while a mask is the target does. Only
## the two rectangles are put down through the server rather than by the nodes'
## own `_draw`: a suite cannot let a frame pass, and a control's drawing waits
## on the message queue the main loop flushes, so a node added here has drawn
## nothing by the time [method RenderingServer.force_draw] returns. The rect
## the cover is drawn over is the one the cover fitted for itself.
func _covered(store: SaColorStore) -> Image:
    var size := Vector2i(SHOWN.size() * BLOCK, BLOCK)
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var holder := Control.new()
    holder.size = Vector2(size)
    viewport.add_child(holder)
    var veil := SaGreyVeil.new(store)
    holder.add_child(veil)
    assert_true(veil.visible, "the cover shows itself over the row")
    assert_eq(veil.size, Vector2(size), "the cover is fitted to what it covers")
    var canvas := viewport.find_world_2d().canvas
    var row := ImageTexture.create_from_image(_row())
    var under := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(under, canvas)
    RenderingServer.canvas_item_set_draw_index(under, 0)
    RenderingServer.canvas_item_set_default_texture_filter(under, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(under, Rect2(Vector2.ZERO, Vector2(size)), row.get_rid())
    var over := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(over, canvas)
    RenderingServer.canvas_item_set_draw_index(over, 1)
    RenderingServer.canvas_item_set_material(over, (veil.material as ShaderMaterial).get_rid())
    RenderingServer.canvas_item_add_rect(over, Rect2(veil.global_position, veil.size), Color.WHITE)
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(over)
    RenderingServer.free_rid(under)
    viewport.free()
    return image


## The grey the store paints *shown* as, through the door a pick goes through:
## the colour is given to the store, and what comes back is the grey.
static func _store_grey(store: SaColorStore, shown: Color) -> Color:
    store.foreground = shown
    return store.foreground


## Every colour of the row covered in a document of *space* reads as the grey
## the store gives for it.
func _assert_cover_is_the_store(space: SaColorSpace, what: String) -> void:
    var store := _bench(space)
    var frame := _covered(store)
    for i in SHOWN.size():
        var shown := _level(i)
        var want := _store_grey(store, shown)
        var got := frame.get_pixel(i * BLOCK + (BLOCK >> 1), BLOCK >> 1)
        var level := roundi(want.r * 255.0)
        assert_true(
            absi(got.r8 - level) <= A_STEP, "%s: %s is covered as %d, the store paints it as %d" % [what, SHOWN[i], got.r8, level]
        )
        assert_eq(Vector2i(got.g8, got.b8), Vector2i(got.r8, got.r8), "%s: %s is covered by a grey" % [what, SHOWN[i]])


## The default new document, whose lightness is Oklab's own L.
func test_an_oklab_document_covers_by_oklabs_lightness() -> void:
    _assert_cover_is_the_store(SaColorSpace.oklab_srgb_gamma30(), "an Oklab document")


## Oklab over a wider gamut, which carries a picked colour into linear sRGB
## through a matrix that is not the identity. A matrix handed to the shader the
## wrong way round reads here and nowhere else.
func test_an_oklab_document_over_display_p3_covers_by_its_own_carry() -> void:
    _assert_cover_is_the_store(SaColorSpace.oklab_p3(), "an Oklab document over Display P3")


## An RGB document, where the lightness is the luminance of the document's own
## primaries over the stored numbers, curve and all.
func test_an_srgb_document_covers_by_its_own_luminance() -> void:
    _assert_cover_is_the_store(SaColorSpace.srgb(), "an sRGB document")


## The same with no curve at all, so the luminance is over light-linear values
## and the greys bend the other way.
func test_a_linear_document_covers_by_its_own_luminance() -> void:
    _assert_cover_is_the_store(SaColorSpace.linear_srgb(), "a linear sRGB document")


## And with wider primaries, whose luminance row is not sRGB's.
func test_a_display_p3_document_covers_by_its_own_luminance() -> void:
    _assert_cover_is_the_store(SaColorSpace.display_p3(), "a Display P3 document")


## With no document there is no lightness to take, and the store paints the
## peak channel. The cover's table is the ramp that leaves that peak alone, so
## the two still agree.
func test_with_no_document_the_table_leaves_the_peak_alone() -> void:
    var rule := SaColorStore.MaskGrey.new(null)
    assert_eq(rule.rule, SaColorStore.MaskGrey.PEAK, "with no space the peak is the coverage")
    for i in rule.greys.size():
        var cover := float(i) / float(rule.greys.size() - 1)
        assert_almost_eq(rule.greys[i], cover, 1.0e-6, "the peak's own grey is the peak")


## The table the cover reads a grey out of is the store's own bisection rather
## than a second inverse: every grey in it is one the store hands back
## unchanged, which is the store's promise that a pick of what the cover shows
## paints what it shows.
func test_the_table_holds_the_stores_own_greys() -> void:
    var store := _bench(SaColorSpace.oklab_srgb_gamma30())
    var rule := store.mask_grey()
    assert_eq(rule.rule, SaColorStore.MaskGrey.OKLAB, "an Oklab document asks for Oklab's L")
    assert_almost_eq(rule.greys[0], 0.0, 1.0e-6, "the table starts at black")
    assert_almost_eq(rule.greys[rule.greys.size() - 1], 1.0, 1.0e-6, "and ends at white")
    var before := -1.0
    for i in rule.greys.size():
        var grey: float = rule.greys[i]
        assert_true(grey > before, "entry %d is lighter than the one before it" % i)
        before = grey
        assert_almost_eq(_store_grey(store, Color(grey, grey, grey)).r, grey, 1.0e-5, "entry %d is its own grey" % i)
