## The pop-up palette's slots show each preset's name whole. The ten cells once
## cut their names to "Charc", "Airbru", "Flat Br" and "Inked", which read as typos.
##
## Every shipped preset's name is put in a slot, ten at a time, on a ring at
## the size it has in the docker at its default 360 by 384, and each cell is
## measured here against the font it draws with, by a paragraph of this suite's
## own rather than the ring's `_fits`, so the ring cannot pass by agreeing with
## itself. The ring is built bare and themed with the app's theme, because a
## window added to a tree in a headless run hangs. The
## running app's proof is the scenario
## `scenarios/the-pop-up-palettes-slots-show-each-preset-whole.json`.
extends "res://tests/test_framework.gd"

## The noise brush's shelf, the shipped presets that are not the stamp's.
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The ring's rectangle in the docker at its default 360 by 384: the drag bar,
## the column's gap and the docker's foot take 53 of the height. Read off the
## running app's state dump, the scenario's `ring` entry, since the column that
## places it lays out only in a tree.
const RING_AT_DEFAULT := Vector2(360, 331)

## A name no cell holds at any size the ring allows.
const TOO_LONG := "An Uncommonly Long Name For One Brush"

var _slots_before: Array = []
var _kept_theme: Theme = null
var _kept_font_scale: float = 1.0


func before_each() -> void:
    _slots_before = SaSettings.brush_slots.duplicate()
    _kept_theme = SaUI.shared_theme
    _kept_font_scale = SaUI.user_font_scale
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)


func after_each() -> void:
    SaSettings.brush_slots = _slots_before
    SaUI.shared_theme = _kept_theme
    SaUI.user_font_scale = _kept_font_scale


## A bare ring at the docker's default size under the app's theme, holding
## *names* in slot order, with nothing loaded so no cell carries the mark.
func _ring(names: Array) -> PaletteSlotRing:
    SaSettings.brush_slots = names
    var ring := PaletteSlotRing.new(Callable(), func() -> String: return "")
    ring.theme = SaUI.shared_theme
    ring.size = RING_AT_DEFAULT
    ring.lay_out()
    return ring


## Every name a shipped preset carries: the stamp's two bundles and the noise
## brush's shelf.
func _shipped_names() -> Array[String]:
    var names: Array[String] = []
    for entry: Dictionary in SaShippedPresets.entries():
        names.append(String(entry["name"]))
    for entry: Dictionary in NoisePresetsScript.entries():
        names.append(String(entry["name"]))
    return names


## Whether *cell* shows its text whole: broken only at spaces, on at most two
## lines, each no wider than the cell less its box's margins, and the lines no
## taller than it, at the size and in the font the cell draws with.
func _whole(cell: Button) -> bool:
    if cell.autowrap_mode != TextServer.AUTOWRAP_WORD:
        return false
    var box := cell.size - cell.get_theme_stylebox("normal").get_minimum_size()
    var paragraph := TextParagraph.new()
    paragraph.add_string(cell.text, cell.get_theme_font("font"), cell.get_theme_font_size("font_size"))
    paragraph.width = box.x
    paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | cell.autowrap_trim_flags
    if paragraph.get_line_count() > 2:
        return false
    for line in paragraph.get_line_count():
        if paragraph.get_line_width(line) > box.x:
            return false
    return paragraph.get_size().y <= box.y


## First clause: at the default size no shipped preset's cell
## text is cut, and none is drawn below the floor.
func test_no_shipped_name_is_cut_at_the_default_size() -> void:
    var names := _shipped_names()
    assert_true(names.size() >= 50, "every shipped preset is measured, %d of them" % names.size())
    assert_true(names.has("Splattered Block"), "the widest word among them, in the stamp's drawn tips")
    assert_true(names.has("Thick Impasto"), "and the noise brush's shelf")
    var floor_size := roundi(SaUI.get_font_size() * PaletteSlotRing.NAME_FLOOR)
    var wanted := Vector2(RING_AT_DEFAULT.y * PaletteSlotRing.CELL_WIDTH, RING_AT_DEFAULT.y * PaletteSlotRing.CELL_HEIGHT).round()
    for first in range(0, names.size(), SaBrushSlotCommands.COUNT):
        var ten := names.slice(first, first + SaBrushSlotCommands.COUNT)
        var ring := _ring(ten)
        for i in ten.size():
            var cell := ring.cells[i]
            assert_eq(cell.text, ten[i], "slot %d holds %s" % [i + 1, ten[i]])
            assert_true(_whole(cell), "%s is whole in its cell at %d pixels" % [ten[i], cell.get_theme_font_size("font_size")])
            assert_true(cell.get_theme_font_size("font_size") >= floor_size, "%s is drawn at the floor or above" % ten[i])
            assert_true(cell.size.is_equal_approx(wanted), "%s keeps its cell's size, %s" % [ten[i], cell.size])
        ring.free()


