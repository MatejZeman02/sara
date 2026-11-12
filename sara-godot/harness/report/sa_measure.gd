## Oklab statistics over a rectangle, for a script that has to see what it
## painted.
##
## Tools for seeing, so a script does not write its own: the mean and the
## spread of L, a and b over a rectangle of the canvas or of a reference, a
## coverage figure, and the distance between two rectangles' means.
## Four numbers a script can reason about, instead of a screenshot it has to
## interpret.
##
## **The canvas is reduced on the graphics card and only the tally comes back.**
## `shaders/compute/measure.gmacs` adds into eight uints per chunk through
## atomics and [SaCompute.Buffer.read] brings those bytes over, which is a
## handful of numbers and never a texel. That is the `texel` step's allowance
## under hard rule 1 widened to a reduction, and it is the same shape of read
## `SaSelection.measure_bounds` already makes for its tight box. Nothing here
## runs during a stroke.
##
## **A reference is read on the processor, because it is already there.** A
## picture on the Reference board is kept as an `Image` as well as a texture,
## for the reason `ui/dockers/reference/reference_board.gd` gives, so measuring one is a
## loop over pixels that are in RAM. Uploading it to reduce it on the card and
## read it back would be slower and would put a picture on the paint path that
## has no business there.
##
## **Two passes, not one.** GLSL has no float atomic, so every value crosses as
## fixed point, and a one-pass variance subtracts the square of a quantised mean
## from a quantised sum of squares: the two disagree by about a quantisation
## step, so a flat fill reports a spread it does not have. Pass one answers the
## means, pass two sums the squared deviations from them, and a flat fill's
## deviation is below one step and quantises to zero. The cost is a second walk
## over the same chunks, which for a step a model takes between brush strokes is
## nothing.
##
## **What the numbers resolve to.** A mean is good to about one part in 32768 of
## its axis, which is 3e-5 in L and 3e-5 in a and b. A standard deviation is the
## square root of a variance resolved to the same step, so a spread under about
## 0.006 reads as the zero it is near rather than as a number. L is clamped to
## the unit interval and a and b to half a unit either way, which is past the
## 0.4 chroma of a wide-gamut primary, so nothing in any gamut Sara ships meets
## the clamp.
class_name SaMeasure
extends RefCounted

## The kernel file, by the name `SaCompute` resolves under `shaders/compute/`.
const SHADER := "measure"

## Where `measure.gmacs` reads its tally. Binding 0 is the chunk's own field,
## which the walk binds.
const BINDING_TALLY: int = 1

## The eight uints a chunk's slot holds, in the kernel's own order.
const CELLS: int = 8
const CELL_TEXELS: int = 0
const CELL_COVERED: int = 1
const CELL_SUM_L: int = 2
const CELL_SUM_A: int = 3
const CELL_SUM_B: int = 4
const CELL_DEV_L: int = 5
const CELL_DEV_A: int = 6
const CELL_DEV_B: int = 7

## The fixed point the kernel sums in. Same constant, written twice on purpose,
## the way `SaOklab` and `oklab_color_space.gmacs` are: change one, change both,
## and `harness/report/tests/test_measure.gd` is what keeps the pair honest.
const QUANT: float = 32768.0

## How far either way a and b are folded before quantisation. The kernel's
## AB_RANGE.
const AB_RANGE: float = 0.5

## The document whose active layer a canvas measurement reduces. A constructor
## argument because that is how a thing outside this class sets what it owns.
var _document: SaDocument = null

## Built on first use, so a measure that never reaches the canvas allocates no
## pipelines.
var _compute: SaCompute = null


func _init(document: SaDocument) -> void:
    _document = document


