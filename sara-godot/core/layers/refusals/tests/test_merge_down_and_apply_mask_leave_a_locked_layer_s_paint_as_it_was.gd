## Merge Down and Apply Mask leave a locked layer's paint as it was, as a
## stroke, Clear and Flatten Filter do. Merge Down onto a locked layer, of a
## locked layer, or of a picked set over one is refused with a line in the
## corner that names the locked layer, and the Layer menu's row is dimmed.
## Apply Mask on a locked layer is refused the same way, its mask and paint
## kept. With nothing locked, both do what they did.
##
## Everything goes through the registered commands, which are what the Layer
## menu's rows and their chords run and dim by, and the texels are read off
## the layers' own chunks.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const AT := Vector2i(10, 10)
const MERGE := &"layer_merge_down"
const APPLY := &"layer_mask_apply"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _ops: SaLayerOps = null
var _lower: SaLayer = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _ops = SaLayerOps.new(_doc)
    _lower = _doc.active_layer
    _lower.name = "Layer 1"
    _lower.fill(BLUE)


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    _registries = null
    _doc = null
    _ops = null
    _lower = null


## A layer filled red above the lower one, made active and the only one picked.
func _upper() -> SaLayer:
    _doc.set_active_layer(_lower)
    var layer := _ops.add()
    layer.name = "Upper"
    layer.fill(RED)
    _pick([layer])
    return layer


func _pick(layers: Array[SaLayer]) -> void:
    _doc.set_active_layer(layers[layers.size() - 1])
    _doc.picked.pick(layers)


func _texel(layer: SaLayer) -> Color:
    var field := layer.get_field(Vector2i.ZERO)
    assert_not_null(field, "'%s' holds paint" % layer.name)
    return Bench.texel(field, AT) if field != null else Color()


func _near(was: Color, now: Color, what: String) -> void:
    var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
    assert_true(moved < 0.01, "%s: %s became %s" % [what, was, now])


func _enabled(command_id: StringName) -> bool:
    return _registries.commands.get_descriptor(command_id).is_enabled()


## What the corner says while *command_id* runs.
func _said_running(command_id: StringName) -> PackedStringArray:
    return _capture(func() -> void: _registries.commands.execute(command_id))


func _says_locked(said: PackedStringArray, named: String, what: String) -> void:
    var line := "'%s' is locked. Unlock it in the Layers docker first." % named
    assert_eq(said.size(), 1, "%s, the corner says one thing: %s" % [what, said])
    assert_true(said.size() == 1 and said[0].contains(line), "%s, and names '%s' as locked: %s" % [what, named, said])


## Merge Down is refused and dimmed, and both layers and their paint stay.
func _merge_refused(upper: SaLayer, named: String, what: String) -> void:
    var count := _ops.layers().size()
    assert_false(_enabled(MERGE), "%s, the Layer menu's Merge Down is dimmed" % what)
    _says_locked(_said_running(MERGE), named, what)
    assert_eq(_ops.layers().size(), count, "%s, no layer goes" % what)
    assert_true(is_instance_valid(upper) and upper.get_parent() == _doc, "%s, the upper layer stays" % what)
    _near(BLUE, _texel(_lower), "%s, Layer 1's paint" % what)
    _near(RED, _texel(upper), "%s, the upper layer's paint" % what)


func test_merge_down_onto_a_locked_layer_is_refused() -> void:
    var upper := _upper()
    _lower.is_locked = true
    _merge_refused(upper, "Layer 1", "Onto a locked Layer 1")


func test_merge_down_of_a_locked_layer_is_refused() -> void:
    var upper := _upper()
    upper.is_locked = true
    _merge_refused(upper, "Upper", "A locked upper layer")


func test_a_picked_set_over_a_locked_layer_is_refused() -> void:
    var upper := _upper()
    _lower.is_locked = true
    _pick([_lower, upper])
    _merge_refused(upper, "Layer 1", "A picked set whose lowest is locked")


func test_a_group_holding_a_locked_layer_does_not_merge_down() -> void:
    var upper := _upper()
    var group := _ops.group_layers([upper])
    upper.is_locked = true
    _pick([group])
    _merge_refused(upper, "Upper", "A group holding a locked layer")


func test_merge_down_with_nothing_locked_merges_as_before() -> void:
    var upper := _upper()
    var count := _ops.layers().size()
    assert_true(_enabled(MERGE), "Merge Down is lit")
    assert_eq(_said_running(MERGE).size(), 0, "and says nothing")
    assert_eq(_ops.layers().size(), count - 1, "The upper layer goes")
    assert_false(is_instance_valid(upper) and upper.get_parent() == _doc, "into Layer 1")
    _near(RED, _texel(_lower), "Layer 1 holds the merged red")


## *layer* with a mask that hides all of it, so applying it empties the paint.
func _masked(layer: SaLayer) -> SaLayer:
    var masks := SaMaskOps.new(_doc)
    assert_true(masks.add(layer), "'%s' takes a mask" % layer.name)
    assert_true(masks.invert(layer), "which is inverted to hide everything")
    _pick([layer])
    return layer


func test_apply_mask_on_a_locked_layer_is_refused() -> void:
    var layer := _masked(_lower)
    var mask := layer.mask
    layer.is_locked = true
    assert_false(_enabled(APPLY), "The Layer menu's Apply Mask is dimmed")
    _says_locked(_said_running(APPLY), "Layer 1", "Apply Mask on a locked layer")
    assert_true(layer.mask == mask, "The mask stays")
    _near(BLUE, _texel(layer), "and the paint")
    _says_locked(_capture(func() -> void: SaMaskOps.new(_doc).apply(layer)), "Layer 1", "Apply asked directly")
    assert_true(layer.mask == mask, "which keeps the mask too")


func test_a_lock_leaves_the_mask_s_other_rows_lit() -> void:
    var layer := _masked(_lower)
    layer.is_locked = true
    for command_id: StringName in [SaMaskOps.DELETE, SaMaskOps.INVERT, SaMaskOps.DISABLE, SaMaskOps.TO_SELECTION]:
        assert_true(SaMaskOps.can(command_id, layer), "%s changes the mask alone and stays lit" % command_id)


func test_apply_mask_with_nothing_locked_applies_as_before() -> void:
    var layer := _masked(_lower)
    assert_true(_enabled(APPLY), "Apply Mask is lit")
    assert_eq(_said_running(APPLY).size(), 0, "and says nothing")
    assert_null(layer.mask, "The mask goes")
    _near(Color(0.0, 0.0, 1.0, 0.0), _texel(layer), "into the paint, which it hid whole")


## What the corner says while *work* runs.
func _capture(work: Callable) -> PackedStringArray:
    var kept := SaProblems.pending_refusals
    var announcing := SaProblems.announce
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false
    work.call()
    var said := SaProblems.pending_refusals
    SaProblems.pending_refusals = kept
    SaProblems.announce = announcing
    return said
