## At 125 per cent Stabiliser is in sight and the Reference
## stays on screen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two things are held. Launched at 1.25 the default's dockers must stand where
## a live change to 1.25 puts them, though the boot's fit reads each docker's
## floor before it has laid out. And the Reference, which ships closed, must not
## open at 1.25 with its foot below a 1048 window or over the Tool Options'
## rows, since the left column has no room under them at that scale. It sits at
## (1280, 320), where at 1.25 the right column lies over it, so it opens beside
## that column instead.
##
## This boots the real dockers in a viewport that embeds them, as the live-scale
## suite does, on the 1920 by 1080 window the default was written for, once at 1.25
## and once at 1.0 with a live change to 1.25. A probe store beside them holds
## the boot's floors moving under the fit. The running app is
## `scenarios/the-tool-options-docker-keeps-its-rows-when-the-interface-scale-changes-live.json`,
## launched at 1.25 and changed live.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolOptionsFloor = preload("res://ui/dockers/tool_options/tool_options_floor.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## A bar this wide shows every control it holds, as the running app's does.
const ROOMY := 4000.0

## The window the default was written for.
const WINDOW := Vector2i(1920, 1080)

## The rows the Tool Options shows through its Stabiliser row with a brush in
## the hand: Hardness, Flow, the two pressure switches and Stabiliser.
const THROUGH_STABILISER := 5

## Every docker of the default at 1.0 on this window, the closed Reference
## where it opens. They are read off this suite's boot. The Tool Options has
## the brush's rows and the Reference stands outside the left column. At 1.25
## they are the same but for the Reference, which opens beside the right column.
## The first row is 79, under the bar's second row, and both columns with it.
## The Minimap heads the right column at 250 tall, so the Colour Picker opens at 329, and the
## left column butts the Toolbox at 60 with the Tool Options 438 tall.
## The Brush Presets probe is closed here, so the Tool Options heads the left column, and
## the Colour Picker is 393 tall, its contents' height, with the Layers under it
## taking what is left. The Toolbox snaps to whole rows
## once it opens, so it stands 70 tall, the bar and one row of buttons, with
## no strip of empty docker under the row.
const AT_ONE := {
    "ToolBoxDocker": Rect2i(0, 79, 60, 70),
    "ToolOptionsDocker": Rect2i(60, 79, 310, 438),
    "ColorDocker": Rect2i(1600, 329, 310, 393),
    "LayersDocker": Rect2i(1600, 722, 310, 319),
    "ReferenceDocker": Rect2i(1280, 320, 310, 223),
}

## The probes' floors as a boot's fit reads them before the dockers lay out,
## and as they stand two frames on. Tool Options' line of what the bar holds is
## wrapped at the width its column had before it was sorted. Read on the
## running app at 1.25 and handed to the probes in units of 1, as the default
## layout fit suite's are. The Brush Presets' grid, which has no preset in it
## yet, moves its floor too, so the probe here starts closed.
const BOOT_FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "ToolOptionsDocker": Vector2i(206, 319),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
}
const SETTLED_FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "ToolOptionsDocker": Vector2i(206, 274),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
}

## The Reference's floor, as the default layout fit suite has it.
const REFERENCE_FLOOR := Vector2i(224, 132)

## The closed Brush Presets' floor, as the default layout fit suite has it.
const PRESETS_FLOOR := Vector2i(295, 212)

## The dockers the default keeps closed, whose probes start hidden as the real
## ones do before a layout is restored.
const CLOSED: Array[String] = ["ReferenceDocker", "BrushPresetsDocker"]

## The bar's foot on the probes' host, as the default layout fit suite has it.
const TOP := 65

## A host whose left column has room for one set of floors and not the other:
## 297 under the status line's 39, the margin's 15 and the first row's 79, for
## a Tool Options asking 319 at the boot and 274 settled.
const BINDING := Vector2i(1280, 430)

static var scratch_profile: String = SaDataRoot.path("test_p6_column_profile.cfg")
static var scratch_layout: String = SaDataRoot.path("test_p6_docker_layout.cfg")

