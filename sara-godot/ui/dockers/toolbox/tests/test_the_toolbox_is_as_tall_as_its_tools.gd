## The toolbox is as tall as its tools and says what its groups
## hold.
##
## Every shipped layout gave the toolbox 520 for five buttons, and the default size should be "computed by code to fit exactly
## what is there". The default is fitted at 1920 by 1080 and at 1280 by 1024
## with a real toolbox and a real Layers docker holding one layer among probe
## windows for the other four, and the toolbox opens at its buttons' height
## while the Layers docker keeps the layout's, though its one layer is shorter
## still. A layout the painter saved keeps its heights, and a shipped layout
## that is not the default opens the toolbox at its buttons' height too. A
## grouped button's tooltip names the tools a right press opens, the bar's
## names the docker, and the corner mark is drawn muted.
##
## Every tool outside the two groups a button of its own,
## twelve of them in the fixture's registry, which a column of 520 cuts short,
## so the shipped layouts give the toolbox 800 and it still opens at its buttons.
##
## The shots are `scenarios/the-toolbox-is-as-tall-as-its-tools-and-says-what-its-groups-hold.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## The first row below a one-row bar, as the other toolbox suites have it.
const TOP := 65

## The two open dockers of the default that stand in as probes, with the
## floors a fresh profile's dump reads at scale 1. The Brush Presets is closed
## in the default, so it is not a probe.
const PROBES := {
    "ToolOptionsDocker": Vector2i(160, 132),
    "ColorDocker": Vector2i(225, 212),
}

## What every shipped layout gives the toolbox, which is what it no longer opens at.
const SHIPPED_TOOLBOX := Vector2i(60, 800)

static var scratch_live: String = SaDataRoot.path("test_n41_docker_layout.cfg")

var _root: Node = null
var _toolbox: ToolBoxDocker = null
var _layers: LayersDocker = null


func after_each() -> void:
    if _root != null:
        _root.free()
        _root = null
    _toolbox = null
    _layers = null
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)


## A host of *host* embedding the real toolbox, the real Layers docker on a
## document of one layer and a probe for each of the rest, and the store over
## them reading the live file.
func _store_on(host: Vector2i) -> DockerLayoutStore:
    _root = Node.new()
    _root.name = "N41Host"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    var configs: Array = []

    _toolbox = ToolBoxDockerScript.new() as ToolBoxDocker
    _toolbox.name = "ToolBoxDocker"
    parent.add_child(_toolbox)
    _toolbox.rebuild_from_registry(Fixtures.make_tool_registry())
    configs.append({"id": "ToolBoxDocker", "name": "ToolBoxDocker", "node": _toolbox})

    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    parent.add_child(canvas)
    _layers = LayersDockerScript.new() as LayersDocker
    _layers.name = "LayersDocker"
    canvas.add_child(_layers)
    _layers.target_canvas = canvas
    configs.append({"id": "LayersDocker", "name": "LayersDocker", "node": _layers})

    for section: String in PROBES:
        var probe := Window.new()
        probe.name = section
        probe.min_size = PROBES[section]
        probe.size = PROBES[section]
        parent.add_child(probe)
        configs.append({"id": section, "name": section, "node": probe})
    var store := DockerLayoutStore.new()
    store.path = scratch_live
    store.dockers_provider = func() -> Array: return configs
    store.save_allowed = func() -> bool: return true
    store.top_inset = func() -> int: return TOP
    _root.add_child(store)
    return store


## The shipped default with its preset name set to *preset*, as the live file.
func _live_default(preset: String) -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_PRESET, preset)
    cfg.save(scratch_live)


## The shipped default's open dockers as the fit takes them, with no docker
## saying how tall its content is: what every docker opened at before docker heights were fitted.
func _fitted_without_content(store: DockerLayoutStore, host: Vector2i) -> Dictionary:
    var cfg := ConfigFile.new()
    cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS)
    var written_for: Vector2i = cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_WRITTEN_FOR)
    var dockers: Dictionary = {}
    for config: Dictionary in store.dockers_provider.call():
        var section: String = config["id"]
        var win: Window = config["node"]
        var rect := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
        # The store reads a docker's `floor_size` from the file as the least the
        # fit may give it, the Layers' 272 since its column was cut to 343 tall
        # to make room for the 250 tall Minimap, so the reading here does too.
        var floor_size: Vector2i = cfg.get_value(section, "floor_size", Vector2i())
        dockers[section] = {"rect": rect, "min": win.min_size.max(floor_size)}
    var above_the_line := host - Vector2i(0, SaStatusLine.rows_taken())
    return SaDockerLayoutFit.new(above_the_line, TOP, written_for).place(dockers)


