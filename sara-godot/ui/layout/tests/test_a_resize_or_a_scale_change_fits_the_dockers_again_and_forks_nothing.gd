## A resize or a scale change fits the dockers again and forks nothing.
##
## Dockers must not stay heaped where scale 2 pushed them after the scale comes
## back to 1, with the menus from Layer to Help out of reach and the layout
## renamed `default (custom)`. Saving the pushed-in positions as the painter's
## would fork, and so would Tab, the second row and every other setting. A scale change and a resize place the
## shipped `default` again
## through the fit, a painter's own layout goes back where it was, and only a
## docker the painter moved, sized, opened or closed, or an element page, forks.
## The first fork of a session says so.
##
## Built the way the app builds it: `MainDockers` over a registry of seven probe
## windows, the six the shipped default opens and its closed Reference, embedded in a host
## viewport whose logical size a scale change halves. A probe has no column, so
## its floor is the one a fresh profile's dump reads, as the default layout fit
## suite beside this says. The shots are `scenarios/a-resize-or-a-scale-change-fits-the-dockers-again-and-forks-nothing.json`.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1920, 1080)

## The first row below a one-row bar, `MainDockers.below_bar` with no bar.
const TOP := 65

const FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "BrushPresetsDocker": Vector2i(295, 212),
    "ToolOptionsDocker": Vector2i(206, 255),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
    "MinimapDocker": Vector2i(168, 132),
    "ReferenceDocker": Vector2i(184, 213),
}

## The dockers the default keeps closed, which is the Reference alone.
const CLOSED: Array[String] = ["ReferenceDocker"]

## The open dockers a host of 960 by 540, which is this one at scale 2, has no
## room for: the Brush Presets, the head of the close order, and the Layers.
const NO_ROOM_AT_SCALE_2: Array[String] = ["BrushPresetsDocker", "LayersDocker"]

static var scratch_live: String = SaDataRoot.path("test_n54_docker_layout.cfg")

var _root: Node = null
var _viewport: SubViewport = null
var _dockers: MainDockers = null
var _menu: SaChoicePopup = null
var _saved_scale: float = 1.0
var _saved_second_row: bool = false

## Every line the corner notice was asked to show while a case ran.
var _told: Array[String] = []


func _hear(line: String) -> void:
    _told.append(line)


func before_each() -> void:
    _told.clear()
    _saved_scale = SaSettings.ui_scale
    _saved_second_row = SaSettings.second_row
    SaFocusMode.active = false
    EventBus.corner_notice.connect(_hear)
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)

    _root = Node.new()
    _root.name = "N54Host"
    EventBus.add_child(_root)
    _viewport = SubViewport.new()
    _viewport.size = HOST
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    _viewport.add_child(parent)

    var registries := SaRegistries.new()
    for section: String in FLOORS:
        var probe := Window.new()
        probe.name = section
        probe.min_size = FLOORS[section]
        probe.size = FLOORS[section]
        parent.add_child(probe)
        registries.ui.register_docker(StringName(section), section, func() -> Window: return Window.new(), &"docker_stub")
        registries.ui.set_docker_node(StringName(section), probe)
    var store := DockerLayoutStore.new()
    store.path = scratch_live
    # The layouts folder beside the scratch file is every suite's, and a run of
    # the whole gate reaches this one with a fork of the default already in it.
    store.delete_preset("default (custom)")
    _dockers = MainDockers.new(registries.ui, store)
    _viewport.add_child(_dockers)
    # The Window menu's own call, which is what connects the doors this suite
    # is about: the host's resize, the scale, the elements and the drag.
    _menu = SaChoicePopup.new()
    _dockers.append_menu_rows(_menu)
    _dockers.load_docker_layout()


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    if _dockers != null:
        _dockers.layout_store.delete_preset("default (custom)")
        _dockers.layout_store.delete_preset("painter own")
    if _root != null:
        _root.free()
        _root = null
        _dockers = null
    if _menu != null:
        _menu.free()
        _menu = null
    SaFocusMode.active = false
    SaSettings.ui_scale = _saved_scale
    SaSettings.second_row = _saved_second_row
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)


## The host's logical size at *factor*, which is what the root window's content
## scale does to the viewport the dockers are embedded in, and then the scale
## itself, which is what announces it.
func _scale_to(factor: float) -> void:
    _viewport.size_2d_override = Vector2i() if is_equal_approx(factor, 1.0) else Vector2i(Vector2(HOST) / factor)
    SaSettings.ui_scale = factor