var _saved_path: String
var _saved_row: bool
var _saved_user: float
var _saved_override: float
var _surface: SaSurface
var _machine: ToolMachine
var _options: ToolOptionsBar
var _bar: TopMenuBar
var _host: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    _saved_user = SaUI.user_scale
    _saved_override = SaUI.os_scale_override
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_scratch_files()
    SaSettings.load_settings()
    SaSettings.second_row = false
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _options = ToolOptionsBar.new()
    _options.target_tool_machine = _machine
    _options._ready()
    _bar = TopMenuBar.new()
    _bar.add_tool_options(_options)
    # Parented to an autoload rather than to the root, because the runner calls
    # a suite from its own `_ready`.
    _host = Node.new()
    _host.name = "P6Host"
    EventBus.add_child(_host)
    _host.add_child(_bar)
    _bar.set_anchor(SIDE_RIGHT, 0.0)
    _bar.size.x = ROOMY
    _bar.apply_layout_settings()


func after_each() -> void:
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _remove_scratch_files()
    SaUI.user_scale = _saved_user
    SaUI.os_scale_override = _saved_override
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


## A launch at 1.25 and a live change to 1.25 give every docker the same
## rectangle, the closed Reference's opening place among them, and no foot
## stands below the status line.
func test_a_launch_and_a_live_change_to_1_25_give_the_same_rectangles() -> void:
    var launched := _rects(_boot_at(1.25))
    _drop_the_boot()
    var dockers := _boot_at(1.0)
    _change_scale(dockers, 1.25)
    var changed := _rects(dockers)
    assert_eq(launched.keys().size(), AT_ONE.keys().size(), "The launch places the five: %s" % [launched.keys()])
    for section: String in AT_ONE:
        assert_eq(changed.get(section), launched.get(section), "%s stands where a launch at 1.25 puts it" % section)
    var line := _above_the_line(1.25)
    for section: String in launched:
        var rect: Rect2i = launched[section]
        assert_true(rect.position.y >= 0 and rect.end.y <= line, "%s %s ends above the line at %d" % [section, rect, line])
        assert_true(rect.position.x >= 0 and rect.end.x <= int(WINDOW.x / 1.25), "%s %s is on the host" % [section, rect])


## At 1.25 the fit gives Tool Options the height to show its rows through
## Stabiliser, as a launch and as a live change.
func test_at_1_25_the_tool_options_shows_its_rows_through_stabiliser() -> void:
    for live: bool in [false, true]:
        var dockers := _boot_at(1.0 if live else 1.25)
        if live:
            _change_scale(dockers, 1.25)
        var docker := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
        var rows := docker.shown_keys()
        assert_true(rows.size() > THROUGH_STABILISER, "The brush shows more rows than five: %s" % [rows])
        assert_eq(rows[THROUGH_STABILISER - 1], &"stabilizer_mode", "and its fifth is Stabiliser")
        var scroll := docker.find_child("Scroll", true, false) as ScrollContainer
        var shown := _scroll_height(docker, scroll)
        var wanted := _first_rows_height(docker, THROUGH_STABILISER)
        var how := "changed live" if live else "launched"
        assert_true(shown >= wanted, "%s, the scroll is %d units and the rows through Stabiliser want %d" % [how, shown, wanted])
        _drop_the_boot()


## The Reference opened at 1.25 stands beside the right column, on the host and
## over none of the dockers the default opens, and Tool Options keeps its rows
## through Stabiliser in sight.
func test_the_reference_opens_beside_the_right_column_at_1_25() -> void:
    var dockers := _boot_at(1.25)
    var before := _rects(dockers)
    dockers.toggle_docker_by_id(SaDockerIds.REFERENCE)
    var board := dockers.registered_docker_node(SaDockerIds.REFERENCE)
    assert_true(board.visible, "The chord opens the Reference")
    var opened := Rect2i(board.position, board.size)
    assert_eq(opened, before["ReferenceDocker"], "where the fit said it opens")
    assert_eq(opened.end.x + SaDockerLayoutFit.SIDE_GAP, before["ColorDocker"].position.x, "beside the right column")
    assert_true(opened.end.y <= _above_the_line(1.25), "with its foot %d above the line" % opened.end.y)
    for section: String in AT_ONE:
        if section != "ReferenceDocker":
            assert_false(opened.intersects(before[section]), "and clear of %s %s" % [section, before[section]])
    var docker := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
    var scroll := docker.find_child("Scroll", true, false) as ScrollContainer
    var shown := _scroll_height(docker, scroll)
    assert_true(shown >= _first_rows_height(docker, THROUGH_STABILISER), "Tool Options still shows Stabiliser, %d" % shown)


