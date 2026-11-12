## Four places pick a preset, the grid, Recent Presets, the
## Pop-up Palette's ring and the bar's button, each drew it its own way, and
## Recent Presets did not mark the preset in use. Recent Presets' rows now carry
## the grid's picture beside the name, and the grid, the rows and the ring draw
## the preset in use with one mark, `SaBrushPresetsChooser.draw_mark`.
##
## Nothing enters the tree, for the reason `test_history_docker.gd` gives. The
## docker is driven through `record`, which is what the bus reaches in the app,
## and the ring hears the bus itself, so a load here is the bar's two halves: the
## brush is put on the preset, then the bus says so. The running app's proof is
## a scenario.
extends "res://tests/test_framework.gd"

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The docker is a Window and the chooser renders through the paint path, so
## both want a device.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_n35_preset_pickers")
static var scratch_list: String = SaDataRoot.path("test_n35_recent_presets.cfg")

## The preset every host is told is in use. A dictionary rather than a String,
## because the hosts ask through a lambda and a lambda keeps its own copy of a
## String it captured.
var _in_use := {"name": ""}

var _slots_before: Array = []
var _tip_before: bool = false


func before_each() -> void:
    _slots_before = SaSettings.brush_slots.duplicate()
    _tip_before = SaSettings.preset_thumb_tip
    SaSettings.preset_thumb_tip = false
    _in_use["name"] = ""
    _clean()


func after_each() -> void:
    SaSettings.brush_slots = _slots_before
    SaSettings.preset_thumb_tip = _tip_before
    _clean()


func _clean() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_list))
    for folder: String in [SaPresetThumbs.thumbs_dir(scratch_dir), scratch_dir]:
        if not DirAccess.dir_exists_absolute(folder):
            continue
        for file_name: String in DirAccess.get_files_at(folder):
            DirAccess.remove_absolute(folder.path_join(file_name))
        DirAccess.remove_absolute(folder)


## The three presets the brush's wrapper ships, Fill, Paint and Sketch, in a
## folder of the suite's own.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    return store


## Writes a picture where the grid caches *preset_name*'s, as its queue would
## have, after the preset's file so the picture is not older than it.
func _draw_picture(preset_name: String) -> void:
    DirAccess.make_dir_recursive_absolute(SaPresetThumbs.thumbs_dir(scratch_dir))
    var image := Image.create(SaPresetThumbs.SIZE.x, SaPresetThumbs.SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.2, 0.3, 0.8))
    image.save_png(SaPresetThumbs.path_for(scratch_dir, preset_name))


func _docker() -> HistoryDocker:
    var docker := HistoryDocker.new()
    docker.path = scratch_list
    docker.store.dir = scratch_dir
    docker.loaded_source = func() -> String: return String(_in_use["name"])
    return docker


func _ring(select: Callable = Callable()) -> PaletteSlotRing:
    return PaletteSlotRing.new(select, func() -> String: return String(_in_use["name"]))


## A load as the bar makes one: the brush is put on *preset_name*, the docker
## records it, and the bus announces it.
func _load(docker: HistoryDocker, preset_name: String) -> void:
    _in_use["name"] = preset_name
    docker.record(preset_name)
    EventBus.preset_loaded.emit(preset_name)


func _row(docker: HistoryDocker, preset_name: String) -> Button:
    return docker.rows.get_node_or_null("Row_" + preset_name) as Button


## Whether *button* is drawn with the mark: the accent rim at the mark's width.
func _marked(button: Button) -> bool:
    if button == null or not button.has_theme_stylebox_override("normal"):
        return false
    var style := button.get_theme_stylebox("normal") as StyleBoxFlat
    return (
        style != null
        and style.border_color == SaTheme.palette.accent_primary
        and style.border_width_left == SaUI.px(SaBrushPresetsChooser.MARK_BORDER)
    )


