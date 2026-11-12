## The pop-up palette, a docker of a special kind the summon
## shows, with the ten brush slots on a ring round the colour wheel.
##
## It has no on and off switch, since a switch would only say what a right
## click with a brush opens. That choice is in its row, which
## `test_a_right_click_with_a_brush_opens_the_docker_the_painter_chose.gd`
## holds. So the chord shows the palette on every profile and says nothing.
##
## The windows are never added to a tree, because a window added to a tree in a headless run hangs,
## so the summon is driven through `DockerSummon.summon` the way the summon suite
## drives it and a press is the cell's own signal. The running app's proof is
## a scenario.
extends "res://tests/test_framework.gd"

static var scratch_layout_path: String = SaDataRoot.path("test_u3_palette_layout.cfg")
const SECTION: String = "PaletteDocker"
const HOME := Vector2i(1500, 120)
const POINT := Vector2i(700, 500)

## The key the switch was stored under, which an older profile
## still carries and nothing reads.
const FORMER_SWITCH_KEY := &"popup_palette_enabled"

var _switch_before: Variant = null
var _slots_before: Array = []
var _colour_before: Color = Color.BLACK

## The node the corner notice is installed under for the suites that read it,
## and what `SaProblems` held before, put back after.
var _host: Node = null
var _pending_before := PackedStringArray()
var _refusals_before := PackedStringArray()


func before_each() -> void:
    _switch_before = SaSettings.module_preference(SaDockerBorrow.MODULE_ID, FORMER_SWITCH_KEY, "")
    _slots_before = SaSettings.brush_slots.duplicate()
    _colour_before = SaColors.foreground


func after_each() -> void:
    var kept: Variant = null if _switch_before is String and _switch_before == "" else _switch_before
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, FORMER_SWITCH_KEY, kept)
    SaSettings.brush_slots = _slots_before
    SaColors.foreground = _colour_before
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))
    if _host != null:
        # Freeing the host takes the problem dialog with it, which uninstalls
        # the notice and lets go of the sink.
        _host.free()
        _host = null
        SaProblems.pending = _pending_before
        SaProblems.pending_refusals = _refusals_before


## The corner notice, installed the way the main window installs it, under a
## node of the suite's own. What `SaProblems` was keeping is set aside first,
## because installing hands every kept line to the new dialog.
func _notice() -> SaNotice:
    _pending_before = SaProblems.pending
    _refusals_before = SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    _host = Node.new()
    _host.name = "PaletteNoticeHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    return SaMessage.notice_widget()


func _palette() -> PaletteDocker:
    var win := PaletteDocker.new()
    win.position = HOME
    win.visible = false
    return win


func _store_with(win: Window) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": win, "id": SECTION, "name": "Pop-up Palette"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    return store


func test_the_palette_is_a_registered_docker_no_profile_opens() -> void:
    var source := FileAccess.get_file_as_string("res://ui/main/sa_builtin_dockers.gd")
    var entry := '[SaDockerIds.PALETTE, "Pop-up Palette", palette_factory, &"docker_palette"]'
    assert_true(source.contains(entry), "registered like the rest")
    assert_true(source.contains("res://ui/dockers/palette/palette_docker.gd"), "from its own folder")
    assert_true(DockerLayoutStore.HIDDEN_UNTIL_ASKED.has(SECTION), "and a fresh profile leaves it closed")
    var rows := SaAppCommands.DOCKER_COMMANDS.filter(func(row: Array) -> bool: return row[1] == &"PaletteDocker")
    assert_eq(rows.size(), 1, "it has a toggle row, so the summon table gives it a summon")
    assert_eq(SaAppCommands.summon_id(&"docker_palette"), &"docker_summon_palette", "the summon's action id")
    assert_true(SaDockerBorrow.new().get(FORMER_SWITCH_KEY) == null, "and it has no switch")


## The chord shows the palette on every profile, one that stored the old
## switch off among them, and nothing is said in the corner.
func test_the_chord_summons_it_on_every_profile_and_says_nothing() -> void:
    var notice := _notice()
    var win := _palette()
    var store := _store_with(win)
    var summon := DockerSummon.new(store)

    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, FORMER_SWITCH_KEY, false)
    assert_false(win.has_method(&"summon_refusal"), "the palette has no refusal to give")
    assert_true(summon.summon(win, SECTION, POINT, 20000), "the chord summons it with the old switch stored off")
    assert_false(notice.showing(), "and nothing is said in the corner")
    assert_true(win.visible, "it is shown")
    assert_true(store.is_borrowed(SECTION), "on a borrow")
    assert_true(Rect2i(win.position, win.size).has_point(POINT), "under the pointer")
    summon.send_back(SECTION)
    assert_false(win.visible, "and goes back like any summoned docker")

    summon.free()
    win.free()
    store.free()


func test_the_ring_is_the_ten_brush_slots_and_a_press_selects_one() -> void:
    SaSettings.brush_slots = []
    SaBrushSlotCommands.fill(2, "Sketch")
    SaBrushSlotCommands.fill(10, "Paint")
    var pressed: Array = []
    var ring := PaletteSlotRing.new(func(slot: int) -> void: pressed.append(slot))

    assert_eq(ring.cells.size(), SaBrushSlotCommands.COUNT, "a cell per slot")
    assert_eq(ring.cells[1].text, "Sketch", "slot two carries the preset the slot holds")
    assert_eq(ring.cells[9].text, "Paint", "and slot ten, the 0 key, its own")
    assert_true(ring.cells[0].disabled, "an empty slot is dimmed and does nothing")
    assert_eq(ring.cells[0].text, "1", "and shows the key it answers to")

    ring.cells[1].pressed.emit()
    ring.cells[9].pressed.emit()
    assert_eq(pressed, [2, 10], "a press selects that slot")

    SaBrushSlotCommands.fill(2, "")
    ring.refresh()
    assert_true(ring.cells[1].disabled, "emptying the slot empties the cell")
    ring.free()

    var win := _palette()
    assert_eq(win.ring._select, Callable(SaBrushSlotCommands.select), "the palette's ring presses through the chord's own select")
    win.free()


func test_the_cells_sit_round_the_wheel_and_apart() -> void:
    var ring := PaletteSlotRing.new(Callable())
    ring.size = Vector2(300, 300)
    ring.lay_out()
    var wheel := Rect2(ring.wheel.position, ring.wheel.size)
    var centre := wheel.get_center()
    assert_almost_eq(centre.x, 150.0, 0.01, "the wheel is in the middle")
    for i in ring.cells.size():
        var cell := Rect2(ring.cells[i].position, ring.cells[i].size)
        assert_true(Rect2(Vector2.ZERO, ring.size).encloses(cell), "cell %d inside the ring" % (i + 1))
        assert_true(DockerSummon.distance_to(cell, centre) > wheel.size.x / 2.0, "cell %d clear of the wheel" % (i + 1))
        for j in range(i + 1, ring.cells.size()):
            var other := Rect2(ring.cells[j].position, ring.cells[j].size)
            assert_false(cell.intersects(other), "cells %d and %d apart" % [i + 1, j + 1])
    ring.free()


func test_a_colour_picked_on_the_wheel_is_the_brush_colour() -> void:
    SaColors.foreground = Color(0.1, 0.2, 0.3)
    var win := _palette()
    var picked := Color(0.8, 0.25, 0.1)
    win.ring.wheel.color_changed.emit(picked)
    assert_true(SaColors.foreground.is_equal_approx(picked), "the wheel moved the foreground every tool paints with")
    win.free()
