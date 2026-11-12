## A Spatter stroke 12 pixels above the document's bottom edge paints.
##
## The risk is the last row of chunks. A document whose height is not a
## whole number of chunks ends in a row the document only partly covers, and a
## dab clipped to the document there, or a dispatch that skips a chunk it thinks
## lies outside, would drop exactly the dabs near the bottom and nowhere else.
## Spatter would show it first because its dots are thrown off the stroke's line
## and are a few pixels wide, so a clipped one is a missing one.
##
## This paints through the real brush, the real preset and the real GPU, on a
## document that ends in a partial row and on one that ends on a chunk's edge,
## and reads the paint back off the layer's chunks. Spatter first, then two
## other shipped presets, so a fault the row finds is a fault for every brush.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The proof is paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## The default document, whose last chunk row it covers for 56 pixels of 256,
## and one that ends exactly on a chunk's edge.
const PARTIAL := Vector2i(1920, 1080)
const WHOLE := Vector2i(1024, 1024)

## How far above the bottom edge the stroke runs, the painter's 12 and the
## closest a dab can be and still sit inside the document.
const HEIGHTS_ABOVE: Array[int] = [12, 2]

## The stroke, left to right, in document pixels, one motion every STEP.
const FROM_X: float = 100.0
const TO_X: float = 900.0
const STEP: float = 8.0

## A fixed seed, so the scatter a failure names is the one a reader reruns.
const SEED: int = 16

## What counts as paint, as in `test_dab_dirty_rect.gd`.
const PAINTED: float = 1.0 / 512.0

## Spatter, the one the painter used, and two whose dabs are not thrown.
const PRESETS: Array[String] = ["Spatter", "Pencil", "Airbrush"]


## A brush on a fresh document of *size* holding the shipped *preset_name*.
func _setup(size: Vector2i, preset_name: String) -> Dictionary:
    var surface := Fixtures.make_surface(size)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var found := false
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == preset_name:
            brush.settings = SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry)
            found = true
    assert_true(found, "%s is a shipped preset" % preset_name)
    brush.stroke_seed = SEED
    return {"surface": surface, "machine": machine, "brush": brush}


## One stroke along *y*, a press, a motion every STEP pixels at full pressure,
## and the release that commits it.
func _stroke(surface: SaSurface, brush: Object, y: float) -> void:
    var was := SaColors.foreground
    SaColors.foreground = Color(1.0, 1.0, 1.0, 1.0)
    surface.view.mouse_position = Vector2(FROM_X, y)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = surface.view.mouse_position
    brush.handle_input(press)
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        surface.view.mouse_position = Vector2(x, y)
        var motion := InputEventMouseMotion.new()
        motion.position = surface.view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    SaColors.foreground = was


## Every painted texel of the active layer as a document row, counted. Read off
## each chunk the layer holds, at the chunk's own pixel size.
func _painted_rows(doc: SaDocument) -> Dictionary:
    var rows := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in doc.active_layer.chunks:
        var chunk: SaChunk = doc.active_layer.chunks[grid]
        var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
        if texture == null:
            continue
        var side := chunk.pixel_size()
        var data: PackedByteArray = rd.texture_get_data(texture.rid, 0)
        for ty in side:
            var y := grid.y * side + ty
            for tx in side:
                if data.decode_float(((ty * side + tx) * 4 + 3) * 4) > PAINTED:
                    rows[y] = int(rows.get(y, 0)) + 1
    return rows


## The row's promise: the stroke leaves paint in the last chunk row on both
## documents, and around the line it was drawn along.
func test_a_stroke_along_the_bottom_edge_paints_in_the_last_chunk_row() -> void:
    for size: Vector2i in [PARTIAL, WHOLE]:
        for above: int in HEIGHTS_ABOVE:
            for preset_name in PRESETS:
                var made := _setup(size, preset_name)
                var surface: SaSurface = made["surface"]
                var doc := surface.easel.document
                var y := float(size.y - above)
                _stroke(surface, made["brush"], y)
                var rows := _painted_rows(doc)
                var side := SaChunk.new().pixel_size()
                var last_row := floori(float(size.y - 1) / float(side))
                var in_last := 0
                var near_line := 0
                var past_edge := 0
                for row: int in rows:
                    if floori(float(row) / float(side)) == last_row:
                        in_last += int(rows[row])
                    if absi(row - int(y)) <= 8:
                        near_line += int(rows[row])
                    if row >= size.y:
                        past_edge += int(rows[row])
                var said := "%s on %dx%d, %d px above the bottom edge" % [preset_name, size.x, size.y, above]
                assert_true(in_last > 0, "%s paints in the last chunk row, %d texels" % [said, in_last])
                assert_true(near_line > 0, "%s paints around the line it was drawn along, %d texels" % [said, near_line])
                # A partial row's chunk is a whole texture, so nothing stops a
                # dab reaching past the document. What lies there is outside the
                # picture and never composited, so it is reported, not failed.
                if past_edge > 0:
                    print("  note: %s left %d texels past the edge, outside the picture" % [said, past_edge])
                Fixtures.teardown(surface, made["machine"])