## The statistics over *rect*, in document pixels, of the active layer.
##
## A rectangle no chunk holds is not an error: it is coverage zero, which is
## what an unpainted part of the canvas is, and the means come back null rather
## than as the zero that would read as black.
func layer_stats(rect: Rect2i) -> Dictionary:
    var area := maxi(rect.size.x, 0) * maxi(rect.size.y, 0)
    if _document == null or area <= 0:
        return _empty(area)
    var layer := _document.active_layer
    if layer == null:
        return _empty(area)

    # The slot each chunk adds into, decided here rather than in the walk, so
    # the kernel is told a number instead of working one out from a grid
    # position it would have to be given the origin of.
    var slots: Dictionary[Vector2i, int] = {}
    for grid_pos in SaChunkWalk.positions_in(rect):
        if layer.get_field(grid_pos, SaFieldSpec.ALBEDO) != null:
            slots[grid_pos] = slots.size()
    if slots.is_empty():
        return _empty(area)

    var tally := SaCompute.Buffer.new(_zeroed(slots.size()))
    var walk := SaChunkWalk.new(_get_compute(), null, null, SaFieldSpec.ALBEDO)
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk: return layer.chunks.get(grid_pos, null)
    var bindings := {BINDING_TALLY: tally}

    walk.run("measure_sum", rect, chunk_at, _push.bind(slots, Vector3.ZERO), bindings)
    var sums := _fold(tally.read().to_int32_array(), slots.size())
    if int(sums["covered"]) <= 0:
        return _empty(area)

    # Pass two is told the means pass one produced, so that what it sums is the
    # deviation and not the value.
    var mean := Vector3(float(sums["mean_l"]), float(sums["mean_a"]), float(sums["mean_b"]))
    tally.update(_zeroed(slots.size()))
    walk.run("measure_spread", rect, chunk_at, _push.bind(slots, mean), bindings)
    var spread := _fold(tally.read().to_int32_array(), slots.size())

    return _report(area, int(sums["reduced"]), int(sums["covered"]), mean, spread)


## The same statistics over *rect*, in texels, of *image* stored in *space*.
##
## Static because it needs no document and no device: the suite grades it on an
## image it made itself, and the reference path has nothing else to hand it.
static func image_stats(image: Image, space: SaColorSpace, rect: Rect2i) -> Dictionary:
    var area := maxi(rect.size.x, 0) * maxi(rect.size.y, 0)
    if image == null or image.is_empty() or area <= 0:
        return _empty(area)
    var window := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
    if window.size.x <= 0 or window.size.y <= 0:
        return _empty(area)

    var covered := 0
    var sum := Vector3.ZERO
    var labs: Array[Vector3] = []
    for y in range(window.position.y, window.end.y):
        for x in range(window.position.x, window.end.x):
            var texel := image.get_pixelv(Vector2i(x, y))
            if texel.a <= 0.0:
                continue
            var lab := to_oklab(space, texel)
            covered += 1
            sum += lab
            labs.append(lab)
    if covered <= 0:
        return _empty(area)

    var mean := sum / float(covered)
    var deviation := Vector3.ZERO
    for lab: Vector3 in labs:
        var off := lab - mean
        deviation += Vector3(off.x * off.x, off.y * off.y, off.z * off.z)
    var spread := {
        "dev_l": deviation.x / float(covered),
        "dev_a": deviation.y / float(covered),
        "dev_b": deviation.z / float(covered),
    }
    return _report(area, window.size.x * window.size.y, covered, mean, spread)


## One stored triple as Oklab, the twin of `stored_to_oklab` in
## `measure.gmacs`. An Oklab document already holds it, and any other is decoded
## out of its own curve and rotated into linear sRGB first, because Oklab is
## defined against linear sRGB and carries no gamut of its own.
static func to_oklab(space: SaColorSpace, color: Color) -> Vector3:
    var descriptor := space if space != null else SaColorSpace.srgb()
    if descriptor.coordinates == SaColorSpace.Coordinates.OKLAB:
        return Vector3(color.r, color.g, color.b)
    var curve := descriptor.transfer
    var document := Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))
    return SaOklab.from_linear_srgb(descriptor.to_linear_srgb_matrix() * document)


## The Oklab distance between two measurements' means, or -1.0 when either has
## no mean to compare. Euclidean in L, a and b, which is what Oklab is for:
## the unit is one of its own, so 0.02 is a difference a painter can just see
## and 0.2 is a different colour.
static func distance(first: Dictionary, second: Dictionary) -> float:
    var a: Variant = first.get("mean", null)
    var b: Variant = second.get("mean", null)
    if not (a is Dictionary) or not (b is Dictionary):
        return -1.0
    return _as_vector(a).distance_to(_as_vector(b))


## A zeroed tally for *count* chunk slots, which is both how the buffer is made
## and how it is reset between the two passes.
static func _zeroed(count: int) -> PackedByteArray:
    var cells := PackedInt32Array()
    cells.resize(count * CELLS)
    cells.fill(0)
    return cells.to_byte_array()


