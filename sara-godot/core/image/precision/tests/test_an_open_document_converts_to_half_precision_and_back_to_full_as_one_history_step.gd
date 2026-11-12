## An open document converts to half precision and back to
## full as one history step, through Image > Depth.
##
## A painter asked on 2026-10-15 for a painting pass paintings at half
## precision, and ruled that the conversion counts the values above 65504 and
## says so. The cases paint a full precision document in several layers, one a
## group's member, one with a mask and one a simulation steps, convert it, and
## read every colour texel against `SaPrecision.held_by_half`, the reference
## arithmetic, rather than against the kernel under test. The questions are
## read off the dialog the Image menu puts up, the way a painter reads them.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)
const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const OCHRE := Color(0.8, 0.4, 0.2, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)
const GREEN := Color(0.2, 0.7, 0.3, 1.0)

static var scratch_sad: String = SaDataRoot.path("test_half.sad")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _host: Node = null
var _menu: SaImageMenu = null


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(CANVAS)
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    # Detached, as the sibling suite holds its files node: a question is a window,
    # and one in the tree hangs a headless run.
    _host = Node.new()
    var popup := SaChoicePopup.new()
    _host.add_child(popup)
    _menu = SaImageMenu.new(popup)


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    _registries = null
    _host.free()
    _host = null
    _menu = null
    if FileAccess.file_exists(scratch_sad):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_sad))


func _document() -> SaDocument:
    return _surface.get_document()