## At 1.0 every rectangle is as it was, the Reference's opening place included,
## launched and after a trip to 1.25 and back.
func test_at_1_0_the_rectangles_are_as_they_were() -> void:
    var dockers := _boot_at(1.0)
    var launched := _rects(dockers)
    _change_scale(dockers, 1.25)
    _change_scale(dockers, 1.0)
    var back := _rects(dockers)
    for section: String in AT_ONE:
        assert_eq(launched.get(section), AT_ONE[section], "%s opens where it did" % section)
        assert_eq(back.get(section), AT_ONE[section], "%s is back there after 1.25" % section)


## The boot's fit read floors that move once the dockers lay out, and the
## follow places them again as soon as one does, so the boot ends where a boot
## that read the settled floors would have begun. Probe windows stand in for
## the dockers, on a host where the floors bind.
func test_a_floor_that_moves_after_the_boot_places_the_dockers_again() -> void:
    var store := _probe_store(BINDING, BOOT_FLOORS, "boot")
    store.restore_all()
    var probes: Array = store.dockers_provider.call()
    var refit := SaDockerLayoutRefit.new(store.top_inset, SaDockerStoredEntry.floored)
    var answered := refit.shipped_entries(_live(store), probes)
    var at_boot := _probe_rects(store)
    var read := refit.floors(probes)
    for config: Dictionary in probes:
        if SETTLED_FLOORS.has(config["id"]):
            (config["node"] as Window).min_size = SETTLED_FLOORS[config["id"]]
    assert_true(refit.floors(probes) != read, "The floors the fit reads have moved")
    answered = refit.fitted_again(store, probes, answered)
    var settled := _probe_rects(store)
    var fresh := _probe_store(BINDING, SETTLED_FLOORS, "settled")
    fresh.restore_all()
    var wanted := _probe_rects(fresh)
    assert_true(at_boot != wanted, "On this host the two sets of floors give two layouts")
    assert_eq(settled, wanted, "and the boot ends where the settled floors place the dockers")
    assert_eq(refit.fitted_again(store, probes, answered), answered, "A second look with nothing moved answers the same")


## The rectangle of each docker of *dockers* that is open, and of the closed
## Reference, which the store has placed where it opens.
func _rects(dockers: MainDockers) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in dockers.get_docker_config():
        var section := DockerLayoutStore.section_for(config)
        var win: Window = config["node"] as Window
        if AT_ONE.has(section) and win != null and (win.visible or section == "ReferenceDocker"):
            out[section] = Rect2i(win.position, win.size)
    return out


## The registry's dockers in a viewport of the window's size at *scale*, with
## the bar bound, Tool Options following a brush and the shipped default
## restored, as at a first boot at that scale.
func _boot_at(scale: float) -> MainDockers:
    SaUI.user_scale = scale
    var viewport := SubViewport.new()
    viewport.name = "P6Viewport"
    viewport.size = WINDOW
    viewport.size_2d_override = Vector2i(Vector2(WINDOW) / scale) if scale != 1.0 else Vector2i()
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    var store := DockerLayoutStore.new()
    store.path = scratch_layout
    var dockers := MainDockers.new(SaUIRegistry.new(), store)
    viewport.add_child(dockers)
    dockers.bind_bar(_bar)
    dockers.register_builtin_dockers()
    var tool_options := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
    tool_options.peer_bar = _options
    tool_options.target_tool_machine = _machine
    _machine.set_active_tool(&"brush")
    tool_options.sync_from_tool()
    dockers.load_docker_layout()
    return dockers


## The last boot's viewport freed and its layout file gone, so the next boot is
## a first run again.
func _drop_the_boot() -> void:
    var viewport := _host.get_node_or_null("P6Viewport")
    if viewport != null:
        _host.remove_child(viewport)
        viewport.free()
    _remove_scratch_files()
    SaUI.user_scale = 1.0


