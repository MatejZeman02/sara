## An open shows what the view needs first and takes no
## stroke until it is done.
##
## A painter's answer to the spec's question: "the canvas shows what has arrived
## and takes strokes only once the open is done, with progress in the corner
## message. A stroke over a chunk not yet uploaded would paint over paint that
## is about to replace it." [SaSadOpening] lands a long file's stack with its
## chunks still to come, reads those the view shows first across the layers in
## the order they composite, and every layer refuses a tool until the last
## chunk is in.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and an open writes them.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Three chunks by two.
const SIZE := Vector2i(768, 512)
## The part of the document the view shows in the suite, inside chunk (0, 0).
const VIEW := Rect2i(16, 16, 160, 160)
const IN_VIEW := Vector2i(0, 0)
const PAINTED := 6
## Where the refused stroke and the later one are made, inside the view.
const STROKE_AT := Vector2(96, 96)

var _surfaces: Array[SaSurface] = []
var _machines: Array[ToolMachine] = []
var _paths: Array[String] = []
var _heard: Array[String] = []


func before_each() -> void:
    _heard.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    for index in _surfaces.size():
        Fixtures.teardown(_surfaces[index], _machines[index])
    _surfaces.clear()
    _machines.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _hear(line: String) -> void:
    _heard.append(line)


func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    _surfaces.append(surface)
    _machines.append(Fixtures.make_bound_machine(surface))
    return surface


## A file of [constant PAINTED] layers over the background, each filling every
## chunk with a colour of its own at half cover, so the composite reads every
## layer.
func _saved() -> String:
    var document := _surface().get_document()
    for i in PAINTED:
        var layer := SaLayerOps.new(document).add(&"")
        layer.name = "Painted %d" % i
        for grid_pos in SaLayer.grid_positions(SIZE):
            var texture := layer.get_or_create_chunk(grid_pos).albedo()
            var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
            var form := Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF
            var image := Image.create_empty(texture.size.x, texture.size.y, false, form)
            image.fill(_colour(i, grid_pos))
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_%d.sad" % _paths.size()))
    _paths.append(path)
    assert_eq(SaExport.save_sad(document, path), OK, "The file is written")
    return path


static func _colour(i: int, grid_pos: Vector2i) -> Color:
    return Color(0.1 + 0.12 * i, 0.2 + 0.2 * grid_pos.x, 0.3 + 0.3 * grid_pos.y, 0.5)


static func _opening(document: SaDocument, path: String) -> SaSadOpening:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    return SaSadOpening.new(document, file, path)


