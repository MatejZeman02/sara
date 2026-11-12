## Escape leaves the quick mask and the banner says the mode is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter who toggles the dockers with Shift and a letter can land in the
## quick mask and be unable to paint. The way out a painter finds without the menu is Escape, and the way they learn
## the mode is on is a line over the canvas. Both are proved here on a real
## canvas, a `SubViewport` standing in for the window the way
## `ui/shortcuts/tests/test_escape_releases_the_focus.gd` does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func _escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.physical_keycode = KEY_ESCAPE
    event.pressed = true
    return event


## A viewport holding a canvas with a document, a text box beside it, and a
## router reading that canvas.
func _bench() -> Dictionary:
    var host := Node.new()
    host.name = "S1EscapeTestHost"
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    viewport.add_child(canvas)
    var field := LineEdit.new()
    field.name = "S1Field"
    viewport.add_child(field)
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return canvas
    router.tool_machine_provider = func() -> ToolMachine: return null
    return {"host": host, "viewport": viewport, "canvas": canvas, "field": field, "router": router}


func _teardown(bench: Dictionary) -> void:
    (bench["router"] as ShortcutRouter).free()
    (bench["host"] as Node).free()


## The plain case: the mask is on, nothing has the keyboard, Escape
## leaves it. What was painted into the mask stays as the selection, because
## leaving a mode is not dropping its work: Deselect does that.
func test_escape_leaves_the_quick_mask_and_keeps_the_selection() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var selection: SaSelection = (bench["canvas"] as SaCanvas).document.selection
    selection.select_rect(Rect2i(8, 8, 16, 16))
    selection.editing = true
    var chunks_before := selection.chunks.size()

    router.handle_viewport_input(_escape(), viewport)

    assert_false(selection.editing, "Escape leaves the quick mask")
    assert_true(selection.active, "the selection painted so far is still a selection")
    assert_eq(selection.chunks.size(), chunks_before, "Escape leaves the mask's chunks where they were")
    _teardown(bench)


## Escape with the mask off changes nothing about the selection, so the key
## keeps releasing the focus.
func test_escape_with_the_mask_off_leaves_the_selection_alone() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var selection: SaSelection = (bench["canvas"] as SaCanvas).document.selection
    selection.select_rect(Rect2i(8, 8, 16, 16))
    var chunks_before := selection.chunks.size()

    router.handle_viewport_input(_escape(), viewport)

    assert_true(selection.active, "a selection Escape did not touch")
    assert_eq(selection.chunks.size(), chunks_before, "and its chunks are all there")
    _teardown(bench)


## A text box holds the keyboard first: one Escape leaves the box and the mask
## stays on, the next leaves the mask.
func test_a_text_box_keeps_the_first_escape() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    var selection: SaSelection = (bench["canvas"] as SaCanvas).document.selection
    selection.editing = true
    field.grab_focus()

    router.handle_viewport_input(_escape(), viewport)
    assert_eq(viewport.gui_get_focus_owner(), null, "the first Escape leaves the text box")
    assert_true(selection.editing, "and the mask is still on")

    router.handle_viewport_input(_escape(), viewport)
    assert_false(selection.editing, "the second Escape leaves the mask")
    _teardown(bench)


## The banner over the canvas shows while the mask is on and not otherwise,
## and it reads the document the view holds now, not the one it was built over.
func test_the_banner_follows_the_quick_mask() -> void:
    var bench := _bench()
    var canvas := bench["canvas"] as SaCanvas
    var host := Control.new()
    (bench["viewport"] as SubViewport).add_child(host)
    var banner := SaQuickMaskBanner.attach_to(host, canvas)
    var selection: SaSelection = canvas.document.selection

    assert_false(banner.is_on(), "no banner over a plain canvas")
    selection.editing = true
    assert_true(banner.is_on(), "the banner while the mask is on")
    selection.deselect()
    assert_false(banner.is_on(), "Deselect leaves the mask, so the banner goes with it")
    _teardown(bench)