## The whole tally summed back into real numbers.
##
## The cells are read as int32 and widened here, because a sum that filled the
## top bit of a uint reads as a negative int and a GDScript int is 64 bits wide
## with room for it. Every slot is summed before anything is divided, so the
## order is the one that loses the least.
static func _fold(cells: PackedInt32Array, count: int) -> Dictionary:
    var totals := PackedFloat64Array()
    totals.resize(CELLS)
    totals.fill(0.0)
    for slot in count:
        for cell in CELLS:
            var at := slot * CELLS + cell
            if at >= cells.size():
                continue
            var raw := cells[at]
            totals[cell] += float(raw) if raw >= 0 else float(raw) + 4294967296.0

    var covered: float = totals[CELL_COVERED]
    var scale := 1.0 / (QUANT * maxf(covered, 1.0))
    # a and b were folded into the unit interval one texel at a time, so the
    # half is taken back off once per texel and the range is unfolded once.
    var mean_a := (totals[CELL_SUM_A] * scale - 0.5) * 2.0 * AB_RANGE
    var mean_b := (totals[CELL_SUM_B] * scale - 0.5) * 2.0 * AB_RANGE
    return {
        "reduced": totals[CELL_TEXELS],
        "covered": covered,
        "mean_l": totals[CELL_SUM_L] * scale,
        "mean_a": mean_a,
        "mean_b": mean_b,
        "dev_l": totals[CELL_DEV_L] * scale,
        "dev_a": totals[CELL_DEV_A] * scale,
        "dev_b": totals[CELL_DEV_B] * scale,
    }


## One measurement as the step and the suite both read it. The spread is a
## standard deviation, so the caller compares it against a tolerance in the
## same unit as the mean, and a variance that rounded below zero is zero rather
## than a NAN out of `sqrt`.
static func _report(area: int, reduced: int, covered: int, mean: Vector3, spread: Dictionary) -> Dictionary:
    return {
        "texels": area,
        "reduced": reduced,
        "covered": covered,
        "coverage": float(covered) / float(maxi(area, 1)),
        "mean": {"l": mean.x, "a": mean.y, "b": mean.z},
        "sd":
        {
            "l": sqrt(maxf(float(spread.get("dev_l", 0.0)), 0.0)),
            "a": sqrt(maxf(float(spread.get("dev_a", 0.0)), 0.0)),
            "b": sqrt(maxf(float(spread.get("dev_b", 0.0)), 0.0)),
        },
    }


## A rectangle with nothing in it: the coverage a model asked about is zero and
## there is no colour to report, which is not the same answer as black.
static func _empty(area: int) -> Dictionary:
    return {"texels": area, "reduced": 0, "covered": 0, "coverage": 0.0, "mean": null, "sd": null}


static func _as_vector(from: Dictionary) -> Vector3:
    return Vector3(float(from.get("l", 0.0)), float(from.get("a", 0.0)), float(from.get("b", 0.0)))


## The push constant for one stop of the walk, in the order `measure.gmacs`
## declares its block. *means* is zero for the summing pass, which never reads
## those three words.
func _push(
    grid_pos: Vector2i, local: Rect2i, start: Vector2i, slots: Dictionary[Vector2i, int], means: Vector3
) -> PackedFloat32Array:
    var space := _document.color_space if _document != null else SaColorSpace.srgb()
    var params := PackedFloat32Array(
        [
            float(start.x),
            float(start.y),
            float(local.position.x),
            float(local.position.y),
            float(local.end.x),
            float(local.end.y),
            float(slots.get(grid_pos, 0)),
            float(space.coordinates),
        ]
    )
    params.append_array(space.transfer.to_params())
    params.append_array(PackedFloat32Array([means.x, means.y, means.z]))
    for column: Vector3 in SaColorSpaceGlsl.basis_columns(space.to_linear_srgb_matrix()):
        params.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    return params


func _get_compute() -> SaCompute:
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    return _compute


# --- The `measure` step -------------------------------------------------------


