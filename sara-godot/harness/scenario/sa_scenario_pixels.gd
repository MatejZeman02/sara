## The `read_pixels` and `write_pixels` steps: a layer's pixels
## cross the door as a NumPy `.npy` file of `float32`, shape `(h, w, 4)`, so a
## notebook reads a layer as an array and writes one back as one undo step.
##
## **A file and not base64 in the dump**, because a dump holding the array
## takes seconds to parse. A file is read by NumPy
## in one call, costs no encoding and keeps the verdict line one short line.
##
## **A readback, and so an explicit command.** Hard rule 1 keeps the canvas in
## VRAM during a stroke. A read here is asked for by name, once, never inside a
## stroke, and goes through the export path's own float readback, the way the
## filter door's `read_pixels` does, so this file calls no readback of its own.
## The small form, `max_size`, reads back only what `harness/sa_layer_preview.gd`
## made of the layer on the graphics card.
## A write goes the other way: one upload into one texture, then a copy per
## chunk GPU to GPU, which is the shape [SaFilterApply] writes in, and which
## `harness/door/sa_pixel_landing.gd` does with what undo keeps of it.
##
## **Nothing clamps** either way (hard rule 5). The body of the file is the
## bytes of an `RGBAF` image, so a value above one leaves as that value and an
## array holding one comes back into the layer as it was sent.
##
## A layer is named by its name or by its index from the bottom of the stack, 0
## the lowest, and a rectangle is `[x, y, w, h]` in document pixels. Every answer is one
## verdict line, `SaCapture: <step> <json>`, and a refusal is the same line with
## an `error` saying which, with the layer left alone.
##
## The arithmetic is static and takes the document and the folder, so a suite
## grades it with no running app. The two instance methods only find the main
## document and print.
##
## Reached by path from the step table rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaScenarioPixels
extends RefCounted

## The canvas driver, for the main document.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The export path's float readback, by script rather than through the autoload
## of the same name, for the reason `core/api/filter/sa_filter_pixels.gd` gives.
const SaExportScript = preload("res://core/export/sa_export.gd")

## What a write records when the request names no step.
const DEFAULT_STEP_NAME := "Write Pixels"

## What a write that adds its layer records when the request names no step.
const ADD_STEP_NAME := "Add Layer"

## What a read's `rect` says to read the whole canvas.
const CANVAS := "canvas"

## The small form of a read, made on the graphics card.
const LayerPreview := preload("res://harness/sa_layer_preview.gd")

## The `.npy` format the pixels cross the door in.
const Npy := preload("res://harness/sa_npy.gd")

## Where a write's array lands, and what undo keeps of it.
const Landing := preload("res://harness/door/sa_pixel_landing.gd")

## The float readbacks reads made since the app started, which a suite counts.
static var float_reads := 0

## The run, read for its tree and for the folder a read writes into.
var _run: CaptureRun = null

## What this session's writes without history overwrote, until a write with
## history records it as one step.
var _held := Landing.Held.new()


func _init(run: CaptureRun) -> void:
    _run = run


## Reads texels into a file: the layer's texels over the rectangle are written as
## a `.npy` file, and the answer is its path, shape and rectangle,
## `{"read_pixels": {"layer": "Paint", "rect": [0, 0, 512, 512], "file":
## "paint.npy"}}`. With no `rect` the layer's allocated bounds are read, and a
## layer that holds nothing answers an array of shape `(0, 0, 4)`. `"rect":
## "canvas"` reads the whole canvas whatever the layer holds, so a client that
## does not know the document's size need not ask for it. `file` is a
## name in the session's folder or an absolute path, and defaults to one named
## after the layer's index. The answer carries `ms`, what the read took from the
## first copy to the file closing.
##
## **`max_size` asks for the small form**: `uint8` of shape
## `(h, w, 4)`, the long side at most `max_size`, as [code]LayerPreview[/code]
## makes it. The answer says `dtype`, and `from`, the size the read was made from.
##
## **The `path` is the machine's own.** With no `--capture-out` the session's
## folder is `user://captures`, which only Godot can open, and `np.load` given
## that raised `Errno 22` on Windows, so the answer is globalised and NumPy opens
## what it names.
func read(spec: Dictionary) -> Dictionary:
    var answer := read_into(_document(), spec, _run.out_dir)
    print("SaCapture: read_pixels %s" % JSON.stringify(answer))
    return answer


