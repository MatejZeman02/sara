## A stroke undone and redone reads at its first dab as it did before.
##
## A scenario painted a band of two strokes on each of four layers, undid
## six steps and redid them, and the left end of one band's first stroke read
## stronger after. Here two layers are painted the same way through the brush
## tool's own input, every step is undone and redone, and every texel of every
## layer is read equal to what it was before the undos.
extends "res://tests/test_framework.gd"

## The strokes are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const DOC_SIZE := Vector2i(1920, 1080)


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
    motion.pressure = 0.9
    machine.active_tool.handle_input(motion)


## One stroke in 24 steps, as the scenario's `stroke` step lays it.
static func _stroke(machine: ToolMachine, from: Vector2, to: Vector2) -> void:
    machine.surface.view.mouse_position = from
    _button(machine, true)
    for i in range(0, 25):
        _move(machine, from.lerp(to, i / 24.0))
        _shown(machine.surface)
    _button(machine, false)
    _shown(machine.surface)


## A band is two strokes, the second over the first, as in the scenario.
static func _band(machine: ToolMachine, y: float) -> void:
    _stroke(machine, Vector2(270.0, y), Vector2(1727.0, y + 66.0))
    _stroke(machine, Vector2(469.0, y + 40.0), Vector2(1925.0, y + 106.0))


## Every layer's every chunk, read back, by layer name and grid position.
static func _texels(doc: SaDocument) -> Dictionary:
    var out := {}
    for layer: SaLayer in SaLayerOps.new(doc).layers():
        var chunks := {}
        for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
            chunks[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
        out[String(layer.name)] = chunks
    return out


## The canvas as a frame shows it: the caches brought up to date and the
## composite owed run, with nothing asked again.
static func _shown(surface: SaSurface) -> PackedByteArray:
    surface.get_document().fold.debt.frame()
    surface.easel.process_pending_composite()
    surface.easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(surface.easel.output.rid, 0)


## The canvas composited again over the whole document, the answer the shown
## one has to equal.
static func _composited_afresh(surface: SaSurface) -> PackedByteArray:
    surface.get_document().update_caches()
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    surface.easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(surface.easel.output.rid, 0)


func test_every_layer_reads_the_same_after_every_step_is_undone_and_redone() -> void:
    var surface := Fixtures.make_surface(DOC_SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var hand := Fixtures.make_bound_machine(surface)
    hand.set_active_tool(&"brush")
    hand.active_tool.settings.radius = 0.05
    var doc := surface.get_document()

    EventBus.color_picked.emit(Color(0.0, 0.0, 0.0))
    _band(hand, 63.0)
    for colour: Color in [Color(0.8, 0.1, 0.1), Color(0.1, 0.6, 0.2), Color(0.1, 0.2, 0.9)]:
        SaLayerOps.new(doc).add()
        _shown(surface)
        EventBus.color_picked.emit(colour)
        _band(hand, 312.0 + 248.0 * [Color(0.8, 0.1, 0.1), Color(0.1, 0.6, 0.2)].find(colour))
    var before := _texels(doc)
    var shown_before := _shown(surface)
    assert_true(shown_before == _composited_afresh(surface), "before the undos the canvas shows what a fresh composite does")
    var steps := 0
    while doc.undo_redo.has_undo() and steps < 6:
        assert_true(doc.undo_redo.undo(), "each step undoes")
        steps += 1
    assert_true(steps == 6, "the bands and the layers are %d steps" % steps)
    _shown(surface)
    for i in steps:
        assert_true(doc.undo_redo.redo(), "and each redoes")
    var after := _texels(doc)
    assert_eq(after.keys(), before.keys(), "the same layers stand after the redos")
    for layer_name: String in before:
        var was: Dictionary = before[layer_name]
        var now: Dictionary = after[layer_name]
        assert_eq(now.keys(), was.keys(), "%s keeps the same chunks" % layer_name)
        for grid_pos: Vector2i in was:
            var same: bool = now.get(grid_pos, PackedByteArray()) == was[grid_pos]
            assert_true(same, "%s reads every texel of %s as before" % [layer_name, grid_pos])
    var shown_after := _shown(surface)
    assert_true(shown_after == shown_before, "and the canvas shows what it showed before the undos")
    assert_true(shown_after == _composited_afresh(surface), "which is what a fresh composite shows")
    Fixtures.teardown(surface, hand)