## The factory ten, which every fresh profile shows, fit larger than the floor,
## and at one size, so the ring is not ten kinds of button.
func test_the_factory_ten_share_one_size_above_the_floor() -> void:
    var ring := _ring(SaSettingsBrushSlots.factory())
    var sizes := {}
    for cell in ring.cells:
        assert_true(_whole(cell), "%s is whole" % cell.text)
        sizes[cell.get_theme_font_size("font_size")] = true
    assert_eq(sizes.size(), 1, "one size for the ten: %s" % [sizes.keys()])
    var floor_size := roundi(SaUI.get_font_size() * PaletteSlotRing.NAME_FLOOR)
    assert_true(int(sizes.keys()[0]) > floor_size, "above the floor, at %s" % [sizes.keys()])
    var report := ring.report(Vector2.ZERO)
    for slot: Dictionary in report["slots"]:
        assert_false(bool(slot["cut"]), "the dump says slot %d is whole" % slot["slot"])
    ring.free()


## A name that fits at no size is cut on one line, and the nine beside it keep
## the size they had without it, so one long name does not shrink the ring.
func test_a_name_that_fits_nowhere_is_cut_alone() -> void:
    var factory := SaSettingsBrushSlots.factory()
    var plain := _ring(factory)
    var size_alone := plain.cells[1].get_theme_font_size("font_size")
    plain.free()

    var names := factory.duplicate()
    names[0] = TOO_LONG
    var ring := _ring(names)
    var cell := ring.cells[0]
    assert_eq(cell.autowrap_mode, TextServer.AUTOWRAP_OFF, "the long name is on one line")
    assert_eq(cell.text_overrun_behavior, SaTheme.TEXT_CUT, "cut with the mark")
    assert_true(bool(ring.report(Vector2.ZERO)["slots"][0]["cut"]), "and the dump says it is cut")
    for i in range(1, ring.cells.size()):
        assert_true(_whole(ring.cells[i]), "%s is still whole" % ring.cells[i].text)
        assert_eq(ring.cells[i].get_theme_font_size("font_size"), size_alone, "%s at the size it had" % ring.cells[i].text)
    ring.free()


## The cells grew taller, and still sit apart and clear of the wheel at the
## default size, and the strip the name line is drawn in touches no cell.
func test_the_taller_cells_and_the_name_line_sit_apart() -> void:
    var ring := _ring(SaSettingsBrushSlots.factory())
    var wheel := Rect2(ring.wheel.position, ring.wheel.size)
    var centre := wheel.get_center()
    var cells: Array[Rect2] = []
    for cell in ring.cells:
        cells.append(Rect2(cell.position, cell.size))
    for i in cells.size():
        assert_true(Rect2(Vector2.ZERO, ring.size).encloses(cells[i]), "cell %d inside the ring" % (i + 1))
        assert_true(DockerSummon.distance_to(cells[i], centre) > wheel.size.x / 2.0, "cell %d clear of the wheel" % (i + 1))
        for j in range(i + 1, cells.size()):
            assert_false(cells[i].intersects(cells[j]), "cells %d and %d apart" % [i + 1, j + 1])
    ring.cells[4].mouse_entered.emit()
    var line := Rect2(ring.name_line.position, ring.name_line.size)
    assert_true(line.position.y >= wheel.end.y, "the name line is under the wheel")
    for i in cells.size():
        assert_false(line.intersects(cells[i]), "the name line clear of cell %d" % (i + 1))
    ring.free()


## The pointer on a slot writes its preset's name whole under the wheel, and
## leaving it empties the line. The longest shipped name is the one tried.
func test_the_hovered_slots_name_is_written_whole_under_the_wheel() -> void:
    var names := SaSettingsBrushSlots.factory()
    names[8] = "Splattered Block"
    var ring := _ring(names)
    assert_eq(ring.name_line.text, "", "nothing under the wheel before the pointer is on a slot")
    ring.cells[8].mouse_entered.emit()
    assert_eq(ring.name_line.text, "Splattered Block", "the hovered slot's name is written")
    var font := ring.name_line.get_theme_font("font")
    var font_size := ring.name_line.get_theme_font_size("font_size")
    var width := font.get_string_size(ring.name_line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    assert_true(width <= ring.name_line.size.x, "whole, %d of the %d pixels its strip has" % [width, ring.name_line.size.x])
    assert_true(font_size > ring.cells[8].get_theme_font_size("font_size"), "and larger than in its cell")
    ring.cells[7].mouse_entered.emit()
    ring.cells[8].mouse_exited.emit()
    assert_eq(ring.name_line.text, "Charcoal", "leaving the last slot after entering the next keeps the next")
    ring.cells[7].mouse_exited.emit()
    assert_eq(ring.name_line.text, "", "and leaving it empties the line")
    ring.free()