## Writes a file into a layer: over the rectangle as one undo step called
## `name`, a relative `file` read from the run's folder and never the caller's,
## `{"write_pixels": {"layer": 1, "rect": [256, 0, 64, 64], "file":
## "/tmp/a.npy", "name": "Fourier"}}`. A chunk is allocated only where the array
## holds a texel that is not transparent black, and one the layer already had is
## written whatever the array holds there. Answers the chunks it wrote, in
## `path` the absolute path of the file it read, and in `ms` what the write took from opening the file to the
## last copy.
## `"new_layer": "Spectrum"` in place of `layer` adds the layer and fills it as
## the one step, or writes into the layer of that name when there is one.
##
## **`"history": false` records no step**, for the writes of a slider's drag.
## What each overwrote is kept, and the next write with history on records all
## of it as its one step, the write a client sends when the slider is let go. A
## write that adds its layer records the add whatever it says, since a layer
## with no step would be one undo could not take away.
func write(spec: Dictionary) -> Dictionary:
    var answer := write_from(_document(), spec, _run.out_dir, _held)
    print("SaCapture: write_pixels %s" % JSON.stringify(answer))
    return answer


## The read under [method read], for *document*, writing into *folder*.
static func read_into(document: SaDocument, spec: Dictionary, folder: String) -> Dictionary:
    var started := Time.get_ticks_usec()
    var layer: Variant = layer_of(document, spec.get("layer", null))
    if layer is String:
        return {"error": layer}
    var target: SaLayer = layer
    var rect := _allocated_bounds(target)
    if spec.has("rect"):
        var asked: Variant = _rect_of(spec["rect"], document)
        if asked is String:
            return {"error": asked}
        rect = asked
    var small := spec.has("max_size")
    var longest: Variant = _max_size_of(spec["max_size"]) if small else 0
    if longest is String:
        return {"error": longest}
    var odd := _odd_chunk(target, rect)
    if not odd.is_empty():
        return {"error": odd}
    var path := _path_in(folder, String(spec.get("file", "read_pixels-%d.npy" % _index_of(document, target))))
    var size := LayerPreview.size_for(rect.size, int(longest)) if small else rect.size
    var body := PackedByteArray()
    if rect.size.x > 0 and rect.size.y > 0:
        var texture := assembled(target, rect)
        if texture != null:
            body = LayerPreview.bytes_of(texture, size) if small else _float_body(texture)
        if body.is_empty():
            return {"error": "the layer's pixels could not be read back"}
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return {"error": "%s could not be written: %s" % [path, error_string(FileAccess.get_open_error())]}
    file.store_buffer(Npy.header(size, Npy.BYTES if small else Npy.FLOATS))
    file.store_buffer(body)
    file.close()
    return {
        "layer": String(target.name),
        "path": ProjectSettings.globalize_path(path),
        "shape": [size.y, size.x, 4],
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "dtype": "uint8" if small else "float32",
        "from": [rect.size.x, rect.size.y],
        "ms": snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.01),
    }


