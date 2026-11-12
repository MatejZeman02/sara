## The scene layer's copy of the whole canvas, timed every frame.
##
## The open question was "whether the viewport copy into F16
## chunks holds at frame rate over a large dirty rectangle". This is the measure
## that answers it, not a fix: a scene whose root declares the whole canvas
## changed at every ask, on a square canvas of 2048 and of 4096 pixels, a
## hundred frames each, with the copy of every frame timed twice. The card's
## time is a pair of timestamps around the frame's `step`, read back frames
## later so nothing waits, and the CPU's is the time `step` takes to record
## its dispatches, since a frame holds only when both fit in it. A sweep of
## narrower squares on the larger canvas says what does hold where the whole
## canvas does not.
##
## Each figure is printed with the device's name, and the numbers it prints are this suite's. Nothing asserts a frame budget,
## because a run beside two other gates is not the machine a painter has: the
## suite asserts that every frame was copied whole and timed, and prints.
##
## A frame here is a forced draw, which renders the scene's viewport and fires
## the signal the layer waits for, then the layer's `step`, as the existing
## scene suite frames it: the runner cannot advance a frame, and an await drops
## every assertion after it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs the main RenderingDevice, the only one whose timestamps resolve and
## the one the viewport draws with.
const REQUIRES_GPU := true

const THIRD_PARTY := &"scene-copy-timing-test-module"
const TYPE := &"whole-canvas-scene"
const SCENE := "res://core/layers/scene/tests/whole_canvas_scene.tscn"

## The two square canvases the row names, in pixels a side.
const SIDES: Array[int] = [2048, 4096]
## Frames timed at each size, after the first, which allocates every chunk and
## is reported on its own, and after the warming ones.
const FRAMES: int = 100
## Frames run and thrown away before the timed ones. The first run of the
## suite timed a 2048 canvas slower on the card than a 4096 one after it,
## which is a card still at its idle clock.
const WARM: int = 30
## The squares, a side each from the top left corner, the sweep declares on
## the largest canvas, each timed over as many frames as a whole canvas is, so
## a worst frame of the sweep is as likely to be seen as one of the canvas.
## Each is a whole number of chunks a side, and the last two lie between what
## held at its worst frame and the whole 4096, which did not always.
const SWEEP: Array[int] = [1024, 2048, 3072, 3584, 3840]
## One frame at sixty to the second, in milliseconds.
const BUDGET_MS: float = 1000.0 / 60.0
## What every capture of this suite is named from, so the engine's own and
## `SaGpuTiming`'s in the same pool are passed over.
const PREFIX: String = "s2-scene-copy"

var _host: Node = null
## Keeps every pair's name unique across the suite's runs.
var _next_run: int = 0


func before_each() -> void:
    _host = Node.new()
    _host.name = "S2SceneCopyTimingHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var descriptor := SaLayerTypeDescriptor.scene_layer(TYPE, SCENE, {})
    descriptor.display_name = "Whole Canvas Scene"
    registries.layer_types.register(descriptor, THIRD_PARTY)
    return registries


## A document of *side* square with the scene layer added and its viewport
## attached, the stage answered.
func _stage(side: int) -> SaSceneLayer:
    var easel := SaEasel.create_default(Vector2i(side, side), null, SaColorSpace.srgb())
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _host.add_child(easel)
    var layer := SaLayerOps.new(easel.document).add(TYPE, _registries().layer_types)
    return SaSceneLayer.attach(layer)


