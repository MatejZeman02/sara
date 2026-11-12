## d9. The capture door's `look` step hands a companion the picture, not the
## numbers the document stores.
##
## The step's own comment says what the file is for: a model asked to keep
## painting has to be able to look at what it painted. It read that picture with
## `SaExport.get_canvas_image`, which is the stored-numbers read, and a default
## document stores Oklab, so what a companion was handed of a grey canvas was a
## dark red field. d7 found the same trap one call along, on the preview a `.sad`
## carries.
##
## This drives the step itself rather than reading the source, so what it holds
## is the picture the step writes rather than that a correct call exists
## somewhere in the tree.
extends "res://tests/test_framework.gd"

## The canvas is composited and the readback converts through compute kernels.
const REQUIRES_GPU := true

const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(64, 64)
## A point clear of the document's edge, so the texel is the background and not
## a border.
const CENTRE := Vector2i(32, 32)
## Where a bare step path lands, the way a scenario's own output folder does.
static var scratch_out_dir: String = SaDataRoot.path("test_d9_look")
const NAME := "look.png"
## The grey the default document opens on, and the same number d7's suite holds
## the preview to.
const GREY := 0.5
## One step of an eight-bit channel, and the room the narrowing gets on top of
## it. No `long_edge` is asked for here, so the CPU resize is not involved.
const STEP := 1.0 / 255.0
const ALLOWANCE := 2.0 * STEP

var _host: Node = null

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look now.
var _front: Fixtures.FrontDocuments = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "LookStepTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_out_dir.path_join(NAME)))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_out_dir))


## A live canvas in the tree the step looks through, on the document a scenario
## opens with: the default store, so Oklab, composited.
func _grey_canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    canvas.easel = SaEasel.create_default(SIZE, null, SaColorSpace.oklab())
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    canvas.easel.request_full_composite()
    _front = Fixtures.FrontDocuments.over(canvas)
    canvas.easel.process_pending_composite()
    return canvas


func test_the_look_step_writes_the_picture_the_view_draws() -> void:
    var canvas := _grey_canvas()
    var document := ScenarioDocument.new(SaCaptureRun.new(scratch_out_dir))

    document.look({"path": NAME})

    var written := Image.load_from_file(ProjectSettings.globalize_path(scratch_out_dir.path_join(NAME)))
    assert_not_null(written, "the look step wrote its file")
    if written == null:
        canvas.free()
        return
    assert_eq(written.get_size(), SIZE, "at the canvas's own size, no long_edge asked for")
    var texel := written.get_pixel(CENTRE.x, CENTRE.y)
    assert_almost_eq(texel.r, texel.g, ALLOWANCE, "the stored Oklab grey is not written as a red channel")
    assert_almost_eq(texel.g, texel.b, ALLOWANCE, "and the two other channels agree")
    assert_almost_eq(texel.r, GREY, ALLOWANCE, "and it stands where the view draws the grey")

    # The app's own answer for what the view draws, read through the recorder's
    # method rather than through the read the step makes.
    var recorder := SaRecorder.new()
    recorder.bind_canvas(canvas)
    var frame := recorder.display_image(canvas)
    recorder.free()
    assert_not_null(frame, "the recorder read the same canvas")
    if frame != null:
        var drawn := frame.get_pixel(CENTRE.x, CENTRE.y)
        assert_almost_eq(texel.r, drawn.r, ALLOWANCE, "and the file holds what the view draws, in R")
        assert_almost_eq(texel.g, drawn.g, ALLOWANCE, "in G")
        assert_almost_eq(texel.b, drawn.b, ALLOWANCE, "and in B")

    # The read this step no longer makes stays right where it belongs: a PNG
    # named for the document's gamut is what it is for. The two are pinned apart
    # rather than one of them becoming the other.
    var stored := SaExport.get_canvas_image(canvas.easel)
    assert_not_null(stored, "the stored-numbers read still answers for the same canvas")
    if stored != null:
        var raw := stored.get_pixel(CENTRE.x, CENTRE.y)
        assert_true(raw.r - raw.g > 0.3, "and it reads the Oklab grey as a dark red")

    canvas.free()
