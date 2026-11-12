## Filter > Apply Again runs the last filter with its last
## settings.
##
## The dialog keeps, on Apply, the filter, its
## widgets' values and the way, and the Filter menu's top row runs them again
## on the active layer with no dialog, as one history step, disabled until a
## filter has been applied. A filter whose module is gone or a way the layer
## refuses leaves the layer alone and says why on the status line.
##
## The painting is two layers holding the same paint, one opaque chunk at the
## left of a document two chunks across, so a blur changes the edges it has
## and spreads nothing the two could disagree on.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const PAINT := Color(0.75, 0.25, 0.125, 1.0)
## A radius away from the slider's default, so a run on the defaults would
## not read equal by accident.
const RADIUS := 17.0
const OWNER := &"sara-base-modules"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _bar: TopMenuBar = null
var _blur: StringName = &""
var _first: SaLayer = null
var _second: SaLayer = null
## Every line the status line was told, in order.
var _said: Array[String] = []
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaProblems.announce = false
    _said.clear()
    EventBus.stroke_explained.connect(_on_said)

    _surface = Fixtures.make_surface(SIZE)
    _doc = _surface.easel.document
    _registries = Fixtures.make_registries(_surface)
    _surface.easel.compositor.filter_chain.registry = _registries.filters
    _blur = SaFilterRegistry.key_for(OWNER, SaGaussianBlurFilter.new())
    _registries.filters.register(SaGaussianBlurFilter.new(), OWNER)

    _first = _doc.get_node("Layer 1") as SaLayer
    _first.get_or_create_chunk(LEFT).clear(PAINT)
    _second = SaLayerOps.new(_doc).add()
    _second.name = "Second"
    _second.get_or_create_chunk(LEFT).clear(PAINT)
    _doc.history.reset()
    _doc.undo_redo.clear_history()

    _host = Node.new()
    _host.name = "U11TestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = _registries.layer_types
    _window.watch(_registries.filters)
    _host.add_child(_window)

    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    (_bar.menu("Filter") as SaFilterMenu).filters = _registries.filters


func after_each() -> void:
    EventBus.stroke_explained.disconnect(_on_said)
    SaStrokeNote.say("")
    SaFilterAgain.forget(_registries.filters)
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
    _window.free()
    _canvas.free()
    _bar.free()
    _host.free()
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    SaProblems.announce = true


func _on_said(line: String) -> void:
    _said.append(line)


## The blur applied through the dialog on *layer*, at [constant RADIUS], the
## way *way* or Apply.
func _apply_through_the_dialog(layer: SaLayer, way: String = "bake") -> void:
    _doc.set_active_layer(layer)
    assert_true(_registries.filters.invoke(_blur), "The Filter menu's door opens the blur")
    var tree := Engine.get_main_loop() as SceneTree
    if way != "bake":
        SaFilterDialogWindow.capture(tree, {"way": way})
    SaFilterDialogWindow.capture(tree, {"widget": "radius", "value": RADIUS})
    _window.dialog.flush_rerun()
    _window.apply_filter()


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## Every texel of *layer*'s chunk at *grid_pos*, or empty where it has none.
func _bytes(layer: SaLayer, grid_pos: Vector2i) -> PackedByteArray:
    if not layer.chunks.has(grid_pos):
        return PackedByteArray()
    return GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid_pos).rid, 0)


## The Filter menu, filled afresh as a press on its title fills it.
func _menu() -> SaFilterMenu:
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.populate()
    return menu


func _row_text(menu: SaFilterMenu) -> String:
    var button := menu.popup.label_button(SaMenu.key(SaFilterMenu.ID_APPLY_AGAIN))
    return button.text if button != null else ""


func test_the_row_is_disabled_until_a_filter_is_applied_and_then_names_it() -> void:
    var menu := _menu()
    var row := SaMenu.key(SaFilterMenu.ID_APPLY_AGAIN)
    assert_eq(menu.popup.row_ids().find(row), 0, "Apply Again is the Filter menu's first row")
    assert_eq(_row_text(menu), "Apply Filter Again", "named after no filter before one is applied")
    assert_true(menu.popup.is_disabled(row), "and disabled")
    assert_false(menu.popup.press_row(row), "so a press does not reach it")
    assert_eq(menu.chord_of(SaFilterAgain.COMMAND), "Ctrl+F", "Its chord is Krita's")
    var before := _bytes(_second, LEFT)
    var steps := _steps()
    assert_false(_registries.commands.execute(SaFilterAgain.COMMAND), "The chord's command runs nothing")
    assert_eq(_steps(), steps, "takes no step")
    assert_eq(_bytes(_second, LEFT), before, "and leaves the layer as it was")

    _apply_through_the_dialog(_first)
    menu = _menu()
    assert_eq(_row_text(menu), "Apply Gaussian Blur Again", "Once a blur is applied the row names it")
    assert_false(menu.popup.is_disabled(row), "and can be pressed")
    # What a suite before this one applied showed in its menu once, when one
    # record served the whole process.
    assert_false(SaFilterAgain.remembered(SaFilterRegistry.new()), "Another registry has applied nothing")


