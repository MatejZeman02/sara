## The Brush Presets panel has a Random button that loads one of the presets
## its filter shows, chosen at random from the filtered presets.
##
## The real bar and the real panel in the tree over a store of twelve presets
## a tag shows, four it hides, and one more under the tag that is of an engine
## no tool takes, so its cell is dimmed. The press is the button's own `pressed`
## signal, the one a click sends.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

const TAG := "randompick"
const SHOWN := 12
const HIDDEN := 4
const GHOST := "Kept Pick Ghost"
const PRESSES := 60

static var scratch_dir: String = SaDataRoot.path("test_random_presets")

var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null
var _button: SaRandomPresetButton = null
var _tag_filter_before: Dictionary = {}


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _tag_filter_before = SaSettings.preset_tag_filter.duplicate()


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_before
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _bar = null
    _docker = null
    _button = null
    ScratchFolder.clear(scratch_dir)


static func _kept(at: int) -> String:
    return "Kept Pick %02d" % at


static func _other(at: int) -> String:
    return "Other Pick %02d" % at


func _build() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    var tagged := PackedStringArray([TAG])
    for at in range(1, SHOWN + 1):
        _bar.preset_store.save_preset(_kept(at), StampSettingsScript.new(), tagged)
    for at in range(1, HIDDEN + 1):
        _bar.preset_store.save_preset(_other(at), StampSettingsScript.new())
    var ghost_meta := {SaPresetMeta.ENGINE_META: &"ghost"}
    _bar.preset_store.save_preset(GHOST, StampSettingsScript.new(), tagged, ghost_meta)
    _bar._ready()
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.rebind()
    _button = _docker.find_child("ChooserRandom", true, false) as SaRandomPresetButton


func _loaded() -> String:
    return _bar.preset_box.selected_preset


func _filter_by_tag() -> void:
    _docker.chooser.tag_filter.only(TAG)
    _docker.chooser.refresh()


func _search(text: String) -> void:
    _docker.chooser.search_field.text = text
    _docker.chooser.search_field.text_changed.emit(text)


func test_sixty_presses_load_only_presets_the_filter_shows_never_the_one_in_hand() -> void:
    _build()
    assert_not_null(_button, "The panel has a Random button")
    if _button == null:
        return
    assert_eq(_button.text, "Random", "labelled Random")
    _filter_by_tag()
    var shown := _docker.chooser.visible_names()
    assert_eq(shown.size(), SHOWN + 1, "The tag shows the twelve and the dimmed one")
    # The preset in hand is one the tag hides, so the grid adds its cell.
    _docker.apply_preset(_other(1))
    assert_eq(String(_docker.chooser.chooser_report()["added"]), _other(1), "The preset in hand is added to the grid")
    var reached: Dictionary[String, bool] = {}
    for press in PRESSES:
        var before := _loaded()
        _button.pressed.emit()
        var now := _loaded()
        assert_true(shown.has(now), "Press %d loads a preset the filter shows: %s" % [press, now])
        assert_false(now.begins_with("Other Pick"), "never a hidden one, nor the cell added for the one in hand")
        assert_true(now != GHOST, "never the cell dimmed for the tool in hand")
        assert_true(now != before, "never the preset that was in hand")
        reached[now] = true
    assert_true(reached.size() > 1, "More than one preset was reached: %s" % [reached.keys()])
    print("Sixty presses reached %d of %d presets" % [reached.size(), SHOWN])


func test_a_press_leaves_the_search_and_tags_as_they_were_and_marks_the_pick() -> void:
    _build()
    if _button == null:
        return
    _filter_by_tag()
    _search("pick")
    var before := _docker.chooser.chooser_report()
    _button.pressed.emit()
    var after := _docker.chooser.chooser_report()
    assert_eq(after["search"], before["search"], "The search reads as it did")
    assert_eq(after["tag_filter"], before["tag_filter"], "and the tags are as they were")
    assert_eq(SaSettings.preset_tag_filter, {TAG: SaBrushPresetTagFilter.SHOW}, "with only the tag shown")
    assert_false(_loaded().is_empty(), "A preset was loaded")
    assert_eq(String(after["marked"]), _loaded(), "and its cell is the one marked in the grid")


func test_the_button_is_disabled_with_none_shown_or_only_the_one_in_hand() -> void:
    _build()
    if _button == null:
        return
    _filter_by_tag()
    _search("nothing is called this")
    await _frame()
    assert_eq(_docker.chooser.visible_names().size(), 0, "The search hides every preset")
    assert_true(_button.disabled, "so Random is disabled, once the frame the search came in ends")
    assert_true(_button.tooltip_text.contains("No preset is shown"), "and says why: %s" % _button.tooltip_text)

    _docker.apply_preset(_kept(1))
    _search(_kept(1).to_lower())
    await _frame()
    assert_eq(_docker.chooser.visible_names(), [_kept(1)] as Array[String], "Only the preset in hand is shown")
    assert_true(_button.disabled, "so Random is disabled")
    assert_true(_button.tooltip_text.contains("Only the preset in hand"), "and says why: %s" % _button.tooltip_text)

    _search(_kept(2).to_lower())
    await _frame()
    assert_false(_button.disabled, "With one other shown, Random can be pressed")
    _button.pressed.emit()
    assert_eq(_loaded(), _kept(2), "and a press loads that one")


func test_the_button_stands_on_the_panel_at_its_default_size_with_no_scrolling() -> void:
    _build()
    if _button == null:
        return
    _docker.size = BrushPresetsDocker.DEFAULT_SIZE
    _docker.show()
    for i in 3:
        await _frame()
    var shown := Rect2(Vector2.ZERO, Vector2(_docker.size))
    var at := _button.get_global_rect()
    assert_true(_button.is_visible_in_tree(), "Random is shown")
    assert_true(shown.encloses(at), "inside the panel's %s: %s" % [_docker.size, at])
    var scroll := _button.get_parent()
    while scroll != null and not scroll is ScrollContainer and scroll != _docker:
        scroll = scroll.get_parent()
    assert_false(scroll is ScrollContainer, "and in no scroll")


func _frame() -> void:
    await (Engine.get_main_loop() as SceneTree).process_frame
