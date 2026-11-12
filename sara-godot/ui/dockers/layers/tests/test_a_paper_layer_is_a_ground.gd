## A Paper layer is named Paper, shows its paper and goes under the paint.
##
## A painter painted on two layers, chose Paper from
## the Add-kind arrow, and got a row called "Layer 5" with an empty checker for
## a picture, directly above the active layer, whose opaque cream covered every
## stroke below it, and with a paint lock and an alpha lock on a layer that
## holds no paint. The suite adds the paper through the menu row the arrow
## runs, reads where it lands, what it is called and what the canvas still
## shows, adds a second and swaps a ground for a canvas, undoes the add, and
## builds the row to read its picture and its locks.
extends "res://tests/test_framework.gd"

## The composite is read back, and the rows bind their thumbnails.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(0.9, 0.1, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _texel(at: Vector2i) -> Color:
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _resolve() -> void:
    _doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()


## Two painted layers, the painter's: Layer 1 red over the top left chunk and
## a second layer blue over the top right one, the second active. The bottom
## half is painted on neither.
func _paint_two_layers() -> Array[SaLayer]:
    var first := _doc.active_layer
    first.get_or_create_chunk(Vector2i(0, 0)).clear(_doc.color_space.from_display(RED))
    var second := SaLayerOps.new(_doc).add()
    second.get_or_create_chunk(Vector2i(1, 0)).clear(_doc.color_space.from_display(BLUE))
    _doc.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    _resolve()
    return [first, second]


## What the Add-kind arrow does with the row the painter picked.
func _add_kind(id: StringName) -> SaLayer:
    assert_true(SaLayerMenuRows.new(_doc, null, _registries.layer_types).run(id), "The %s row adds a layer" % id)
    _resolve()
    return _doc.active_layer


## A ground added past the menus, which only ever swap one.
func _add_beside(id: StringName) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(id, _registries.layer_types)
    _resolve()
    return layer


func _names() -> Array[String]:
    var out: Array[String] = []
    for child in _doc.get_children():
        out.append(str(child.name))
    return out


func test_a_paper_is_named_paper_and_goes_under_the_paint() -> void:
    var painted := _paint_two_layers()
    var paper := _add_kind(&"paper")
    assert_eq(paper.layer_type, &"paper", "The arrow made a paper")
    assert_eq(str(paper.name), "Paper", "called Paper, not Layer 3")
    assert_eq(
        _names(),
        ["Background", "Paper", str(painted[0].name), str(painted[1].name)],
        "over the Background New laid and under both painted layers"
    )
    assert_null(paper.group, "at the top level")
    assert_eq(_doc.active_layer, paper, "and it is the active layer, so its options show")
    assert_true(paper.chunks.is_empty(), "A ground allocates no chunk (hard rule 3, sparse chunks)")
    var red := _texel(Vector2i(64, 64))
    assert_true(red.r > 0.5 and red.g < 0.2 and red.b < 0.2, "The red stroke is still on the canvas, %s" % red)
    var blue := _texel(Vector2i(320, 64))
    assert_true(blue.b > 0.5 and blue.r < 0.2, "and so is the blue one, %s" % blue)
    var shown := _texel(Vector2i(64, 400))
    assert_true(shown.r - shown.b > 0.02, "Where nothing is painted the warm paper shows, not the grey, %s" % shown)


## A second ground comes by another route than the menus, since the Ground row
## swaps the one that stands, so it is added here the way the door or a module
## adds one.
func test_a_second_paper_is_paper_2_and_lies_over_the_first() -> void:
    _paint_two_layers()
    var first := _add_kind(&"paper")
    var second := _add_beside(&"paper")
    assert_eq(str(second.name), "Paper 2", "The second paper is Paper 2")
    assert_eq(second.get_index(), first.get_index() + 1, "over the first, so the one just added is the one in sight")
    var canvas := _add_beside(&"canvas")
    assert_eq(str(canvas.name), "Canvas", "A canvas is named Canvas")
    assert_eq(canvas.get_index(), second.get_index() + 1, "and goes over the grounds already laid")


func test_a_ground_added_inside_a_group_goes_to_the_top_level() -> void:
    var member := _doc.active_layer
    var group := SaLayerOps.new(_doc).group_active()
    _doc.set_active_layer(member)
    assert_eq(SaLayerStack.parent_of(member), group, "The active layer is in a group")
    var paper := _add_kind(&"paper")
    assert_null(SaLayerStack.parent_of(paper), "and the paper is not")
    assert_eq(paper.get_index(), 1, "it goes over the Background under the group")


func test_a_painters_own_bottom_layer_keeps_the_paper_under_it() -> void:
    var bottom: SaLayer = _doc.get_child(0)
    bottom.name = "Sky"
    var paper := _add_kind(&"paper")
    assert_eq(paper.get_index(), 0, "A bottom layer the painter named is paint, and the paper goes under it")