## The default fitted on *host*: the toolbox at its buttons' height, which
## shows every button, and the Layers docker at the layout's.
func _assert_fitted_on(host: Vector2i) -> void:
    _live_default(SaDockerLayoutPresets.DEFAULT_PRESET)
    var store := _store_on(host)
    store.restore_all()
    var opening := _toolbox.opening_height(SHIPPED_TOOLBOX)
    var buttons := _toolbox.grid_container.get_combined_minimum_size().y
    assert_true(opening >= buttons, "the toolbox's own height holds its %d of buttons at %s" % [buttons, host])
    assert_true(opening < SHIPPED_TOOLBOX.y, "and is less than the 800 every layout gives it, %d" % opening)
    assert_eq(_toolbox.size.y, opening, "the toolbox opens at its buttons' height at %s" % host)
    assert_eq(_toolbox.size.x, SHIPPED_TOOLBOX.x, "at the width the layout gives it")

    var before := _fitted_without_content(store, host)
    assert_eq(_layers.size, before["LayersDocker"].size, "the Layers docker keeps the layout's height at %s" % host)
    var one_layer := DockerWindow.column_content_height(_layers)
    assert_true(one_layer < _layers.size.y, "though its one layer, %d, is shorter than that" % one_layer)
    for section: String in PROBES:
        var probe: Window = _root.find_child(section, true, false)
        assert_eq(Rect2i(probe.position, probe.size), before[section], "%s is where it was at %s" % [section, host])


func test_the_default_at_1920_by_1080_opens_the_toolbox_at_its_buttons() -> void:
    _assert_fitted_on(Vector2i(1920, 1080))


func test_the_default_at_1280_by_1024_opens_the_toolbox_at_its_buttons() -> void:
    _assert_fitted_on(Vector2i(1280, 1024))


func test_a_resize_keeps_the_toolbox_at_its_buttons() -> void:
    _live_default(SaDockerLayoutPresets.DEFAULT_PRESET)
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    var opened := _toolbox.size
    (_root.get_child(0) as SubViewport).size = Vector2i(1280, 1024)
    store.reflow_to_host()
    assert_eq(_toolbox.size, opened, "a reflow fits the default again and the toolbox keeps its buttons' height")


func test_a_layout_the_painter_saved_keeps_its_heights() -> void:
    _live_default("default (custom)")
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    assert_eq(_toolbox.size, SHIPPED_TOOLBOX, "a painter's layout gives the toolbox the height it was saved with")
    assert_eq(_layers.size, Vector2i(310, 343), "and the Layers docker its own")


func test_a_shipped_layout_that_is_not_the_default_opens_the_toolbox_at_its_buttons() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load("res://layouts/useful.cfg"), OK, "the useful layout reads")
    var written: Vector2i = cfg.get_value("LayersDocker", "size")
    cfg.save(scratch_live)
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    assert_eq(_toolbox.size.y, _toolbox.opening_height(SHIPPED_TOOLBOX), "the toolbox at its buttons' height in a shipped layout")
    assert_true(
        _layers.size.y <= written.y and _layers.size.y >= 272,
        "and the Layers docker at the file's, or less where the foot of the window takes some"
    )


## A toolbox the painter dragged into a row is measured as the column the
## layout makes of it. Measured as it stood, it read the row's height, and the
## rectangle cut to that stayed a row.
func test_a_toolbox_dragged_into_a_row_opens_the_layouts_column() -> void:
    _live_default(SaDockerLayoutPresets.DEFAULT_PRESET)
    var store := _store_on(Vector2i(1920, 1080))
    _toolbox.size = Vector2i(700, 90)
    assert_true(_toolbox.grid_container.columns > 1, "the drag made a row of it first")
    var as_a_row := DockerWindow.column_content_height(_toolbox)
    store.restore_all()
    assert_eq(_toolbox.grid_container.columns, 1, "the layout's rectangle makes a column of it")
    assert_eq(_toolbox.size.y, _toolbox.opening_height(SHIPPED_TOOLBOX), "at the column's height")
    assert_true(_toolbox.size.y > as_a_row, "and not the row's %d" % as_a_row)
    assert_eq(_toolbox.grid_container.columns, 1, "and the measurement left the grid as the size says")


## A shipped layout other than the default cuts against the shipped file, so a
## height an earlier session saved under its name is not where it stops. A
## toolbox saved at 200, with fewer tools than now, opens at its buttons' height.
func test_a_shipped_layout_cuts_against_the_shipped_file_and_not_the_last_save() -> void:
    var cfg := ConfigFile.new()
    cfg.load("res://layouts/useful.cfg")
    cfg.set_value("ToolBoxDocker", "size", Vector2i(60, 200))
    cfg.save(scratch_live)
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    var opening := _toolbox.opening_height(SHIPPED_TOOLBOX)
    assert_true(opening > 200, "five buttons want more than the 200 the last session saved, %d" % opening)
    assert_eq(_toolbox.size.y, opening, "and the toolbox grows back to them")