func _rects() -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in _dockers.get_docker_config():
        var win: Window = config["node"]
        out[config["id"]] = Rect2i(win.position, win.size)
    return out


func _index_of(section: String) -> int:
    var configs := _dockers.get_docker_config()
    for i in configs.size():
        if configs[i]["id"] == section:
            return i
    return -1


## The case that matters, in one run: scale 2 and back, the window down and up, Tab
## twice and the second row on and off, and the layout is still `default` with
## every docker where it opened.
func test_the_scale_a_resize_tab_and_the_second_row_leave_default_where_it_opened() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    var first := _rects()
    assert_eq(_dockers.layout_store.current_preset(), "default", "A fresh profile opens in default")

    _scale_to(2.0)
    var host := Vector2i(Vector2(HOST) / 2.0)
    var at_two := SaDockerLayoutFit.new(host, TOP, Vector2i(1920, 1080))
    var at_scale_two := _rects()
    for section: String in at_scale_two:
        # A host of 960 by 540 has no room for some of the four, and the fit
        # closes them, so only the open ones are placed.
        if not _dockers.registered_docker_node(StringName(section)).visible:
            continue
        var rect: Rect2i = at_scale_two[section]
        assert_true(rect.position.y >= TOP, "At scale 2 %s %s starts below the bar" % [section, rect])
        assert_true(rect.position.x >= 0 and rect.end.x <= host.x, "and is across the host %s" % host)
    assert_true(at_scale_two["ColorDocker"] != first["ColorDocker"], "so scale 2 moved the right column in")
    assert_eq(at_scale_two["ColorDocker"].end.x, host.x - 10, "to its distance from the right edge, which is the fit")
    assert_eq(at_two.kept(Vector2i(0, 0), Vector2i(60, 60)).y, TOP, "and nothing is ever kept above the bar")
    _scale_to(1.0)
    assert_eq(_rects(), first, "Back at scale 1 every docker is where it opened")

    _viewport.size = Vector2i(1280, 800)
    assert_eq(_rects()["LayersDocker"].end.x, 1280 - 10, "A smaller window fits the right column to it")
    _viewport.size = HOST
    assert_eq(_rects(), first, "and the window grown back puts every docker where it opened")

    _dockers.toggle_all_dockers()
    _dockers.toggle_all_dockers()
    assert_eq(_rects(), first, "Tab twice gives the same dockers in the same places")

    SaSettings.second_row = not _saved_second_row
    SaSettings.second_row = _saved_second_row

    assert_eq(_dockers.layout_store.current_preset(), "default", "and after all of it the layout is still default")
    assert_false(_dockers.layout_store.list_presets().has("default (custom)"), "with no fork of it")
    assert_eq(_told, [] as Array[String], "and nothing was said about a fork")


## Tab, scale 2 and Tab again: the way back shows what Tab hid, and the reflow
## after it closes the ones a host of 960 by 540 has no room for, which stood
## where scale 1 had them, the Layers docker off the host. The
## Tool Options has room there because the Brush Presets over it, the head of
## the close order, closes first, and the closed Reference never opens.
func test_tab_a_scale_change_and_tab_again_close_what_has_no_room() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    var first := _rects()
    _dockers.toggle_all_dockers()
    _scale_to(2.0)
    _dockers.toggle_all_dockers()
    for section: String in CLOSED + NO_ROOM_AT_SCALE_2:
        assert_false(_dockers.registered_docker_node(StringName(section)).visible, "%s has no room at scale 2" % section)
    assert_true(_dockers.registered_docker_node(&"ColorDocker").visible, "and the Colour Picker has")
    assert_true(_dockers.registered_docker_node(&"ToolOptionsDocker").visible, "and the Tool Options")
    _scale_to(1.0)
    for config: Dictionary in _dockers.get_docker_config():
        assert_eq((config["node"] as Window).visible, not CLOSED.has(config["id"]), "%s as it opened at scale 1" % config["id"])
    assert_eq(_rects(), first, "where it opened")
    assert_eq(_dockers.layout_store.current_preset(), "default", "and nothing forked")


