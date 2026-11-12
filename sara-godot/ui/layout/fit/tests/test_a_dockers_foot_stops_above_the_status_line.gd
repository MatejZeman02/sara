## A docker's foot stops above the status line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker must not stand over the status line's size and colour space, as Full's
## Undo History would at 560,681, 240 by 328, on a window 1280 by 1024 with its
## foot at 1009, or Default's Layers at a font size of 1.3. The line takes the
## window's last 24 rows, from 1000, so the store hands the fit the window less
## the line's rows, `SaStatusLine.rows_taken`, the way it hands it the
## bar's at the head, and a docker the font grows is kept above the line as well.
##
## Held here: the floor is the line's own height, each of the four shipped layouts loaded through the store on a
## host of 1280 by 1024 and of 1920 by 1080 opens every docker with its foot at
## or above the line's top, and the built-in dockers booted at a font size of
## 1.3 and grown for it the way a font change grows them do the same in the
## default. The running app is
## `scenarios/a-dockers-foot-stops-above-the-status-line.json`.
extends "res://tests/test_framework.gd"

## The first row below a one-row bar, `MainDockers.below_bar` with no bar.
const TOP := 65

## The two window sizes at a UI scale of 1.
const HOSTS: Array[Vector2i] = [Vector2i(1280, 1024), Vector2i(1920, 1080)]

## Each docker's floor as the fit is handed it on the running app, as
## `test_a_shipped_layout_fits_its_columns_to_the_window_at_any_ui_scale.gd`.
const FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "BrushPresetsDocker": Vector2i(295, 212),
    "ToolOptionsDocker": Vector2i(206, 281),
    "ReferenceDocker": Vector2i(256, 132),
    "ColorDocker": Vector2i(294, 212),
    "LayersDocker": Vector2i(269, 212),
    "InfoDocker": Vector2i(234, 172),
    "PaletteDocker": Vector2i(240, 272),
    "RecorderDocker": Vector2i(241, 212),
    "GraphDocker": Vector2i(180, 212),
    "HistoryDocker": Vector2i(229, 152),
    "UndoDocker": Vector2i(212, 152),
    "MinimapDocker": Vector2i(168, 132),
    "ExposureDocker": Vector2i(226, 272),
}

## A font size at which the default's Layers once met the line.
const FONT_SCALE := 1.3

static var scratch_live: String = SaDataRoot.path("test_d102_docker_layout.cfg")
static var scratch_presets_dir: String = SaDataRoot.path("layouts")

var _root: Node = null
var _store: DockerLayoutStore = null
var _kept_font_scale: float = 1.0

## What a preset load writes beyond geometry, put back after every test, for
## the reason `test_docker_layout_presets.gd` gives.
var _saved_state := ConfigFile.new()


func before_each() -> void:
    _kept_font_scale = SaUI.user_font_scale


func after_each() -> void:
    SaFocusMode.active = false
    if _store != null:
        _store.presets().apply(_saved_state)
        _store = null
    if _root != null:
        _root.free()
        _root = null
    SaUI.user_font_scale = _kept_font_scale
    SaUI.refresh_font_sizes()
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)
    var dir := DirAccess.open(scratch_presets_dir)
    if dir != null:
        for file_name in dir.get_files():
            if file_name.ends_with(" (custom).cfg"):
                DirAccess.remove_absolute(scratch_presets_dir.path_join(file_name))


## The line's top on *host*, the row no docker's foot may pass.
static func _line_top(host: Vector2i) -> int:
    return host.y - SaStatusLine.rows_taken()


func test_the_floor_is_the_status_lines_own_height_while_it_shows() -> void:
    assert_true(SaStatusLine.shown_in_profile(), "a fresh profile shows the line")
    _root = Node.new()
    _root.name = "D102Line"
    EventBus.add_child(_root)
    var line := SaStatusLine.new(func() -> SaSurface: return null)
    _root.add_child(line)
    line.size = Vector2(1280.0, 29.0)
    assert_eq(SaStatusLine.rows_taken(), 29, "a line 29 tall, as at a font size of 1.6, takes 29 rows")
    line.size = Vector2(1280.0, float(SaStatusLine.HEIGHT))
    assert_eq(SaStatusLine.rows_taken(), SaStatusLine.HEIGHT, "and one of its least height takes 24")
    assert_eq(SaDockerLayoutRefit.status_rows_in(2.0), 2 * SaStatusLine.HEIGHT, "in a window's own units at scale 2")