## The write under [method write], for *document*, a relative `file` read from
## *folder*, and *held* keeping what writes without history overwrote. With no
## *held* such a write keeps nothing, which is a suite's write and no session's.
##
## With `new_layer` naming a layer in place of `layer`, the write adds that
## layer above the active one first, and the add and its pixels are the one
## step Undo takes away whole, called `name` or Add Layer. The
## request is checked before the layer is added, so a refusal adds nothing.
## A layer of that name already there is written instead and made active, by
## the rule of [method named_target], so a rerun of the cell leaves one.
static func write_from(document: SaDocument, spec: Dictionary, folder: String, held: Landing.Held = null) -> Dictionary:
    var started := Time.get_ticks_usec()
    var adding := spec.has("new_layer")
    var target: SaLayer = null
    if adding:
        if document == null:
            return {"error": "there is no document"}
        if String(spec["new_layer"]).is_empty():
            return {"error": "a new layer needs a name"}
        target = named_target(document, String(spec["new_layer"]))
        if target != null:
            adding = false
            var kept_refused := refusal_of(target)
            if not kept_refused.is_empty():
                return {"error": kept_refused}
    else:
        var layer: Variant = layer_of(document, spec.get("layer", null))
        if layer is String:
            return {"error": layer}
        target = layer
        var refused := refusal_of(target)
        if not refused.is_empty():
            return {"error": refused}
    if not spec.has("rect"):
        return {"error": "a write names the rectangle it lands on"}
    var asked: Variant = _rect_of(spec["rect"])
    if asked is String:
        return {"error": asked}
    var rect: Rect2i = asked
    if rect.size.x <= 0 or rect.size.y <= 0:
        return {"error": "the rectangle %s is empty" % [spec["rect"]]}
    var path := _path_in(folder, String(spec.get("file", "")))
    var machine := ProjectSettings.globalize_path(path)
    if not path.is_empty() and not FileAccess.file_exists(path):
        # A relative name is a name in the run's folder, not the caller's, and
        # saying both spares a caller a search for the file.
        return {
            "error":
            (
                "%s is not there, and the run's folder, which a relative name is read from, is %s"
                % [machine, ProjectSettings.globalize_path(folder)]
            )
        }
    var loaded: Variant = Npy.read(path)
    if loaded is String:
        return {"error": loaded}
    var image: Image = loaded
    if image.get_size() != rect.size:
        return {
            "error":
            (
                "the array is (%d, %d, 4) and the rectangle wants (%d, %d, 4), so the layer was left alone"
                % [image.get_height(), image.get_width(), rect.size.y, rect.size.x]
            )
        }
    if adding:
        target = _added_quietly(document, String(spec["new_layer"]))
    elif spec.has("new_layer") and document.active_layer != target:
        # Asked only when it is not already, because making a layer active
        # rebuilds the caches and redraws every chunk, 13 ms of each write of a
        # drag at 1920 by 1080 that was the same layer every time.
        document.set_active_layer(target)
    var odd := _odd_chunk(target, rect, true)
    if not odd.is_empty():
        return {"error": odd}
    var step_name := String(spec.get("name", ADD_STEP_NAME if adding else DEFAULT_STEP_NAME))
    var recording := bool(spec.get("history", true))
    var kept: Dictionary = {}
    if held != null and not adding:
        kept = held.take(document, target) if recording else held.of(document, target)
    var written := Landing.land(target, rect, image, _grid_positions(target, rect), kept)
    if recording and not adding and not kept.is_empty():
        document.record_pixel_step(step_name, target, kept)
    if not written.is_empty():
        document.invalidate_chunks(written)
        document.modified = true
        document.document_changed.emit()
    if adding:
        SaLayerOps.new(document).commit_added(step_name, [target] as Array[SaLayer])
    var chunks: Array = []
    for grid_pos: Vector2i in written:
        chunks.append([grid_pos.x, grid_pos.y])
    return {
        "layer": String(target.name),
        "path": machine,
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "chunks": chunks,
        "ms": snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.01),
    }


## A plain layer called *layer_name* put above the active one, in the group
## that one is in, the way `SaLayerOps.add` puts it but with no step of its
## own, so the write that fills it records the add and the pixels together
## through `SaLayerOps.commit_added`, the door an import of layers uses.
static func _added_quietly(document: SaDocument, layer_name: String) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    layer.schema = SaFieldSpec.schema_for_space(document.color_space)
    var active := document.active_layer
    var index := active.get_index() + 1 if active != null else document.get_child_count()
    layer.group = SaLayerStack.parent_of(active)
    document.add_child(layer)
    document.move_child(layer, index)
    document.set_active_layer(layer)
    return layer


