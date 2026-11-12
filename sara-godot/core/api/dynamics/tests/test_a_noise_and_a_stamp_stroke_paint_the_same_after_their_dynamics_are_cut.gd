## A Wet Into Wet stroke and an Oil Smudge stroke over the same path paint the
## same layer they painted before the dynamics of a point were made cheaper,
## every texel within [constant TOLERANCE].
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Before.** The two layers as the dynamics painted them before the cut are
## kept under `fixtures/`, one float image a chunk, written by this suite with
## `SARA_WRITE_DYNAMICS_FIXTURES=1` on the reference GPU. A fixture is the
## paint of one machine's card, and the cut is CPU work, so the suite compares
## on that card only and skips elsewhere.
##
## **The strokes.** The S of the timing suite beside this one, with the
## pressure up and back down and the pen leaning, at a pen's report every 4 ms
## and four reports a frame. Wet Into Wet goes through `gather_sample` and
## `lay_frame` as the module's frame does, and Oil Smudge through the tool
## machine's events, with the pen's clock pinned to frames so its time sensor
## reads the same at every run.
##
## **The brush's own work.** [method test_the_brush_s_own_work_a_noise_stroke]
## times Wet Into Wet the way it was timed before, on a 2560 by 1600
## document, 40 motions four to a frame, the CPU time inside `gather_sample`
## and `lay_frame`, and prints it. It asserts nothing of the figure.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Timing = preload("res://core/api/dynamics/tests/test_a_point_s_dynamics_cost_half_the_cpu_time_they_did.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

const FIXTURES: String = "res://core/api/dynamics/tests/fixtures/"
## The card the fixtures were painted on.
const PAINTED_ON: String = "NVIDIA GeForce RTX 3090"
## How far a channel of a texel may move from the fixture.
const TOLERANCE: float = 0.0001
const CANVAS := Vector2i(768, 384)
const MOTIONS: int = 40
const A_FRAME: int = 4
const REPORT_MS: float = 4.0
const INK := Color(0.12, 0.25, 0.6, 1.0)
## The document `halv` timed the brush on, and the strokes timed.
const LARGE := Vector2i(2560, 1600)
const TIMED_STROKES: int = 3

static var scratch_dir: String = SaDataRoot.path("test_presets")

var _surfaces: Array[SaSurface] = []
var _machine: ToolMachine = null
## The stamp's layer before its stroke.
var _stamp_ground: Dictionary = {}


func before_each() -> void:
    SaPenClock.pin_to_frames()


func after_each() -> void:
    SaPenClock.unpin()
    if _machine != null:
        Fixtures.teardown(_surfaces.pop_back(), _machine)
        _machine = null
    for surface: SaSurface in _surfaces:
        Fixtures.teardown(surface)
    _surfaces.clear()
    # A script that failed to compile leaves the path empty, and an empty path
    # is the working folder, whose files this loop would then delete.
    if scratch_dir.ends_with("test_presets") and DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


## Where the S is at *t* on a canvas of *side*.
static func point_at(t: float, side: Vector2i) -> Vector2:
    var inset := float(side.y) * 0.25
    var x := inset + t * (float(side.x) - 2.0 * inset)
    var y := float(side.y) * 0.5 - sin(t * TAU) * (float(side.y) * 0.5 - inset)
    return Vector2(x, y)


## A Wet Into Wet brush on a fresh surface of *side*.
func _noise_brush(side: Vector2i) -> StateNoiseBrushScript:
    var settings: Resource = null
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Wet Into Wet":
            settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    assert_not_null(settings, "Wet Into Wet ships")
    var surface := Fixtures.make_surface(side)
    _surfaces.append(surface)
    var brush := StateNoiseBrushScript.new()
    brush.surface = surface
    brush.stroke_seed = 1
    settings.color = INK
    brush.settings = settings
    return brush


## Paints the S with *brush*, four motions a frame, and answers the CPU time
## in microseconds spent inside the brush's calls.
func _noise_stroke(brush: StateNoiseBrushScript, side: Vector2i) -> int:
    var started := Time.get_ticks_usec()
    brush.begin_stroke(point_at(0.0, side), 0.0, Vector2.ZERO, 0.0, true)
    var spent := Time.get_ticks_usec() - started
    for i in range(1, MOTIONS + 1):
        var t := float(i) / float(MOTIONS)
        started = Time.get_ticks_usec()
        brush.gather_sample(point_at(t, side), Timing.pressure_at(t), Timing.tilt_at(t), i * REPORT_MS)
        if i % A_FRAME == 0:
            brush.lay_frame()
        spent += Time.get_ticks_usec() - started
    started = Time.get_ticks_usec()
    brush.lay_frame()
    brush.end_stroke()
    return spent + Time.get_ticks_usec() - started


