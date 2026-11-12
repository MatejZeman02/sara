## With a mask the paint
## target, Copy holds the mask as a grey picture, Paste writes a held picture
## into a mask as its grey, Paste with a layer the target lays the grey down as
## a paint layer, and Cut hides what it copied. A painter's note of 2026-10-31
## was "Bug: not able to copy and paste a mask layer."
##
## Every mask here is drawn the same way, hidden over the canvas, shown over
## one rectangle and half shown over another, so a copy read at the three
## points says whether the coverage travelled whole. A layer's mask, a group's
## and an attached filter's record's each take the same cases, since a mask
## keeps its coverage in two different stores.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)

## Where the mask shows, where it is half shown, and where it hides, each in a
## chunk of its own, and the rectangles that draw the first two.
const SHOWN := Vector2i(60, 60)
const HALF := Vector2i(300, 60)
const HIDDEN := Vector2i(60, 300)
const SHOWN_BOX := Rect2i(20, 20, 120, 120)
const HALF_BOX := Rect2i(280, 20, 120, 120)

## A selection over the shown and the hidden points and not the half one.
const LEFT := Rect2i(0, 0, 200, 512)

const EXACT := 1.0e-3

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layers: SaLayerOps = null
var _masks: SaMaskOps = null


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _layers = SaLayerOps.new(_doc)
    _masks = SaMaskOps.new(_doc)
    _doc.active_layer.fill(Color(0.8, 0.2, 0.1, 1.0))


func after_each() -> void:
    _doc = null
    _layers = null
    _masks = null
    _easel.free()
    _easel = null


## What *mask* reads at document pixel *at*, its rest where it holds nothing.
static func _reads(mask: SaMask, at: Vector2i) -> float:
    var edge := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / edge), floori(float(at.y) / edge))
    var texture := mask.texture_for(grid_pos)
    if texture == null:
        return mask.rest
    var local := Vector2i((Vector2(at - grid_pos * edge) * texture.size.x / float(edge)).floor())
    return Bench.texel(texture, local).r


## The paint of *layer* at *at*, transparent where it holds no chunk.
static func _paint(layer: SaLayer, at: Vector2i) -> Color:
    var edge := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / edge), floori(float(at.y) / edge))
    var texture := layer.get_field(grid_pos)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    return Bench.texel(texture, at - grid_pos * edge)


## A paint layer filled with *color*, made the active one.
func _painted(color: Color) -> SaLayer:
    var layer := _layers.add()
    layer.fill(color)
    return layer


## Gives *owner* the three part mask, through the fill keys' own steps.
func _draw_mask(owner: Object) -> SaMask:
    if SaMaskOps.mask_of(owner) == null:
        _masks.add(owner)
    _masks.fill(owner, 0.0, "Clear Mask")
    _doc.selection.select_rect(SHOWN_BOX)
    _masks.fill(owner, 1.0, "Fill Mask")
    _doc.selection.select_rect(HALF_BOX)
    _masks.fill(owner, 0.5, "Fill Mask")
    _doc.selection.deselect()
    return SaMaskOps.mask_of(owner)


## A mask that reads *value* everywhere on *owner*, the target of a paste.
func _plain_mask(owner: Object, value: float) -> SaMask:
    if SaMaskOps.mask_of(owner) == null:
        _masks.add(owner)
    _masks.fill(owner, value, "Fill Mask")
    return SaMaskOps.mask_of(owner)


## The three owners, each with the three part mask: a paint layer, a group and
## an attached filter's record, answered with what each is called.
func _owners() -> Array:
    var layer := _painted(Color(0.1, 0.5, 0.9, 1.0))
    var grouped := _painted(Color(0.3, 0.3, 0.3, 1.0))
    var group := _layers.group_active()
    var filtered := _painted(Color(0.2, 0.7, 0.2, 1.0))
    var record := SaFilterOps.new(_doc).attach(filtered, Bench.INVERT)
    assert_not_null(grouped, "the group holds a layer")
    var found := []
    for pair: Array in [["a layer's mask", layer], ["a group's mask", group], ["a record's mask", record]]:
        _draw_mask(pair[1])
        found.append(pair)
    _doc.undo_redo.clear_history()
    return found