## Two loads, a picture on each row, the mark on the loaded
## preset's row and on its slot, and both marks moving on the next load.
func test_two_loads_give_each_row_a_picture_and_mark_the_loaded_one_in_both_pickers() -> void:
    _store()
    _draw_picture("Sketch")
    _draw_picture("Paint")
    SaSettings.brush_slots = []
    SaBrushSlotCommands.fill(1, "Sketch")
    SaBrushSlotCommands.fill(2, "Paint")
    var docker := _docker()
    var ring := _ring()

    _load(docker, "Sketch")
    _load(docker, "Paint")
    assert_eq(Array(docker.entries), ["Paint", "Sketch"], "Two loads, two rows, newest first")
    for preset_name: String in ["Paint", "Sketch"]:
        assert_not_null(_row(docker, preset_name).icon, "The %s row shows the preset's picture" % preset_name)
    assert_true(_marked(_row(docker, "Paint")), "The row of the preset in use carries the mark")
    assert_false(_marked(_row(docker, "Sketch")), "and the other row does not")
    assert_eq(ring._marked, [2] as Array[int], "The ring marks the slot holding the preset in use")
    assert_true(_marked(ring.cells[1]), "with the same rim")
    assert_false(_marked(ring.cells[0]), "and the slot holding the other does not carry it")

    _load(docker, "Sketch")
    assert_true(_marked(_row(docker, "Sketch")), "The next load moves the row's mark")
    assert_false(_marked(_row(docker, "Paint")), "off the row it was on")
    assert_eq(ring._marked, [1] as Array[int], "and the ring's mark to the slot it loaded")
    assert_true(_marked(ring.cells[0]), "drawn on that slot's cell")
    assert_false(_marked(ring.cells[1]), "and gone from the cell it left")
    var slots: Array = ring.report(Vector2.ZERO)["slots"]
    assert_eq(slots.map(func(row: Dictionary) -> bool: return bool(row["marked"])).count(true), 1, "The report marks one slot")
    assert_true(bool((slots[0] as Dictionary)["marked"]), "and it is slot one")

    ring.free()
    docker.free()


## The grid's look, the rows' and the ring's are one mark: the same ground, rim,
## width and name colour, from the one static all three call.
func test_the_grid_the_rows_and_the_ring_draw_the_one_mark() -> void:
    var store := _store()
    _in_use["name"] = "Paint"
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(
        store,
        StateBrushScript,
        func() -> Resource: return BrushSettingsScript.new(),
        func() -> String: return String(_in_use["name"])
    )
    var docker := _docker()
    SaSettings.brush_slots = []
    SaBrushSlotCommands.fill(3, "Paint")
    var ring := _ring()
    docker.record("Paint")

    var tile := (chooser.grid.get_child(1) as Control).get_node("Icon") as Button
    var row := _row(docker, "Paint")
    var cell := ring.cells[2]
    var accent: Color = SaTheme.palette.accent_primary
    for button: Button in [tile, row, cell]:
        assert_true(_marked(button), "%s carries the mark" % button.name)
        for state: String in SaBrushPresetsChooser.MARK_STATES:
            var style := button.get_theme_stylebox(state) as StyleBoxFlat
            var tile_style := tile.get_theme_stylebox(state) as StyleBoxFlat
            assert_eq(style.bg_color, tile_style.bg_color, "%s's %s ground is the grid's" % [button.name, state])
            assert_eq(style.border_color, tile_style.border_color, "and its rim's colour")
            assert_eq(style.border_width_top, tile_style.border_width_top, "and its rim's width")
    var label := (chooser.grid.get_child(1) as Control).get_node("Name") as Label
    assert_eq(label.get_theme_color("font_color"), accent, "The grid's name is in the accent")
    for button: Button in [row, cell]:
        for colour: String in SaBrushPresetsChooser.MARK_FONT_COLORS:
            assert_eq(button.get_theme_color(colour), accent, "and so is %s's %s, its own words" % [button.name, colour])

    ring.free()
    docker.free()
    chooser.free()


