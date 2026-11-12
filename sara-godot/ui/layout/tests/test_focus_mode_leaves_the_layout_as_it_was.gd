## A close under focus mode leaves the layout file as it was
## before the Tab, so the next start shows the dockers and not an empty window.
##
## Tab hides the dockers without closing them, and `SaFocusMode` keeps their ids
## in memory only. The store must not write each docker's `visible` straight from its
## window, or a close, or a switch to another program, under the mode writes
## every hidden docker as closed. The next start would read that, with the mode
## off and nothing remembered, and the painter would open every docker again
## from the Window menu.
##
## A save is taken here the way the window's close takes it, and the file is read
## into a fresh store and fresh windows, which is what a start is. The windows
## sit in an embedded viewport, as `test_docker_layout_intent.gd`'s do.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1200, 800)
const SIZE := Vector2i(200, 150)

## Where each docker stands, left to right, and which ones are open to begin with.
const STANDS := {
    "ToolBoxDocker": Vector2i(20, 80),
    "ColorDocker": Vector2i(300, 80),
    "LayersDocker": Vector2i(600, 80),
    "BrushDocker": Vector2i(900, 80),
    "InfoDocker": Vector2i(900, 400),
}

var _root: Node = null
var _viewport: SubViewport = null
var _focus: SaFocusMode = null
var _table: Array = []
var _store: DockerLayoutStore = null
var _file: String = SaDataRoot.path("test_n6_focus_layout.cfg")


func before_each() -> void:
    SaFocusMode.leave()
    DirAccess.remove_absolute(_file)
    _root = Node.new()
    _root.name = "FocusLayoutTestHost"
    EventBus.add_child(_root)
    _focus = SaFocusMode.new()
    _root.add_child(_focus)
    var built := _build()
    _viewport = built["viewport"]
    _table = built["table"]
    _store = _store_over(_table)
    _root.add_child(_store)


func after_each() -> void:
    SaFocusMode.leave()
    if _root != null:
        _root.free()
        _root = null
    DirAccess.remove_absolute(_file)


## A viewport with a window for each docker of `STANDS`, the first four open and
## the Info docker closed, and the table `MainDockers` hands the mode and the
## store.
func _build() -> Dictionary:
    var viewport := SubViewport.new()
    viewport.size = HOST
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var host := Control.new()
    host.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(host)
    var table: Array = []
    for docker_id: String in STANDS:
        var window := Window.new()
        window.name = docker_id
        window.size = SIZE
        host.add_child(window)
        window.position = STANDS[docker_id]
        window.visible = docker_id != "InfoDocker"
        table.append({"id": docker_id, "name": docker_id, "node": window})
    return {"viewport": viewport, "table": table}


func _store_over(table: Array) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = _file
    store.dockers_provider = func() -> Array: return table
    store.save_allowed = func() -> bool: return true
    return store


func _window(table: Array, docker_id: String) -> Window:
    for config: Dictionary in table:
        if config["id"] == docker_id:
            return config["node"] as Window
    return null


func _stood() -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in _table:
        var window := config["node"] as Window
        if window.visible:
            out[config["id"]] = Rect2(Vector2(window.position), Vector2(window.size))
    return out


## What `MainDockers.toggle_all_dockers` does on a Tab.
func _tab(pinned: Array = []) -> void:
    _focus.toggle(_table, _stood() if not SaFocusMode.active else {}, pinned)


## A start: a fresh store over the file the last run left, and fresh windows with
## the layout restored into them. Answers the docker ids that are open then.
func _restart() -> Dictionary:
    SaFocusMode.leave()
    _viewport.free()
    var built := _build()
    _viewport = built["viewport"]
    for config: Dictionary in built["table"]:
        (config["node"] as Window).visible = false
    var fresh := _store_over(built["table"])
    _root.add_child(fresh)
    fresh.restore_all()
    var open: Dictionary = {}
    for config: Dictionary in built["table"]:
        var window := config["node"] as Window
        open[config["id"]] = {"visible": window.visible, "position": window.position}
    fresh.free()
    return open


func _open_ids(state: Dictionary) -> Array:
    var ids: Array = []
    for docker_id: String in state:
        if state[docker_id]["visible"]:
            ids.append(docker_id)
    ids.sort()
    return ids


func _file_says(docker_id: String) -> bool:
    var cfg := ConfigFile.new()
    cfg.load(_file)
    return bool(cfg.get_value(docker_id, "visible", false))