## Measures a mean colour: of the canvas or a reference, or the distance between
## two, from a scenario or through the door, `{"measure": {...}}`.
##
## `rect` is `[x, y, w, h]`, in document pixels for the canvas and in texels for
## a reference. `reference` names a picture on the Reference board, by its file
## name with or without the extension or by its whole path, and measures that
## instead of the canvas. `against` is a second block of the same shape, and
## then the answer carries the Oklab distance between the two means, which is
## the "difference between the two rectangles as a distance" the step exists for.
##
## The answer is one line of JSON: `a`, the first measurement, `b` and
## `distance` when there was a second, and `of`, what each side looked at, so a
## run log says what was measured and not only what came out.
##
## `{"measure": {"perf": "begin"}}`, `"end"` and `"read"` are the perf form and
## measure no rectangle. `begin` opens a window over the
## performance ledgers, `end` closes it and answers the window's block, the
## dispatches per kernel, the GPU time, the stroke latency, the memory and the
## boot, and `read` answers the last block again. `"trace": true` beside a
## `begin` prints a `Sara frame:` line at every frame of the window. The same block is the dump's
## `perf` key. `SaPerfWindow` owns all of it, and this is only its door.
##
## `{"measure": {"frame": 60}}` is the frame form: the main
## window drawn that many times, and the render time it measured, CPU and GPU,
## so a view's cost with a switch on and off is two numbers in the run log.
##
## `{"measure": {"memory": "before"}}` is the memory form: the process's
## resident set and the engine's static memory, kept under the name given, and
## `{"measure": {"memory": "after", "since": "before"}}` answers the growth
## since the reading named, so twenty moves and their undos read as one number.
static func capture(document: SaDocument, spec: Variant) -> String:
    var wanted: Dictionary = spec if spec is Dictionary else {}
    if wanted.has("memory"):
        return ProcessMemory.capture(String(wanted["memory"]), String(wanted.get("since", "")))
    if wanted.has("perf"):
        return SaPerfWindow.capture(document, String(wanted["perf"]), bool(wanted.get("trace", false)))
    if wanted.has("frame"):
        return FrameTime.capture(int(wanted["frame"]))
    var answer := {"of": _subject(wanted), "a": _region(document, wanted)}
    if wanted.has("against"):
        var against: Dictionary = wanted["against"] if wanted["against"] is Dictionary else {}
        answer["against"] = _subject(against)
        answer["b"] = _region(document, against)
        answer["distance"] = distance(answer["a"], answer["b"])
    return "SaCapture: measure %s" % JSON.stringify(answer)


## One side of a measurement: the canvas, or the reference the block names.
##
## A reference that cannot be found is a measurement of nothing with the reason
## in it, rather than a silent fall back to the canvas, because a model reading
## a mean it did not ask for would draw a conclusion from it.
static func _region(document: SaDocument, ask: Dictionary) -> Dictionary:
    var rect := _rect(ask.get("rect", []))
    if not ask.has("reference"):
        return SaMeasure.new(document).layer_stats(rect)
    var named := String(ask["reference"])
    var path := reference_path(document, named)
    if path.is_empty():
        var missing := _empty(maxi(rect.size.x, 0) * maxi(rect.size.y, 0))
        missing["problem"] = "no reference named %s" % named
        return missing
    return image_stats(_picture(path), SaImageImport.space_for(path), rect)


## The picture at *path*, by whichever door the path has.
##
## A `res://` path is a resource and is loaded as one, because `Image.load` on it
## warns that it will not work on export and is right to. The same two lines
## `SaReferenceBoard._read` has, repeated rather than reached for: that one is a
## docker's and this one is the step's, and a reference measured in a test has no
## docker to borrow from.
static func _picture(path: String) -> Image:
    if not path.begins_with("res://"):
        return SaImageImport.read(path)
    var texture := ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null
    return texture.get_image() if texture != null else null


