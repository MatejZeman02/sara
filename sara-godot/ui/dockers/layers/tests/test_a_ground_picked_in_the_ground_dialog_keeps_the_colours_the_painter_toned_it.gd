## A ground picked in the Ground dialog's own Ground choice keeps the colours
## the painter toned the old one with, where the new kind has a colour of the
## same name, as the Layer menu's Ground row does. Giving the new ground
## its defaults instead would turn a toned Paper tried as a Canvas warm white
## under the paint and back to Paper's white again.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the docker shows.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## A tone no ground is born with, so a kept colour is told from a default.
const TONE := Color(0.31, 0.27, 0.22, 1.0)
## The second colour of the tone, apart from the first so the two are told
## from each other.
const SECOND := Color(0.45, 0.40, 0.33, 1.0)
const CLOSE := 0.001

var _docker: LayersDocker = null
var _registries: SaRegistries = null
var _paper: SaLayer = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    canvas.add_child(_docker)
    _docker.target_canvas = canvas
    _docker._ready()
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _paper = SaLayerOps.new(_document()).add(&"paper", _registries.layer_types)
    SaGeneratedLayer.set_color(_document(), _paper, SaGeneratedLayer.PARAM_COLOR, TONE, "Ground Colour")
    SaGeneratedLayer.set_color(_document(), _paper, SaGeneratedLayer.PARAM_SECOND, SECOND, "Ground Colour")
    _document().set_active_layer(_paper)
    _follow()


func after_each() -> void:
    _docker.target_canvas.free()
    _registries = null
    _paper = null


func _document() -> SaDocument:
    return _docker.target_canvas.document


## What the docker does on every sync of the document, which a docker outside
## the tree never hears of on its own.
func _follow() -> void:
    _docker._sync_controls_from_active_layer()


func _rows() -> SaGroundRows:
    return _docker.ground_dialog.rows


func _pick(kind: StringName) -> void:
    _rows().ground_choice.choice_picked.emit(kind)
    _follow()


func _assert_toned(what: String) -> void:
    var params := _paper.generator_params
    for pair: Array in [[SaGeneratedLayer.PARAM_COLOR, TONE], [SaGeneratedLayer.PARAM_SECOND, SECOND]]:
        var held: Color = params.get(pair[0], Color.BLACK)
        var want: Color = pair[1]
        for channel in 3:
            assert_almost_eq(
                held[channel], want[channel], CLOSE, "%s: the %s's channel %d holds the tone" % [what, pair[0], channel]
            )


func test_canvas_picked_in_the_dialog_keeps_the_paper_s_tone() -> void:
    assert_eq(_rows().ground_choice._values.has(&"canvas"), true, "the dialog's Ground choice offers Canvas")
    var steps := _document().history.step_count()
    _pick(&"canvas")
    assert_eq(_paper.layer_type, &"canvas", "the dialog's pick swapped the Paper for a Canvas")
    _assert_toned("the Canvas")
    assert_eq(_document().history.step_count(), steps + 1, "the swap is one history step")
    var space := _document().color_space
    var shown: Color = _rows().swatches[SaGeneratedLayer.PARAM_COLOR].color
    var want := space.to_display(TONE) if space != null else TONE
    for channel in 3:
        assert_almost_eq(shown[channel], want[channel], CLOSE, "the dialog's colour row shows the tone, channel %d" % channel)
    _document().undo()
    _follow()
    assert_eq(_paper.layer_type, &"paper", "one undo gives the Paper back")
    _assert_toned("the Paper undone to")


func test_paper_picked_again_still_holds_the_tone() -> void:
    _pick(&"canvas")
    _pick(&"paper")
    assert_eq(_paper.layer_type, &"paper", "the second pick swapped the Canvas back for a Paper")
    _assert_toned("the Paper picked again")