## A stroke of *colour* across the canvas at height *y* on the active layer,
## through the stamp brush's own input, soft so its edge holds small alphas.
func _stroke(colour: Color, y: float) -> void:
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.color = colour
    brush.settings.radius = 20.0 / float(mini(CANVAS.x, CANVAS.y))
    brush.settings.hardness = GammaFloat.new(0.3, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.spacing = 0.1
    var was := SaColors.foreground
    SaColors.foreground = colour
    var from := Vector2(40.0, y)
    var to := Vector2(470.0, y)
    _surface.view.mouse_position = from
    brush.handle_input(_button(true, from))
    for i in range(1, 31):
        _surface.view.mouse_position = from.lerp(to, float(i) / 30.0)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = _surface.view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    brush.handle_input(_button(false, to))
    SaColors.foreground = was


func _button(pressed: bool, at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    return event


## *values*, four floats a texel, written into *texture* from its first texel,
## the rest of it left as it was.
func _upload(texture: SaTexture, values: PackedFloat32Array) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var written := values.to_byte_array()
    for i in written.size():
        bytes[i] = written[i]
    rd.texture_update(texture.rid, 0, bytes)


## Floats spread over every magnitude a half has and some it has not, both
## signs, the one painted value no brush reaches: subnormals of a half and of a
## float, ties and the edges of the range.
func _spread_values(count: int) -> PackedFloat32Array:
    var random := RandomNumberGenerator.new()
    random.seed = 142
    var values := PackedFloat32Array()
    for i in count:
        var magnitude := pow(2.0, random.randf_range(-30.0, 15.9))
        values.append(magnitude if random.randf() < 0.5 else -magnitude)
    return values


## The painted document: Layer 1 with a stroke and a chunk of spread values, a
## second layer with a stroke inside a group, a third with a stroke and a mask
## of spread values, and a fourth that Spread steps. Answers the layers.
func _paint() -> Dictionary[String, SaLayer]:
    var document := _document()
    var ops := SaLayerOps.new(document)
    var first := document.active_layer
    _stroke(OCHRE, 60.0)
    _upload(first.get_or_create_chunk(Vector2i(1, 0)).albedo(), _spread_values(256 * 64 * 4))
    var member := ops.add(&"")
    document.set_active_layer(member)
    _stroke(BLUE, 120.0)
    var group := SaLayerGroups.new(document).group_layers([member])
    var masked := ops.add(&"")
    document.set_active_layer(masked)
    _stroke(GREEN, 180.0)
    masked.add_mask(1.0)
    var mask := masked.get_field(Vector2i(0, 0), SaFieldSpec.MASK)
    var coverage := PackedFloat32Array()
    for value: float in _spread_values(256 * 16):
        coverage.append(absf(value) / 65536.0)
    _upload(mask, coverage)
    var stepped := ops.add(&"")
    document.set_active_layer(stepped)
    _stroke(OCHRE, 220.0)
    assert_not_null(SaSimulation.put_on(stepped, _registries.simulation_rules.find(&"spread")), "Spread goes on the fourth layer")
    document.update_caches()
    return {"first": first, "member": member, "group": group, "masked": masked, "stepped": stepped}


## Every layer of *document* the way the save walks it, the stroke buffer last.
func _layers(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    _collect(document, document, found)
    found.append(document.stroke_layer)
    return found


func _collect(document: SaDocument, from: Node, into: Array[SaLayer]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer != null and layer != document.stroke_layer:
            into.append(layer)
            _collect(document, layer, into)


## Every texture *document* holds, by where it is held: each chunk's fields,
## each simulation seed, and each cache of the fold, marked colour or not.
func _textures(document: SaDocument) -> Dictionary[String, Dictionary]:
    var found: Dictionary[String, Dictionary] = {}
    for layer: SaLayer in _layers(document):
        for grid_pos: Vector2i in layer.chunks:
            var chunk: SaChunk = layer.chunks[grid_pos]
            for field_id: StringName in chunk.fields:
                var where := "%s %s %s" % [layer.name, grid_pos, field_id]
                found[where] = {"texture": chunk.fields[field_id], "colour": layer.is_color_field(field_id)}
        var record := SaSimulation.record_of(layer)
        if record != null:
            for grid_pos: Vector2i in record.seed_chunks:
                found["%s seed %s" % [layer.name, grid_pos]] = {"texture": record.seed_chunks[grid_pos], "colour": true}
    for cache: SaLayer in document.fold.caches():
        for grid_pos: Vector2i in cache.chunks:
            var chunk: SaChunk = cache.chunks[grid_pos]
            for field_id: StringName in chunk.fields:
                var where := "cache %s %s %s" % [cache.name, grid_pos, field_id]
                found[where] = {"texture": chunk.fields[field_id], "colour": true, "cache": true}
    return found


## The bytes and the format of every texture [method _textures] finds but the
## caches, which are derived and rebuilt rather than held.
func _held(document: SaDocument) -> Dictionary[String, Dictionary]:
    var held: Dictionary[String, Dictionary] = {}
    var rd := GlobalShaderCompiler.get_rd()
    var textures := _textures(document)
    for where: String in textures:
        var entry: Dictionary = textures[where]
        if entry.get("cache", false):
            continue
        var texture: SaTexture = entry["texture"]
        var bytes := rd.texture_get_data(texture.rid, 0)
        held[where] = {"format": texture.format, "colour": entry["colour"], "bytes": bytes, "size": texture.bytes}
    return held


static func _same(a: float, b: float) -> bool:
    return (is_nan(a) and is_nan(b)) or a == b


## How *after*, half floats, holds *before*, floats: the channels that are not
## the reference's nearest half, the ones whose nearest half truncation would
## have missed, and the ones read.
static func _against_reference(before: PackedByteArray, after: PackedByteArray) -> Dictionary[String, int]:
    var floats := before.to_float32_array()
    var tally: Dictionary[String, int] = {"off": 0, "truncation_differs": 0, "read": floats.size(), "finite_became_infinite": 0}
    for i in floats.size():
        var value := floats[i]
        var half := after.decode_half(i * 2)
        if value == 0.0 and half == 0.0:
            continue
        if not _same(half, SaPrecision.held_by_half(value)):
            tally["off"] += 1
        elif not _same(half, SaPrecision.truncated_to_half(value)):
            tally["truncation_differs"] += 1
        if not is_nan(value) and not is_inf(value) and is_inf(half):
            tally["finite_became_infinite"] += 1
    return tally


## The question up under the host, or null.
func _question() -> SaMessage:
    for child: Node in _host.get_children():
        if child is SaMessage and not child.is_queued_for_deletion():
            return child as SaMessage
    return null


func _labels(question: SaMessage) -> Array:
    var labels: Array = []
    for button: Button in question.buttons:
        labels.append(button.text)
    return labels


## Asks Image > Depth for *depth* and presses *button* of its question,
## answering the question's text.
func _convert_through_the_menu(depth: SaColorSpace.Depth, button: int) -> String:
    var question := _menu.ask_depth(depth, _document())
    assert_not_null(question, "%s asks a question" % SaColorSpace.depth_name(depth))
    if question == null:
        return ""
    var text := question.text_label.text
    assert_eq(_labels(question), ["Cancel", "Convert"], "with Cancel first and Convert after it")
    question.buttons[button].pressed.emit()
    return text


func test_a_painted_document_converts_to_half_within_half_s_last_place_and_the_mask_keeps_its_bits() -> void:
    var layers := _paint()
    var document := _document()
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F32, "The document starts at full precision")
    var before := _held(document)
    var text := _convert_through_the_menu(SaColorSpace.Depth.F16, 1)
    assert_eq(text, tr(SaImageMenu.HALF_QUESTION), "Nothing past 65504 is painted, so the question is the plain one")
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F16, "Convert leaves the document at half precision")
    assert_true(document.modified, "and marks it modified")
    var after := _held(document)
    assert_eq(after.keys(), before.keys(), "Every texture is still held where it was")
    var tally: Dictionary[String, int] = {"off": 0, "truncation_differs": 0, "read": 0, "finite_became_infinite": 0}
    var colour := 0
    for where: String in before:
        var old: Dictionary = before[where]
        var now: Dictionary = after[where]
        if not old["colour"]:
            assert_eq(now["format"], old["format"], "%s is no colour and keeps its format" % where)
            assert_true(now["bytes"] == old["bytes"], "and its texels bit for bit")
            continue
        colour += 1
        assert_eq(now["format"], F16, "%s is at the half format" % where)
        var compared := _against_reference(old["bytes"], now["bytes"])
        for key: String in tally:
            tally[key] += compared[key]
    assert_true(colour >= 6, "The layers, the group's member and the seed hold colour, %d textures" % colour)
    assert_true(before.has("%s (0, 0) mask" % layers["masked"].name), "and the mask is among what was read")
    assert_eq(tally["off"], 0, "Every colour channel is the nearest half of what was painted, %d read" % tally["read"])
    print(
        (
            (
                "the stored halves are the nearest, ties to even, rounded in the kernel by nearest_half.gmacs. "
                + "On %d channels a truncating store would have differed, and every one of them reads the nearest."
            )
            % tally["truncation_differs"]
        )
    )
    assert_true(tally["truncation_differs"] > 0, "and the spread values hold channels a truncation would have missed")
    assert_eq(tally["finite_became_infinite"], 0, "and no finite value became infinite")
    var textures := _textures(document)
    for where: String in textures:
        var entry: Dictionary = textures[where]
        if entry["colour"]:
            assert_eq((entry["texture"] as SaTexture).format, F16, "%s is at the half format" % where)
    assert_eq(document.stroke_layer.schema[0].format, F16, "The stroke buffer allocates at half")
    for cache: SaLayer in document.fold.caches():
        assert_eq(cache.schema[0].format, F16, "%s allocates at half" % cache.name)
    for layer: SaLayer in _layers(document):
        for spec: SaFieldSpec in layer.schema:
            if spec.is_color:
                assert_eq(spec.format, F16, "%s's %s is declared at half" % [layer.name, spec.id])
    var masked: SaLayer = layers["masked"]
    for spec: SaFieldSpec in masked.schema:
        if spec.id == SaFieldSpec.MASK:
            assert_eq(spec.format, SaSelection.FORMAT, "The mask's field keeps its format")


func test_undo_puts_back_every_painted_bit_and_redo_the_halves_and_the_history_holds_both() -> void:
    _paint()
    var document := _document()
    var before := _held(document)
    var tally_before := document.history.total_bytes()
    var steps_before := document.history.step_count()
    _convert_through_the_menu(SaColorSpace.Depth.F16, 1)
    var after := _held(document)
    assert_eq(document.history.step_count(), steps_before + 1, "The conversion is one history step")
    var expected := 0
    for where: String in before:
        expected += int(before[where]["size"]) + int(after[where]["size"])
    assert_eq(document.history._step_bytes.back(), expected, "and the step is charged both sets of chunks, %d bytes" % expected)
    assert_eq(document.history.total_bytes(), tally_before + expected, "which is what the history's tally grew by")

    assert_true(document.undo(), "Undo is taken")
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F32, "Undo puts the descriptor back at full precision")
    var undone := _held(document)
    for where: String in before:
        assert_eq(undone[where]["format"], before[where]["format"], "%s is at its old format" % where)
        assert_true(undone[where]["bytes"] == before[where]["bytes"], "%s holds what was painted, bit for bit" % where)
    assert_eq(document.stroke_layer.schema[0].format, F32, "and the stroke buffer allocates at full again")

    assert_true(document.redo(), "Redo is taken")
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F16, "Redo puts the half descriptor back")
    var redone := _held(document)
    for where: String in after:
        assert_true(redone[where]["bytes"] == after[where]["bytes"], "%s holds the halves again" % where)