## A layout of the painter's own is pushed in by scale 2, every title below the
## bar, and goes back to where the painter put it at scale 1, even after the
## painter closed a docker at scale 2: the save that close makes is the
## painter's, and the positions the scale pushed are still not.
func test_a_painters_layout_pushed_by_scale_2_comes_back_after_a_close_there() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    # At the bar's foot, since the Tool Options is 563 tall
    # and scale 2 keeps no lower a docker of that height on a host half of 1080.
    var moved := Vector2i(1300, TOP)
    _dockers.registered_docker_node(&"ToolOptionsDocker").position = moved
    _dockers.layout_store.note_placement(_dockers.registered_docker_node(&"ToolOptionsDocker"))
    assert_true(_dockers.layout_store.save_preset("painter own"), "The painter saves their own layout")
    var first := _rects()

    _scale_to(2.0)
    var host := Vector2i(Vector2(HOST) / 2.0)
    var pushed: Rect2i = _rects()["ToolOptionsDocker"]
    # Fitted over the painter's own rectangles as a shipped layout is, so it keeps its distance from the right edge and its top.
    var gap: int = HOST.x - moved.x - (first["ToolOptionsDocker"] as Rect2i).size.x
    assert_eq(pushed.end.x, host.x - gap, "Scale 2 keeps it %d from the right edge" % gap)
    assert_eq(pushed.position.y, moved.y, "and at its top")
    for section: String in _rects():
        assert_true(_rects()[section].position.y >= TOP, "and %s starts below the bar" % section)
    _dockers.toggle_docker(_index_of("ReferenceDocker"))
    assert_eq(_dockers.layout_store.current_preset(), "painter own", "A close at scale 2 is written in place")

    _scale_to(1.0)
    for section: String in first:
        if section != "ReferenceDocker":
            assert_eq(_rects()[section].position, first[section].position, "%s is back where the painter put it" % section)
    assert_eq(_told, [] as Array[String], "and a painter's own layout forks nothing to tell of")


## An element page is the one door besides a docker that still forks, and the
## first fork of the session says so, naming the layout the painter is in now.
func test_an_element_page_forks_and_the_first_fork_says_so_once() -> void:
    var before := SaSettings.get_element_visible("LayersDocker", "Opacity")
    SaSettings.set_element_visible("LayersDocker", "Opacity", not before)
    assert_eq(_dockers.layout_store.current_preset(), "default (custom)", "Hiding an element forks the default")
    assert_eq(_told.size(), 1, "and the fork is said")
    assert_true(_told[0].contains("Default (Custom)"), "naming the new layout: %s" % _told[0])

    _dockers.toggle_docker(_index_of("ReferenceDocker"))
    SaSettings.set_element_visible("LayersDocker", "Opacity", before)
    assert_eq(_dockers.layout_store.current_preset(), "default (custom)", "Later edits stay in the fork")
    assert_eq(_told.size(), 1, "and say nothing more")


## A docker the painter drags is still the painter's, and forks the default,
## because `docker_layout_changed` is the drag handle's word for it.
func test_a_drag_still_forks_the_default() -> void:
    var colour := _dockers.registered_docker_node(&"ColorDocker")
    # Its foot a hundred pixels below the shorter window's bottom edge, at
    # whatever height the docker ships.
    var dragged := Vector2i(900, 800 - colour.size.y)
    colour.position = dragged
    EventBus.docker_layout_changed.emit()
    assert_eq(_dockers.layout_store.current_preset(), "default (custom)", "The drag forks")
    var before := _rects()
    _viewport.size = Vector2i(1280, 700)
    # Fitted over the painter's own rectangles as a shipped layout is, rather than each docker pushed in on its own.
    var line := 700 - SaDockerLayoutRefit.status_rows_in(1.0)
    var after := _rects()
    for section: String in after:
        if not _dockers.registered_docker_node(StringName(section)).visible:
            continue
        var rect: Rect2i = after[section]
        assert_true(
            rect.position.x >= 0 and rect.end.x <= 1280 and rect.end.y <= line, "A shorter window fits %s %s" % [section, rect]
        )
        for other: String in after:
            if not _dockers.registered_docker_node(StringName(other)).visible:
                continue
            if other != section and not before[section].intersects(before[other]):
                assert_false(rect.intersects(after[other]), "%s %s is clear of %s %s" % [section, rect, other, after[other]])
    _viewport.size = HOST
    assert_eq(colour.position, dragged, "and the window grown back puts it where the painter put it")


## Whether no screen here is 1920 wide. These tests lay the shipped layout on a
## host of 1920 by 1080, and the store rightly keeps every docker on a screen,
## so on a smaller screen it puts them where no 1920 wide layout has them.
func _no_screen_is_1920_wide() -> bool:
    return SaDockerStoredEntry.all_screens_rect().size.x < 1920