## Every shipped layout loaded from the Window menu's store on both hosts.
func test_each_shipped_layout_keeps_every_foot_above_the_line() -> void:
    for host in HOSTS:
        var store := _store_on(host)
        for preset_name: String in SaDockerLayoutPresets.SHIPPED:
            assert_true(store.load_preset(preset_name), "%s loads at %s" % [preset_name, host])
            var opened := _open_rects(store.dockers_provider.call())
            assert_true(opened.size() > 1, "%s opens its dockers at %s" % [preset_name, host])
            for section: String in opened:
                var rect: Rect2i = opened[section]
                var at := "%s's foot at %d in %s at %s" % [section, rect.end.y, preset_name, host]
                assert_true(rect.end.y <= _line_top(host), "%s, above the line's %d" % [at, _line_top(host)])
        _store.presets().apply(_saved_state)
        _store = null
        _root.free()
        _root = null


## The note's two cases by name: Full's Undo History on the panel, and the
## default's Layers on the window the file was written for, where its foot
## stood at 1065.
func test_fulls_undo_and_the_defaults_layers_stand_clear_of_the_line() -> void:
    var store := _store_on(HOSTS[0])
    store.load_preset("full")
    var undo: Rect2i = _open_rects(store.dockers_provider.call())["UndoDocker"]
    assert_eq(undo.end.y, _line_top(HOSTS[0]) - SaDockerLayoutFit.BOTTOM_MARGIN, "Full's Undo History ends 15 above the line")
    _store.presets().apply(_saved_state)
    _store = null
    _root.free()
    _root = null
    store = _store_on(HOSTS[1])
    store.load_preset("default")
    var layers: Rect2i = _open_rects(store.dockers_provider.call())["LayersDocker"]
    assert_eq(layers.end.y, _line_top(HOSTS[1]) - SaDockerLayoutFit.BOTTOM_MARGIN, "the default's Layers ends 15 above the line")


## The built-in dockers at a font size of 1.3 on the panel: the default placed
## the way a boot places it, restored, every docker grown for the font the way
## a change of it grows them, and the store's fit run again after, as the
## bar's resize runs it.
func test_the_default_at_a_font_size_of_1_3_keeps_every_foot_above_the_line() -> void:
    var host: Vector2i = HOSTS[0]
    SaUI.user_font_scale = FONT_SCALE
    SaUI.refresh_font_sizes()
    var dockers := _boot(host)
    dockers.apply_default_docker_geometry()
    var layers := dockers.registered_docker_node(SaDockerIds.LAYERS)
    var foot := layers.position.y + layers.size.y
    assert_true(foot <= _line_top(host), "the boot's own placing ends the Layers at %d, above the line" % foot)
    dockers.load_docker_layout()
    for config: Dictionary in dockers.get_docker_config():
        var docker := config["node"] as DockerWindow
        if docker == null or not docker.visible:
            continue
        SaUI.apply_ui_theme(docker)
        var counted := SaDockerFontGrowth.begin(docker)
        var progress: Dictionary = {}
        for _round in SaDockerFontGrowth.ROUNDS:
            if not SaDockerFontGrowth.step(docker, counted, progress):
                break
        SaDockerFontGrowth.end(docker)
        var rect := Rect2i(docker.position, docker.size)
        assert_true(rect.end.y <= _line_top(host), "%s grown for the font %s, above the line" % [config["id"], rect])
    dockers.layout_store.reflow_to_host()
    var opened := _open_rects(dockers.get_docker_config())
    assert_true(opened.has("LayersDocker"), "the default opens the Layers at a font size of 1.3")
    for section: String in opened:
        var rect: Rect2i = opened[section]
        assert_true(rect.end.y <= _line_top(host), "%s %s fitted again, above the line's %d" % [section, rect, _line_top(host)])


## A host of *host* embedding one probe window per built-in docker, each at its
## floor in [constant FLOORS], and the store over them.
func _store_on(host: Vector2i) -> DockerLayoutStore:
    _root = Node.new()
    _root.name = "D102Host"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    var configs: Array = []
    for section: String in FLOORS:
        var probe := Window.new()
        probe.name = section
        probe.min_size = FLOORS[section]
        probe.size = FLOORS[section]
        probe.visible = false
        parent.add_child(probe)
        configs.append({"id": section, "name": section, "node": probe})
    _store = DockerLayoutStore.new()
    _store.path = scratch_live
    _store.dockers_provider = func() -> Array: return configs
    _store.save_allowed = func() -> bool: return true
    _store.top_inset = func() -> int: return TOP
    _store.presets().capture(_saved_state)
    _root.add_child(_store)
    return _store


## The registry's dockers in a viewport of *host* that embeds them, the way the
## main window does, every one hidden until the layout is restored.
func _boot(host: Vector2i) -> MainDockers:
    _root = Node.new()
    _root.name = "D102Boot"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)
    var store := DockerLayoutStore.new()
    store.path = scratch_live
    var dockers := MainDockers.new(SaUIRegistry.new(), store)
    viewport.add_child(dockers)
    dockers.register_builtin_dockers()
    return dockers


## Section to rectangle for every open docker of *configs*.
static func _open_rects(configs: Array) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in configs:
        var win: Window = config["node"]
        if win.visible:
            out[config["id"]] = Rect2i(win.position, win.size)
    return out