func test_apply_again_blurs_a_second_layer_as_the_dialog_blurred_the_first() -> void:
    var painted := _bytes(_first, LEFT)
    var steps := _steps()
    _apply_through_the_dialog(_first)
    assert_eq(_steps(), steps + 1, "The dialog's Apply is one step")
    assert_true(_bytes(_first, LEFT) != painted, "and blurs the first layer's edges")
    assert_eq(_bytes(_second, LEFT), painted, "while the second holds the paint the first had")

    _doc.set_active_layer(_second)
    steps = _steps()
    assert_true(_registries.commands.execute(SaFilterAgain.COMMAND), "Apply Again runs on the second layer")
    assert_false(_window.visible, "with no dialog")
    assert_eq(_steps(), steps + 1, "as one history step")
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        assert_true(
            _bytes(_second, grid_pos) == _bytes(_first, grid_pos),
            "and the second layer's texels at %s equal the first's, the radius kept" % grid_pos
        )
    assert_eq(_said.back() if not _said.is_empty() else "", "", "The status line says nothing against it")

    _doc.undo_redo.undo()
    assert_eq(_bytes(_second, LEFT), painted, "Undo takes the one step back")


func test_attach_is_repeated_as_an_attach() -> void:
    var painted := _bytes(_second, LEFT)
    _apply_through_the_dialog(_first, "attach")
    assert_eq(_first.filters.size(), 1, "The dialog's Attach puts one record on the first layer")

    _doc.set_active_layer(_second)
    var steps := _steps()
    assert_true(_registries.commands.execute(SaFilterAgain.COMMAND), "Apply Again runs on the second layer")
    assert_eq(_steps(), steps + 1, "as one history step")
    assert_eq(_second.filters.size(), 1, "and attaches one record there")
    assert_eq(_second.filters[0].key, _blur, "of the blur")
    assert_eq(_second.filters[0].parameters, _first.filters[0].parameters, "with the settings the dialog attached")
    assert_eq(float(_second.filters[0].parameters.get("radius", 0.0)), RADIUS, "the radius among them")
    assert_eq(_bytes(_second, LEFT), painted, "and writes no pixel")
    assert_eq(_first.filters.size(), 1, "The first layer keeps its one record")


func test_a_way_the_layer_refuses_leaves_it_alone_and_says_why() -> void:
    _apply_through_the_dialog(_first)
    _second.is_locked = true
    _doc.set_active_layer(_second)
    var painted := _bytes(_second, LEFT)
    var steps := _steps()
    assert_false(_registries.commands.execute(SaFilterAgain.COMMAND), "A bake into a locked layer is refused")
    assert_eq(_steps(), steps, "takes no step")
    assert_eq(_bytes(_second, LEFT), painted, "and leaves the layer alone")
    assert_false(_said.is_empty(), "The status line is told")
    assert_true(_said.back().contains("locked"), "why: %s" % [_said])


func test_a_filter_whose_module_is_gone_leaves_the_layer_alone_and_says_why() -> void:
    _apply_through_the_dialog(_first)
    _registries.filters.unregister_module(OWNER)
    _doc.set_active_layer(_second)
    var painted := _bytes(_second, LEFT)
    var steps := _steps()
    assert_false(_registries.commands.execute(SaFilterAgain.COMMAND), "Apply Again finds no blur to run")
    assert_eq(_steps(), steps, "takes no step")
    assert_eq(_bytes(_second, LEFT), painted, "and leaves the layer alone")
    assert_false(_said.is_empty(), "The status line is told")
    assert_true(_said.back().contains("Gaussian Blur cannot be applied again"), "why, naming the filter: %s" % [_said])
    assert_eq(_row_text(_menu()), "Apply Gaussian Blur Again", "and the row still names what it would run")