## The plain case: four open, Tab, the save a close makes, and a
## start shows the same four where they stood.
func test_a_close_under_focus_mode_gives_the_same_dockers_at_the_next_start() -> void:
    _store.save()
    _tab()
    assert_true(SaFocusMode.active, "Tab entered the mode")
    assert_false(_window(_table, "ColorDocker").visible, "and hid the dockers")
    _store.save()

    for docker_id: String in ["ToolBoxDocker", "ColorDocker", "LayersDocker", "BrushDocker"]:
        assert_true(_file_says(docker_id), "%s is open in the layout under the mode" % docker_id)
    assert_false(_file_says("InfoDocker"), "a docker that was closed before the Tab stays closed")

    var state := _restart()
    assert_eq(
        _open_ids(state), ["BrushDocker", "ColorDocker", "LayersDocker", "ToolBoxDocker"], "the next start shows the four dockers"
    )
    for docker_id: String in ["ToolBoxDocker", "ColorDocker", "LayersDocker", "BrushDocker"]:
        assert_eq(state[docker_id]["position"], STANDS[docker_id], "%s stands where it stood" % docker_id)
    assert_false(SaFocusMode.active, "Sara starts with focus mode off")
    assert_eq(SaFocusMode.status_text(), "off", "and the status line has no focus mode message")


## A pinned docker is open and stays shown, and the layout holds it as open.
func test_the_pinned_docker_is_open_in_the_layout_and_so_are_the_hidden_ones() -> void:
    _store.save()
    _tab(["LayersDocker"])
    assert_true(_window(_table, "LayersDocker").visible, "the pinned docker stays")
    _store.save()
    assert_eq(
        _open_ids(_restart()),
        ["BrushDocker", "ColorDocker", "LayersDocker", "ToolBoxDocker"],
        "the pinned docker and the three it stayed among are all open at the start"
    )


## The mode comes back off with a save after the way back, and that save is the
## windows as they stand.
func test_a_save_after_tab_again_writes_the_windows_as_they_stand() -> void:
    _store.save()
    _tab()
    _tab()
    assert_false(SaFocusMode.active, "Tab again left the mode")
    _window(_table, "BrushDocker").visible = false
    _store.save()
    assert_false(_file_says("BrushDocker"), "a docker closed after the way back is closed")
    assert_true(_file_says("ColorDocker"), "and the ones brought back are open")


## A docker the painter closes under the mode, from the Window menu or the
## docker's close button, is closed in the layout and stays closed at the start.
func test_a_docker_closed_under_focus_mode_stays_closed_after_a_restart() -> void:
    _store.save()
    _tab(["LayersDocker"])
    # The pinned one is shown, and closing it is the painter's word.
    _window(_table, "LayersDocker").visible = false
    SaFocusMode.forget("LayersDocker")
    # A hidden one opened and closed again is the painter's word too.
    _window(_table, "ColorDocker").visible = true
    SaFocusMode.forget("ColorDocker")
    _window(_table, "ColorDocker").visible = false
    _store.save()

    assert_false(_file_says("LayersDocker"), "the pinned docker closed under the mode is closed")
    assert_false(_file_says("ColorDocker"), "so is the one opened and closed again")
    assert_true(_file_says("ToolBoxDocker"), "the others are still the layout under the mode")
    assert_eq(_open_ids(_restart()), ["BrushDocker", "ToolBoxDocker"], "the start shows what the painter left")


## A docker the painter opens under the mode is open in the layout, and the way
## back leaves it open.
func test_a_docker_opened_under_focus_mode_is_open_in_the_layout() -> void:
    _store.save()
    _tab()
    _window(_table, "InfoDocker").visible = true
    SaFocusMode.forget("InfoDocker")
    _store.save()
    assert_true(_file_says("InfoDocker"), "the docker opened under the mode is open")
    _tab()
    assert_true(_window(_table, "InfoDocker").visible, "and the way back leaves it shown")


## A layout chosen under the mode leaves it first, so no remembered docker is
## written over the layout's own choice and the layout's dockers are the ones
## shown.
func test_a_layout_chosen_under_focus_mode_leaves_the_mode_first() -> void:
    _store.save()
    _tab()
    assert_true(SaFocusMode.active, "Tab entered the mode")
    assert_true(_store.load_preset(SaDockerLayoutPresets.DEFAULT_PRESET), "the default layout loads")
    assert_false(SaFocusMode.active, "choosing a layout left the mode")
    assert_false(SaFocusMode.layout_visible("ColorDocker", false), "and no docker is remembered as open")
    assert_true(_file_says("ColorDocker") == _window(_table, "ColorDocker").visible, "the file says what the window shows")
