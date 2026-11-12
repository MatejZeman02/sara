## The dockers come back to their layout when subwindows are
## embedded again.
##
## Turning Embed subwindows off and on under Wayland must not pile every docker
## in the top left corner, over the menus. A position means the main window's
## logical space on one side of the switch and the screen's pixels on the other,
## and a window of the system under Wayland reads (0, 0) while it is out. So the
## layout store remembers each docker's place in the main window's terms before
## the switch and puts it back in the new side's units after it, and the row
## says what it does in a painter's words.
##
## Built the way the app builds it: a `DockerLayoutStore` in the tree, which is
## what hears `SaSettingsApply`, over three probe windows, and the switch thrown
## through `SaSettings.embed_subwindows`, whose handler is the one the two rows
## run. **The probes are never shown.** A window shown while the root does not
## embed maps a real window of the system and stalls the run, the rule
## `render/cursor/tests/test_cursor_modes.gd` states, and a hidden one still
## reports which side of the switch it is on and still takes a position, so
## everything but the picture is read here. The picture is
## `scenarios/the-dockers-come-back-to-their-layout-when-subwindows-are-embedded-again.json`.
extends "res://tests/test_framework.gd"

## The first logical row below the bar, the store's `top_inset`.
const TOP := 65

## Three dockers where a painter might leave them, all inside a 960 by 540
## logical host, which is the smallest the runner's window is at scale 2.
const PLACES := {
    "ToolBoxDocker": Vector2i(0, 78),
    "LayersDocker": Vector2i(600, 300),
    "ColorDocker": Vector2i(640, 80),
}

const SIZES := {
    "ToolBoxDocker": Vector2i(60, 300),
    "LayersDocker": Vector2i(300, 200),
    "ColorDocker": Vector2i(280, 300),
}

static var scratch_live: String = SaDataRoot.path("test_n62_docker_layout.cfg")

var _host: Node = null
var _store: DockerLayoutStore = null
var _probes: Dictionary = {}
var _saved_embed: bool = true
var _saved_scale: float = 1.0


func before_each() -> void:
    _saved_embed = SaSettings.embed_subwindows
    _saved_scale = SaSettings.ui_scale
    SaSettings.embed_subwindows = true
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)
    _host = Node.new()
    _host.name = "N62Host"
    EventBus.add_child(_host)
    _probes.clear()
    for section: String in PLACES:
        var probe := Window.new()
        probe.name = section
        probe.visible = false
        # Its own floor, as a docker has one, or the store floors a probe at
        # the generic docker minimum, which at scale 2 is wider than these.
        probe.min_size = SIZES[section]
        probe.size = SIZES[section]
        _host.add_child(probe)
        _probes[section] = probe
    _store = DockerLayoutStore.new()
    _store.path = scratch_live
    _store.dockers_provider = _entries
    _store.top_inset = func() -> int: return TOP
    _host.add_child(_store)


func after_each() -> void:
    SaSettings.embed_subwindows = _saved_embed
    SaSettings.ui_scale = _saved_scale
    if is_instance_valid(_host):
        _host.free()
    _host = null
    _store = null
    _probes.clear()
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)


func _entries() -> Array:
    var out: Array = []
    for section: String in _probes:
        out.append({"id": section, "name": section, "node": _probes[section]})
    return out


## Each probe put at its place and noted there, which is what a restore or a
## drag leaves in the store.
func _place_all() -> void:
    for section: String in PLACES:
        var probe: Window = _probes[section]
        probe.position = PLACES[section]
        _store.note_placement(probe)


## Where a place in the main window's logical space is on the screen, written
## out rather than asked of the code under test.
func _on_screen(place: Vector2i) -> Vector2i:
    var root := (Engine.get_main_loop() as SceneTree).root
    return root.position + Vector2i((Vector2(place) * SaUI.window_scale(root)).round())


func _assert_each_at_its_place(why: String) -> void:
    for section: String in PLACES:
        var probe: Window = _probes[section]
        assert_true(probe.is_embedded(), "%s is inside the main window again" % section)
        assert_eq(probe.position, PLACES[section], "%s %s" % [section, why])


## The note itself: three dockers placed, the switch off and on, each read back
## where it was.
func test_off_and_on_puts_each_docker_back_where_it_was() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    SaSettings.embed_subwindows = true
    _assert_each_at_its_place("is back where the painter put it")


## While they are out, each docker stands on the screen where it stood over the
## main window, the main window's corner plus its place at the main window's
## scale, which the switch must not drop.
func test_out_each_docker_stands_where_it_stood_over_the_window() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    for section: String in PLACES:
        var probe: Window = _probes[section]
        assert_false(probe.is_embedded(), "%s is a window of its own" % section)
        assert_eq(probe.position, _on_screen(PLACES[section]), "%s stands on the screen where it stood inside" % section)


## The same at scale 2, where the two sides' units differ by the factor and the
## old switch put a docker at x 600 of the screen for x 1200.
func test_at_scale_2_the_units_are_converted_both_ways() -> void:
    if _no_screen_is_1920_wide():
        skip("no screen here is 1920 wide, and the store keeps the dockers on the screens there are")
        return
    SaSettings.ui_scale = 2.0
    _place_all()
    SaSettings.embed_subwindows = false
    var layers: Window = _probes["LayersDocker"]
    assert_eq(layers.position, _on_screen(PLACES["LayersDocker"]), "out, the place is the screen's, at the scale")
    SaSettings.embed_subwindows = true
    _assert_each_at_its_place("is back at scale 2")


