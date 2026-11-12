## The `kernel` step: a notebook cell's kernel, sent as source, compiled by the
## compiler the module loader uses and run once over a layer.
##
## The driver owns the compile-once cache and the dispatch, which is a filter's
## Apply except that it reads one layer and writes another over a rectangle the
## request names. Chunks move GPU to GPU (hard rules 1 to 3). The request, the
## halo and the verdict are on `kernel()`, and `sara_steps.py kernel` prints them.
class_name SaKernelDriver
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The text half of the pixel function door, which wraps the short form and
## whose rule a matrix's opening is.
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

## The pass that bounds a cell's loops, and the two the compiler reads a text
## through before it, so the guard reads the GLSL the compiler would.
const LoopGuard := preload("res://core/custom-shader/dialect/sa_loop_guard.gd")
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## The folder a short form body is registered under as an include, so its lines
## read as `cell_pixels/<stem>.gmacs` in the line map.
const INCLUDE_FOLDER: String = "cell_pixels"

## Appended to a wrapped source's file name, so the generated kernel and the body
## it imports never share a stem the error text would confuse.
const WRAPPED_SUFFIX: String = "_wrapped"

## The folder under the data root the generated files go in.
const GENERATED_FOLDER: String = "cell-kernels"

## The two images the step binds, by the names a cell's kernel declares.
const SOURCE_IMAGE: String = "src"
const TARGET_IMAGE: String = "dst"

## Params the dispatch writes itself, from the rectangle, so a cell never sets
## them and they are not offered as sliders.
const REGION_FIELDS: Array[String] = ["origin", "extent"]

## The pixels a source is gathered past the rectangle on each side when the
## request names no `halo`.
const DEFAULT_HALO: int = 16

## How many components each params type takes, for writing its zero.
const COMPONENTS: Dictionary = {
    "float": 1, "int": 1, "uint": 1, "vec2": 2, "ivec2": 2, "uvec2": 2, "vec3": 3, "ivec3": 3, "vec4": 4, "ivec4": 4
}


