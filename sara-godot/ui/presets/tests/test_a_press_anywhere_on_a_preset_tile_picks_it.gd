## A press anywhere on a preset tile picks it, not on its picture only.
##
## In eighteen preset picks a
## press on a preset's name did nothing and said nothing, and only the picture
## above it picked. The name, the engine line the docker adds under it and the
## gap between them are labels and a column, and a label lets the mouse through
## to a column that took nothing.
##
## The presses go in through the window's GUI pass, `push_input`, because the
## fix is in which control the event reaches and a `gui_input.emit` on the column
## would prove the handler and not that the column is what the press lands on.
## The suite cannot advance a frame, so the layout the next frame would make is
## made by hand, the way the wheel suite of the colour spaces page does.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const WINDOW := Vector2i(520, 420)

## Three names of a painter's kind, one word and two, so a tile's name runs to
## one line and to two.
const NAMES: Array[String] = ["Charcoal", "Inked Pen", "Soft Airbrush"]

static var scratch_dir: String = SaDataRoot.path("test_a_press_anywhere_on_a_preset_tile_picks_it")

var _host: Node = null
var _was_embedding: bool = false
var _window: Window = null
var _picked: Array[String] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _picked.clear()
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    ScratchFolder.clear(scratch_dir)


## The chooser over three presets in a window of its own, laid out, with the
## engine line under each name the way the presets docker's marks put it there.
func _chooser_over_three() -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for preset_name: String in NAMES:
        store.save_preset(preset_name, BrushSettingsScript.new())

    _host = Node.new()
    _host.name = "TileHost"
    EventBus.add_child(_host)
    _window = Window.new()
    _window.title = "Preset tiles"
    _window.position = Vector2i(40, 40)
    _window.size = WINDOW
    _host.add_child(_window)
    SaUI.apply_to_window(_window)

    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _window.add_child(chooser)
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    chooser.preset_chosen.connect(func(picked: String) -> void: _picked.append(picked))
    for preset_name: String in NAMES:
        var cell := chooser.grid.get_node("Cell_" + preset_name.validate_node_name())
        SaMake.label(cell, "Engine", "Stamp").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _lay_out(chooser)
    return chooser


func _lay_out(chooser: Control) -> void:
    chooser.size = Vector2(WINDOW)
    for _pass in 3:
        _sort(chooser)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()


func _tile(chooser: SaBrushPresetsChooser, preset_name: String) -> Control:
    return chooser.grid.get_node("Cell_" + preset_name.validate_node_name()) as Control


## One press and its release at *at*, through the window's GUI pass.
func _click(at: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = true
    event.position = at
    event.global_position = at
    _window.push_input(event, true)
    var release := event.duplicate() as InputEventMouseButton
    release.pressed = false
    _window.push_input(release, true)


## The middle of the strip between the picture's foot and the name's top, which
## is the gap of the tile's own separation.
func _gap_of(tile: Control) -> Vector2:
    var picture := (tile.get_node("Icon") as Control).get_global_rect()
    var name_rect := (tile.get_node("Name") as Control).get_global_rect()
    return Vector2(picture.get_center().x, (picture.end.y + name_rect.position.y) * 0.5)


func test_a_press_on_the_name_picks_the_tile() -> void:
    var chooser := _chooser_over_three()
    for preset_name: String in NAMES:
        var label := _tile(chooser, preset_name).get_node("Name") as Control
        _click(label.get_global_rect().get_center())
    assert_eq(_picked, NAMES, "A press on each tile's name picked that tile, in the order pressed")


func test_a_press_on_the_engine_line_picks_the_tile() -> void:
    var chooser := _chooser_over_three()
    var line := _tile(chooser, "Inked Pen").get_node("Engine") as Control
    assert_true(line.get_global_rect().size.y > 0.0, "The engine line has a height to press on")
    _click(line.get_global_rect().get_center())
    assert_eq(_picked, ["Inked Pen"] as Array[String], "A press on the engine line picked its tile")


func test_a_press_in_the_gap_under_the_picture_picks_the_tile() -> void:
    var chooser := _chooser_over_three()
    var tile := _tile(chooser, "Charcoal")
    var gap := _gap_of(tile)
    assert_true(tile.get_global_rect().has_point(gap), "The gap is inside the tile")
    assert_false((tile.get_node("Icon") as Control).get_global_rect().has_point(gap), "and is neither on the picture")
    assert_false((tile.get_node("Name") as Control).get_global_rect().has_point(gap), "nor on the name")
    _click(gap)
    assert_eq(_picked, ["Charcoal"] as Array[String], "A press in it picked the tile")


## The picture picked before and must not pick twice now that the column under it
## answers as well. A button picks on the release of a press it saw the pointer
## arrive for, and a suite that advances no frame has no arrival to show it, so
## its `pressed` is what this holds once and the press on the name, which the
## column takes outright, is the one the pointer tests above hold.
func test_a_press_on_the_picture_picks_once() -> void:
    var chooser := _chooser_over_three()
    (_tile(chooser, "Soft Airbrush").get_node("Icon") as Button).pressed.emit()
    assert_eq(_picked, ["Soft Airbrush"] as Array[String], "The picture's press picked its tile, once")


## A right press on the name opens the tag menu of that tile's preset, where a
## right press on its picture has always opened it.
func test_a_right_press_on_the_name_opens_the_tag_menu() -> void:
    var chooser := _chooser_over_three()
    var label := _tile(chooser, "Inked Pen").get_node("Name") as Control
    _click(label.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
    var report := chooser.tags.tags_report()
    assert_eq(report["preset"], "Inked Pen", "The menu is for the tile whose name was pressed")
    assert_true(bool(report["menu_open"]), "and it is open")
    assert_true(_picked.is_empty(), "A right press picks nothing")
    chooser.tags.menu.hide()


## The tile reads as one control: the pointer on its column or on its picture
## marks the tile, which is what the plate under it is drawn from, and the pointer
## leaving clears the mark.
##
## The enter and leave are the signals the engine sends, because a suite that
## advances no frame has no pointer for the viewport to track. Where the pointer
## is when a leave arrives is the viewport's own, so the tiles are put where it cannot be.
func test_the_pointer_over_a_tile_marks_the_whole_tile() -> void:
    var chooser := _chooser_over_three()
    # The tiles are moved where no pointer can be, since the viewport's pointer
    # is the compositor's, which a run of many suites leaves over Inked Pen.
    chooser.position = Vector2(-10000.0, -10000.0)
    assert_eq(chooser.cells._hovered, "", "No tile is hovered to begin with")
    _tile(chooser, "Charcoal").mouse_entered.emit()
    assert_eq(chooser.cells._hovered, "Charcoal", "The pointer on the column marks the tile")
    (_tile(chooser, "Inked Pen").get_node("Icon") as Button).mouse_entered.emit()
    assert_eq(chooser.cells._hovered, "Inked Pen", "and on another tile's picture marks that one")
    _tile(chooser, "Inked Pen").mouse_exited.emit()
    assert_eq(chooser.cells._hovered, "", "and leaving the tile clears it")
    _tile(chooser, "Charcoal").mouse_exited.emit()
    assert_eq(chooser.cells._hovered, "", "a leave of a tile that was not marked changes nothing")
