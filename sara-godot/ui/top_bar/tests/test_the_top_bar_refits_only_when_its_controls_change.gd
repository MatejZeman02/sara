## A tool switch that shows the same controls at the same width
## does not refit the top bar, and one that shows other controls refits once.
##
## The brush and the eraser are painting tools and share every control on the
## bar. The tool that shows something else is found rather than named, the first
## registered one whose shown set differs from the brush's, so the suite says
## the rule and not which tool happens to carry an extra control today.
##
## Built detached and `_ready()`ed by hand, the way `test_top_bar_rows.gd` does.
## The rows' handler is called directly, because a detached bar is not in the
## tree and `_ready` is what would connect it to `EventBus.tool_changed`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine with the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: TopMenuBar = null
## The node an in-tree bar hangs from, and the root's embedding before it did.
var _host: Node = null
var _kept_embedding: bool = true


func before_each() -> void:
    _saved_row = SaSettings.second_row
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_c3_top_bar_refits.cfg"))
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _bar = _build(false)


## A bar with its tool options, the way main builds them, detached, readied by
## hand and 1920 wide. With *in_tree* it is then hung in the tree, where the rows
## hear the switch themselves. Readied first either way, because readied by the
## tree the tool options bar lays the bar out while the bar is still adding its
## children, and the engine refuses the move.
func _build(in_tree: bool) -> TopMenuBar:
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    bar.set_anchor(SIDE_RIGHT, 0.0)
    bar.size.x = 1920.0
    if in_tree:
        # The bar's menus are Windows, and one added without embedding maps a
        # real OS window, so the root embeds for as long as the host stands. The
        # host hangs from `EventBus` because the root is still readying its own
        # children while the suites run.
        var root := (Engine.get_main_loop() as SceneTree).root
        _kept_embedding = root.gui_embed_subwindows
        root.gui_embed_subwindows = true
        _host = Node.new()
        _host.name = "C3TopBarTestHost"
        EventBus.add_child(_host)
        _host.add_child(bar)
    return bar


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(SaDataRoot.path("test_c3_top_bar_refits.cfg")) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## Makes *tool* the active one and delivers the switch to the rows, as the
## signal would in the tree.
func _switch(tool: StringName) -> void:
    _machine.set_active_tool(tool)
    if not _bar.is_inside_tree():
        _bar.rows._on_tool_changed(String(tool))


func _shown() -> Array:
    return _bar.rows._fit_key(SaSettings.get_layout_order("TopMenuBar"))[4]


func test_the_overflow_is_on_for_this_suite() -> void:
    assert_true(SaTopBarOverflow.enabled(), "The overflow is the default, and the refit on a switch is its path")


func test_a_switch_between_tools_with_the_same_controls_does_not_refit() -> void:
    _switch(&"brush")
    var brush_shown := _shown()
    var before: int = _bar.rows._refits
    _switch(&"eraser")
    assert_eq(_shown(), brush_shown, "The eraser shows the brush's controls, both being painting tools")
    _switch(&"brush")
    _switch(&"eraser")
    _switch(&"brush")
    assert_eq(_bar.rows._refits, before, "so four switches between them refit nothing")


func test_a_switch_to_other_controls_refits_once() -> void:
    # The default profile keeps every control that follows one tool off the bar
    # by default, so the painter's profile has to put one there for a switch to
    # show something else. A profile change is followed by a layout pass in the
    # app, which is the refit here.
    SaSettings.set_element_visible("TopMenuBar", "selection_mode", true)
    _switch(&"brush")
    _bar.rows.refit()
    var brush_shown := _shown()
    _machine.set_active_tool(&"marquee")
    assert_true(_shown().has("selection_mode"), "The marquee shows its selection mode on the bar")
    assert_false(brush_shown.has("selection_mode"), "and the brush does not")
    _machine.set_active_tool(&"brush")
    var before: int = _bar.rows._refits
    _switch(&"marquee")
    assert_eq(_bar.rows._refits, before + 1, "A switch to the marquee refits once")
    _switch(&"marquee")
    assert_eq(_bar.rows._refits, before + 1, "and a second switch to it refits no more")
    _switch(&"brush")
    assert_eq(_bar.rows._refits, before + 2, "and the switch back to the brush refits again")


## On the default profile no tool shows a control of its own on the bar, so a
## switch to any of them from the brush refits nothing. Every switch the painter
## makes there is the skipped one.
func test_on_the_default_profile_no_switch_refits() -> void:
    _switch(&"brush")
    var before: int = _bar.rows._refits
    for id: StringName in _machine.registered_tools.keys():
        _switch(id)
    _switch(&"brush")
    assert_eq(_bar.rows._refits, before, "Every registered tool shows the brush's controls on the default profile")


func test_a_new_width_refits_on_the_next_switch() -> void:
    _switch(&"brush")
    _bar.rows.refit()
    var before: int = _bar.rows._refits
    _bar.size.x = 1280.0
    _switch(&"eraser")
    assert_eq(_bar.rows._refits, before + 1, "The bar is narrower than it was fitted at, so the switch refits")


## A control that grew after the last split is a change of controls, the way a
## preset name or a dropdown label read after the first pass is in the app, and
## the switch that follows fits it again. In the tree, because a detached
## control keeps the minimum size it cached and never hears that it grew.
func test_a_control_that_grew_refits_on_the_next_switch() -> void:
    _bar.free()
    _bar = _build(true)
    _switch(&"brush")
    _bar.rows.refit()
    var before: int = _bar.rows._refits
    var edit_brush: Control = _bar.rows.elements()["Edit Brush"]
    edit_brush.custom_minimum_size.x = edit_brush.get_combined_minimum_size().x + 40.0
    _switch(&"eraser")
    assert_eq(_bar.rows._refits, before + 1, "The Edit Brush button is wider than it was fitted at, so the switch refits")
    _switch(&"brush")
    assert_eq(_bar.rows._refits, before + 1, "and once fitted, the switch back does not")


func test_a_skipped_refit_leaves_the_rows_as_a_refit_would() -> void:
    _switch(&"brush")
    _switch(&"eraser")
    var skipped := _layout()
    _bar.rows.refit()
    assert_eq(_layout(), skipped, "The rows after a skipped refit are the rows a refit makes")


## Where every control sits and whether it shows, by element name.
func _layout() -> Dictionary:
    var out := {}
    var elements: Dictionary = _bar.rows.elements()
    for element: String in elements:
        var node: Control = elements[element]
        if node == null:
            continue
        var parent := node.get_parent()
        out[element] = [String(parent.name) if parent != null else "", node.get_index(), node.visible]
    return out
