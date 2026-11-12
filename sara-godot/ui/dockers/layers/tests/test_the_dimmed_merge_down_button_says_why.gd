## The Layers docker's dimmed Merge Down button says why it is
## dimmed.
##
## The Layer menu's row and the More menu's give the reason, and the button on
## the docker's row, which a painter hovers first, gives it too and does not
## read the command's own sentence above a ground, what Merge Down does and not why
## it would not. What this suite holds is the button's hover, its name and
## chord on the first line, the reason on the second while it is dimmed, and the
## command's sentence there while it is live.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the docker shows.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(256, 256)
const MERGE_DOWN := &"layer_merge_down"

var _docker: LayersDocker = null
var _registries: SaRegistries = null


## A docker on a document made with Ground Paper, as File > New makes one, its
## buttons reading the skeleton's commands.
func before_each() -> void:
    _registries = Fixtures.make_registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    canvas.easel = SaEasel.create_default(SIZE)
    canvas.add_child(canvas.easel)
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    var doc := canvas.easel.document
    doc.reset_to_default(SIZE, doc.color_space, SaDocument.DEFAULT_DPI, choice, _registries.layer_types)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    canvas.add_child(_docker)
    _docker.target_canvas = canvas
    _docker._ready()
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.actions.op_buttons.commands = _registries.commands


func after_each() -> void:
    _docker.target_canvas.free()
    _docker = null
    _registries = null


func _doc() -> SaDocument:
    return _docker.target_canvas.document


func _button() -> Button:
    return _docker.actions.op_buttons.button(MERGE_DOWN)


## The button's first line, "Merge Down (Ctrl+E)", read from the registry the
## way the button reads it.
func _first_line() -> String:
    var commands := _registries.commands
    return "%s (%s)" % [commands.get_descriptor(MERGE_DOWN).label, commands.chord_text(MERGE_DOWN, 1)]


func _sentence() -> String:
    return _registries.commands.get_descriptor(MERGE_DOWN).sentence


func _hover_on(layer: SaLayer) -> String:
    _doc().set_active_layer(layer)
    _docker.actions.sync_buttons()
    return _button().tooltip_text


func test_above_a_ground_the_button_names_the_ground() -> void:
    assert_true(SaLayerOps.new(_doc()).layers()[0].is_generated(), "The paper lies at the bottom")
    var hover := _hover_on(_doc().get_node("Layer 1") as SaLayer)
    assert_true(_button().disabled, "Merge Down is dimmed above the paper")
    var lines := hover.split("\n")
    assert_eq(lines.size(), 2, "Its hover is two lines: %s" % hover)
    assert_eq(lines[0], _first_line(), "the button's name and chord first")
    assert_true(lines[1].contains("'Background' is a generated layer"), "and the paper's reason under it: %s" % hover)
    assert_false(hover.contains(_sentence()), "in place of what Merge Down does")


func test_on_the_bottom_layer_the_button_says_there_is_nothing_below() -> void:
    var hover := _hover_on(SaLayerOps.new(_doc()).layers()[0])
    assert_true(_button().disabled, "Merge Down is dimmed on the bottom layer")
    assert_true(hover.begins_with(_first_line() + "\n"), "Its name and chord first: %s" % hover)
    assert_true(hover.contains("nothing below it"), "and that there is nothing below: %s" % hover)
    assert_false(hover.contains(_sentence()), "in place of what Merge Down does")


func test_above_paint_the_live_button_says_what_it_does() -> void:
    _doc().set_active_layer(_doc().get_node("Layer 1") as SaLayer)
    SaLayerOps.new(_doc()).add()
    var hover := _hover_on(_doc().active_layer)
    assert_false(_button().disabled, "Merge Down is live on paint over paint")
    assert_eq(hover, "%s\n%s" % [_first_line(), _sentence()], "and its hover is the command's own sentence")


## The reason goes with the dim: the button dimmed above the paper and then
## live above paint says what Merge Down does again.
func test_the_reason_leaves_with_the_dim() -> void:
    _hover_on(_doc().get_node("Layer 1") as SaLayer)
    SaLayerOps.new(_doc()).add()
    var hover := _hover_on(_doc().active_layer)
    assert_false(_button().disabled, "Merge Down is live again")
    assert_false(hover.contains("generated layer"), "and the paper's reason is gone: %s" % hover)


## Several picked rows dim the button by the pick's own test, so the reason is the
## pick's: two rows with one between them.
func test_a_pick_with_a_gap_says_the_picks_reason() -> void:
    var ops := SaLayerOps.new(_doc())
    var layer_1 := _doc().get_node("Layer 1") as SaLayer
    _doc().set_active_layer(layer_1)
    ops.add()
    var layer_3 := ops.add()
    _docker.sync_layer_list()
    _doc().set_active_layer(layer_3)
    _docker.item_list.picked.press(_row_of(layer_3), false, false)
    _docker.item_list.picked.press(_row_of(layer_1), true, false)
    _docker.actions.sync_buttons()
    assert_eq(_docker.item_list.selected_layers().size(), 2, "Two rows are picked, one between them is not")
    assert_true(_button().disabled, "Merge Down is dimmed over a gap")
    var hover := _button().tooltip_text
    assert_true(hover.begins_with(_first_line() + "\n"), "Its name and chord first: %s" % hover)
    assert_true(hover.contains("Merge needs layers that sit next to each other"), "and the pick's reason: %s" % hover)


func _row_of(layer: SaLayer) -> int:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.layer_at(i) == layer:
            return i
    return -1
