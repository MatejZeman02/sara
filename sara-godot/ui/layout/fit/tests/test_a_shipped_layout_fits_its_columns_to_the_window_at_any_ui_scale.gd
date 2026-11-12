## A shipped layout fits its columns to the window at any UI scale.
##
## The layouts Sara ships carry no UI scale, so a load keeps the painter's, and
## at 1.25 on a 1920 by 1080 window the host is 1536 by 864. Every shipped
## layout is fitted to its host and none is kept on it the way a resize keeps a
## painter's layout, or Minimalistic's Layers would stand at y 344 with its title
## under the Colour Picker. Each is fitted from its own file and with a close
## order of its own.
##
## Held here: each shipped layout loaded through the store on 1536 by 864 and
## on 1280 by 1024 opens no two dockers over each other and none off the host,
## the fit does the same on every size of [constant HOSTS], the host a file was
## written for gets the file, what each layout closes on the two named hosts, Full's middle as the two columns
## the file draws, and a painter's fork
## kept rather than fitted. The shot is
## `scenarios/a-shipped-layout-fits-its-columns-to-the-window-at-any-ui-scale.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The first row below a one-row bar, `MainDockers.below_bar` with no bar.
const TOP := 65

## Each docker's floor as the fit is handed it on the running app, the column's
## want included: the largest a run of the four layouts at a UI scale of 1 and
## of 1.25 read. The Colour Picker's is 294 wide with the slider rows Useful and
## Full show. The Tool Options' height moves with what the tool shows, 274 to
## 281 in the run, and once 319 on a default 1048 tall, which is over Useful's
## 300 and would grow it there whatever the fit did. The Stats docker's is
## [constant STATS_FLOOR].
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

## The Stats docker's floor, what Full read at 1 and at 1.25 alike with the
## quantizer's slider beside its switch and its line, 294 by 172. The docker lives in the base modules, so its
## section's name is read from its module rather than written here.
const STATS_FLOOR := Vector2i(294, 172)

## The Stats docker's section in the layout files, as its module names it.
static var stats_id: String = String(load(Fixtures.STATS_MODULE).Docker.DOCKER_ID)

## [constant FLOORS] and the Stats docker's beside them.
static var floors: Dictionary = _floors_with_stats()

## The two named hosts: a 1920 by 1080 window at a UI scale of 1.25,
## and the 1280 by 1024 panel at 1.
const NAMED_HOSTS: Array[Vector2i] = [Vector2i(1536, 864), Vector2i(1280, 1024)]

## Those two and the rest a painter's window and scale make: 1920 by 1080 and
## the 1048 a capture's window is, the same at 1.25 on the panel, at 2 on
## 1280 by 800 and 1280 by 1024, and the laptops between.
const HOSTS: Array[Vector2i] = [
    Vector2i(1920, 1080),
    Vector2i(1920, 1048),
    Vector2i(1536, 864),
    Vector2i(1280, 1024),
    Vector2i(1024, 819),
    Vector2i(2560, 1440),
    Vector2i(1600, 900),
    Vector2i(1440, 900),
    Vector2i(1366, 768),
    Vector2i(1280, 800),
    Vector2i(1024, 640),
    Vector2i(960, 540),
    Vector2i(640, 512),
    Vector2i(640, 400),
]

## What each layout closes on [constant NAMED_HOSTS], in that order. Useful on
## the panel closes the Minimap and the Graph for the painting's two fifths, and
## Full there takes the Recorder, the Graph and the Stats, and on the shorter
## panel the Recent Presets as well, which its middle columns would lay over the
## left column. Full opens without the Info and the Pop-up Palette, so those two
## are never in the answer.
const FULL_SHARE := 0.17

const CLOSED_ON_NAMED_HOSTS := {
    "default": [[], []],
    "minimalistic": [[], []],
    "useful": [[], ["GraphDocker", "MinimapDocker"]],
    "full": [["GraphDocker", "RecorderDocker", "StatsDocker"], ["GraphDocker", "HistoryDocker", "RecorderDocker", "StatsDocker"]],
    "krita": [[], []],
    "photoshop": [[], []],
    "clip_studio": [[], []],
}