## The layer a door step names as its target, *layer_name*, when the stack
## already holds one of that name, and null when the step is to make it.
##
## The one rule every named target follows, `new_layer` here, the layer step's
## `add`, the kernel's `into` and the import's file name: a layer of that name is
## used again, and one is made above the active layer only when there is none.
## A notebook cell is run again and again, and each target misbehaves its own
## way on the second run without this: a node named before it is added gets
## Godot's fallback name, a rename after adding gets "name2", the kernel refuses
## an `into` that does not exist, and the import adds "color_chart 2". A group or a locked layer of that name is still the one
## named, and the step refuses it as [method refusal_of] says.
static func named_target(document: SaDocument, layer_name: String) -> SaLayer:
    if document == null or layer_name.is_empty():
        return null
    for layer: SaLayer in SaLayerOps.new(document).layers():
        if layer.shown_name() == layer_name or String(layer.name) == layer_name:
            return layer
    return null


## The layer *key* names, or a String saying why none: a name, or an index from
## the bottom of the stack with 0 the lowest.
## Why a door step that writes pixels leaves *layer* alone, empty when a
## painter could paint it. A group is named before the lock, because a group
## reports itself locked, and a generated layer stores no chunk the compositor
## reads, so a write there would record a step that shows nothing.
## The kernel driver asks the same question of the layer it writes.
static func refusal_of(layer: SaLayer) -> String:
    if layer.is_group:
        return "layer '%s' is a group and holds no paint, so it was left alone" % layer.name
    if layer.is_locked:
        return "layer '%s' is locked, so it was left alone" % layer.name
    if layer.is_generated():
        return "layer '%s' is drawn by its generator and holds no paint, so it was left alone" % layer.name
    return ""


## The layer *key* names: a name, or an index from the bottom of the stack, and
## the active layer for no key at all. A String saying why when there is none,
## which is what the `read_pixels` and `write_pixels` steps and the `layer`
## step's `of` all refuse with.
static func layer_of(document: SaDocument, key: Variant) -> Variant:
    if document == null:
        return "there is no document"
    var stack := SaLayerOps.new(document).layers()
    if key == null:
        if document.active_layer == null:
            return "there is no active layer"
        return document.active_layer
    if key is int or key is float:
        var index := int(key)
        if index < 0 or index >= stack.size():
            return "there is no layer %d, the stack holds %d" % [index, stack.size()]
        return stack[index]
    for layer: SaLayer in stack:
        if String(layer.name) == String(key):
            return layer
    return "there is no layer named '%s'" % key


static func _index_of(document: SaDocument, layer: SaLayer) -> int:
    return SaLayerOps.new(document).layers().find(layer)


## `[x, y, w, h]` as a rectangle, or a String saying why it is not one. With a
## *document*, `"canvas"` is the whole of it.
static func _rect_of(value: Variant, document: SaDocument = null) -> Variant:
    if document != null and value is String and value == CANVAS:
        return Rect2i(Vector2i.ZERO, document.canvas_size)
    if not (value is Array) or (value as Array).size() != 4:
        return "a rectangle is [x, y, w, h], not %s" % [value]
    for part: Variant in value:
        if not (part is int or part is float):
            return "a rectangle is four numbers, not %s" % [value]
    return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))


## The union of the rectangles *layer*'s chunks cover, empty for none.
static func _allocated_bounds(layer: SaLayer) -> Rect2i:
    var bounds := Rect2i()
    var first := true
    for grid_pos: Vector2i in layer.chunks.keys():
        var covered := Rect2i(grid_pos * layer.CHUNK_SIZE, Vector2i(layer.CHUNK_SIZE, layer.CHUNK_SIZE))
        bounds = covered if first else bounds.merge(covered)
        first = false
    return bounds