func test_values_past_65504_are_counted_held_at_it_and_cancel_changes_nothing() -> void:
    var document := _document()
    var texture := document.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo()
    var values := PackedFloat32Array([100000.0, 0.5, 0.5, 1.0, -100000.0, 0.5, 0.5, 1.0, INF, 0.5, 0.5, 1.0, 0.5, NAN, 0.5, 1.0])
    values.append_array(PackedFloat32Array([-INF, 0.25, 70000.0 / 65536.0, 1.0, 1.0e-9, 3.0e-8, 6.0e-5, 1.0]))
    _upload(texture, values)
    var before := _held(document)

    var question := _menu.ask_depth(SaColorSpace.Depth.F16, document)
    var text := question.text_label.text
    assert_true(text.begins_with(tr(SaImageMenu.HALF_QUESTION)), "The question says what half does")
    assert_true(text.contains(tr(SaImageMenu.HALF_RANGE) % 2), "and that two texels hold a value past 65504, read: %s" % text)
    assert_true(text.contains("65504, with their sign, and not turned to infinity"), "and what becomes of them")
    assert_true(text.contains("becomes zero"), "and that a value too small for a half becomes zero")
    assert_eq(_labels(question)[0], "Cancel", "Cancel is the first button")
    question.buttons[0].pressed.emit()
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F32, "Cancel leaves the document at full precision")
    var cancelled := _held(document)
    for where: String in before:
        assert_true(cancelled[where]["bytes"] == before[where]["bytes"], "and %s as it was" % where)

    _convert_through_the_menu(SaColorSpace.Depth.F16, 1)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(document.active_layer.get_field(Vector2i(0, 0)).rid, 0)
    assert_eq(bytes.decode_half(0), 65504.0, "100000 is held at 65504")
    assert_eq(bytes.decode_half(8 * 1), -65504.0, "and -100000 at -65504")
    assert_true(is_inf(bytes.decode_half(8 * 2)) and bytes.decode_half(8 * 2) > 0.0, "the infinity stays infinite")
    assert_true(is_nan(bytes.decode_half(8 * 3 + 2)), "and the NaN stays NaN")
    assert_true(is_inf(bytes.decode_half(8 * 4)) and bytes.decode_half(8 * 4) < 0.0, "and so does minus infinity")
    assert_eq(bytes.decode_half(8 * 5), 0.0, "1e-9, too small for a half, becomes zero")
    var painted := "%s %s %s" % [document.active_layer.name, Vector2i(0, 0), SaFieldSpec.ALBEDO]
    var compared := _against_reference(before[painted]["bytes"], bytes)
    assert_eq(compared["off"], 0, "Every channel is the reference's half")
    assert_eq(compared["finite_became_infinite"], 0, "and no finite texel became infinite")