static var scratch_live: String = SaDataRoot.path("test_d50_docker_layout.cfg")
static var scratch_presets_dir: String = SaDataRoot.path("layouts")

var _root: Node = null
var _store: DockerLayoutStore = null

## What a preset load writes beyond geometry, put back after every test, for
## the reason `test_docker_layout_presets.gd` gives.
var _saved_state := ConfigFile.new()


func after_each() -> void:
    SaFocusMode.active = false
    if _store != null:
        _store.presets().apply(_saved_state)
        _store = null
    if _root != null:
        _root.free()
        _root = null
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)
    var dir := DirAccess.open(scratch_presets_dir)
    if dir != null:
        for file_name in dir.get_files():
            if file_name.ends_with(" (custom).cfg"):
                DirAccess.remove_absolute(scratch_presets_dir.path_join(file_name))


static func _floors_with_stats() -> Dictionary:
    var out := FLOORS.duplicate()
    out[stats_id] = STATS_FLOOR
    return out


static func _shipped_path(preset_name: String) -> String:
    return SaDockerLayoutPresets.SHIPPED_DIR.path_join(preset_name + ".cfg")


## *preset_name*'s open dockers, section to `{"rect", "min"}`, the floor raised
## by the file's own `floor_size` the way the refit raises it.
func _shipped(preset_name: String) -> Dictionary:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(_shipped_path(preset_name)), OK, "%s reads" % preset_name)
    var out: Dictionary = {}
    for section in cfg.get_sections():
        if String(section).begins_with("_") or not bool(cfg.get_value(section, "visible", false)):
            continue
        var rect := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
        var floor_size: Vector2i = cfg.get_value(section, SaDockerLayoutRefit.FLOOR_SIZE, Vector2i())
        out[section] = {"rect": rect, "min": floor_size.max(floors[section])}
    return out