## A refusal naming the first chunk under *rect* stored at another resolution
## than the grid, or "" when there is none. A copy moves texels one for one,
## and a chunk stored at another size wants a resample nobody has written yet,
## so the whole request is refused rather than half of it answered. A write
## passes *creating*, because where the layer holds no chunk it would make one
## at the layer's own scale, 512 texels across at 2.0, and a copy by document
## pixels would put the array at half its size in the corner.
static func _odd_chunk(layer: SaLayer, rect: Rect2i, creating: bool = false) -> String:
    var fresh := SaChunk.create([], layer.resolution_scale).pixel_size()
    for grid_pos: Vector2i in _grid_positions(layer, rect):
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk == null and creating and fresh != layer.CHUNK_SIZE:
            return (
                "layer '%s' is at resolution %s, so chunk %s would be stored %d pixels across and the layer was left alone"
                % [layer.name, layer.resolution_scale, grid_pos, fresh]
            )
        if chunk != null and chunk.pixel_size() != layer.CHUNK_SIZE:
            return "chunk %s is stored %d pixels across, so the layer was left alone" % [grid_pos, chunk.pixel_size()]
    return ""


## Every chunk grid position *rect* reaches.
static func _grid_positions(layer: SaLayer, rect: Rect2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if rect.size.x <= 0 or rect.size.y <= 0:
        return out
    var edge := float(layer.CHUNK_SIZE)
    var first := Vector2i(floori(rect.position.x / edge), floori(rect.position.y / edge))
    var last := Vector2i(floori((rect.end.x - 1) / edge), floori((rect.end.y - 1) / edge))
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            out.append(Vector2i(x, y))
    return out


## A `max_size` as a whole number above zero, JSON's 512.0 being 512, or why not.
static func _max_size_of(value: Variant) -> Variant:
    if (value is int or value is float) and float(value) == floorf(float(value)) and float(value) >= 1.0:
        return int(value)
    return "max_size is a whole number of texels above zero, not %s" % JSON.stringify(value)


## *texture* as the bytes of an `RGBAF` image, the one float readback this
## file makes, counted in [member float_reads].
static func _float_body(texture: SaTexture) -> PackedByteArray:
    float_reads += 1
    var image := SaExportScript.get_texture_image_float(texture)
    if image == null:
        return PackedByteArray()
    if image.get_format() != Image.FORMAT_RGBAF:
        image.convert(Image.FORMAT_RGBAF)
    return image.get_data()


## *layer*'s albedo over *rect* in one texture at the layer's depth: one copy per
## chunk into one cleared texture, all of it on the graphics card.
static func assembled(layer: SaLayer, rect: Rect2i) -> SaTexture:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return null
    var texture := SaTexture.new(rect.size, _format_of(layer))
    # A fresh texture is undefined rather than blank, and every texel no chunk
    # covers is one the loop never writes, so a read with no paint reads zeros.
    texture.clear(Color(0.0, 0.0, 0.0, 0.0))
    for grid_pos: Vector2i in _grid_positions(layer, rect):
        var source := layer.get_field(grid_pos)
        if source == null:
            continue
        var covered := Rect2i(grid_pos * layer.CHUNK_SIZE, Vector2i(layer.CHUNK_SIZE, layer.CHUNK_SIZE))
        var overlap := covered.intersection(rect)
        var from := overlap.position - covered.position
        var to := overlap.position - rect.position
        rd.texture_copy(
            source.rid,
            texture.rid,
            Vector3(from.x, from.y, 0),
            Vector3(to.x, to.y, 0),
            Vector3(overlap.size.x, overlap.size.y, 1),
            0,
            0,
            0,
            0
        )
    return texture


static func _format_of(layer: SaLayer) -> int:
    var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    return spec.format if spec != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT


## *name* in *folder* when it is relative, itself when it is absolute.
static func _path_in(folder: String, name: String) -> String:
    return name if name.is_absolute_path() else folder.path_join(name)


func _document() -> SaDocument:
    var canvas := CanvasDriver.main_canvas()
    return canvas.document if canvas != null else null
