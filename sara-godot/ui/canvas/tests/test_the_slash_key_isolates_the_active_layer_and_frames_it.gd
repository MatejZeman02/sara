## The slash key isolates the active layer and frames it, as
## Blender's local view does.
##
## The key hides everything and zooms to the layer (90% zoom out) and acts as a
## toggle.
##
## Every press is a key as a keyboard sends it, through the router over the
## application's whole map, so a second command on `/` would take it first.
## Three layers over a ground: a red square, a small green blob and a blue
## square, with the blob's layer active. The canvas is read off the easel's own
## output, and the view is the fixtures' view with a room of 1000 by 1000.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The proof is the canvas's pixels, which needs a RenderingDevice.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const GROUND := Color(0.5, 0.5, 0.5, 1.0)
const RED := Color(0.8, 0.1, 0.1, 1.0)
const GREEN := Color(0.1, 0.8, 0.2, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)
const RED_AT := Rect2i(0, 0, 200, 200)
const BLOB := Rect2i(300, 310, 40, 20)
const BLUE_AT := Rect2i(250, 0, 100, 100)
## Where each layer alone draws, and where only the ground does.
const POINTS: Array[Vector2i] = [Vector2i(50, 50), Vector2i(310, 315), Vector2i(300, 50), Vector2i(450, 450)]
## The view the painter left, turned so the rotation is seen to stay.
const ZOOM := 0.7
const PAN := Vector2(12.0, 34.0)
const TURN := 0.3

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _saved_events: Dictionary = {}
var _layers: Array[SaLayer] = []
var _paths: Array[String] = []


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _surface = Fixtures.make_surface(SIZE)
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _layers = _three()
    var view := _surface.view
    view.set_zoom(ZOOM)
    view.set_rotation(TURN)
    view.set_pan(PAN)


func after_each() -> void:
    SaLocalView.forget(_surface.easel.document)
    _router.free()
    _router = null
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## The slash as a keyboard sends it.
func _slash() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_SLASH
    event.physical_keycode = KEY_SLASH
    event.key_label = KEY_SLASH
    event.unicode = "/".unicode_at(0)
    event.pressed = true
    return event


## The ground grey, then a red square, the green blob and a blue square, each a
## layer of its own, the blob's layer active.
func _three() -> Array[SaLayer]:
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    var stack := ops.layers()
    doc.fill_layer(GROUND, stack[0])
    var red := stack[1]
    _paint(red, RED, RED_AT)
    var green := ops.add()
    _paint(green, GREEN, BLOB)
    var blue := ops.add()
    _paint(blue, BLUE, BLUE_AT)
    doc.set_active_layer(green)
    return [red, green, blue]


func _paint(layer: SaLayer, color: Color, rect: Rect2i) -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(rect)
    doc.fill_layer(color, layer)
    doc.selection.deselect()


func _canvas() -> Array[Color]:
    Bench.composite(_surface.easel)
    var found: Array[Color] = []
    for at in POINTS:
        found.append(Bench.texel(_surface.easel.output, at))
    return found


func _near(a: Color, b: Color, tolerance: float = 0.01) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= tolerance


func _eyes() -> Array[bool]:
    var eyes: Array[bool] = []
    for layer in SaLayerOps.new(_surface.easel.document).layers():
        eyes.append(layer.visible)
    return eyes


## `/` leaves the other two layers and the ground out of the canvas's pixels,
## moves no eye and writes no step, and frames the blob's box at 90 per cent
## of the room in one direction, centred, at the rotation it had. A second
## `/` gives the canvas and the view back as they were.
func test_slash_isolates_the_blob_frames_it_and_a_second_slash_puts_everything_back() -> void:
    var doc: SaDocument = _surface.easel.document
    var view := _surface.view
    var before := _canvas()
    assert_true(_near(before[0], RED) and _near(before[1], GREEN) and _near(before[2], BLUE), "Three layers drawn")
    var eyes := _eyes()
    var steps := doc.history.step_count()

    assert_true(_router.handle(_slash()), "The router takes the slash")
    assert_true(SaLocalView.is_on(doc), "and the document is isolated")
    var isolated := _canvas()
    assert_true(_near(isolated[1], GREEN), "The blob is drawn: %s" % isolated[1])
    for i: int in [0, 2, 3]:
        assert_true(isolated[i].a < 0.001, "and nothing else is, point %s: %s" % [POINTS[i], isolated[i]])
    assert_eq(_eyes(), eyes, "No eye moved")
    assert_eq(doc.history.step_count(), steps, "No step was written")

    var box := SaLocalView.painted_box(doc)
    assert_eq(box, BLOB, "The box is the blob's paint and not its chunk")
    var room := view.get_free_rect()
    var spans := SaView.rotated_extent(Vector2(box.size), view.get_rotation()) * view.get_zoom()
    var share := maxf(spans.x / room.size.x, spans.y / room.size.y)
    assert_true(absf(share - 0.9) < 0.001, "The blob spans 90 per cent of the room in one direction: %f" % share)
    assert_true(spans.x <= room.size.x * 0.9 + 0.01 and spans.y <= room.size.y * 0.9 + 0.01, "and no more in the other")
    var middle := view.document_to_screen(Rect2(box).get_center())
    assert_true(middle.distance_to(room.get_center()) < 0.01, "centred in the room: %s" % middle)
    assert_almost_eq(view.get_rotation(), TURN, 0.0001, "The rotation stays")

    assert_true(_router.handle(_slash()), "A second slash is taken")
    assert_false(SaLocalView.is_on(doc), "and isolation is off")
    var after := _canvas()
    for i in POINTS.size():
        assert_true(_near(after[i], before[i]), "The canvas is as before at %s: %s" % [POINTS[i], after[i]])
    assert_almost_eq(view.get_zoom(), ZOOM, 0.0001, "The zoom is back")
    assert_true(view.get_pan().distance_to(PAN) < 0.0001, "the pan is back: %s" % view.get_pan())
    assert_almost_eq(view.get_rotation(), TURN, 0.0001, "and the rotation")
    assert_eq(doc.history.step_count(), steps, "Still no step")