## Runs *frames* timed frames of *stage* after a first one, which allocates
## every chunk, and *warm* more, which bring the card's clock up from idle
## and are thrown away. Answers what each timed frame took, `gpu_ms` and
## `cpu_ms`, and `pixels`, the area each copied. `first_gpu_ms`,
## `first_cpu_ms` and `first_pixels` are the first frame's, and `untimed` is
## how many timed frames the device answered no pair for.
func _time(stage: SaSceneLayer, frames: int, warm: int) -> Dictionary:
    var rd := RenderingServer.get_rendering_device()
    var run := _next_run
    _next_run += 1
    var total := 1 + warm + frames
    var stamps: Dictionary[String, Array] = {}
    var cpu_usec: Array[int] = []
    var pixels: Array[int] = []
    var chunks := 0
    for i: int in total:
        RenderingServer.force_draw(false)
        _gather(rd, stamps)
        var pair := "%s|%d|%d|" % [PREFIX, run, i]
        rd.capture_timestamp(pair + "b")
        var began := Time.get_ticks_usec()
        var copied := stage.step()
        cpu_usec.append(Time.get_ticks_usec() - began)
        rd.capture_timestamp(pair + "e")
        var area := 0
        for grid_pos: Vector2i in copied:
            area += copied[grid_pos].get_area()
        pixels.append(area)
        chunks = copied.size()
    # As many draws as the device keeps frames bring the last pair back.
    for i: int in rd.get_frame_delay() + 1:
        RenderingServer.force_draw(false)
        _gather(rd, stamps)

    var per_usec := _ticks_per_usec(stamps, run, total - 1)
    var gpu_ms: Array[float] = []
    var cpu_ms: Array[float] = []
    var untimed := 0
    for i: int in range(total - frames, total):
        var ms := _pair_ms(stamps, "%s|%d|%d|" % [PREFIX, run, i], per_usec)
        if ms < 0.0:
            untimed += 1
        else:
            gpu_ms.append(ms)
        cpu_ms.append(cpu_usec[i] / 1000.0)
    return {
        "gpu_ms": gpu_ms,
        "cpu_ms": cpu_ms,
        "pixels": pixels.slice(total - frames),
        "first_pixels": pixels[0],
        "first_cpu_ms": cpu_usec[0] / 1000.0,
        "first_gpu_ms": _pair_ms(stamps, "%s|%d|0|" % [PREFIX, run], per_usec),
        "untimed": untimed,
        "chunks": chunks,
    }


## The milliseconds between the two halves of *pair*, or -1 when the device
## answered either half not at all.
static func _pair_ms(stamps: Dictionary[String, Array], pair: String, per_usec: int) -> float:
    if per_usec <= 0 or not stamps.has(pair + "b") or not stamps.has(pair + "e"):
        return -1.0
    var ended: int = stamps[pair + "e"][0]
    var begun: int = stamps[pair + "b"][0]
    return float(ended - begun) / float(per_usec) / 1000.0


## Adds every capture of this suite the device has made readable to *stamps*,
## by name, as `[gpu, cpu]`.
static func _gather(rd: RenderingDevice, stamps: Dictionary[String, Array]) -> void:
    for i: int in rd.get_captured_timestamps_count():
        var name := rd.get_captured_timestamp_name(i)
        if name.begins_with(PREFIX + "|"):
            stamps[name] = [int(rd.get_captured_timestamp_gpu_time(i)), int(rd.get_captured_timestamp_cpu_time(i))]


## Raw GPU ticks per microsecond over run *run*: the span from its first stamp
## to the end of frame *last* on the card against the same span on the CPU,
## which tells the nanoseconds the drivers measured count from the
## microseconds the class reference promises, the way `SaGpuTiming` tells
## them. 0 when too few came.
static func _ticks_per_usec(stamps: Dictionary[String, Array], run: int, last_frame: int) -> int:
    var first := "%s|%d|0|b" % [PREFIX, run]
    var last := "%s|%d|%d|e" % [PREFIX, run, last_frame]
    if not stamps.has(first) or not stamps.has(last):
        return 0
    var gpu_span: int = stamps[last][0] - stamps[first][0]
    var cpu_span: int = stamps[last][1] - stamps[first][1]
    if gpu_span <= 0 or cpu_span <= 0:
        return 0
    return 1000 if float(gpu_span) / float(cpu_span) > SaGpuTiming.NANOSECOND_THRESHOLD else 1


