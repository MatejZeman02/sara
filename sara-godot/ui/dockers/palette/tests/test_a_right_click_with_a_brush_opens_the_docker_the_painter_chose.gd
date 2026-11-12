## A right click with a brush opens the pop-up palette or Brush
## Presets, as the painter chooses on Preferences > Brushes.
##
## The palette had an on and off switch, which existed only because a right
## click had to open one of the two. The choice took its row, and the tool
## machine asks `SaRightClickDocker`, which reads it, rather than naming either
## docker.
##
## Driven through `handle_input` with both dockers in the tree, as
## `test_a_second_right_press_closes_the_presets.gd` drives the presets alone,
## because each docker attaches its toggle when it enters the tree. With no main
## scene the dockers show and hide in place. The summon under the pointer and the
## second press on the palette itself are held by a scenario.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PresetsScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

const REQUIRES_GPU := true

## A preset folder nobody writes, so the Brush Slots page this suite builds
## offers nothing rather than whatever the last suite left in the real one.
static var scratch_presets_dir: String = SaDataRoot.path("test_no_presets")

var _choice_before: Variant = null


func before_each() -> void:
    _choice_before = SaSettings.module_preference(SaRightClickDocker.MODULE_ID, SaRightClickDocker.KEY, "")


func after_each() -> void:
    # An empty string is what was read when the profile held no choice, which a
    # null forgets again.
    var kept: Variant = null if _choice_before is String and _choice_before == "" else _choice_before
    SaSettings.set_module_preference(SaRightClickDocker.MODULE_ID, SaRightClickDocker.KEY, kept)


class Docker:
    extends RefCounted
    var points: Array[Vector2] = []

    func toggle_at(point: Vector2) -> bool:
        points.append(point)
        return true


## A profile with no choice stored opens Brush Presets, and a value the row
## never writes reads as Brush Presets too.
func test_a_fresh_profile_opens_the_presets() -> void:
    SaSettings.set_module_preference(SaRightClickDocker.MODULE_ID, SaRightClickDocker.KEY, null)
    assert_eq(SaRightClickDocker.chosen(), SaRightClickDocker.PRESETS, "a fresh profile chooses Brush Presets")
    SaSettings.set_module_preference(SaRightClickDocker.MODULE_ID, SaRightClickDocker.KEY, 3)
    assert_eq(SaRightClickDocker.new().opens, SaRightClickDocker.PRESETS, "and so does a value nobody wrote")
    SaRightClickDocker.new().opens = SaRightClickDocker.PALETTE
    assert_eq(SaRightClickDocker.chosen(), SaRightClickDocker.PALETTE, "the row's property writes the choice")


## The door asks the docker the choice names, at the point asked, and a docker
## that leaves takes only its own toggle with it.
func test_the_door_asks_the_chosen_docker() -> void:
    var presets := Docker.new()
    var palette := Docker.new()
    SaRightClickDocker.attach(SaRightClickDocker.PRESETS, presets.toggle_at)
    SaRightClickDocker.attach(SaRightClickDocker.PALETTE, palette.toggle_at)
    SaRightClickDocker.new().opens = SaRightClickDocker.PALETTE
    assert_true(SaRightClickDocker.toggle_at(Vector2(12, 34)), "the palette answers")
    assert_eq(palette.points, [Vector2(12, 34)] as Array[Vector2], "at the point asked")
    assert_true(presets.points.is_empty(), "and Brush Presets is not asked")
    SaRightClickDocker.detach(SaRightClickDocker.PALETTE, presets)
    assert_true(SaRightClickDocker.toggle_at(Vector2.ONE), "a docker that is not the attached one detaches nothing")
    SaRightClickDocker.detach(SaRightClickDocker.PALETTE, palette)
    assert_false(SaRightClickDocker.toggle_at(Vector2.ONE), "and once the palette left, nothing opens")
    SaRightClickDocker.new().opens = SaRightClickDocker.PRESETS
    assert_true(SaRightClickDocker.toggle_at(Vector2.ONE), "while Brush Presets still answers its own choice")
    SaRightClickDocker.detach(SaRightClickDocker.PRESETS, presets)