## Every painted chunk of *layer* as a float image, by grid position.
static func _layer(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid: Vector2i in layer.chunks:
        out[grid] = SaExport.get_texture_image_float((layer.chunks[grid] as SaChunk).albedo())
    return out


## Oil Smudge's S, through the tool machine's events, on a fresh surface whose
## layer holds [method _bands], so the smudge has paint to drag.
func _stamp_layer() -> Dictionary:
    var surface := Fixtures.make_surface(CANVAS)
    _surfaces.append(surface)
    _machine = Fixtures.make_bound_machine(surface)
    _machine.set_active_tool(&"brush")
    var brush: Object = _machine.active_tool
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(brush.settings, ShippedPresetsScript)
    assert_true(store.apply_preset("Oil Smudge", brush.settings), "Oil Smudge loads")
    brush.settings.color = INK
    brush.stroke_seed = 1
    var document := surface.get_document()
    SaPictureFile.fill_layer(document, document.active_layer, _bands(), Vector2i.ZERO, SaColorSpace.srgb())
    _stamp_ground = _layer(document.active_layer)
    surface.view.mouse_position = point_at(0.0, CANVAS)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    for i in range(1, MOTIONS + 1):
        var t := float(i) / float(MOTIONS)
        var motion := InputEventMouseMotion.new()
        motion.pressure = Timing.pressure_at(t)
        motion.tilt = Timing.tilt_at(t) / 60.0
        surface.view.mouse_position = point_at(t, CANVAS)
        brush.handle_input(motion)
        if i % A_FRAME == 0:
            _frame(brush)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)
    return _layer(surface.get_document().active_layer)


## Bands of two colours across the canvas, for the smudge to drag.
static func _bands() -> Image:
    var image := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBAF)
    for y in CANVAS.y:
        var band := Color(0.9, 0.7, 0.1, 1.0) if posmod(y, 48) < 24 else Color(0.7, 0.1, 0.2, 1.0)
        for x in CANVAS.x:
            image.set_pixel(x, y, band)
    return image


## Runs the sends the stamp asked the frame for, as `test_a_frames_reports_go_to_the_card_as_one_list.gd` does.
static func _frame(brush: Object) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var asked: Array[Callable] = []
    for connection: Dictionary in tree.process_frame.get_connections():
        var callable: Callable = connection["callable"]
        if callable.get_object() == brush._walk_batch:
            asked.append(callable)
    for callable in asked:
        tree.process_frame.disconnect(callable)
        callable.call()


func _noise_layer() -> Dictionary:
    var brush := _noise_brush(CANVAS)
    _noise_stroke(brush, CANVAS)
    return _layer(brush.surface.easel.document.active_layer)


## Writes *painted* as the fixture *name*, or compares it with the one kept. A
## texel counts as painted where either differs from *ground*, the layer before
## the stroke, empty where it holds no chunk.
func _against(name: String, painted: Dictionary, ground: Dictionary = {}) -> void:
    assert_false(painted.is_empty(), "%s painted" % name)
    var path := FIXTURES + name + ".bin"
    if OS.get_environment("SARA_WRITE_DYNAMICS_FIXTURES") == "1":
        var stored := {}
        for grid: Vector2i in painted:
            var image: Image = painted[grid]
            stored[grid] = [image.get_width(), image.get_height(), image.get_format(), image.get_data()]
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURES))
        var written := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
        written.store_var(stored)
        written.close()
        print("Dynamics fixture: wrote %s, %d chunks" % [path, stored.size()])
        return
    if RenderingServer.get_video_adapter_name() != PAINTED_ON:
        skip("the fixtures were painted on an %s" % PAINTED_ON)
        return
    var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
    assert_not_null(file, "%s's fixture is kept" % name)
    if file == null:
        return
    var kept: Dictionary = file.get_var()
    file.close()
    assert_eq(painted.size(), kept.size(), "%s reaches the chunks it reached before" % name)
    var painted_texels := 0
    var worst := 0.0
    for grid: Vector2i in kept:
        var held: Array = kept[grid]
        var before := Image.create_from_data(held[0], held[1], false, held[2], held[3])
        var after: Image = painted.get(grid)
        assert_not_null(after, "%s paints chunk %s" % [name, grid])
        if after == null:
            continue
        for y in before.get_height():
            for x in before.get_width():
                var a := before.get_pixel(x, y)
                var b := after.get_pixel(x, y)
                var under := Color(0, 0, 0, 0)
                if ground.has(grid):
                    under = (ground[grid] as Image).get_pixel(x, y)
                if a != under or b != under:
                    painted_texels += 1
                worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    print("Dynamics paint, %s: %d texels painted, the largest change %.7f" % [name, painted_texels, worst])
    assert_true(painted_texels > 500, "%s painted %d texels" % [name, painted_texels])
    assert_true(worst <= TOLERANCE, "%s: every texel within %.4f of before, the largest change %.7f" % [name, TOLERANCE, worst])


func test_wet_into_wet_paints_what_it_painted_before() -> void:
    _against("wet_into_wet", _noise_layer())


func test_oil_smudge_paints_what_it_painted_before() -> void:
    var painted := _stamp_layer()
    _against("oil_smudge", painted, _stamp_ground)


func test_the_brush_s_own_work_a_noise_stroke() -> void:
    var best := 1 << 62
    for stroke in TIMED_STROKES:
        best = mini(best, _noise_stroke(_noise_brush(LARGE), LARGE))
    print("Dynamics, the brush's own work: %.1f ms a Wet Into Wet stroke of %d motions on %s" % [best / 1000.0, MOTIONS, LARGE])
    assert_true(best > 0, "the stroke took time")