## The scale change `SaSettingsApply._apply_ui_scale` makes, as the live-scale
## suite makes it: the host shrinks by the scale, the bus says so, and the store fits
## the layout again.
func _change_scale(dockers: MainDockers, scale: float) -> void:
    SaUI.user_scale = scale
    var viewport := dockers.get_parent() as SubViewport
    viewport.size_2d_override = Vector2i(Vector2(WINDOW) / scale) if scale != 1.0 else Vector2i()
    EventBus.ui_scale_changed.emit(SaUI.scale())
    dockers.layout_store.reflow_to_host()


## The last row a docker's foot may reach at *scale*, the status line's top.
func _above_the_line(scale: float) -> int:
    return int(WINDOW.y / scale) - SaDockerLayoutRefit.status_rows_in(1.0)


## How tall *docker*'s scroll is at the size the layout gave it,
## once its containers are sorted. A suite runs before any frame, and until a
## sort the line naming what the bar holds wraps at no width, a word to a line,
## and its height is taken from the scroll's.
func _scroll_height(docker: ToolOptionsDocker, scroll: ScrollContainer) -> int:
    for i in 2:
        _sort_children(docker)
        _ask_again(docker)
    var column := docker.content_column()
    var least := column.get_combined_minimum_size().y
    var around := least - scroll.get_combined_minimum_size().y
    return int(maxf(docker.size.y + column.offset_bottom, least) - around)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


## The first *count* rows the docker shows, each read side by side as the floor
## reads it, with the gaps between them and the margin around them.
func _first_rows_height(docker: ToolOptionsDocker, count: int) -> int:
    var rows := docker._rows_box
    var held := 0.0
    var counted := 0
    for key: StringName in docker.shown_keys():
        if counted == count:
            break
        held += ToolOptionsFloor.side_by_side_height(docker._rows[key] as Control)
        counted += 1
    var margin := rows.get_parent() as MarginContainer
    held += rows.get_theme_constant(&"separation") * maxi(counted - 1, 0)
    held += margin.get_theme_constant(&"margin_top") + margin.get_theme_constant(&"margin_bottom")
    return int(held)


## A store over probe windows on *host*, each with *floors* for its floor and
## the closed Reference with its own, as the default layout fit suite builds it. *named* keeps
## its file apart from another store's.
func _probe_store(host: Vector2i, floors: Dictionary, named: String) -> DockerLayoutStore:
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    var configs: Array = []
    var all := floors.duplicate()
    all["ReferenceDocker"] = REFERENCE_FLOOR
    all["BrushPresetsDocker"] = PRESETS_FLOOR
    for section: String in all:
        var probe := Window.new()
        probe.name = section
        probe.min_size = all[section]
        probe.size = all[section]
        # The real Reference and Brush Presets are hidden before a layout is
        # restored, and the fit gives only a hidden docker the place it opens
        # at, which differs from where it is kept on a host
        # the right column lies over.
        probe.visible = not CLOSED.has(section)
        parent.add_child(probe)
        configs.append({"id": section, "name": section, "node": probe})
    var store := DockerLayoutStore.new()
    store.path = _probe_path(named)
    store.dockers_provider = func() -> Array: return configs
    store.save_allowed = func() -> bool: return true
    store.top_inset = func() -> int: return TOP
    viewport.add_child(store)
    return store


static func _probe_path(named: String) -> String:
    return scratch_layout.get_basename() + "_%s.cfg" % named


## The rectangle of each probe *store* shows, and of the closed Reference,
## which is placed where it opens. A docker the fit closed keeps the place it
## had, which says nothing.
func _probe_rects(store: DockerLayoutStore) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in store.dockers_provider.call():
        var win: Window = config["node"]
        if win.visible or config["id"] == "ReferenceDocker":
            out[config["id"]] = Rect2i(win.position, win.size)
    return out


func _live(store: DockerLayoutStore) -> ConfigFile:
    var live := ConfigFile.new()
    live.load(store.path)
    return live


func _remove_scratch_files() -> void:
    var paths: Array[String] = [scratch_layout, ProjectSettings.globalize_path(scratch_profile)]
    for named: String in ["boot", "settled"]:
        paths.append(_probe_path(named))
    for path: String in paths:
        for suffix: String in ["", ".bak", ".broken"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(path + suffix)