## The first clause, in a suite's tree: with the palette chosen the brush's
## right press opens the palette and a second shuts it, and Brush Presets is left
## alone. With Brush Presets chosen it is the other way round.
func test_the_right_press_opens_the_docker_chosen() -> void:
    var built := _build()
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    var presets: Window = built["presets"]
    var palette: Window = built["palette"]
    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    SaRightClickDocker.new().opens = SaRightClickDocker.PALETTE
    machine.handle_input(_right_press())
    assert_true(palette.visible, "the palette chosen, the right press opens it")
    assert_false(presets.visible, "and leaves Brush Presets shut")
    machine.handle_input(_right_press())
    assert_false(palette.visible, "and a second right press shuts it")

    SaRightClickDocker.new().opens = SaRightClickDocker.PRESETS
    machine.handle_input(_right_press())
    assert_true(presets.visible, "Brush Presets chosen, the right press opens it")
    assert_false(palette.visible, "and leaves the palette shut")
    machine.handle_input(_right_press())
    assert_false(presets.visible, "and a second right press shuts it")
    assert_eq(asked.size(), 0, "no press fell through to the context menu")

    _tear_down(built)


## The second clause's row: the choice stands where the switch stood, after the
## tenth slot, with Brush Presets picked on a fresh profile, and picking the
## palette there is what the door reads.
func test_the_brushes_page_offers_the_choice() -> void:
    SaSettings.set_module_preference(SaRightClickDocker.MODULE_ID, SaRightClickDocker.KEY, null)
    var store := SaPresetStore.new()
    store.dir = scratch_presets_dir
    var page := SaBrushSlotsPage.new(store)
    var row := page.page.row(&"brush_right_click")
    assert_not_null(row, "Brushes has the right click's choice")
    if row == null:
        page.free()
        return
    assert_null(page.page.row(&"popup_palette"), "and no longer the palette's switch")
    var keys: Array[StringName] = []
    for each: SaPageRow in page.page.rows():
        keys.append(each.key)
    assert_eq(keys.find(&"brush_right_click"), keys.find(&"slot_10") + 1, "the row after the tenth slot")
    var ids: Array = []
    for entry: Dictionary in row.choices:
        ids.append(entry["id"])
    assert_eq(ids, [SaRightClickDocker.PRESETS, SaRightClickDocker.PALETTE], "offering the two dockers")
    assert_eq((row.control as SaChoiceButton).selected_value(), SaRightClickDocker.PRESETS, "Brush Presets is picked")
    row.drive(1)
    assert_eq(SaRightClickDocker.chosen(), SaRightClickDocker.PALETTE, "and the row picks the palette")
    page.free()


## Both dockers and a machine bound to a surface, in the tree under an autoload,
## for the reason `test_a_second_right_press_closes_the_presets.gd` gives.
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree")
    if tree == null:
        return {}
    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "RightPressTestHost"
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    host.add_child(machine)
    machine.set_active_tool(&"brush")
    var presets := PresetsScript.new()
    host.add_child(presets)
    presets.hide()
    var palette := PaletteDocker.new()
    host.add_child(palette)
    palette.hide()
    var built := {"tree": tree, "host": host, "machine": machine, "surface": surface, "embedded": embedded}
    built["presets"] = presets
    built["palette"] = palette
    return built


func _tear_down(built: Dictionary) -> void:
    var host: Node = built["host"]
    var machine: ToolMachine = built["machine"]
    host.remove_child(machine)
    host.free()
    Fixtures.teardown(built["surface"], machine)
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])


func _right_press() -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.pressed = true
    event.position = Vector2(100, 100)
    event.global_position = Vector2(100, 100)
    return event