func test_a_mask_copied_whole_pastes_into_another_mask_as_itself_and_one_undo_gives_the_mask_back() -> void:
    for pair: Array in _owners():
        var source: SaMask = SaMaskOps.mask_of(pair[1])
        var target_layer := _painted(Color(0.6, 0.4, 0.2, 1.0))
        var target := _plain_mask(target_layer, 1.0)
        _doc.undo_redo.clear_history()
        var paint := [_paint(target_layer, SHOWN), _paint(target_layer, HALF), _paint(target_layer, HIDDEN)]
        var held := SaClipboard.new()
        var clipboard := SaMaskClipboard.new(_doc)
        assert_true(clipboard.copy(held, pair[1]) > 0, "%s is held" % pair[0])
        assert_true(clipboard.paste(held, target_layer), "and pasted into a layer's mask")
        for at: Vector2i in [SHOWN, HALF, HIDDEN]:
            assert_almost_eq(_reads(target, at), _reads(source, at), EXACT, "%s lands as itself at %s" % [pair[0], at])
        assert_eq(
            [_paint(target_layer, SHOWN), _paint(target_layer, HALF), _paint(target_layer, HIDDEN)],
            paint,
            "the layer's paint is what it was"
        )
        assert_eq(_doc.undo_redo.get_history_count(), 1, "in one step")
        assert_eq(_doc.undo_redo.get_current_action_name(), SaMaskClipboard.PASTE_NAME, "titled for the mask")
        assert_true(_doc.undo(), "one undo")
        for at: Vector2i in [SHOWN, HALF, HIDDEN]:
            assert_almost_eq(_reads(target, at), 1.0, EXACT, "gives the mask back at %s" % at)


func test_a_mask_copied_through_a_selection_pastes_only_what_was_selected() -> void:
    for pair: Array in _owners():
        var target_layer := _painted(Color(0.6, 0.4, 0.2, 1.0))
        var target := _plain_mask(target_layer, 0.25)
        _doc.selection.select_rect(LEFT)
        var held := SaClipboard.new()
        var clipboard := SaMaskClipboard.new(_doc)
        assert_true(clipboard.copy(held, pair[1]) > 0, "%s is held through the selection" % pair[0])
        _doc.selection.deselect()
        assert_true(clipboard.paste(held, target_layer), "and pasted")
        assert_almost_eq(_reads(target, SHOWN), 1.0, EXACT, "%s shows where it showed inside the selection" % pair[0])
        assert_almost_eq(_reads(target, HIDDEN), 0.0, EXACT, "and hides where it hid")
        assert_almost_eq(_reads(target, HALF), 0.25, EXACT, "and the mask outside the selection is what it was")


func test_a_mask_pasted_into_a_group_s_and_a_record_s_mask_lands_as_itself() -> void:
    var source := _draw_mask(_painted(Color(0.1, 0.5, 0.9, 1.0)))
    var source_layer := source.layer
    _layers.add()
    var group := _layers.group_active()
    var record := SaFilterOps.new(_doc).attach(_painted(Color(0.2, 0.7, 0.2, 1.0)), Bench.INVERT)
    var held := SaClipboard.new()
    var clipboard := SaMaskClipboard.new(_doc)
    assert_true(clipboard.copy(held, source_layer) > 0, "a layer's mask is held")
    for pair: Array in [["a group's mask", group], ["a record's mask", record]]:
        var target := _plain_mask(pair[1], 1.0)
        assert_true(clipboard.paste(held, pair[1]), "and pasted into %s" % pair[0])
        for at: Vector2i in [SHOWN, HALF, HIDDEN]:
            assert_almost_eq(_reads(target, at), _reads(source, at), EXACT, "%s takes it at %s" % [pair[0], at])


func test_a_held_mask_pasted_with_a_layer_the_target_is_a_grey_paint_layer() -> void:
    for pair: Array in _owners():
        var source: SaMask = SaMaskOps.mask_of(pair[1])
        for selected: bool in [false, true]:
            if selected:
                _doc.selection.select_rect(LEFT)
            var held := SaClipboard.new()
            SaMaskClipboard.new(_doc).copy(held, pair[1])
            _doc.selection.deselect()
            var pasted := held.paste(_doc)
            assert_not_null(pasted, "%s pastes as a layer" % pair[0])
            if pasted == null:
                continue
            for at: Vector2i in [SHOWN, HALF, HIDDEN]:
                var got := _paint(pasted, at)
                if selected and at == HALF:
                    assert_true(got.a <= EXACT, "outside the selection the layer holds nothing")
                    continue
                var want := _reads(source, at)
                assert_almost_eq(got.a, 1.0, EXACT, "%s is opaque at %s" % [pair[0], at])
                assert_almost_eq(_doc.color_space.lightness(got), want, EXACT, "and as light as the mask showed")
                assert_almost_eq(got.r, got.b, EXACT, "and grey")


