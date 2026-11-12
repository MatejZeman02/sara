## A toggle on the top bar makes the document's new paint layers at double
## resolution.
##
## The toggle sits on the top menu bar and makes new paint layers at twice the
## document's density. The bar's button drives the switch on the document in front, Layer > New, the Layers
## docker's button and its menu read it, an empty layer is raised when it is
## turned on, a painted one is never resampled, and the `.sad` keeps it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## A file written before the switch existed.
const BEFORE := "res://tests/data/plain_v4.sad"

static var scratch_sad: String = SaDataRoot.path("double-resolution.sad")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _canvas: SaCanvas = null
var _layers: LayersDocker = null
var _host: Node = null
var _doc: SaDocument = null
var _was_placeable: bool = false


func before_each() -> void:
    _was_placeable = SaSettings.is_placeable(SaTopBarDoubleResolution.CATEGORY, SaTopBarDoubleResolution.ELEMENT)
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.bind_registries(_registries.blend_modes, _registries.layer_types)
    _host = Node.new()
    _host.name = "DoubleResolutionTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _was_placeable:
        SaTopBarDoubleResolution.register()
    else:
        SaSettings.unregister_layout_element(SaTopBarDoubleResolution.CATEGORY, SaTopBarDoubleResolution.ELEMENT)
    if FileAccess.file_exists(scratch_sad):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_sad))
    _host.free()
    _host = null
    _layers.free()
    _layers = null
    _canvas.free()
    _canvas = null
    _registries = null
    _doc = null
    Fixtures.teardown(_surface)
    _surface = null


## The bar's button, from the call the top bar makes, driving this suite's
## document.
func _button() -> Button:
    var bar := Control.new()
    _host.add_child(bar)
    var home := SaTopBarDoubleResolution.home(bar, func() -> SaDocument: return _doc)
    return home[SaTopBarDoubleResolution.ELEMENT]


## A press on *button*, as the pointer's toggle sends it.
func _press(button: Button, wanted: bool) -> void:
    button.button_pressed = wanted
    SaTopBarDoubleResolution.follower_of(button).sync()


func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


func test_the_element_is_on_the_top_bar_after_environment_view_with_its_tooltip() -> void:
    var button := _button()
    var placeable := SaSettings.is_placeable(SaTopBarDoubleResolution.CATEGORY, SaTopBarDoubleResolution.ELEMENT)
    assert_true(placeable, "a TopMenuBar element with a view")
    var order: Array = SaSettingsLayout.DEFAULT_ORDERS["TopMenuBar"]
    assert_eq(order.find("Double Resolution"), order.find("Environment View") + 1, "after Environment View on a fresh bar")
    assert_true(button.toggle_mode, "a toggle")
    var tip := button.tooltip_text
    assert_true(tip.contains("four times the texels"), "its tooltip says what a new layer holds: %s" % tip)
    assert_true(button.tooltip_text.contains("left as they are"), "and that painted layers stay: %s" % button.tooltip_text)


func test_on_raises_the_empty_first_layer_and_every_way_of_making_one_reads_it() -> void:
    var first := _doc.active_layer
    assert_almost_eq(first.resolution_scale, 1.0, 1e-6, "a fresh document's first layer starts at 1.0")
    assert_true(first.chunks.is_empty(), "and holds no chunk")
    var button := _button()
    _press(button, true)
    assert_true(_doc.double_resolution.on, "the press turns the document's switch on")
    assert_true(button.button_pressed, "and the button shows it")
    assert_almost_eq(first.resolution_scale, 2.0, 1e-6, "the empty first layer is raised to 2.0")

    assert_true(_registries.commands.execute(&"layer_new_paint"), "Layer > New makes a layer")
    var from_menu := _doc.active_layer
    assert_almost_eq(from_menu.resolution_scale, 2.0, 1e-6, "Layer > New makes it at 2.0")
    _layers.actions.add_layer()
    var from_button := _doc.active_layer
    assert_true(from_button != from_menu, "the docker's button makes a layer")
    assert_almost_eq(from_button.resolution_scale, 2.0, 1e-6, "the docker's button makes it at 2.0")
    var rows := SaLayerMenuRows.new(_doc, null, _registries.layer_types)
    assert_true(rows.run(SaLayerTypeDescriptor.PLAIN), "the docker's menu makes a paint layer")
    var from_rows := _doc.active_layer
    assert_almost_eq(from_rows.resolution_scale, 2.0, 1e-6, "the docker's menu makes it at 2.0")
    var named := SaLayerOps.new(_doc).add(&"", null, 1.0)
    assert_almost_eq(named.resolution_scale, 1.0, 1e-6, "a caller that names 1.0 still gets 1.0")

    _press(button, false)
    assert_false(_doc.double_resolution.on, "the second press turns it off")
    assert_true(_registries.commands.execute(&"layer_new_paint"), "Layer > New again")
    assert_almost_eq(_doc.active_layer.resolution_scale, 1.0, 1e-6, "with it off a new layer is at 1.0")
    for layer: SaLayer in [first, from_menu, from_button, from_rows]:
        assert_almost_eq(layer.resolution_scale, 2.0, 1e-6, "and %s stays at 2.0" % layer.name)


func test_a_layer_with_paint_is_never_resampled() -> void:
    var painted := _doc.active_layer
    _doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0), painted)
    var before := _bytes(painted)
    assert_false(before.is_empty(), "the layer holds paint")
    _doc.double_resolution.turn(_doc, true)
    assert_almost_eq(painted.resolution_scale, 1.0, 1e-6, "a painted layer stays at 1.0 when the switch turns on")
    var after := _bytes(painted)
    assert_eq(after.keys(), before.keys(), "with the same chunks")
    for grid_pos: Vector2i in before:
        assert_true(after[grid_pos] == before[grid_pos], "chunk %s byte for byte as before" % grid_pos)
        assert_eq(painted.chunks[grid_pos].pixel_size(), 256, "and still 256 texels across")


func test_a_ground_keeps_its_scale() -> void:
    _doc.double_resolution.turn(_doc, true)
    assert_almost_eq(SaDoubleResolution.new().scale_for(_doc.active_layer), 1.0, 1e-6, "an off switch answers 1.0")
    var group := SaLayer.new()
    group.is_group = true
    assert_almost_eq(_doc.double_resolution.scale_for(group), 1.0, 1e-6, "a group stores no paint and keeps 1.0")
    group.free()


func test_the_switch_is_saved_and_a_file_from_before_opens_with_it_off() -> void:
    _doc.double_resolution.turn(_doc, true)
    assert_eq(SaExport.save_sad(_doc, scratch_sad, 0), OK, "the document saves")
    var opened := Fixtures.make_surface(Vector2i(512, 512))
    assert_false(opened.easel.document.double_resolution.on, "a fresh document starts with it off")
    assert_eq(SaExport.load_sad(opened.easel.document, scratch_sad, opened.easel.compositor), OK, "the file opens")
    assert_true(opened.easel.document.double_resolution.on, "and reads the switch on")
    opened.easel.document.double_resolution.turn(opened.easel.document, true)
    assert_eq(SaExport.load_sad(opened.easel.document, BEFORE, opened.easel.compositor), OK, "a file from before opens")
    assert_false(opened.easel.document.double_resolution.on, "with the switch off")
    Fixtures.teardown(opened)