## A picture the grid has not drawn yet leaves the row its name, and the row takes
## the picture once it lands, the way a grid cell waits for its queue.
func test_a_row_shows_its_name_until_its_picture_is_drawn() -> void:
    _store()
    _draw_picture("Sketch")
    var docker := _docker()
    _load(docker, "Sketch")
    _load(docker, "Fill")

    var waiting := _row(docker, "Fill")
    assert_eq(waiting.text, "Fill", "A row with no picture yet shows the name")
    assert_null(waiting.icon, "and no picture")
    assert_true(docker.is_processing(), "and keeps looking for one")
    docker.take_pictures()
    assert_null(waiting.icon, "Looking finds nothing while nothing is drawn")

    _draw_picture("Fill")
    docker.take_pictures()
    assert_not_null(waiting.icon, "Once the grid's queue has drawn it, the row shows it")
    assert_eq(waiting.text, "Fill", "beside the name")
    assert_false(docker.is_processing(), "and nothing is left looking")
    docker.free()


## The brush put on no preset, which is what `new_preset` announces, takes the
## mark off the row and the slot without taking the row off the list.
func test_no_preset_in_use_marks_nothing() -> void:
    _store()
    SaSettings.brush_slots = []
    SaBrushSlotCommands.fill(1, "Sketch")
    var docker := _docker()
    var ring := _ring()
    _load(docker, "Sketch")
    assert_true(_marked(_row(docker, "Sketch")), "Loaded, the row is marked")

    _load(docker, "")
    assert_eq(Array(docker.entries), ["Sketch"], "No preset records nothing")
    assert_false(_marked(_row(docker, "Sketch")), "and the row loses the mark")
    assert_eq(ring._marked, [] as Array[int], "and so does the slot")
    assert_false(_marked(ring.cells[0]), "on its cell too")
    ring.free()
    docker.free()


## A save puts the brush on the preset it wrote. The rows hear it on the store's
## signal and the ring on the same, so the mark follows a save as it does a load.
func test_a_save_moves_the_mark_to_the_preset_it_wrote() -> void:
    _store()
    SaSettings.brush_slots = []
    SaBrushSlotCommands.fill(1, "Sketch")
    SaBrushSlotCommands.fill(2, "Paint")
    var docker := _docker()
    var ring := _ring()
    _load(docker, "Sketch")
    _load(docker, "Paint")

    _in_use["name"] = "Sketch"
    docker.forget_deleted("Sketch", true)
    EventBus.preset_store_changed.emit("Sketch", true)
    assert_true(_marked(_row(docker, "Sketch")), "The row of the preset a save wrote is marked")
    assert_false(_marked(_row(docker, "Paint")), "and the one before it is not")
    assert_eq(ring._marked, [1] as Array[int], "and the ring's mark is on its slot")
    ring.free()
    docker.free()


## The cell the mark left is built again, because a mark cannot be taken off a
## button in place. The new cell stands where the old one did and still presses
## its slot.
func test_a_cell_the_mark_leaves_keeps_its_place_and_its_press() -> void:
    SaSettings.brush_slots = []
    SaBrushSlotCommands.fill(1, "Sketch")
    var pressed: Array = []
    var ring := _ring(func(slot: int) -> void: pressed.append(slot))
    ring.size = Vector2(300, 300)
    ring.lay_out()
    _in_use["name"] = "Sketch"
    ring.refresh()
    var before := ring.cells[0]
    var place := before.get_index()
    var rect := Rect2(before.position, before.size)

    _in_use["name"] = ""
    ring.refresh()
    var after := ring.cells[0]
    assert_false(after == before, "The cell the mark left is a new one")
    assert_false(_marked(after), "and carries no mark")
    assert_eq(String(after.name), "Slot1", "It keeps the slot's name")
    assert_eq(after.get_index(), place, "its place among the ring's children")
    assert_eq(Rect2(after.position, after.size), rect, "and its rectangle")
    assert_eq(after.text, "Sketch", "and reads the preset its slot holds")
    after.pressed.emit()
    assert_eq(pressed, [1], "and a press still selects the slot")
    ring.free()