## One source compiled, kept for as long as the driver is, so a second send of the
## same text is answered from here.
class CellKernel:
    extends RefCounted

    ## The kernel's name as the request gave it.
    var name: String = ""

    ## Where the source was written, and the key the compiler files it under.
    var path: String = ""
    var shader_name: String = ""

    ## The compute over the shader once it compiled, null when it did not.
    var compute: SaCompute = null

    ## The compiler's message with the generated file named as the kernel, and
    ## the first source line it names, or 0.
    var error: String = ""
    var line: int = 0

    ## `{name, type, default}` per field of the params block, in declared order,
    ## and `length` beside them on an array, which a `float` one of a square
    ## length is a matrix the notebook draws as a grid. A field the dialect moved
    ## into a storage buffer, because the block would not fit the push constant
    ## with it, comes after the block's own, and is set the same way.
    var params: Array = []

    ## The images the kernel reads and writes, the wrapper's own pair for the
    ## short pixel form.
    var source_image: String = SOURCE_IMAGE
    var target_image: String = TARGET_IMAGE

    ## What a short form body is registered as, empty for a whole kernel.
    var include_name: String = ""

    ## The `uniform` lines of a short form, as `sa_pixel_source.gd` reads them.
    var uniforms: Array = []

    ## How many loops the guard bounded, the short form's body and its wrapper
    ## together. A kernel with none declares no guard and binds nothing more.
    var loops: int = 0

    func _init(kernel_name: String, source: String) -> void:
        name = kernel_name
        var stem := "%s_%s" % [_safe(kernel_name), source.md5_text().substr(0, 12)]
        path = SaDataRoot.path(GENERATED_FOLDER).path_join(stem + ".gmacs")
        shader_name = "sara/" + stem
        if is_pixel_form(source):
            source = _wrapped(source, stem)
            if not error.is_empty():
                return
        source = _bounded(source, true)
        if not error.is_empty():
            return
        _compile(source, stem)

    ## Whether *source* is the short pixel form: a `def pixel(` at the start of a
    ## line and no `kernel` line, which a whole kernel always has.
    static func is_pixel_form(source: String) -> bool:
        var signature := RegEx.new()
        signature.compile("(?m)^def\\s+pixel\\s*\\(")
        var kernel_line := RegEx.new()
        kernel_line.compile("(?m)^\\s*kernel\\s+\\w+")
        return signature.search(source) != null and kernel_line.search(source) == null

    ## The short form's wrapper, its body registered as an include beside it, or
    ## "" with [member error] set when the source is not a pixel function the
    ## wrapper can take.
    func _wrapped(source: String, stem: String) -> String:
        var problems := PixelSource.problems(source, name)
        if not problems.is_empty():
            error = "%s.gmacs: %s" % [name, " ".join(problems)]
            var pattern := RegEx.new()
            pattern.compile("^line (\\d+)")
            var found := pattern.search(problems[0])
            line = int(found.get_string(1)) if found != null else 0
            return ""
        uniforms = PixelSource.uniforms(source)
        include_name = INCLUDE_FOLDER.path_join(stem)
        source_image = PixelSource.SOURCE_IMAGE
        target_image = PixelSource.TARGET_IMAGE
        path = path.get_basename() + WRAPPED_SUFFIX + ".gmacs"
        var body := _bounded(PixelSource.body(source), false)
        if not error.is_empty():
            return ""
        GlobalShaderCompiler.set_virtual_include(include_name, body)
        return PixelSource.wrap(
            name, include_name, uniforms, PixelSource.imports(source), PixelSource.PixelImages.declared(source)
        )

    ## *text* as the GLSL the compiler would read, every loop of it bounded by
    ## `sa_loop_guard.gd`, so a cell's `while true:` is stopped rather than
    ## hanging the GPU. The kernel's own file, *whole*, takes the guard's
    ## declarations when this kernel has any loop at all, the body's included,
    ## and a short form's body never does, because its wrapper declares them
    ## above the import. "" with [member error] set when the guard cannot read a
    ## loop, at the line it is on.
    ##
    ## What is written is GLSL, which the compiler reads unchanged, and as many
    ## lines as the cell sent, so an error still names the cell's own line.
    func _bounded(text: String, whole: bool) -> String:
        var bounded := LoopGuard.bounded(KernelSource.remove_comments(Dialect.to_glsl(text)))
        var refusal := String(bounded["error"])
        if not refusal.is_empty():
            line = int(bounded["line"])
            var file := name if whole or include_name.is_empty() else INCLUDE_FOLDER.path_join(name)
            error = "%s.gmacs:%d: %s" % [file, line, refusal]
            return ""
        loops += int(bounded["loops"])
        var glsl := String(bounded["text"])
        return LoopGuard.with_prelude(glsl) if whole and loops > 0 else glsl

    func _compile(source: String, stem: String) -> void:
        DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
            error = "cannot write %s (%s)." % [path, error_string(FileAccess.get_open_error())]
            return
        file.store_string(source)
        file.close()
        if GlobalShaderCompiler.get_rd() == null:
            error = "there is no rendering device to compile on."
            return
        GlobalShaderCompiler.compile_compute_shader(path)
        shader_name = GlobalShaderCompiler.index.shader_key(path)
        error = GlobalShaderCompiler.compile_error(shader_name).replace(stem + ".gmacs", name + ".gmacs")
        var kernels := GlobalShaderCompiler.get_kernel_names(shader_name)
        if error.is_empty() and not kernels.has(name):
            error = "the source declares no kernel called %s, it declares %s." % [name, kernels]
        if not error.is_empty():
            line = _first_line(error)
            return
        compute = SaCompute.new(shader_name)
        var fields := GlobalShaderCompiler.push_constant_layout(shader_name).duplicate()
        for moved: Dictionary in SaCompute.BindingSlots.moved_params(GlobalShaderCompiler.binding_layout(shader_name)):
            fields.append(moved["layout"][0])
        for field: Dictionary in fields:
            var field_name := String(field["name"])
            if field_name.is_empty() or bool(field.get("pad", false)) or REGION_FIELDS.has(field_name):
                continue
            # The short form's `step` and `t` are the wrapper's, nought in a
            # cell, which is neither a simulation nor a filter that plays.
            if not include_name.is_empty() and field_name in PixelSource.PROVIDED_FIELDS:
                continue
            var type_name := String(field["type"])
            var length := int(field.get("length", 0))
            var param := {"name": field_name, "type": type_name, "default": _default_of(field_name, type_name, length)}
            if length > 0:
                param["length"] = length
            params.append(param)

    ## The value *field_name* opens at: its `uniform` line's default in the short
    ## form, a vector as an array the way a whole kernel's zero is, and what
    ## [method _opening] gives *type_name* and *length* everywhere else.
    func _default_of(field_name: String, type_name: String, length: int) -> Variant:
        for field: Dictionary in uniforms:
            if String(field["name"]) != field_name:
                continue
            var value: Variant = field["default"]
            if value is Vector2:
                return [value.x, value.y]
            if value is Vector3:
                return [value.x, value.y, value.z]
            if value is Vector4:
                return [value.x, value.y, value.z, value.w]
            return value
        return _opening(type_name, length)

    ## The values the block takes, *given* over the zero of every field.
    func values(given: Dictionary) -> Dictionary:
        var out: Dictionary = {}
        for field: Dictionary in params:
            out[field["name"]] = given.get(field["name"], field["default"])
        if not include_name.is_empty():
            out[PixelSource.STEP_FIELD] = 0
            out[PixelSource.TIME_FIELD] = 0.0
        return out

    ## Why *given* cannot set the block, empty when it can: it names a field the
    ## kernel does not declare, which [method values] would pass over unheard.
    func params_refusal(given: Dictionary) -> String:
        var known := PackedStringArray(values({}).keys())
        var unknown := PackedStringArray(given.keys().filter(func(key: Variant) -> bool: return not known.has(str(key))))
        var listed := "its parameters are " + ", ".join(known) if known else "it declares none"
        return "" if unknown.is_empty() else "kernel %s has no parameter called %s, %s." % [name, " or ".join(unknown), listed]

    ## The name as a file stem: letters, digits and underscores.
    static func _safe(text: String) -> String:
        var out := ""
        for character in text:
            out += character if character.is_valid_identifier() or character.is_valid_int() else "_"
        return out if not out.is_empty() else "kernel"

    ## The first `name.gmacs:N` the compiler's message names, the line map's own
    ## spelling of a source line.
    func _first_line(message: String) -> int:
        var pattern := RegEx.new()
        pattern.compile("%s\\.gmacs:(\\d+)" % _safe(name))
        var found := pattern.search(message)
        return int(found.get_string(1)) if found != null else 0

    ## Drops the body's registration when the compile it belongs to goes, and
    ## only while the compiler stands, the way `SaPixelFunction` drops its own.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE and not include_name.is_empty() and is_instance_valid(GlobalShaderCompiler):
            GlobalShaderCompiler.clear_virtual_include(include_name)

    ## What a field of *type_name* opens at, *length* entries of it for an
    ## array. A matrix holds a one in the middle, the pixel function's rule for
    ## one with no default, so a grid opens on the picture unchanged. Any other
    ## array is its zeros, flat.
    static func _opening(type_name: String, length: int) -> Variant:
        if length == 0:
            return _zero(type_name)
        var matrix := PixelSource.unchanged_matrix(length)
        if type_name == PixelSource.MATRIX_TYPE and not matrix.is_empty():
            return matrix
        var out: Array = []
        for _entry in length:
            var zero: Variant = _zero(type_name)
            if zero is Array:
                out.append_array(zero)
            else:
                out.append(zero)
        return out

    ## A params block declares no defaults, so each field opens at its zero.
    static func _zero(type_name: String) -> Variant:
        var count: int = COMPONENTS.get(type_name, 1)
        var zero: Variant = 0.0
        if type_name.begins_with("i") or type_name.begins_with("u"):
            zero = 0
        if count == 1:
            return zero
        var out: Array = []
        for _i in count:
            out.append(zero)
        return out