func test_half_converts_back_to_full_exactly_and_a_saved_half_file_reopens_as_it() -> void:
    _paint()
    var document := _document()
    _convert_through_the_menu(SaColorSpace.Depth.F16, 1)
    var halves := _held(document)
    assert_eq(SaPrecision.new(document).count_beyond_half(), 0, "A half document has nothing past the range to count")

    assert_eq(SaSadFile.save_file(document, scratch_sad, 0), OK, "The half document saves")
    var header := _header(scratch_sad)
    assert_eq(str(SaTyped.strings(header.get("color_space", {})).get("depth", "")), "F16", "and the file's header says F16")
    var easel := SaEasel.create_default(CANVAS)
    assert_eq(SaSadFile.load_file(easel.document, scratch_sad, easel.compositor), OK, "It opens again")
    assert_eq(easel.document.color_space.depth, SaColorSpace.Depth.F16, "at half precision")
    var reopened := _held(easel.document)
    for where: String in halves:
        if where.contains("seed") or where.begins_with("StrokeBuffer"):
            continue
        assert_true(reopened.has(where), "%s is in the reopened file" % where)
        if reopened.has(where):
            var same: bool = reopened[where]["bytes"] == halves[where]["bytes"]
            assert_true(same, "%s reopens as the converted document held it" % where)
    easel.free()

    var text := _convert_through_the_menu(SaColorSpace.Depth.F32, 1)
    assert_eq(text, tr(SaImageMenu.FULL_QUESTION), "Going to full asks the question that loses nothing")
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F32, "and leaves the document at full precision")
    var full := _held(document)
    for where: String in halves:
        if not halves[where]["colour"]:
            continue
        assert_eq(full[where]["format"], F32, "%s is at full precision" % where)
        var half_bytes: PackedByteArray = halves[where]["bytes"]
        var floats: PackedFloat32Array = (full[where]["bytes"] as PackedByteArray).to_float32_array()
        var off := 0
        for i in floats.size():
            if not _same(floats[i], half_bytes.decode_half(i * 2)):
                off += 1
        assert_eq(off, 0, "%s holds every half value exactly" % where)