static func _median(values: Array[float]) -> float:
    if values.is_empty():
        return -1.0
    var sorted := values.duplicate()
    sorted.sort()
    return sorted[sorted.size() >> 1]


static func _worst(values: Array[float]) -> float:
    return values.max() if not values.is_empty() else -1.0


## The device the figures were taken on, as a line ends with it.
static func _device() -> String:
    var rd := RenderingServer.get_rendering_device()
    return (
        "%s, %s, %s"
        % [
            rd.get_device_name(),
            RenderingServer.get_video_adapter_vendor(),
            RenderingServer.get_video_adapter_api_version(),
        ]
    )


## What a 60 Hz frame says to the copy: the copy holds a frame when the card's
## time and the CPU's both fit in it, since the two run side by side.
static func _verdict(gpu: Array[float], cpu: Array[float]) -> String:
    if maxf(_worst(gpu), _worst(cpu)) <= BUDGET_MS:
        return "holds at its worst frame"
    if maxf(_median(gpu), _median(cpu)) <= BUDGET_MS:
        return "holds at the median and not at the worst frame"
    return "does not hold"


## Prints one line of figures for *label*.
static func _report(label: String, timed: Dictionary) -> void:
    var gpu: Array[float] = timed["gpu_ms"]
    var cpu: Array[float] = timed["cpu_ms"]
    var card := "card median %.3f ms worst %.3f ms" % [_median(gpu), _worst(gpu)]
    var host := "CPU median %.3f ms worst %.3f ms" % [_median(cpu), _worst(cpu)]
    print(
        (
            "scene copy, %s, %d chunks a frame, %d frames: %s, %s, a 60 Hz frame %s"
            % [label, timed["chunks"], cpu.size(), card, host, _verdict(gpu, cpu)]
        )
    )


## The storage format of *texture* by name, for the two a chunk is held in.
static func _format(texture: SaTexture) -> String:
    match texture.format:
        RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
            return "32-bit float"
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            return "16-bit float"
    return "format %d" % texture.format


func test_the_whole_canvas_is_copied_and_timed_at_both_sizes() -> void:
    print("scene copy, device: %s" % _device())
    for side: int in SIDES:
        var stage := _stage(side)
        var timed := _time(stage, FRAMES, WARM)
        var area := side * side
        assert_eq(timed["first_pixels"], area, "At %d the first frame copies the whole canvas" % side)
        var pixels: Array[int] = timed["pixels"]
        assert_eq(pixels.count(area), FRAMES, "and so does every frame after it, the scene declaring all of it")
        assert_eq(timed["untimed"], 0, "The card answered a pair for every one of the %d frames" % FRAMES)
        var gpu: Array[float] = timed["gpu_ms"]
        assert_true(_median(gpu) > 0.0, "and the copy took the card a time above nothing")
        assert_eq(timed["chunks"], stage.layer.chunks.size(), "Every chunk the layer holds is written every frame")
        print(
            (
                "scene copy, %d x %d whole canvas, chunks in %s: the first frame, allocating them, card %.3f ms CPU %.3f ms"
                % [side, side, _format(stage.layer.get_field(Vector2i.ZERO)), timed["first_gpu_ms"], timed["first_cpu_ms"]]
            )
        )
        _report("%d x %d whole canvas" % [side, side], timed)
        # The smaller canvas's chunks and viewport go before the larger's come.
        for easel: Node in _host.get_children():
            easel.free()


func test_a_sweep_of_narrower_squares_says_what_holds() -> void:
    var side: int = SIDES.back()
    var stage := _stage(side)
    _time(stage, 1, WARM)
    for square: int in SWEEP:
        stage.root.set("declared_side", square)
        var timed := _time(stage, FRAMES, 1)
        var pixels: Array[int] = timed["pixels"]
        assert_eq(pixels.count(square * square), FRAMES, "A %d square declared is a %d square copied" % [square, square])
        _report("%d square on a %d canvas" % [square, side], timed)