## What a block looked at, for the line the door prints.
static func _subject(ask: Dictionary) -> String:
    var rect := _rect(ask.get("rect", []))
    var where := "reference %s" % String(ask["reference"]) if ask.has("reference") else "canvas"
    return "%s %d %d %d %d" % [where, rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## The file behind *named*, which is a whole path, a file name, or a file name
## with the extension left off.
##
## The boards are read off the document rather than out of the docker, because
## the reference docker keeps a board as paths and rectangles and the document is where it puts
## them, so naming a reference needs no node in the tree and works in a test
## that has none.
static func reference_path(document: SaDocument, named: String) -> String:
    if named.is_empty():
        return ""
    if FileAccess.file_exists(named) or ResourceLoader.exists(named):
        return named
    if document == null:
        return ""
    for board: Variant in document.reference_boards:
        if not (board is Dictionary):
            continue
        for entry: Variant in (board as Dictionary).get("pictures", []):
            if not (entry is Dictionary):
                continue
            var path := String((entry as Dictionary).get("path", ""))
            var file := path.get_file()
            if file == named or file.get_basename() == named:
                return path
    return ""


## `[x, y, w, h]` as a rectangle, and the empty one for anything shorter, which
## reads as a measurement of nothing rather than as a measurement of everything.
static func _rect(raw: Variant) -> Rect2i:
    var numbers: Array = raw if raw is Array else []
    if numbers.size() < 4:
        return Rect2i()
    return Rect2i(int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3]))


## The memory form of the step: what the process holds, read where a painter's
## system monitor reads it, so a step that leaves memory behind is a number in
## the run log. The resident set is Linux's `/proc/self/status`, and elsewhere
## only the engine's static memory is answered. Each reading carries the
## engine's object count beside it, and the nodes, cached resources and orphan
## nodes among them, so an object an open leaves behind shows as a number even
## where the memory it holds is small.
class ProcessMemory:
    ## The readings taken so far, by the name each was taken under.
    static var _taken: Dictionary[String, Dictionary] = {}

    static func capture(named: String, since: String) -> String:
        var reading := {
            "name": named,
            "rss_kib": rss_kib(),
            "static_kib": int(OS.get_static_memory_usage() / 1024.0),
            "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
            "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
            "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
            "orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
        }
        _taken[named] = reading
        if _taken.has(since):
            var before: Dictionary = _taken[since]
            reading["since"] = since
            reading["rss_growth_mib"] = snappedf((int(reading["rss_kib"]) - int(before["rss_kib"])) / 1024.0, 0.1)
            reading["static_growth_mib"] = snappedf((int(reading["static_kib"]) - int(before["static_kib"])) / 1024.0, 0.1)
            reading["objects_growth"] = int(reading["objects"]) - int(before.get("objects", 0))
        return "SaCapture: measure memory %s" % JSON.stringify(reading)

    ## The process's resident set in KiB, or -1 where no `/proc` says it.
    static func rss_kib() -> int:
        var status := FileAccess.open("/proc/self/status", FileAccess.READ)
        if status == null:
            return -1
        while not status.eof_reached():
            var line := status.get_line()
            if line.begins_with("VmRSS:"):
                return line.trim_prefix("VmRSS:").strip_edges().split(" ")[0].to_int()
        return -1


## The frame form of the step: the root viewport's own render time over forced
## draws, which is the view's shader and everything else in the window, so what
## a switch costs is the difference of two of these taken either side of it.
class FrameTime:
    ## Draws dropped before the count, while the measure settles and the
    ## timestamps of the frames before it resolve.
    const SETTLE: int = 4

    ## *frames* forced draws of the main window, and the mean, the least and
    ## the most of the render time Godot measured for each, in milliseconds.
    static func capture(frames: int) -> String:
        var tree := Engine.get_main_loop() as SceneTree
        if tree == null:
            return "SaCapture: measure frame refused, no tree"
        var viewport := tree.root.get_viewport_rid()
        RenderingServer.viewport_set_measure_render_time(viewport, true)
        for i in SETTLE:
            RenderingServer.force_draw(true, 0.0)
        var gpu: Array[float] = []
        var cpu: Array[float] = []
        for i in maxi(frames, 1):
            RenderingServer.force_draw(true, 0.0)
            gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
            cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
        RenderingServer.viewport_set_measure_render_time(viewport, false)
        var answer := {"frames": gpu.size(), "gpu_ms": _spread(gpu), "cpu_ms": _spread(cpu)}
        return "SaCapture: measure frame %s" % JSON.stringify(answer)

    static func _spread(values: Array[float]) -> Dictionary:
        var total := 0.0
        for value in values:
            total += value
        return {
            "mean": snappedf(total / values.size(), 0.0001),
            "min": snappedf(values.min(), 0.0001),
            "max": snappedf(values.max(), 0.0001)
        }