## The GPU time of one dispatch, from a pair of timestamps around its compute
## list, read inside the step that ran it.
##
## A capture is readable once the device has finished the frame it was taken
## in, and `SaGpuTiming` waits drawn frames for that. A step that waited the
## same way would lose its pair to the first flush in between, a shot's or a
## thumbnail's readback, and under weston's pixman renderer to every frame. So
## the clock ends the device's frame
## itself: four bytes of a buffer of its own read back, which flushes the
## device, waits for it and makes the frame's captures readable at once. No
## texel of the canvas leaves VRAM, and the wait is for the kernel the step has
## just sent.
##
## The device answers raw ticks, nanoseconds on the drivers measured though the
## class reference says microseconds. So the first answer of a run times two
## captures a known wait apart and keeps the ratio, the way `SaGpuTiming` tells
## the two apart from a window's spans.
class DispatchClock:
    extends RefCounted

    ## What every capture name of the clock starts with, which `SaGpuTiming`
    ## passes over because its own names start `sa|`.
    const PREFIX: String = "kernel-step"

    ## The wait between the two calibrating captures, long beside a flush.
    const CALIBRATION_USEC: int = 2000

    ## Raw ticks per microsecond on this device, 0 until the first answer.
    static var _ticks_per_usec: int = 0

    ## The running index that makes every pair's names unique in a frame.
    static var _next: int = 0

    ## The name both halves of the open pair share, empty when none is open.
    var _pair: String = ""

    ## The buffer whose read ends the device's frame, made at the first answer.
    var _flusher: SaCompute.Buffer = null

    ## Captures the begin half, before the kernel's list opens: the engine
    ## refuses a capture inside an open list.
    func begin() -> void:
        _pair = ""
        var rd := _device()
        if rd == null:
            return
        _pair = "%s|%d|" % [PREFIX, _next]
        _next += 1
        rd.capture_timestamp(_pair + "b")

    ## Captures the end half, after the list has closed.
    func end() -> void:
        var rd := _device()
        if rd != null and not _pair.is_empty():
            rd.capture_timestamp(_pair + "e")

    ## `{"gpu_ms": <float>}` for the pair just closed, or `gpu_ms` null beside
    ## `gpu_unknown`, the reason, when the device answered no time for it.
    func answer() -> Dictionary:
        var rd := _device()
        if rd == null:
            return _unknown("there is no rendering device")
        if rd != RenderingServer.get_rendering_device():
            return _unknown("the kernel ran on a device of its own, whose timestamps this step cannot read")
        if _pair.is_empty():
            return _unknown("no timestamp was captured before the dispatch")
        var stamps := _collected(rd)
        if not stamps.has(_pair + "b") or not stamps.has(_pair + "e"):
            return _unknown("the device answered no timestamps for the dispatch")
        var begun: Array = stamps[_pair + "b"]
        var ended: Array = stamps[_pair + "e"]
        var ticks: int = ended[0] - begun[0]
        if ticks <= 0:
            return _unknown("the device's timestamps did not advance over the dispatch")
        var per_usec := _calibrated(rd)
        if per_usec <= 0:
            return _unknown("the device's timestamps did not tell nanoseconds from microseconds")
        return {"gpu_ms": float(ticks) / float(per_usec) / 1000.0}

    ## The device the kernel is dispatched on.
    func _device() -> RenderingDevice:
        return GlobalShaderCompiler.get_rd()

    ## Ends the device's frame and answers every capture it returns, by name,
    ## as `[gpu, cpu]`. The seam a suite fakes a device with no timestamps at.
    func _collected(rd: RenderingDevice) -> Dictionary:
        if _flusher == null:
            _flusher = SaCompute.Buffer.new(PackedByteArray([0, 0, 0, 0]))
        _flusher.read()
        var out: Dictionary = {}
        for i: int in rd.get_captured_timestamps_count():
            var name := rd.get_captured_timestamp_name(i)
            if name.begins_with(PREFIX + "|"):
                out[name] = [int(rd.get_captured_timestamp_gpu_time(i)), int(rd.get_captured_timestamp_cpu_time(i))]
        return out

    ## Raw ticks per microsecond, measured once a run: two captures
    ## `CALIBRATION_USEC` apart on the CPU, each read by a flush of its own,
    ## are as far apart on the GPU. 0 when the device answers neither.
    func _calibrated(rd: RenderingDevice) -> int:
        if _ticks_per_usec > 0:
            return _ticks_per_usec
        var first := "%s|calibrate|%d|a" % [PREFIX, _next]
        var second := "%s|calibrate|%d|b" % [PREFIX, _next]
        _next += 1
        rd.capture_timestamp(first)
        var before := _collected(rd)
        OS.delay_usec(CALIBRATION_USEC)
        rd.capture_timestamp(second)
        var after := _collected(rd)
        if not before.has(first) or not after.has(second):
            return 0
        var a: Array = before[first]
        var b: Array = after[second]
        var cpu_span: int = b[1] - a[1]
        var gpu_span: int = b[0] - a[0]
        if cpu_span <= 0 or gpu_span <= 0:
            return 0
        var ratio := float(gpu_span) / float(cpu_span)
        _ticks_per_usec = 1000 if ratio > SaGpuTiming.NANOSECOND_THRESHOLD else 1
        return _ticks_per_usec

    static func _unknown(why: String) -> Dictionary:
        return {"gpu_ms": null, "gpu_unknown": why}


