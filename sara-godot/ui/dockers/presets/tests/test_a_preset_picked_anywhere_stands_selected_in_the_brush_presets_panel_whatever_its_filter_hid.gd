## A preset picked from Recent Presets stands selected in the Brush Presets
## panel, its cell in the grid and scrolled into view, however the panel's search
## or tag had hidden it. The preset is selected because the user selected it, the
## search and the tag stay as the painter set them, and the cell is added for as long as the preset is in hand.
##
## The panel, Recent Presets and a real bar with a real store in the tree, the
## shape `test_the_presets_buttons_say_what_they_did.gd` builds, and the pick a
## press on Recent Presets' own row.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const HistoryScript = preload("res://ui/dockers/presets/history_docker.gd")

const REQUIRES_GPU := true

## Enough presets of one name that the grid outgrows the panel's scroll, and one
## last in the order that a search for the rest leaves out.
const MANY := 30
const HIDDEN := "Zeta Hidden"
const TAG := "hiddenink"

static var scratch_dir: String = SaDataRoot.path("test_hidden_presets")
static var scratch_list: String = SaDataRoot.path("test_hidden_recent.cfg")

var _tag_filter_before: Dictionary = {}


func before_each() -> void:
    _clean()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))
    _tag_filter_before = SaSettings.preset_tag_filter.duplicate()


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_before
    _clean()


func _clean() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_list))


static func _alpha(at: int) -> String:
    return "Alpha Many %02d" % at


func test_a_search_that_hid_the_preset_keeps_its_text_and_the_cell_is_added_selected_and_in_view() -> void:
    var built := await _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var chooser := docker.chooser
    chooser.search_field.text = "alpha"
    chooser.refresh()
    var searched := chooser.visible_names()
    assert_eq(searched.size(), MANY, "The search alone shows the Alpha presets")
    assert_false(searched.has(HIDDEN), "and hides Zeta")

    await _pick(built, HIDDEN)
    _assert_added_and_in_view(docker, searched, "alpha")

    await _pick(built, _alpha(1))
    _assert_taken_out(docker, searched, "alpha")
    _tear_down(built)


func test_a_tag_that_hid_the_preset_stays_on_and_the_cell_is_added_selected_and_in_view() -> void:
    var built := await _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var chooser := docker.chooser
    chooser.tag_filter.only(TAG)
    chooser.refresh()
    var tagged := chooser.visible_names()
    assert_eq(tagged.size(), MANY, "The tag alone shows the Alpha presets")
    assert_false(tagged.has(HIDDEN), "and hides Zeta")

    await _pick(built, HIDDEN)
    _assert_added_and_in_view(docker, tagged, "")
    assert_eq(SaSettings.preset_tag_filter, {TAG: SaBrushPresetTagFilter.SHOW}, "The tag stays as the painter set it")

    await _pick(built, _alpha(2))
    _assert_taken_out(docker, tagged, "")
    assert_eq(SaSettings.preset_tag_filter, {TAG: SaBrushPresetTagFilter.SHOW}, "and stays so after the next pick")
    _tear_down(built)


func test_a_pick_the_filter_shows_selects_its_cell_and_adds_nothing() -> void:
    var built := await _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var chooser := docker.chooser
    chooser.search_field.text = "alpha"
    chooser.refresh()
    var searched := chooser.visible_names()

    await _pick(built, _alpha(MANY))
    var report := chooser.chooser_report()
    assert_eq(String(report["marked"]), _alpha(MANY), "The pick the search shows is selected")
    assert_eq(String(report["added"]), "", "and nothing is added for it")
    assert_eq(chooser.visible_names(), searched, "The grid is what the search shows")
    assert_true(_in_view(docker, _alpha(MANY)), "and the cell, last in the grid, is scrolled into view")
    _tear_down(built)