func test_a_step_past_the_history_s_budget_says_older_steps_go_and_is_kept() -> void:
    _stroke(OCHRE, 60.0)
    var document := _document()
    var before := _held(document)
    document.history.pin_budget = true
    document.history.budget_bytes = 1
    var text := _convert_through_the_menu(SaColorSpace.Depth.F16, 1)
    assert_true(text.ends_with(tr(SaImageMenu.HISTORY_FULL)), "The question says the oldest steps are dropped, read: %s" % text)
    assert_eq(document.color_space.depth, SaColorSpace.Depth.F16, "Convert converts")
    assert_true(document.undo(), "and the step it promised can still be undone")
    var undone := _held(document)
    for where: String in before:
        assert_true(undone[where]["bytes"] == before[where]["bytes"], "%s comes back bit for bit" % where)


func test_the_menu_marks_the_documents_own_depth_and_asks_nothing_for_it() -> void:
    assert_null(_menu.ask_depth(SaColorSpace.Depth.F32, _document()), "A full document's own depth asks nothing")
    assert_eq(
        SaPrecision.new(_document()).blocked_reason(SaColorSpace.Depth.F32).is_empty(), false, "and the conversion refuses it"
    )
    assert_false(SaPrecision.new(_document()).convert_to(SaColorSpace.Depth.F32), "so nothing is converted")


static func _header(path: String) -> Dictionary[String, Variant]:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    file.close()
    return SaTyped.strings(JSON.parse_string(text))