## A shipped layout's live file holding the toolbox as a row opens it as the
## shipped file's column, the way the default does. It was measured at the
## row's width and opened as saved until the fit read all four shipped
## layouts from their own files.
func test_a_row_in_a_shipped_layout_opens_the_shipped_column() -> void:
    var cfg := ConfigFile.new()
    cfg.load("res://layouts/useful.cfg")
    cfg.set_value("ToolBoxDocker", "size", Vector2i(700, 90))
    cfg.save(scratch_live)
    var store := _store_on(Vector2i(1920, 1080))
    store.restore_all()
    assert_eq(_toolbox.grid_container.columns, 1, "the shipped rectangle makes a column of it")
    assert_eq(_toolbox.size.y, _toolbox.opening_height(SHIPPED_TOOLBOX), "at the column's height")


func test_a_docker_that_says_nothing_keeps_the_layouts_height() -> void:
    var probe := Window.new()
    assert_eq(SaDockerLayoutRefit.opening_height(probe, SHIPPED_TOOLBOX), 0, "a window with no opening height asks for none")
    probe.free()


## The fit's own half: a docker shorter than the file asks its content's
## height, the one under it in its column keeps its gap and moves up, and a
## docker longer than the file opens at its content's height too, so a tool
## added since the file was written is never cut off.
func test_a_column_closes_up_under_a_docker_that_opens_at_its_content() -> void:
    var dockers := {
        "Top": {"rect": Rect2i(0, 100, 300, 400), "min": Vector2i(100, 100), "content": 250},
        "Under": {"rect": Rect2i(0, 510, 300, 300), "min": Vector2i(100, 100), "content": 500},
    }
    var placed := SaDockerLayoutFit.new(Vector2i(1920, 1080), TOP, Vector2i(1920, 1080)).place(dockers)
    assert_eq(placed["Top"], Rect2i(0, 100, 300, 250), "the top docker opens at its content's height")
    assert_eq(
        placed["Under"], Rect2i(0, 360, 300, 500), "the one under it keeps its gap of 10 and opens at its own content's height"
    )


## No group of the default holds three tools, so the
## lasso is dragged in with the marquees, and the profile put back after.
func test_a_grouped_buttons_tooltip_names_what_a_right_press_opens() -> void:
    var order := SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    var groups_raw: Variant = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY)
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    var registry := Fixtures.make_tool_registry()
    var select := docker._group_names.find("select")
    assert_true(docker.move_tool("lasso", select, 2, false), "the lasso joins the marquees")
    var members := docker.tools_in_category_of("marquee")
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, groups_raw)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, order)
    assert_true(members.size() > 2, "the marquee's group holds more than two tools, %s" % [members])
    var names := PackedStringArray()
    for tool_id: String in members.slice(1):
        names.append(registry.get_descriptor(StringName(tool_id)).display_name)
    var tip := docker.button_for_tool("marquee").tooltip_text
    var listed := "%s and %s" % [", ".join(names.slice(0, -1)), names[-1]]
    assert_true(tip.ends_with(". Right-click for %s." % listed), "the tooltip names the group's other tools: %s" % tip)
    assert_true(tip.begins_with(registry.get_descriptor(&"marquee").display_name + " ("), "after the face and its chord")
    var alone := docker.button_for_tool("eyedropper").tooltip_text
    assert_false(alone.contains("Right-click"), "a group of one promises no flyout: %s" % alone)
    docker.free()


func test_a_group_of_two_names_its_other_tool_alone() -> void:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    var members := docker.tools_in_category_of("bucket_fill")
    assert_eq(members.size(), 2, "the fills' group holds two tools, %s" % [members])
    var other := Fixtures.make_tool_registry().get_descriptor(StringName(members[1])).display_name
    var tip := docker.button_for_tool("bucket_fill").tooltip_text
    assert_true(tip.ends_with(". Right-click for %s." % other), "one name and no 'and': %s" % tip)
    docker.free()


func test_the_bar_names_the_docker_and_the_mark_is_muted() -> void:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    assert_eq(docker.drag_handle.tooltip_text, "Toolbox", "the bar, which has room for the wrench alone, says what it is")
    var mark := docker.button_for_tool("marquee").get_node("FlyoutMark") as Control
    var colour := mark.get_theme_color(&"font_color")
    assert_eq(colour, SaTheme.palette.text_muted, "the corner mark is drawn in the muted text colour")
    docker.free()