## An empty active layer frames the whole document at 90 per cent.
func test_an_empty_layer_frames_the_whole_document() -> void:
    var doc: SaDocument = _surface.easel.document
    var empty := SaLayerOps.new(doc).add()
    doc.set_active_layer(empty)
    assert_true(_router.handle(_slash()), "The router takes the slash")
    assert_eq(SaLocalView.painted_box(doc), Rect2i(), "The layer holds no paint")
    var view := _surface.view
    var room := view.get_free_rect()
    var spans := SaView.rotated_extent(Vector2(SIZE), view.get_rotation()) * view.get_zoom()
    var share := maxf(spans.x / room.size.x, spans.y / room.size.y)
    assert_true(absf(share - 0.9) < 0.001, "The document spans 90 per cent of the room: %f" % share)


## Picking another layer while isolated shows that layer instead, as Krita's
## Isolate Active Layer does, and the view stays where the slash put it.
func test_the_isolated_layer_follows_the_active_one() -> void:
    var doc: SaDocument = _surface.easel.document
    _router.handle(_slash())
    var zoom := _surface.view.get_zoom()
    doc.set_active_layer(_layers[0])
    var now := _canvas()
    assert_true(_near(now[0], RED), "The red square shows: %s" % now[0])
    assert_true(now[1].a < 0.001 and now[2].a < 0.001, "and the blob and the blue square do not")
    assert_almost_eq(_surface.view.get_zoom(), zoom, 0.0001, "The view did not move")


## A save and an export made while isolated hold every visible layer, and the
## canvas is isolated again once the frame ends.
func test_a_save_and_an_export_while_isolated_hold_every_layer() -> void:
    var doc: SaDocument = _surface.easel.document
    var easel := _surface.easel
    var before := _canvas()
    _router.handle(_slash())
    _canvas()

    var png := SaDataRoot.path("test_isolated_export.png")
    _paths.append(png)
    assert_eq(SaExport.export_png(easel, png), OK, "The export writes")
    var exported := Image.load_from_file(png)
    assert_not_null(exported, "and the picture loads")
    for i in POINTS.size():
        var at := exported.get_pixelv(POINTS[i])
        assert_true(_near(at, before[i], 0.01), "The export holds every layer at %s: %s" % [POINTS[i], at])

    var sad := SaDataRoot.path("test_isolated_save.sad")
    _paths.append(sad)
    var preview := SaExport.get_preview_image(easel)
    assert_eq(SaExport.save_sad(doc, sad, -1, preview), OK, "The save writes")
    for i in POINTS.size():
        var at := preview.get_pixelv(POINTS[i])
        assert_true(at.a > 0.99, "The save's preview holds every layer at %s: %s" % [POINTS[i], at])
    var loaded := SaEasel.create_default(SIZE)
    assert_eq(SaExport.load_sad(loaded.document, sad, loaded.compositor), OK, "and loads back")
    assert_false(SaLocalView.is_on(loaded.document), "and the loaded document is not isolated")
    var shown := 0
    for layer in SaLayerOps.new(loaded.document).layers():
        shown += 1 if layer.visible else 0
    assert_eq(shown, 4, "with the ground and all three layers shown")
    Bench.composite(loaded)
    for i in POINTS.size():
        var at := Bench.texel(loaded.output, POINTS[i])
        assert_true(_near(at, before[i]), "The saved document draws every layer at %s: %s" % [POINTS[i], at])
    loaded.free()

    # What the end of the frame runs, since a suite cannot await one.
    SaLocalView.resume(easel)
    assert_true(SaLocalView.is_on(doc), "Isolation is still on after the frame")
    var after := _canvas()
    assert_true(after[0].a < 0.001 and after[2].a < 0.001, "and the canvas is isolated again")
    assert_true(_near(after[1], GREEN), "with the blob drawn")