## The run, read for its document. Null in a suite that hands the document in.
var _run: CaptureRun = null

## Source hash plus name -> [CellKernel], every source this driver has compiled.
var _compiled: Dictionary = {}

## How many sources this driver has compiled, which a second send leaves alone.
var compiles: int = 0

## Times each run's dispatch. A suite hands in one that fakes the device.
var _clock: DispatchClock = null


func _init(run: CaptureRun, clock: DispatchClock = null) -> void:
    _run = run
    _clock = clock if clock != null else DispatchClock.new()


## Runs a notebook cell's kernel: *spec* against the main document, over its
## `rect`, `"canvas"` for the whole canvas, and with none over the chunks the read
## layer holds or the whole canvas when it holds none, and prints the verdict
## line, which on a run carries the dispatch's own GPU time as `gpu_ms`.
##
##     {"kernel": {"source": "kernel invert\n...", "name": "invert",
##                 "layer": "Paint", "into": "Result", "rect": [0, 0, 256, 256],
##                 "halo": 16, "params": {"amount": 1.0}}}
##
## The source is a whole `.gmacs` file that reads an image called `src` and
## writes one called `dst`. `layer` is read (name or index from the bottom, the
## active layer when absent). `into` is written (name or index, a layer named
## after the kernel when absent), and a name no layer has yet is made above the
## active layer, so a rerun leaves one layer of that name. `"run": false`
## compiles and answers without touching a layer. `inputs` binds further
## read-only images. No selection is consulted, and the kernel registers
## nothing: no filter, no menu row, no module.
##
## The run records one undo step, "Kernel <name>" or the `"step"` given, and
## `"history": false` records none. When the verdict's `in_place` is true a bench
## records only its first rerun, so an undo hands back the layer as it was
## before the first.
##
## The halo: every image is gathered over the rectangle grown by `halo` pixels on
## each side (16 when absent), so a neighbour-reading kernel does not darken the
## rectangle's border. A texel past the canvas reads the nearest canvas texel, and
## a position inside the canvas with no chunk reads transparent. The dispatch
## covers the grown rectangle, `origin` is its corner and `extent` its size, and
## only the rectangle itself is written back.
##
## The answer is one `SaCapture: kernel <json>` line with `ok`, `compiled`, the
## declared `params`, and on a run the layers, `in_place`, the rectangle, the
## chunks written and `gpu_ms`. A device with no timestamps answers `null` with
## `gpu_unknown` rather than a 0 that reads as a fast kernel. A failure answers
## `ok: false` with the compiler's `error` and the source `line`, or the complaint
## about unbound images or undeclared params, and writes nothing.
##
## The source is compiled from a generated file under the data root, named by a
## hash of the source, so the compiler's line map names the cell's own lines and
## two cells that name one kernel differently stay two shaders. Every loop is
## bounded by `sa_loop_guard.gd` first, and a kernel past `LoopGuard.BUDGET`
## answers `ok: false`, `stopped`, and writes nothing.
##
## A source holding `def pixel(ivec2 at) -> vec4` and no `kernel` line is the
## short form, wrapped as `SaPixelFunction` wraps a file: its `uniform` lines
## become the params block, and the generated kernel binds the wrapper's two
## images rather than `src` and `dst`.
func kernel(spec: Dictionary) -> Dictionary:
    var document := _run.main_document() if _run != null else null
    var verdict := run_on(document, spec, _run.layer_types() if _run != null else null)
    print("SaCapture: kernel %s" % JSON.stringify(verdict))
    return verdict