## What Wayland does: a window of the system is given no position, so every
## docker reads (0, 0) while it is out, and the switch back must not take that
## as the place. The store's own memory is what carries them.
func test_a_docker_the_system_gave_no_position_comes_back_all_the_same() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    for section: String in PLACES:
        (_probes[section] as Window).position = Vector2i()
    SaSettings.embed_subwindows = true
    _assert_each_at_its_place("is back, not in the corner")


## The same with a save while they are out, which a docker losing focus makes
## at the first click elsewhere. The store takes the (0, 0) it reads as the
## painter's place then, so its memory alone would pile them all the same.
func test_a_save_while_the_system_gave_no_position_does_not_pile_them() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    for section: String in PLACES:
        (_probes[section] as Window).position = Vector2i()
    _store.save()
    SaSettings.embed_subwindows = true
    _assert_each_at_its_place("is back after a save while out")


## A docker the painter dragged while it was out, which a system that does
## report positions allows, comes back in where the drag left it over the main
## window rather than where it was before.
func test_a_docker_moved_while_out_comes_back_where_it_was_moved() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    var layers: Window = _probes["LayersDocker"]
    var moved_to := Vector2i(400, 200)
    layers.position = _on_screen(moved_to)
    _store.save(true)
    SaSettings.embed_subwindows = true
    assert_eq(layers.position, moved_to, "the drag is kept across the switch")


## A docker let out above the main window's bar, which a window of its own can
## be dragged to, comes back in with its title below the bar, where a hand can
## still take it and the menus beside it still take a press.
func test_a_docker_out_above_the_bar_comes_back_below_it() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    var colour: Window = _probes["ColorDocker"]
    colour.position = _on_screen(Vector2i(640, 0))
    _store.save(true)
    SaSettings.embed_subwindows = true
    assert_eq(colour.position, Vector2i(640, TOP), "kept below the bar")


## The layout file names the side its numbers were written on, and a file from
## the other side is not read at a start. The switch writes it again at once,
## so a quit before anything else saved does not leave the next start ignoring
## the whole layout.
func test_the_file_is_written_in_the_new_units_at_once() -> void:
    _place_all()
    SaSettings.embed_subwindows = false
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(scratch_live), OK, "the switch wrote the file")
    assert_false(bool(cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_EMBEDDED, true)), "written as out")
    SaSettings.embed_subwindows = true
    cfg.load(scratch_live)
    assert_true(bool(cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_EMBEDDED, false)), "and as in again")
    assert_eq(cfg.get_value("LayersDocker", "position"), PLACES["LayersDocker"], "at the painter's place")


## A docker summoned under the pointer has a return address in the units the
## switch changes, so the borrow is given back before the switch, and the
## docker comes back to the painter's place rather than the summon's.
func test_a_summoned_docker_comes_back_to_the_painters_place() -> void:
    _place_all()
    var layers: Window = _probes["LayersDocker"]
    _store.borrow(layers, "LayersDocker", Vector2i(300, 300))
    layers.visible = false
    SaSettings.embed_subwindows = false
    SaSettings.embed_subwindows = true
    assert_false(_store.is_borrowed("LayersDocker"), "the borrow is given back")
    assert_eq(layers.position, PLACES["LayersDocker"], "and the docker is at the painter's place")


## The welcome window's switch writes the same setting, so it runs the same
## handler and the dockers come back from it as well.
func test_the_welcome_windows_switch_brings_them_back_too() -> void:
    _place_all()
    var pane := WelcomeQuickSettingsPane.new()
    pane.embed_check.toggled.emit(false)
    for section: String in PLACES:
        (_probes[section] as Window).position = Vector2i()
    pane.embed_check.toggled.emit(true)
    pane.free()
    _assert_each_at_its_place("is back from the welcome window's switch")


## The row says what a painter gets rather than the engine's word, its hint says
## what off does, and its key is still the setting's, which every scenario that
## drives it names, so `{"page_row": {"row": "embed_subwindows"}}` still finds it.
## The row is on Layouts and dockers.
func test_the_row_is_named_for_what_a_painter_sees() -> void:
    var page := SaDockersPage.new()
    _host.add_child(page)
    var row := page.page.row(&"embed_subwindows")
    assert_not_null(row, "the row is keyed by the setting")
    if row == null:
        return
    assert_eq(
        String(row.line.get_meta(SaSettingsRows.TITLE_META)), "Dockers inside the main window", "titled for what a painter sees"
    )
    var words: Array[String] = []
    for label: Label in row.line.find_children("*", "Label", true, false):
        words.append(label.text)
    assert_true(words.has(SaDockersPage.EMBED_HINT), "its hint says what off does")
    _place_all()
    row.drive(false)
    assert_false(SaSettings.embed_subwindows, "the row writes the setting it always wrote")
    row.drive(true)
    _assert_each_at_its_place("is back from the Layouts and dockers row")


## Whether no screen here is 1920 wide. These tests lay the shipped layout on a
## host of 1920 by 1080, and the store rightly keeps every docker on a screen,
## so on a smaller screen it puts them where no 1920 wide layout has them.
func _no_screen_is_1920_wide() -> bool:
    return SaDockerStoredEntry.all_screens_rect().size.x < 1920