## Zeta selected and in view, the search reading *search*, and the grid what
## *filtered* holds with Zeta in its place in the order, which is last.
func _assert_added_and_in_view(docker: BrushPresetsDocker, filtered: Array[String], search: String) -> void:
    var chooser := docker.chooser
    var report := chooser.chooser_report()
    assert_eq(chooser.search_field.text, search, "The search reads as typed")
    assert_eq(String(report["marked"]), HIDDEN, "The preset picked is the cell selected")
    assert_eq(String(report["added"]), HIDDEN, "added to the grid because the filter hides it")
    var wanted := filtered.duplicate()
    wanted.append(HIDDEN)
    assert_eq(chooser.visible_names(), wanted, "next to the cells the filter alone shows, in its place in the order")
    assert_true(_in_view(docker, HIDDEN), "and inside the scroll's visible area")


func _assert_taken_out(docker: BrushPresetsDocker, filtered: Array[String], search: String) -> void:
    var chooser := docker.chooser
    var report := chooser.chooser_report()
    assert_eq(chooser.search_field.text, search, "The search still reads as typed after another pick")
    assert_eq(String(report["added"]), "", "Another pick takes the added cell out")
    assert_eq(chooser.visible_names(), filtered, "and the grid is the filter's again")
    assert_false(chooser.grid.has_node("Cell_" + HIDDEN.validate_node_name()), "with no cell of Zeta left in it")


## Whether the cell of *stored_name* is built and inside the scroll's visible area.
func _in_view(docker: BrushPresetsDocker, stored_name: String) -> bool:
    var cell := docker.chooser.grid.get_node_or_null("Cell_" + stored_name.validate_node_name()) as Control
    var scroll := docker.find_child("Scroll", true, false) as ScrollContainer
    if cell == null or scroll == null:
        return false
    var seen := scroll.get_global_rect()
    var at := cell.get_global_rect()
    var outgrown := scroll.get_v_scroll_bar().max_value > seen.size.y
    assert_true(outgrown, "The grid outgrows the scroll, so a view has to be scrolled to")
    return seen.encloses(at)


## Presses the row of *stored_name* in Recent Presets, as a painter does, and
## lets the panel lay its grid out and scroll.
func _pick(built: Dictionary, stored_name: String) -> void:
    var history: HistoryDocker = built["history"]
    var row := history.rows.get_node_or_null("Row_" + stored_name) as Button
    assert_not_null(row, "Recent Presets has a row for %s" % stored_name)
    if row != null:
        row.pressed.emit()
    for i in 3:
        await _frame()


func _frame() -> void:
    await (Engine.get_main_loop() as SceneTree).process_frame


func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, which the docker searches for the bar")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "HiddenPresetsHost"
    EventBus.add_child(host)

    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()
    for at in range(1, MANY + 1):
        bar.save_current_as_preset(_alpha(at))
        bar.preset_store.assign_tag(_alpha(at), TAG)
    bar.save_current_as_preset(HIDDEN)

    var history: HistoryDocker = HistoryScript.new()
    history.path = scratch_list
    history.store.dir = scratch_dir
    host.add_child(history)
    history.show()

    var docker := DockerScript.new()
    host.add_child(docker)
    docker.show()
    docker.rebind()
    # Every preset the suite picks has a row in Recent Presets, as one loaded before.
    for stored_name: String in [HIDDEN, _alpha(MANY), _alpha(2), _alpha(1)]:
        bar.load_preset(stored_name)
    # Two frames, because Recent Presets writes its rows in a frame after the
    # load's, and the first test of a run can start before the tree's
    # first frame, whose number is then the load's.
    await _frame()
    await _frame()

    return {
        "tree": tree,
        "host": host,
        "bar": bar,
        "docker": docker,
        "history": history,
        "surface": surface,
        "machine": machine,
        "embedded": embedded
    }


func _tear_down(built: Dictionary) -> void:
    var tree: SceneTree = built["tree"]
    (built["host"] as Node).free()
    Fixtures.teardown(built["surface"], built["machine"])
    tree.root.gui_embed_subwindows = bool(built["embedded"])