## Compiles *spec*'s source when this driver has not, and runs it over *document*
## unless the request says `"run": false`. Answers the verdict.
func run_on(document: SaDocument, spec: Dictionary, types: SaLayerTypeRegistry = null) -> Dictionary:
    var source := String(spec.get("source", ""))
    var name := String(spec.get("name", ""))
    if source.is_empty() or name.is_empty():
        return {"ok": false, "error": "a kernel step names its source and its kernel."}
    var key := "%s:%s" % [name, source.md5_text()]
    var compiled_now := not _compiled.has(key)
    if compiled_now:
        _compiled[key] = CellKernel.new(name, source)
        compiles += 1
    var cell: CellKernel = _compiled[key]
    var verdict := {"ok": cell.error.is_empty(), "name": name, "compiled": compiled_now, "params": cell.params}
    if not cell.error.is_empty():
        verdict["error"] = cell.error
        verdict["line"] = cell.line
        return verdict
    if not bool(spec.get("run", true)):
        return verdict
    verdict.merge(_dispatch(document, cell, spec, types), true)
    return verdict


## The run half: the layers, the rectangle, the gather, the dispatch and the
## write. Answers what goes into the verdict beside the compile's half.
func _dispatch(document: SaDocument, cell: CellKernel, spec: Dictionary, types: SaLayerTypeRegistry) -> Dictionary:
    if document == null:
        return {"ok": false, "error": "there is no document to run the kernel on."}
    var unknown := cell.params_refusal(spec.get("params", {}))
    if not unknown.is_empty():
        return {"ok": false, "error": unknown}
    var oversized := _block_refusal(cell)
    if not oversized.is_empty():
        return {"ok": false, "error": oversized}
    var read := layer_of(document, spec.get("layer", null))
    if read == null:
        return {"ok": false, "error": "no layer called %s." % [spec.get("layer")]}
    # The written layer is refused as the pixel step refuses it, before the
    # rectangle, so a refusal adds no layer and records no step. A name no layer
    # has is the layer to make, after every check, and an index has to exist.
    var into_name := cell.name
    var named_into: SaLayer = null
    if spec.has("into"):
        var asked: Variant = spec["into"]
        named_into = layer_of(document, asked)
        if named_into == null and (asked is int or asked is float):
            return {"ok": false, "error": "no layer %d to write into." % int(asked)}
        into_name = str(asked)
        if into_name.is_empty():
            return {"ok": false, "error": "`into` names a layer, and it was empty."}
    else:
        named_into = SaScenarioPixels.named_target(document, into_name)
    if named_into != null:
        var refused := _into_refusal(named_into, read)
        if not refused.is_empty():
            return {"ok": false, "error": refused}
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    var wanted: Variant = spec.get("rect", null)
    if wanted == null and not _bounds_of(read).has_area():
        wanted = SaScenarioPixels.CANVAS
    var named_rect := wanted != null
    var rect := _rect_of(wanted, canvas) if named_rect else _bounds_of(read)
    rect = rect.intersection(canvas)
    if rect.size.x <= 0 or rect.size.y <= 0:
        return {"ok": false, "error": 'the rectangle is empty on the canvas, and a rect is [x, y, w, h] or "canvas".'}
    var halo := maxi(0, int(spec.get("halo", DEFAULT_HALO)))
    var grown := rect.grow(halo)
    var extra: Variant = _inputs(document, spec.get("inputs", {}), rect, halo)
    if extra is String:
        return {"ok": false, "error": extra}
    # `SaCompute.run` only pushes an error on a binding it refuses and returns,
    # so the step asks first and answers the complaint, before a layer is added.
    var named := {cell.source_image: true, cell.target_image: true}
    named.merge(extra as Dictionary)
    var declared := GlobalShaderCompiler.binding_layout(cell.compute.shader_name)
    # A kernel with a loop declares the guard's buffer, which says after the
    # dispatch whether a loop was stopped, so it is bound here, zeroed each run.
    var guard: SaCompute.Buffer = null
    if SaCompute.BindingSlots.slot_of(declared, LoopGuard.INSTANCE, "buffer") >= 0:
        guard = SaCompute.Buffer.new(PackedByteArray([0, 0, 0, 0]))
        named[LoopGuard.INSTANCE] = true
    var complaint := SaCompute.BindingSlots.binding_complaint(declared, named)
    if not complaint.is_empty():
        return {"ok": false, "error": complaint}
    var into: SaLayer = named_into
    if into == null:
        # At 1.0 whatever the Double Resolution switch says, the density a
        # kernel's output is written at.
        into = SaLayerOps.new(document).add(&"", types, 1.0)
        into.name = into_name
    # A chunk stored below full resolution wants a resample nobody has written,
    # the edge `SaFilterApply` stops at too, so it is left out on either layer
    # and the verdict names it rather than a report.
    var held := _held_positions(read, rect)
    var skipped := _reduced(read, held)
    skipped.append_array(_reduced(into, _grid_positions(rect)))
    var positions: Array[Vector2i] = []
    for grid_pos in _grid_positions(rect) if named_rect else held:
        if not skipped.has(grid_pos):
            positions.append(grid_pos)
    var unmade := _unmade(into, positions)
    if not unmade.is_empty():
        return {"ok": false, "error": unmade}
    var format := _format_of(read)
    var source := _gathered(read, grown, document.canvas_size)
    var target := SaTexture.new(grown.size, format)
    target.clear(Color(0.0, 0.0, 0.0, 0.0))
    var bindings := {cell.source_image: source, cell.target_image: target}
    bindings.merge(extra as Dictionary)
    if guard != null:
        bindings[LoopGuard.INSTANCE] = guard
    _clock.begin()
    cell.compute.run(cell.name, bindings, cell.values(spec.get("params", {})), grown)
    _clock.end()
    # Read before the write, whose history step and the redraws it asks for
    # could flush the device and take the pair with them.
    var timed := _clock.answer()
    # Four bytes read back after a kernel step, which is no stroke, so hard
    # rule 1 does not reach it. A stopped kernel wrote a picture of loops cut
    # short, which no layer is given.
    if guard != null and LoopGuard.tripped(guard.read()):
        var stopped := {"ok": false, "stopped": true, "error": _stopped(cell.name)}
        stopped.merge(timed)
        return stopped
    var step_name := String(spec.get("step", "Kernel %s" % cell.name)) if bool(spec.get("history", true)) else ""
    var written := _write(document, into, target, grown.position, rect, positions, step_name)
    var answer := {
        "layer": String(read.name),
        "into": String(into.name),
        "in_place": _reads_target(document, into, read, spec.get("inputs", {})),
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "halo": halo,
        "chunks": written,
        "skipped": skipped.map(func(grid_pos: Vector2i) -> Array: return [grid_pos.x, grid_pos.y])
    }
    answer.merge(timed)
    return answer