## The fit of *preset_name* on *host*, with the file's host and close order.
func _fit(preset_name: String, host: Vector2i) -> SaDockerLayoutFit:
    var cfg := ConfigFile.new()
    cfg.load(_shipped_path(preset_name))
    var meta := DockerLayoutStore.META_SECTION
    var written_for: Vector2i = cfg.get_value(meta, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
    return SaDockerLayoutFit.new(host, TOP, written_for, cfg.get_value(meta, SaDockerLayoutRefit.CLOSE_ORDER, []))


## Every pair of *placed* that lies one over the other, and every rectangle not
## wholly on *host* below the bar, as lines a failure reads.
static func _faults(placed: Dictionary, host: Vector2i) -> Array[String]:
    var out: Array[String] = []
    var screen := Rect2i(Vector2i(0, TOP), host - Vector2i(0, TOP))
    var sections := placed.keys()
    for i in sections.size():
        var rect: Rect2i = placed[sections[i]]
        if not screen.encloses(rect):
            out.append("%s %s off the host" % [sections[i], rect])
        for j in range(i + 1, sections.size()):
            if rect.intersects(placed[sections[j]]):
                out.append("%s over %s" % [sections[i], sections[j]])
    return out


func test_each_shipped_layout_names_its_host_and_closes_every_open_docker_but_the_toolbox() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(_shipped_path(preset_name)), OK, "%s reads" % preset_name)
        var meta := DockerLayoutStore.META_SECTION
        var written_for: Vector2i = cfg.get_value(meta, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
        assert_eq(written_for, Vector2i(1920, 1080), "%s says the host it was written for" % preset_name)
        var order: Array = cfg.get_value(meta, SaDockerLayoutRefit.CLOSE_ORDER, [])
        var open := _shipped(preset_name).keys()
        open.erase("ToolBoxDocker")
        open.sort()
        var ordered := order.duplicate()
        ordered.sort()
        assert_eq(ordered, open, "%s's close order names every docker it opens but the toolbox, once" % preset_name)


func test_on_every_host_no_docker_lies_over_another_or_off_the_host() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var dockers := _shipped(preset_name)
        for host in HOSTS:
            var placed := _fit(preset_name, host).place(dockers)
            assert_true(placed.has("ToolBoxDocker"), "%s keeps the toolbox at %s" % [preset_name, host])
            assert_eq(_faults(placed, host), [] as Array[String], "%s at %s" % [preset_name, host])
            for section: String in placed:
                var rect: Rect2i = placed[section]
                var floor_size: Vector2i = dockers[section]["min"]
                var floored := rect.size.x >= floor_size.x and rect.size.y >= floor_size.y
                assert_true(floored, "%s %s keeps its floor in %s at %s" % [section, rect, preset_name, host])


func test_the_host_a_file_was_written_for_gets_the_file() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var dockers := _shipped(preset_name)
        var placed := _fit(preset_name, Vector2i(1920, 1080)).place(dockers)
        assert_eq(placed.size(), dockers.size(), "%s opens every docker its file opens" % preset_name)
        for section: String in dockers:
            var stored: Rect2i = dockers[section]["rect"]
            assert_eq(placed.get(section), stored, "%s is where %s puts it" % [section, preset_name])


## What a file's columns leave the painting on its own host is all it asks of
## any other, and never more than two fifths. Full leaves it 60 of 1920 with the
## Info and the Pop-up Palette open. They ship closed, and its middle columns
## overlap one another across, so the share the fit holds for Full is the
## [constant FULL_SHARE] below and not the span the painter sees at home.
func test_the_painting_keeps_the_share_its_file_leaves_it() -> void:
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var dockers := _shipped(preset_name)
        var at_home := _fit(preset_name, Vector2i(1920, 1080)).place(dockers)
        var share := minf(SaDockerLayoutFit.PAINTING_SHARE, _painting(at_home, 1920) / 1920.0)
        if preset_name == "full":
            share = FULL_SHARE
        for host in HOSTS:
            var painting := _painting(_fit(preset_name, host).place(dockers), host.x)
            var asked := "%d of %d in %s" % [painting, host.x, preset_name]
            assert_true(painting >= floorf(host.x * share), "the painting keeps %s" % asked)


static func _painting(placed: Dictionary, width: int) -> int:
    var spans: Array[Vector2i] = []
    for rect: Rect2i in placed.values():
        spans.append(Vector2i(rect.position.x, rect.end.x))
    return width - SaWorkspacePage.covered_width(spans)


func test_what_each_layout_closes_on_the_two_named_hosts() -> void:
    for preset_name: String in CLOSED_ON_NAMED_HOSTS:
        var dockers := _shipped(preset_name)
        for i in NAMED_HOSTS.size():
            var placed := _fit(preset_name, NAMED_HOSTS[i]).place(dockers)
            var closed: Array = []
            for section: String in dockers:
                if not placed.has(section):
                    closed.append(section)
            closed.sort()
            assert_eq(closed, CLOSED_ON_NAMED_HOSTS[preset_name][i], "what %s closes at %s" % [preset_name, NAMED_HOSTS[i]])


## Full's middle is the Recorder over the Graph over the Recent Presets, and
## beside them the Minimap over the Stats over the Undo History, the last of
## which overlaps the Graph's span by 80. One column of the six stacked them on
## 1920 by 1080, and on 1700 by 900 the two stay side by side, the first
## squeezed to 246 wide. A host as small as 1536 by 864 closes the Recorder, the
## Graph and the Stats, which the Info and the Pop-up Palette used to do before
## they shipped closed. The Stats stands under the Minimap, where the file puts it.
func test_fulls_middle_is_the_two_columns_its_file_draws() -> void:
    var placed := _fit("full", Vector2i(1700, 900)).place(_shipped("full"))
    assert_eq(placed["RecorderDocker"], Rect2i(734, 79, 246, 270), "the Recorder heads the first")
    assert_eq(placed["GraphDocker"], Rect2i(814, 370, 246, 300), "the Graph under it")
    assert_eq(placed["HistoryDocker"], Rect2i(734, 680, 246, 205), "and the Recent Presets gives the height up")
    assert_eq(placed["MinimapDocker"], Rect2i(1076, 79, 294, 230), "the Minimap heads the second")
    assert_eq(placed[stats_id], Rect2i(1076, 319, 294, 352), "and the Stats under it")
    assert_eq(placed["UndoDocker"], Rect2i(980, 680, 240, 205), "and the Undo History stands beside the Recent Presets")


## A host of *host* embedding one probe window per built-in docker, each at its
## floor in [member floors], and the store over them.
func _store_on(host: Vector2i) -> DockerLayoutStore:
    _root = Node.new()
    _root.name = "D50Host"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    var configs: Array = []
    for section: String in floors:
        var probe := Window.new()
        probe.name = section
        probe.min_size = floors[section]
        probe.size = floors[section]
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


## The rectangle of every docker open in *store*.
static func _open_rects(store: DockerLayoutStore) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in store.dockers_provider.call():
        var win: Window = config["node"]
        if win.visible:
            out[config["id"]] = Rect2i(win.position, win.size)
    return out


## The note's case through the door a painter uses: each layout loaded from the
## Window menu's store, on a 1920 by 1080 window at 1.25 and on the panel.
func test_each_shipped_layout_loaded_on_the_two_named_hosts_lays_nothing_over_anything() -> void:
    for host in NAMED_HOSTS:
        var store := _store_on(host)
        for preset_name: String in SaDockerLayoutPresets.SHIPPED:
            assert_true(store.load_preset(preset_name), "%s loads at %s" % [preset_name, host])
            var opened := _open_rects(store)
            assert_eq(_faults(opened, host), [] as Array[String], "%s loaded at %s" % [preset_name, host])
            var above_the_line := host - Vector2i(0, SaStatusLine.rows_taken())
            var placed := _fit(preset_name, above_the_line).place(_shipped(preset_name))
            assert_eq(opened, placed, "%s opens where the fit puts it at %s" % [preset_name, host])
            assert_eq(store.current_preset(), preset_name, "and is still %s, forked by nothing" % preset_name)
        _store.presets().apply(_saved_state)
        _store = null
        _root.free()
        _root = null


## Minimalistic at 1.25 on a 1920 by 1080 window, the reference case: the
## Layers docker under the Colour Picker's foot rather than its title under it.
func test_minimalistic_at_1_25_puts_the_layers_under_the_colour_picker() -> void:
    var store := _store_on(NAMED_HOSTS[0])
    store.load_preset("minimalistic")
    var opened := _open_rects(store)
    var colour: Rect2i = opened["ColorDocker"]
    var layers: Rect2i = opened["LayersDocker"]
    assert_eq(colour, Rect2i(1216, 79, 310, 396), "the Colour Picker 10 in from the right edge")
    assert_eq(layers.position, Vector2i(1216, colour.end.y + 10), "the Layers title 10 under its foot")
    var line := SaStatusLine.rows_taken()
    assert_eq(layers.end.y, 864 - line - SaDockerLayoutFit.BOTTOM_MARGIN, "and its own foot at the margin above the line")


## A painter's fork is only ever kept, and a live file naming no layout Sara
## ships is not fitted.
func test_a_fork_or_a_name_sara_does_not_ship_is_not_fitted() -> void:
    var store := _store_on(NAMED_HOSTS[0])
    var refit := SaDockerLayoutRefit.new(func() -> int: return TOP, func(_win: Window, size: Vector2i) -> Vector2i: return size)
    for named: String in ["full", "full (custom)", "a module/desk", ""]:
        var live := ConfigFile.new()
        live.load(_shipped_path("full"))
        live.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, named)
        var entries := refit.shipped_entries(live, store.dockers_provider.call())
        assert_eq(entries.is_empty(), named != "full", "a live file naming '%s' is fitted only when it is Full" % named)
