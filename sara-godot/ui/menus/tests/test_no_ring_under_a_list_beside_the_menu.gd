## No ring is drawn under a filter section's list opened beside the Filter menu.
##
## Under the cursor the items of a secondary menu must not be hidden. A section's list is a child of the
## menu's own window, and the window walk the cursor policy scans stopped at the
## menu, so the list over the canvas was read as the canvas and the main window
## drew the ring beneath it.
##
## The bar stands in a tree with embedding forced, the way
## `test_a_filter_section_opens_beside_the_filter_menu.gd` stands it, with a
## canvas under the whole root that wants a ring, so a point on the list is a
## point the canvas would claim if nothing stood over it. A suite cannot map a
## window of its own, the rule `render/cursor/tests/test_a_window_of_its_own.gd`
## gives, so with subwindows off what is asked here is the walk both halves of
## the policy start from, and the let-out list itself is the scenario
## `scenarios/a-list-opened-beside-the-menu-leaves-the-ring-under-it.json`.
extends "res://tests/test_framework.gd"

## Real windows and a canvas go in the tree.
const REQUIRES_GPU := true

const RING := 12.0


## A filter with a title and a section of the suite's choosing. Public members,
## written in `_init` alone.
class SortedFilter:
    extends SaFilter
    var entry_title: String
    var entry_section: StringName

    func _init(text: String, section_id: StringName) -> void:
        entry_title = text
        entry_section = section_id

    func title() -> String:
        return entry_title

    func family() -> StringName:
        return entry_section

    func run(_ctx: SaFilterContext) -> void:
        pass


var _host: Control = null
var _was_embedding: bool = false
var _previous_mode: String = "auto"
var _bar: TopMenuBar = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _previous_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## A canvas under the whole root, the bar over it, the Filter menu open and the
## Blur section's list beside it.
func _open_list() -> SaChoicePopup:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    var alpha := registries.context.for_module(&"alpha")
    alpha.register_filter_section(&"blur", "Blur", 400)
    alpha.register_filter(SortedFilter.new("Smear", &"blur"))
    alpha.register_filter(SortedFilter.new("Streak", &"blur"))
    var root := (Engine.get_main_loop() as SceneTree).root
    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    _host = Control.new()
    _host.name = "E2RingUnderAListHost"
    EventBus.add_child(_host)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    _host.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = root.get_visible_rect().size
    canvas.cursor_ring_radius = RING
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(registries.commands)
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    _bar._on_menu_button_pressed("Filter")
    return menu.show_section(menu.section_item(&"blur"))


## The middle of *list*, in the root's space, where an embedded list is placed.
func _middle_of(list: SaChoicePopup) -> Vector2:
    return Vector2(list.position) + Vector2(list.size) * 0.5


## A pen motion, known for a pen by its tilt, fed to the policy in *window*.
func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


func test_the_list_beside_the_menu_is_a_window_over_the_canvas() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var list := _open_list()
    var root := (Engine.get_main_loop() as SceneTree).root
    assert_true(list.visible and list.is_embedded(), "the Blur list is open and embedded in the root")
    var point := _middle_of(list)
    assert_true(
        SaCursorPolicy.canvas_ring_radius_at(root, point) >= 0.0,
        "the canvas is under the list at %s, so the ring is there to be claimed" % point
    )
    assert_true(
        SaCursorPolicy.pointer_is_over_embedded_window(root, point), "and the policy answers that the point is over a window"
    )
    assert_true(SaCursorPolicy.pointer_is_over_ui(root, point), "rather than over the canvas")
    assert_eq(SaCursorPolicy.cursor_ring_radius_at(root, point), -1.0, "so the main window claims no ring under the list")


func test_a_pen_over_the_list_has_the_lists_arrow_and_no_ring() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var list := _open_list()
    var root := (Engine.get_main_loop() as SceneTree).root
    var point := _middle_of(list)
    _pen_at(root, point)
    assert_not_null(list.get_node_or_null("CursorOverlay"), "the child list carries an overlay of its own")
    assert_eq(SaCursorPolicy.drawn_at(root, point), &"pointer", "so the pen is shown Sara's arrow there and never the ring")
    SaCursorPolicy.forget_pointer_device()
    assert_eq(SaCursorPolicy.drawn_at(root, point), &"system", "and a mouse keeps the system pointer over it")


func test_the_walk_reaches_the_list_that_hangs_from_the_menu() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var list := _open_list()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var root := (Engine.get_main_loop() as SceneTree).root
    var walked := SaCursorRing.WindowWalk.under(root, true)
    assert_true(walked.has(popup), "the walk finds the Filter menu")
    assert_true(
        walked.has(list),
        "and the list under it, which with subwindows off is a window of its own that windows_of_their_own finds by the same walk"
    )
    assert_false(SaCursorRing.WindowWalk.under(root, false).has(list), "while a walk without internal children stays as it was")