## Why *cell*'s params block cannot be pushed, empty when it can. The size is
## the compiler's own for the block, its tail pad and `origin` and `extent`
## included, since the region is written into fields the block declares. The
## engine drops a larger block with a line in its log and runs nothing, so a
## step that went on would read back an untouched layer as if it had run.
static func _block_refusal(cell: CellKernel) -> String:
    var size := GlobalShaderCompiler.push_constant_bytes(cell.compute.shader_name)
    var limit := push_constant_limit()
    if size <= limit:
        return ""
    return (
        (
            "kernel %s needs %d bytes of push constants and a dispatch takes at most %d, so it did not run."
            + " Fewer or narrower params fit."
        )
        % [cell.name, size, limit]
    )


## The most bytes of push constants a dispatch takes: what the device reports,
## and never past the 128 the engine refuses beyond whatever the device says.
static func push_constant_limit() -> int:
    var device := RenderingServer.get_rendering_device()
    var reported := device.limit_get(RenderingDevice.LIMIT_MAX_PUSH_CONSTANT_SIZE) if device != null else 0
    return mini(int(reported), Dialect.PUSH_CONSTANT_LIMIT) if reported > 0 else Dialect.PUSH_CONSTANT_LIMIT


## What a kernel the loop guard stopped answers, its name first.
static func _stopped(kernel_name: String) -> String:
    return (
        (
            "kernel %s ran past its loop budget, %d turns of its loops in one pixel, and Sara stopped it, so nothing was"
            + " written. A loop whose condition never turns false, `while true:` among them, is the usual cause."
        )
        % [kernel_name, LoopGuard.BUDGET]
    )