func test_one_undo_takes_the_paper_away_and_gives_the_brush_back() -> void:
    var painted := _paint_two_layers()
    var steps := _doc.undo_redo.get_history_count()
    var paper := _add_kind(&"paper")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "The add is one history step")
    _doc.undo()
    _resolve()
    assert_null(paper.get_parent(), "Ctrl+Z takes the paper out")
    assert_eq(_doc.get_child_count(), 3, "and only the paper")
    assert_eq(_doc.active_layer, painted[1], "and the brush is back on the layer it was on")
    _doc.redo()
    assert_eq(paper.get_parent(), _doc, "The redo puts it back")
    assert_eq(paper.get_index(), 1, "in its place")


func test_a_swap_renames_a_ground_that_kept_its_kinds_name() -> void:
    var paper := _add_kind(&"paper")
    var rows := SaGroundRows.new()
    rows.show_layer(_doc, paper, _registries.layer_types)
    rows.ground_choice.choice_picked.emit(&"canvas")
    assert_eq(paper.layer_type, &"canvas", "The options swapped the ground")
    assert_eq(str(paper.name), "Canvas", "and an unrenamed row is called Canvas")
    _doc.undo()
    assert_eq(str(paper.name), "Paper", "The undo gives the name back with the paper")
    rows.free()

    var second := _add_kind(&"paper")
    SaGeneratedLayer.swap(_doc, second, _registries.layer_types.get_descriptor(&"canvas"), _registries.layer_types)
    assert_eq(str(second.name), "Canvas", "Paper 2 is a kind's name too, and the first Canvas is free")

    paper.name = "Hot pressed"
    SaGeneratedLayer.swap(_doc, paper, _registries.layer_types.get_descriptor(&"canvas"), _registries.layer_types)
    assert_eq(paper.layer_type, &"canvas", "A renamed paper swaps")
    assert_eq(str(paper.name), "Hot pressed", "and keeps the name the painter wrote")


func test_the_ground_names_read_as_their_kinds() -> void:
    assert_true(SaGeneratedLayer.is_kind_name("Paper", "Paper"), "Paper is a paper's own name")
    assert_true(SaGeneratedLayer.is_kind_name("Paper 12", "Paper"), "and so is Paper 12")
    assert_false(SaGeneratedLayer.is_kind_name("Paper 1", "Paper"), "Paper 1 was never made")
    assert_false(SaGeneratedLayer.is_kind_name("Paper two", "Paper"), "Paper two is the painter's")
    assert_false(SaGeneratedLayer.is_kind_name("Papers", "Paper"), "and so is Papers")


func test_the_row_shows_the_paper_and_no_paint_locks() -> void:
    _paint_two_layers()
    var paper := _add_kind(&"paper")
    var viewport := SubViewport.new()
    viewport.size = Vector2i(320, 120)
    EventBus.add_child(viewport)
    var column := VBoxContainer.new()
    column.size = Vector2(320, 120)
    viewport.add_child(column)
    var ground_row := SaLayerRowView.new(str(paper.name), 0, false, 0, paper)
    var paint_row := SaLayerRowView.new("Layer 1", 0, false, 1, _doc.get_child(2) as SaLayer)
    column.add_child(ground_row)
    column.add_child(paint_row)
    ground_row.refresh(_doc)
    paint_row.refresh(_doc)
    ground_row.thumb.refresh()
    _sort_children(viewport)

    var rim: Dictionary = ground_row.thumb.rim_report()
    var first: Color = _doc.color_space.to_display(paper.generator_params["color"])
    var second: Color = _doc.color_space.to_display(paper.generator_params["second"])
    assert_eq(rim["ground"], [first.to_html(false), second.to_html(false)], "The picture is the paper's two colours")
    assert_false(rim["checker"], "not the empty checker")
    assert_true(paper.chunks.is_empty(), "and drawing it allocated no chunk")
    assert_eq((paint_row.thumb.rim_report()["ground"] as Array).size(), 0, "A painted layer's picture is its paint")

    for which: StringName in [&"paint", &"alpha"]:
        assert_false((ground_row.toggles[which] as Button).is_visible_in_tree(), "The ground's row draws no %s lock" % which)
        assert_true((paint_row.toggles[which] as Button).is_visible_in_tree(), "where a painted layer's row does")
    assert_not_null(ground_row.paint_slot, "The ground keeps a slot where the two locks are")
    assert_eq(ground_row.paint_slot.tooltip_text, "A ground holds no paint", "which says why on hover")
    var slot := ground_row.paint_slot.get_global_rect()
    var paint_lock := (paint_row.toggles[&"paint"] as Button).get_global_rect()
    var alpha_lock := (paint_row.toggles[&"alpha"] as Button).get_global_rect()
    assert_almost_eq(slot.position.x, paint_lock.position.x, 0.5, "from the paint lock's column")
    assert_almost_eq(slot.end.x, alpha_lock.end.x, 0.5, "to the alpha lock's")
    var clip := (ground_row.toggles[&"clip"] as Button).global_position.x
    var painted_clip := (paint_row.toggles[&"clip"] as Button).global_position.x
    assert_almost_eq(clip, painted_clip, 0.5, "and the clip lock keeps its column")
    viewport.free()


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
