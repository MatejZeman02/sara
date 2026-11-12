## Escape with a mask as the paint target leaves it, first, and
## the colour pair the mask turned grey comes back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The original foreground and background colours restore when the painter
## escapes the mask painting. A real canvas
## in a `SubViewport` standing in for the window, as
## `test_escape_leaves_the_quick_mask.gd` builds it, and a real key press
## through the router. The store's own suite is
## `core/colors/tests/test_while_a_mask_is_painted_the_pickers_offer_greys_and_the_colours_come_back_after.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func _escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.physical_keycode = KEY_ESCAPE
    event.pressed = true
    return event


## Red over blue, a mask as the target and a grey picked meanwhile, the quick
## mask on, and one Escape: the mask goes
## first and the pair comes back, and the quick mask is left
## for the next Escape.
func test_escape_leaves_the_mask_first_and_gives_the_pair_back() -> void:
    var host := Node.new()
    host.name = "U161EscapeTestHost"
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    viewport.add_child(canvas)
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return canvas
    router.tool_machine_provider = func() -> ToolMachine: return null
    var document := canvas.document
    var layer := document.active_layer
    assert_true(SaMaskOps.new(document).run(SaMaskOps.ADD, layer), "the layer takes a mask")
    # The router asks the app's own store, so this suite drives it and puts
    # the pair it found back at the end.
    var store := SaColors
    var found := [store.foreground, store.background]
    store.foreground = Color.RED
    store.background = Color.BLUE
    store.follow(document)
    document.mask_target = layer.mask
    store.foreground = Color(0.6, 0.6, 0.6)
    assert_true(store.masking, "the mask as the target greys the pair")
    document.selection.editing = true

    router.handle_viewport_input(_escape(), viewport)

    assert_null(document.mask_target, "Escape clears the mask target")
    assert_false(store.masking, "the pair is no longer grey")
    assert_eq(store.foreground, Color.RED, "red is the foreground again")
    assert_eq(store.background, Color.BLUE, "over blue again")
    assert_true(document.selection.editing, "the quick mask waits for the next Escape")

    router.handle_viewport_input(_escape(), viewport)
    assert_false(document.selection.editing, "which leaves it as before")
    store.follow(null)
    store.foreground = found[0]
    store.background = found[1]
    router.free()
    host.free()