## Why the kernel's result cannot go into *into*, empty when it can: the pixel
## step's refusals, and a format other than *read*'s, which no copy converts.
static func _into_refusal(into: SaLayer, read: SaLayer) -> String:
    var refused := SaScenarioPixels.refusal_of(into)
    if not refused.is_empty():
        return refused + "."
    if _format_of(into) != _format_of(read):
        return (
            "layer '%s' stores another format than '%s', so the kernel's result would not copy into it." % [into.name, read.name]
        )
    return ""


## Whether a run writing *into* reads it too: *read* is that layer, or one of the
## layers *inputs* names. A rerun of such a run starts from what the last wrote.
static func _reads_target(document: SaDocument, into: SaLayer, read: SaLayer, inputs: Variant) -> bool:
    if into == read:
        return true
    if not (inputs is Dictionary):
        return false
    for image: Variant in inputs:
        var ask: Variant = inputs[image]
        var named: Variant = ask.get("layer", null) if ask is Dictionary else ask
        if layer_of(document, named) == into:
            return true
    return false


## The layer *which* names, by its name or its index from the bottom of the
## stack, 0 the lowest, and the active layer for null. Null when nothing answers.
static func layer_of(document: SaDocument, which: Variant) -> SaLayer:
    if which == null:
        return document.active_layer
    var stack := SaLayerOps.new(document).layers()
    if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
        var index := int(which)
        return stack[index] if index >= 0 and index < stack.size() else null
    for layer in stack:
        if String(layer.name) == String(which):
            return layer
    return null


## The images beside `src` a request names, so one kernel reads
## several layers: `"inputs": {"src1": {"layer": "Sky", "at": [x, y]}}` binds
## the image `src1` to *rect*'s size of that layer from the corner `at`, the
## run's own corner when it is left out. Each is gathered GPU to GPU as `src` is,
## grown by the same *halo*, so its texels sit under the same `pixel`.
## Answers the bindings, or a String saying which input could not be found.
static func _inputs(document: SaDocument, named: Variant, rect: Rect2i, halo: int) -> Variant:
    var out: Dictionary = {}
    if not (named is Dictionary):
        return "inputs is a dictionary of image names to {layer, at}."
    for image: Variant in named:
        var ask: Dictionary = named[image] if named[image] is Dictionary else {"layer": named[image]}
        var layer := layer_of(document, ask.get("layer", null))
        if layer == null:
            return "no layer called %s for the input %s." % [ask.get("layer"), image]
        var at: Array = ask.get("at", [rect.position.x, rect.position.y])
        var from := Rect2i(Vector2i(int(at[0]), int(at[1])), rect.size).grow(halo)
        out[String(image)] = _gathered(layer, from, document.canvas_size)
    return out


## `[x, y, w, h]` as a rectangle, *canvas* for the word `"canvas"`, and empty
## when it is neither.
static func _rect_of(value: Variant, canvas: Rect2i) -> Rect2i:
    if value is String and value == SaScenarioPixels.CANVAS:
        return canvas
    if not (value is Array) or (value as Array).size() != 4:
        return Rect2i()
    var parts := value as Array
    return Rect2i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))


## The rectangle the chunks *layer* holds cover, empty when it holds none.
static func _bounds_of(layer: SaLayer) -> Rect2i:
    var bounds := Rect2i()
    for grid_pos: Vector2i in layer.chunks.keys():
        var covered := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        bounds = covered if bounds.size == Vector2i.ZERO else bounds.merge(covered)
    return bounds


## The depth the read layer stores colour at, which both textures share.
static func _format_of(layer: SaLayer) -> int:
    var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    return spec.format if spec != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT


## Every chunk grid position *rect* reaches.
static func _grid_positions(rect: Rect2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var first := Vector2i(floori(float(rect.position.x) / SaChunk.SIZE), floori(float(rect.position.y) / SaChunk.SIZE))
    var last := Vector2i(floori(float(rect.end.x - 1) / SaChunk.SIZE), floori(float(rect.end.y - 1) / SaChunk.SIZE))
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            out.append(Vector2i(x, y))
    return out


## The positions *layer* holds a chunk at that *rect* reaches.
static func _held_positions(layer: SaLayer, rect: Rect2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for grid_pos: Vector2i in _grid_positions(rect):
        if layer.chunks.get(grid_pos, null) != null:
            out.append(grid_pos)
    return out


## The positions among *positions* where *layer* holds a chunk stored at other
## than full resolution.
static func _reduced(layer: SaLayer, positions: Array[Vector2i]) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for grid_pos in positions:
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk != null and chunk.pixel_size() != SaChunk.SIZE:
            out.append(grid_pos)
    return out


## A refusal naming *layer*'s scale when one of *positions* holds no chunk and
## the chunk `_write` would make there is not a texel for a document pixel, or
## "" when every position can be written. A layer at 2.0 makes chunks 512
## texels across, and a copy by document pixels would put the result at half
## its size in the corner of each.
static func _unmade(layer: SaLayer, positions: Array[Vector2i]) -> String:
    var fresh := SaChunk.create([], layer.resolution_scale).pixel_size()
    if fresh == SaChunk.SIZE:
        return ""
    for grid_pos in positions:
        if layer.chunks.get(grid_pos, null) == null:
            return (
                "layer '%s' is at resolution %s, so chunk %s would be stored %d pixels across and the layer was left alone."
                % [layer.name, layer.resolution_scale, grid_pos, fresh]
            )
    return ""


## A texture covering *area* of *layer*, which may reach past the canvas of
## *canvas_size*: the full resolution chunks inside the canvas copied in GPU to
## GPU, transparent where the layer holds none, and every texel past the canvas
## the nearest one on it. Nothing is read back.
static func _gathered(layer: SaLayer, area: Rect2i, canvas_size: Vector2i) -> SaTexture:
    var texture := SaTexture.new(area.size, _format_of(layer))
    texture.clear(Color(0.0, 0.0, 0.0, 0.0))
    var on_canvas := area.intersection(Rect2i(Vector2i.ZERO, canvas_size))
    if on_canvas.size.x <= 0 or on_canvas.size.y <= 0:
        return texture
    var held := _held_positions(layer, on_canvas)
    var skipped := _reduced(layer, held)
    _gather(
        layer, on_canvas, held.filter(func(grid_pos: Vector2i) -> bool: return not skipped.has(grid_pos)), texture, area.position
    )
    if on_canvas != area:
        _clamp_past_canvas(texture, Rect2i(on_canvas.position - area.position, on_canvas.size))
    return texture


## The texels of *texture* outside *inside*, in its own pixels, filled with the
## nearest texel inside it, by the kernel the neighbourhood runner pads a chunk
## past the document's edge with.
static func _clamp_past_canvas(texture: SaTexture, inside: Rect2i) -> void:
    var clamp_edge := SaCompute.new("clamp_edge")
    clamp_edge.use_storage_format(texture.format)
    clamp_edge.set_texture(0, texture.rid)
    var values := PackedFloat32Array([0.0, 0.0, texture.size.x, texture.size.y])
    values.append_array(PackedFloat32Array([inside.position.x, inside.position.y, inside.size.x, inside.size.y]))
    clamp_edge.set_push_constant_float_array(values)
    clamp_edge.dispatch_kernel("clamp_edge", SaCompute.groups_for(texture.size.x), SaCompute.groups_for(texture.size.y), 1)


## *layer*'s chunks at *positions* copied into *texture*, whose first texel is
## the document pixel *first*, over the part of each inside *rect*, one
## `texture_copy` each.
static func _gather(layer: SaLayer, rect: Rect2i, positions: Array, texture: SaTexture, first: Vector2i) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in positions:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var field := chunk.field(SaFieldSpec.ALBEDO)
        if field == null:
            continue
        var covered := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(chunk.pixel_size(), chunk.pixel_size()))
        var overlap := covered.intersection(rect)
        var from := overlap.position - covered.position
        var to := overlap.position - first
        rd.texture_copy(
            field.rid,
            texture.rid,
            Vector3(from.x, from.y, 0),
            Vector3(to.x, to.y, 0),
            Vector3(overlap.size.x, overlap.size.y, 1),
            0,
            0,
            0,
            0
        )


## *result*, whose first texel is the document pixel *first*, copied over *rect*
## into *layer*'s chunks at *positions* as one history step called *step_name*,
## or as none when *step_name* is empty. Answers how many chunks it wrote.
##
## The write `SaFilterApply.apply` makes without a selection: each chunk is
## snapshotted before it is written, and a position that held none goes into the
## undo state as null so undo removes it again.
static func _write(
    document: SaDocument,
    layer: SaLayer,
    result: SaTexture,
    first: Vector2i,
    rect: Rect2i,
    positions: Array[Vector2i],
    step_name: String
) -> int:
    var rd := GlobalShaderCompiler.get_rd()
    var state: Dictionary = {}
    var touched: Array[Vector2i] = []
    for grid_pos in positions:
        var covered := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        var overlap := covered.intersection(rect)
        var local := Rect2i(overlap.position - covered.position, overlap.size)
        var existing: SaChunk = layer.chunks.get(grid_pos, null)
        var before: Variant = null
        if existing != null:
            before = SaChunkDelta.capture(existing, local)
            if before == null:
                before = layer.duplicate_chunk(grid_pos)
        state[grid_pos] = before
        var destination := layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        if destination == null:
            state.erase(grid_pos)
            continue
        var from := overlap.position - first
        rd.texture_copy(
            result.rid,
            destination.rid,
            Vector3(from.x, from.y, 0),
            Vector3(local.position.x, local.position.y, 0),
            Vector3(overlap.size.x, overlap.size.y, 1),
            0,
            0,
            0,
            0
        )
        layer.mark_unresolved(grid_pos)
        touched.append(grid_pos)
    if touched.is_empty():
        return 0
    if not step_name.is_empty():
        document.record_pixel_step(step_name, layer, state)
    document.invalidate_chunks(touched)
    document.modified = true
    document.document_changed.emit()
    return touched.size()
