## A stroke straight after a click on a row paints what it paints after a full
## fold.
##
## An activation owes the fold now, and the stroke's press pays it. Two
## surfaces are built alike on the stack: on one the press comes straight
## after the activation and finds the caches stale, on the other a full
## `update_caches` runs first. Both strokes leave the same pixels in the layer
## and on the canvas. The suite prints the time from the press to the first
## dab on each, which is what the stale press adds.
##
## A click on a row reaches the document as `set_active_layer`, and nothing
## else of it touches the caches. the sibling docker suite reads that end of it.
extends "res://tests/test_framework.gd"

## The strokes and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const DOC_SIZE := Vector2i(2160, 720)
const PAINT_LAYERS := 30

## The layers each surface paints on in turn, the first a warm-up.
const TARGETS: Array[String] = ["Paint 3", "Paint 20", "Paint 8", "Paint 15"]


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(DOC_SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := surface.get_document()
    for i: int in PAINT_LAYERS:
        var layer := SaLayerOps.new(doc).add()
        layer.name = "Paint %d" % i
        doc.fill_layer(Color(float(i) / PAINT_LAYERS, 0.4, 0.2, 0.5), layer)
    doc.update_caches()
    return surface


static func _button(machine: ToolMachine, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = machine.surface.view.mouse_position
    machine.active_tool.handle_input(event)


static func _move(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = at
    motion.pressure = 1.0
    machine.active_tool.handle_input(motion)


## Makes *layer_name* active, folds at once when *fresh*, and paints a short
## stroke on it. Returns the microseconds from the press to the first dab
## laid and finished on the GPU.
static func _stroke(surface: SaSurface, machine: ToolMachine, layer_name: String, fresh: bool) -> int:
    var doc := surface.get_document()
    doc.set_active_layer(doc.find_child(layer_name, false, false) as SaLayer)
    if fresh:
        doc.update_caches()
    var at := Vector2(400.0 + 60.0 * TARGETS.find(layer_name), 300.0)
    machine.surface.view.mouse_position = at
    var start := Time.get_ticks_usec()
    _button(machine, true)
    _move(machine, at)
    GlobalShaderCompiler.get_rd().texture_get_data(doc.stroke_layer.chunks.values()[0].albedo().rid, 0)
    var spent := Time.get_ticks_usec() - start
    for i in range(1, 12):
        _move(machine, at + Vector2(6.0 * i, 3.0 * i))
    _button(machine, false)
    return spent


static func _bytes_of(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


static func _canvas(surface: SaSurface) -> PackedByteArray:
    surface.get_document().update_caches()
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    surface.easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(surface.easel.output.rid, 0)


func test_a_stroke_after_a_click_paints_what_it_paints_after_a_full_fold() -> void:
    var stale := _surface()
    var stale_hand := Fixtures.make_bound_machine(stale)
    stale_hand.set_active_tool(&"brush")
    var fresh := _surface()
    var fresh_hand := Fixtures.make_bound_machine(fresh)
    fresh_hand.set_active_tool(&"brush")
    var stale_best := 1 << 40
    var fresh_best := 1 << 40
    for i: int in TARGETS.size():
        var stale_doc := stale.get_document()
        stale_doc.fold.debt.quiet_msec = 60000
        var folds_owed := not stale_doc.fold.reads_as_built(stale_doc)
        var stale_usec := _stroke(stale, stale_hand, TARGETS[i], false)
        var fresh_usec := _stroke(fresh, fresh_hand, TARGETS[i], true)
        var line := "probe press to first dab on %s: %.2f ms stale, %.2f ms fresh"
        print(line % [TARGETS[i], stale_usec / 1000.0, fresh_usec / 1000.0])
        assert_false(folds_owed, "before the click the caches are built where the last stroke left them")
        if i == 0:
            continue
        stale_best = mini(stale_best, stale_usec)
        fresh_best = mini(fresh_best, fresh_usec)
    print(
        (
            "probe press to first dab, best of %d: %.2f ms stale, %.2f ms fresh, %.2f ms more"
            % [TARGETS.size() - 1, stale_best / 1000.0, fresh_best / 1000.0, (stale_best - fresh_best) / 1000.0]
        )
    )
    for layer_name: String in TARGETS:
        var a := stale.get_document().find_child(layer_name, false, false) as SaLayer
        var b := fresh.get_document().find_child(layer_name, false, false) as SaLayer
        assert_true(not a.chunks.is_empty(), "The stroke on %s is in the layer" % layer_name)
        assert_eq(_bytes_of(a), _bytes_of(b), "and its pixels are the ones painted after a full fold")
    assert_eq(_canvas(stale), _canvas(fresh), "and so is the canvas")
    Fixtures.teardown(fresh, fresh_hand)
    Fixtures.teardown(stale, stale_hand)


## The press pays what the activation owed before the first dab is laid.
func test_the_press_pays_the_fold_the_click_owed() -> void:
    var surface := _surface()
    var hand := Fixtures.make_bound_machine(surface)
    hand.set_active_tool(&"brush")
    var doc := surface.get_document()
    doc.fold.debt.quiet_msec = 60000
    doc.set_active_layer(doc.find_child("Paint 20", false, false) as SaLayer)
    assert_true(doc.fold.debt.is_owed(), "The click leaves the caches stale")
    assert_false(doc.fold.reads_as_built(doc), "around the layer active before it")
    _button(hand, true)
    assert_false(doc.fold.debt.is_owed(), "and the press folds them")
    assert_true(doc.fold.reads_as_built(doc), "around the layer it paints")
    _button(hand, false)
    Fixtures.teardown(surface, hand)