static func _painted(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for i in PAINTED:
        found.append(document.get_node(NodePath("Painted %d" % i)) as SaLayer)
    return found


static func _picture(surface: SaSurface) -> Image:
    return SaExport.get_texture_image_float(surface.easel.output)


func _stroke(surface: SaSurface) -> void:
    var machine: ToolMachine = _machines[_surfaces.find(surface)]
    surface.view.mouse_position = STROKE_AT
    machine.active_tool.handle_input(_button(true))
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    for step in 8:
        surface.view.mouse_position = STROKE_AT + Vector2(4.0 * step, 0.0)
        motion.position = surface.view.mouse_position
        machine.active_tool.handle_input(motion)
    machine.active_tool.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## The opening landed with every chunk to come and stepped once with time to
## spare, which stops where the view's chunks end.
func _landed_and_viewed(surface: SaSurface, path: String) -> SaSadOpening:
    var document := surface.get_document()
    var opening := _opening(document, path)
    opening.defer_chunks()
    var reads := 0
    while not opening.step(0) and reads < 1000:
        reads += 1
    assert_true(reads < 1000, "The stack is read within a thousand steps")
    assert_eq(opening.land(), OK, "The stack lands")
    assert_eq(SaSadOpening.still_filling(document), opening, "and the open is filling the document")
    Bench.composite(surface.easel)
    opening.begin_filling(VIEW)
    assert_false(opening.fill(60_000_000), "A step with a minute to spare stops where the view's chunks end")
    return opening


func test_after_the_first_step_the_view_s_chunks_are_in_and_the_rest_are_not() -> void:
    var path := _saved()
    var surface := _surface()
    var document := surface.get_document()
    var opening := _landed_and_viewed(surface, path)
    var layers := _painted(document)
    assert_eq(layers.size(), PAINTED, "Every painted layer is in the document")
    for i in PAINTED:
        var layer := layers[i]
        if layer == null:
            continue
        assert_true(layer.chunks.has(IN_VIEW), "%s holds the view's chunk" % layer.name)
        if layer.chunks.has(IN_VIEW):
            var texel := Bench.texel(layer.get_field(IN_VIEW), VIEW.position)
            assert_true(texel.is_equal_approx(_colour(i, IN_VIEW)), "with its saved paint: %s" % texel)
        for grid_pos in SaLayer.grid_positions(SIZE):
            if grid_pos != IN_VIEW:
                assert_false(layer.chunks.has(grid_pos), "and not yet its chunk at %s" % grid_pos)
    assert_true(opening.percent_in() > 0 and opening.percent_in() < 100, "The open is part way: %d%%" % opening.percent_in())

    # Drawn as a frame draws, from what the arrival marked.
    surface.easel.process_pending_composite()
    var early := _picture(surface).get_region(VIEW)
    opening.finish_filling()
    assert_null(SaSadOpening.still_filling(document), "Once the last chunk is in the open is done")
    Bench.composite(surface.easel)
    var done := _picture(surface).get_region(VIEW)
    var worst := 0.0
    for y in VIEW.size.y:
        for x in VIEW.size.x:
            var a := early.get_pixel(x, y)
            var b := done.get_pixel(x, y)
            worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    var said := "and the view's region drawn after the first step is the one drawn at the end, %s against %s, worst %f"
    assert_true(early.get_data() == done.get_data(), said % [early.get_pixel(5, 5), done.get_pixel(5, 5), worst])


func test_a_stroke_before_the_open_is_done_paints_nothing_and_says_so() -> void:
    var path := _saved()
    var surface := _surface()
    var document := surface.get_document()
    var opening := _landed_and_viewed(surface, path)
    var top := _painted(document)[PAINTED - 1]
    document.set_active_layer(top)
    var before := GlobalShaderCompiler.get_rd().texture_get_data(top.get_field(IN_VIEW).rid, 0)
    var steps := document.history.step_count()
    _stroke(surface)
    var after := GlobalShaderCompiler.get_rd().texture_get_data(top.get_field(IN_VIEW).rid, 0)
    assert_true(after == before, "A stroke while the open fills changes no pixel")
    assert_eq(document.history.step_count(), steps, "and adds no history step")
    assert_eq(_heard.size(), 1, "The corner says one line: %s" % [_heard])
    if not _heard.is_empty():
        assert_eq(_heard[0], SaSadOpening.refusal(document, tr("stroke")), "the open's own")
        assert_true(_heard[0].contains("still opening"), "saying the open is not done")
        assert_true(_heard[0].contains("%d%%" % opening.percent_in()), "with its progress")

    opening.finish_filling()
    _heard.clear()
    _stroke(surface)
    var painted := GlobalShaderCompiler.get_rd().texture_get_data(top.get_field(IN_VIEW).rid, 0)
    assert_false(painted == before, "The same stroke once the open is done paints")
    assert_eq(document.history.step_count(), steps + 1, "as one history step")
    assert_true(_heard.is_empty(), "and nothing is refused: %s" % [_heard])


## A press reaches a tool through its machine, and a tool's own guard may ask
## less than `refuses_paint`: the brush on a mask asks the mask's owner's lock
## alone. The machine stops the press first, whatever the tool asks.
func test_the_machine_refuses_a_press_on_a_mask_while_the_open_fills() -> void:
    var path := _saved()
    var surface := _surface()
    var document := surface.get_document()
    var opening := _landed_and_viewed(surface, path)
    var top := _painted(document)[PAINTED - 1]
    document.set_active_layer(top)
    document.mask_target = top.add_mask(1.0)
    var machine: ToolMachine = _machines[_surfaces.find(surface)]
    surface.view.mouse_position = STROKE_AT
    machine.handle_input(_button(true))
    assert_false(machine.active_tool.is_drawing, "The brush never began a stroke")
    machine.handle_input(_button(false))
    assert_eq(_heard.size(), 1, "The corner says one line: %s" % [_heard])
    if not _heard.is_empty():
        assert_true(_heard[0].contains("%d%%" % opening.percent_in()), "the open's, with its progress")
    document.mask_target = null
    opening.finish_filling()


func test_the_finished_document_reads_as_the_file_read_whole() -> void:
    var path := _saved()
    var whole := _surface().get_document()
    assert_eq(SaExport.load_sad(whole, path), OK, "The file read whole")
    var filled_surface := _surface()
    var filled := filled_surface.get_document()
    _landed_and_viewed(filled_surface, path).finish_filling()
    _assert_same_layers(whole, filled)


func test_an_open_over_frames_lands_first_fills_then_answers_once() -> void:
    var path := _saved()
    var surface := _surface()
    var document := surface.get_document()
    var answers: Array[Error] = []
    var landed: Array[int] = []
    var land := func() -> Rect2i:
        landed.append(document.get_child_count())
        return VIEW
    _opening(document, path).over_frames(answers.append, land, 0)
    var frames_filling := 0
    for _i in 400:
        if not answers.is_empty():
            break
        if SaSadOpening.still_filling(document) != null:
            frames_filling += 1
        await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(answers, [OK] as Array[Error], "The answer comes once, and it is OK")
    assert_eq(landed.size(), 1, "The window was asked once to show the landed stack")
    assert_true(frames_filling > 1, "and the document filled over %d frames after it" % frames_filling)
    assert_null(SaSadOpening.still_filling(document), "The open is done")
    var whole := _surface().get_document()
    assert_eq(SaExport.load_sad(whole, path), OK, "The file read whole")
    _assert_same_layers(whole, document)


func test_a_save_while_the_open_fills_writes_the_whole_file() -> void:
    var path := _saved()
    var surface := _surface()
    var document := surface.get_document()
    _landed_and_viewed(surface, path)
    var copy := ProjectSettings.globalize_path(SaDataRoot.path("test_copy.sad"))
    _paths.append(copy)
    assert_eq(SaExport.save_sad(document, copy), OK, "A save while the open fills")
    assert_null(SaSadOpening.still_filling(document), "fills the rest first")
    var read := _surface().get_document()
    assert_eq(SaExport.load_sad(read, copy), OK, "and its file opens")
    var whole := _surface().get_document()
    assert_eq(SaExport.load_sad(whole, path), OK, "as the original does")
    _assert_same_layers(whole, read)


func _assert_same_layers(expected: SaDocument, actual: SaDocument) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    for i in PAINTED:
        var want := _painted(expected)[i]
        var have := _painted(actual)[i]
        assert_not_null(have, "Painted %d is there" % i)
        if want == null or have == null:
            continue
        var have_keys := have.chunks.keys()
        var want_keys := want.chunks.keys()
        have_keys.sort()
        want_keys.sort()
        assert_eq(have_keys, want_keys, "%s holds the same chunks" % want.name)
        for grid_pos: Vector2i in want.chunks:
            if not have.chunks.has(grid_pos):
                continue
            var a := rd.texture_get_data(want.get_field(grid_pos).rid, 0)
            var b := rd.texture_get_data(have.get_field(grid_pos).rid, 0)
            assert_true(a == b, "%s at %s reads the same texels" % [want.name, grid_pos])
