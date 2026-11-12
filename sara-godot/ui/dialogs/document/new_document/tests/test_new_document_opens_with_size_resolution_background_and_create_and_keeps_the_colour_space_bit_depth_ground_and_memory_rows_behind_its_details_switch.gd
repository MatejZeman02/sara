## New Document opens with size, resolution, background and Create, and keeps
## the colour space, bit depth, ground and memory rows behind its details
## switch.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ground, Colour space, Bit depth and
## a GPU memory line are four questions someone who has never painted on a
## computer cannot answer. Closed, the dialog asks the seven, and the one cost
## that bites is said beside Create without a row to answer.
##
## The dialog is built detached, since a Window added to the tree without
## embedding maps a real OS window and hangs the run.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

## The labelled lines shown with the details closed, in page order: the six
## rows a newcomer is asked, with the three lines that belong to them, the save
## under Template, the swap between the numbers and the background's colour,
## and the switch. Create is the seventh, a button under them.
const SHOWN_CLOSED: Array[StringName] = [
    &"template", &"save_template", &"size", &"width", &"swap", &"height", &"dpi", &"background", &"background_colour", &"details"
]

## The four the finding names, which the switch shows.
const FOLDED: Array[StringName] = [&"ground", &"space", &"depth", &"memory"]

var _types: SaLayerTypeRegistry = null
var _kept_last: String = ""
var _kept_details: bool = false


## A fresh profile: no last template and the switch never opened.
func before_each() -> void:
    _types = SaLayerTypeRegistry.new()
    _types.register(SaLayerTypeDescriptor.paper())
    _types.register(SaLayerTypeDescriptor.canvas())
    _kept_last = SaSettings.last_template
    _kept_details = SaSettings.new_document_details
    SaSettings.last_template = ""
    SaSettings.new_document_details = false


func after_each() -> void:
    SaSettings.last_template = _kept_last
    SaSettings.new_document_details = _kept_details
    _types = null


## Whether the row of *key* is on the page, as the page's own dump reads it.
static func _shown(dialog: NewDocumentDialog, key: StringName) -> bool:
    return bool(dialog.page.row(key).describe()["shown"])


## The keys of every row the page shows, in order.
static func _shown_keys(dialog: NewDocumentDialog) -> Array:
    var out: Array = []
    for entry: SaPageRow in dialog.page.rows():
        if _shown(dialog, entry.key):
            out.append(entry.key)
    return out


func test_closed_the_dialog_asks_the_seven_and_the_switch_shows_the_four() -> void:
    var dialog := NewDocumentDialog.new(_types)
    assert_false(dialog.details_open, "a fresh profile opens the details closed")
    assert_eq(_shown_keys(dialog), SHOWN_CLOSED, "closed, the page is Template, Size, Width, Height, Resolution and Background")
    for key: StringName in NewDocumentDialog.FIRST_ROWS:
        assert_true(SHOWN_CLOSED.has(key), "%s is one of them" % key)
    assert_true(dialog.create_button.visible, "with Create under them")
    assert_eq(dialog.create_button.text, "Create", "named Create")
    assert_false(dialog.memory_warning.visible, "and no memory warning at the screen size")
    var switch := dialog.page.row(&"details")
    assert_eq(switch.label, "Ground, colour and memory", "the switch is named for what it holds")

    switch.drive(true)
    for key: StringName in FOLDED:
        assert_true(_shown(dialog, key), "open, %s is shown" % key)
    assert_true(SaSettings.new_document_details, "and the profile remembers the switch open")
    var again := NewDocumentDialog.new(_types)
    assert_true(again.details_open, "so the next dialog opens with it open")
    assert_true(_shown(again, &"depth"), "and its rows shown")
    again.free()
    switch.drive(false)
    assert_false(SaSettings.new_document_details, "closed, the profile remembers that too")
    for key: StringName in FOLDED:
        assert_false(_shown(dialog, key), "closed again, %s goes" % key)
    dialog.free()


func test_the_largest_size_says_its_memory_beside_create_with_the_details_closed() -> void:
    var dialog := NewDocumentDialog.new(_types)
    dialog.page.row(&"width").drive(NewDocumentDialog.MAX_DIMENSION)
    dialog.page.row(&"height").drive(NewDocumentDialog.MAX_DIMENSION)
    assert_false(dialog.details_open, "the details stay closed")
    assert_false(_shown(dialog, &"memory"), "the memory row stays folded")
    assert_true(dialog.memory_warning.visible, "16384 by 16384 shows the memory line beside Create")
    var bytes := NewDocumentDialog.MemoryLine.layer_bytes(dialog.selected_size(), dialog.selected_space())
    var figure := NewDocumentDialog.MemoryLine.size_text(bytes)
    assert_true(dialog.memory_warning.text.contains(figure), "naming the figure %s: %s" % [figure, dialog.memory_warning.text])
    assert_true(dialog.memory_warning.text.contains("slow a laptop"), "in the painter's words")
    assert_eq(dialog.memory_warning.get_parent(), dialog.create_button.get_parent(), "on Create's row")
    dialog.page.row(&"width").drive(2480)
    dialog.page.row(&"height").drive(3508)
    assert_false(dialog.memory_warning.visible, "A4 at 300 dpi is no cost a laptop notices")
    dialog.free()


func test_a_document_made_closed_takes_the_profile_default_space_and_depth() -> void:
    var dialog := NewDocumentDialog.new(_types)
    var made: Array = []
    dialog.document_requested.connect(
        func(size: Vector2i, asked: SaColorSpace, dpi: float, background: Dictionary) -> void:
            made.append([size, asked, dpi, background])
    )
    dialog.create_button.pressed.emit()
    assert_eq(made.size(), 1, "Create asks for one document")
    var space: SaColorSpace = made[0][1]
    var wanted := SaEasel.default_space()
    assert_true(space.matches(wanted), "in the profile default space")
    assert_eq(space.depth, wanted.depth, "at its depth")
    dialog.free()