func test_a_layer_s_paint_pasted_into_a_mask_becomes_its_grey() -> void:
    var paint := _painted(Color(0.2, 0.6, 0.4, 1.0))
    _doc.selection.select_rect(HALF_BOX)
    _doc.fill_layer(Color(0.9, 0.9, 0.1, 1.0), paint)
    _doc.selection.deselect()
    var held := SaClipboard.new()
    assert_true(held.copy(_doc, paint) > 0, "the layer's paint is held")
    var target_layer := _painted(Color(0.6, 0.4, 0.2, 1.0))
    var target := _plain_mask(target_layer, 1.0)
    assert_true(SaMaskClipboard.new(_doc).paste(held, target_layer), "and pasted into a mask")
    for at: Vector2i in [SHOWN, HALF, HIDDEN]:
        var want := clampf(_doc.color_space.lightness(_paint(paint, at)), 0.0, 1.0)
        assert_almost_eq(_reads(target, at), want, EXACT, "the mask is the paint's grey at %s" % at)


func test_a_paste_into_a_mask_keeps_to_the_selection_standing_where_it_lands() -> void:
    var source := _draw_mask(_painted(Color(0.1, 0.5, 0.9, 1.0)))
    var held := SaClipboard.new()
    var clipboard := SaMaskClipboard.new(_doc)
    clipboard.copy(held, source.layer)
    var target_layer := _painted(Color(0.6, 0.4, 0.2, 1.0))
    var target := _plain_mask(target_layer, 0.25)
    _doc.selection.select_rect(HALF_BOX)
    assert_true(clipboard.paste(held, target_layer), "the paste lands inside the selection")
    assert_almost_eq(_reads(target, HALF), 0.5, EXACT, "it writes inside")
    assert_almost_eq(_reads(target, SHOWN), 0.25, EXACT, "and leaves the rest of the mask alone")
    assert_almost_eq(_reads(target, HIDDEN), 0.25, EXACT, "everywhere")


func test_cut_on_a_mask_holds_it_and_hides_where_the_selection_was() -> void:
    for pair: Array in _owners():
        var mask: SaMask = SaMaskOps.mask_of(pair[1])
        _plain_mask(pair[1], 1.0)
        _doc.selection.select_rect(LEFT)
        var held := SaClipboard.new()
        assert_true(SaMaskClipboard.new(_doc).cut(held, pair[1]), "%s is cut" % pair[0])
        _doc.selection.deselect()
        assert_false(held.is_empty(), "and held")
        assert_almost_eq(_reads(mask, SHOWN), 0.0, EXACT, "hidden where the selection was")
        assert_almost_eq(_reads(mask, HIDDEN), 0.0, EXACT, "all over it")
        assert_almost_eq(_reads(mask, HALF), 1.0, EXACT, "and shown outside it")
        var pasted := held.paste(_doc)
        assert_not_null(pasted, "what the cut held pastes")
        if pasted != null:
            assert_almost_eq(_paint(pasted, SHOWN).r, 1.0, EXACT, "as the white the mask was")


func test_a_held_mask_travels_to_another_document_as_a_layer_and_into_a_mask() -> void:
    var source := _draw_mask(_painted(Color(0.1, 0.5, 0.9, 1.0)))
    var held := SaClipboard.new()
    SaMaskClipboard.new(_doc).copy(held, source.layer)
    var other: SaEasel = Bench.easel(SIZE)
    var elsewhere := other.document
    var layer := SaLayerOps.new(elsewhere).add()
    layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var masks := SaMaskOps.new(elsewhere)
    masks.add(layer)
    assert_true(SaMaskClipboard.new(elsewhere).paste(held, layer), "the held mask pastes into a mask of another document")
    var pasted := held.paste(elsewhere)
    assert_not_null(pasted, "and as a layer there")
    for at: Vector2i in [SHOWN, HALF, HIDDEN]:
        assert_almost_eq(_reads(layer.mask, at), _reads(source, at), EXACT, "the mask lands as itself at %s" % at)
        if pasted != null:
            var grey := elsewhere.color_space.lightness(_paint(pasted, at))
            assert_almost_eq(grey, _reads(source, at), EXACT, "the layer as its grey")
    other.free()
