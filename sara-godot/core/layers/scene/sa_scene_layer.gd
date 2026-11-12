## The live half of a scene layer: the offscreen viewport its scene renders
## into, and the copy of that viewport into the layer's chunks once a frame.
##
## A scene layer is a layer type whose descriptor names a `PackedScene` rather
## than a generator. The layer
## stores chunks like paint, so the compositor, the fold and the export read it
## as any layer with an opacity and a blend mode, and only who writes the
## chunks differs. This node is that writer. The registry attaches one as the
## layer's child when it gives a layer a scene type or rebinds a loaded one,
## because a viewport draws only inside the tree and the layer is where the
## document puts it there.
##
## **What a scene declares.** Its root may define `sara_dirty_rect() -> Rect2i`,
## the part of the viewport it changed since it was last asked, in document
## pixels, and an empty rectangle when nothing moved. It is asked once a
## frame, right after the renderer drew that frame, and the copy runs over that
## rectangle and nothing else in the next, which is hard rule 2 for a scene.
## Under a live transform the copy is drawn through the map where it shows,
## `SaLiveTransform.scene_copied`, so the scene keeps moving under a move, a scale or a turn. A
## root with no such method is a still picture: it is copied whole once, when
## it first draws and again when the document changes size, and never after.
##
## **Input.** The root may define `sara_pointer(phase: StringName, at: Vector2,
## pressure: float)`, and while its layer is active and the tool in hand is
## not pan or zoom, the tool machine hands it a left press, its drag and its
## release over the canvas, `&"press"`, `&"drag"` and `&"release"`, in document
## pixels and with the pen's pressure. A root without it gets nothing. It may
## define `sara_stroke(phase: StringName, at: Vector2, pressure: float, radius:
## float, color: Color)` as well, and is then handed a brush's stroke there, the
## same three phases with the brush's radius and its colour, at alpha 0 for an
## eraser, while Sara lays nothing on the layer.
##
## **Its parameters** are the root's properties, set by name from the layer's
## `scene_params`, so a scene exports what a painter may change and the `.sad`
## saves those values with the path instead of any pixel.
##
## The viewport is a float one in linear light, rule 5, and the copy is a
## kernel on the device the viewport draws with, rule 1: nothing comes back to
## the CPU. Chunks are allocated over the rectangles copied, rule 3.
class_name SaSceneLayer
extends Node

## The name the node takes under its layer, so a second attach finds the first.
const NODE_NAME := "SceneLayerViewport"
const SHADER_NAME := "scene_copy"

## The layer whose chunks this writes.
var layer: SaLayer = null
## The viewport the scene draws into, sized to the document.
var viewport: SubViewport = null
## The scene's root, or null when the path held no scene.
var root: Node = null

## The part of the viewport still to copy, in document pixels. The whole
## viewport when it has just been made or resized, then what the scene says.
var _pending: Rect2i = Rect2i()
## Whether the viewport has drawn since it was made, so a copy never reads a
## texture nothing has rendered into.
var _drawn: bool = false
var _compute: SaCompute = null


func _init(owner_layer: SaLayer) -> void:
    layer = owner_layer
    name = NODE_NAME
    viewport = SubViewport.new()
    viewport.name = "Viewport"
    viewport.transparent_bg = true
    viewport.use_hdr_2d = true
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    var path := layer.scene
    var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
    if packed == null:
        push_warning("SaSceneLayer: '%s' is not a scene, so its layer stays empty." % path)
        return
    root = packed.instantiate()
    viewport.add_child(root)
    apply_params()


## Gives *target* its viewport when it is a scene layer and has none yet, and
## answers the one it has. A layer with no live transform gets the one it
## rests at, `SaLiveTransform.rest_scene`, so the Transform tool can move it.
static func attach(target: SaLayer) -> SaSceneLayer:
    if target == null or not target.is_scene():
        return null
    SaLiveTransform.rest_scene(target)
    var existing := target.get_node_or_null(NODE_NAME) as SaSceneLayer
    if existing != null:
        return existing
    var stage := SaSceneLayer.new(target)
    target.add_child(stage)
    return stage


## Takes *target*'s viewport away, for a type whose module has gone. The layer
## keeps its chunks, its path and its parameters, the way a generated layer of
## an uninstalled module keeps its own.
static func detach(target: SaLayer) -> void:
    if target == null:
        return
    var existing := target.get_node_or_null(NODE_NAME)
    if existing != null:
        target.remove_child(existing)
        existing.queue_free()


## Sets the layer's parameters onto the scene's root, and copies the whole
## viewport again on its next frame, since a parameter may change any of it.
func apply_params() -> void:
    if root == null:
        return
    var params := layer.scene_params
    for key: String in params:
        root.set(key, params[key])
    _pending = Rect2i(Vector2i.ZERO, viewport.size)


## Sized as the layer enters its document, so the first frame the renderer
## draws is already the document's size and the copy after it has a picture.
func _ready() -> void:
    RenderingServer.frame_post_draw.connect(_on_frame_drawn)
    var document := _document()
    if document != null:
        _follow_size(document.canvas_size)


func _exit_tree() -> void:
    if RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
        RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)


func _process(_delta: float) -> void:
    step()


func _on_frame_drawn() -> void:
    _drawn = true
    _ask()


## Asks the root what it changed, right after a frame drew it. Asked in
## `_process`, a change input made would be copied before the renderer drew
## it, because a frame's input comes before every node's `_process`.
func _ask() -> void:
    if not is_instance_valid(root) or not root.has_method(&"sara_dirty_rect"):
        return
    var declared: Rect2i = root.call(&"sara_dirty_rect")
    if declared.has_area():
        _pending = declared if not _pending.has_area() else _pending.merge(declared)


## One frame's work: follow the document's size, and copy into the chunks
## what the scene said it changed before the last frame drew. Answers the
## regions it copied, grid position to chunk-local rectangle, which it has
## already handed to the document as dirty, through the layer's live
## transform where it shows.
func step() -> Dictionary[Vector2i, Rect2i]:
    var copied: Dictionary[Vector2i, Rect2i] = {}
    var document := _document()
    if document == null or root == null:
        return copied
    _follow_size(document.canvas_size)
    if not _drawn or not _pending.has_area():
        return copied
    var rect := _pending.intersection(Rect2i(Vector2i.ZERO, document.canvas_size))
    _pending = Rect2i()
    if not rect.has_area():
        return copied
    copied = _copy(rect, document.color_space)
    if not copied.is_empty():
        document.invalidate_chunk_regions(SaLiveTransform.scene_copied(document, layer, copied))
    return copied


## The document the layer is in, or null while it is in none.
func _document() -> SaDocument:
    return layer.get_parent() as SaDocument


## Gives the viewport the document's size, and when that changes it, waits
## for a frame drawn at the new size and then copies the whole of it.
func _follow_size(canvas_size: Vector2i) -> void:
    if viewport.size == canvas_size:
        return
    viewport.size = canvas_size
    _pending = Rect2i(Vector2i.ZERO, canvas_size)
    _drawn = false


## Copies *rect*, in document pixels, from the viewport into every chunk it
## touches, one dispatch a chunk.
func _copy(rect: Rect2i, space: SaColorSpace) -> Dictionary[Vector2i, Rect2i]:
    var copied: Dictionary[Vector2i, Rect2i] = {}
    var rd := GlobalShaderCompiler.get_rd()
    # The viewport's texture lives on the device the renderer draws with, and
    # a kernel on a device of its own could not read it.
    if rd == null or rd != RenderingServer.get_rendering_device():
        return copied
    var source := RenderingServer.texture_get_rd_texture(viewport.get_texture().get_rid())
    if not source.is_valid():
        return copied
    if _compute == null:
        _compute = SaCompute.new(SHADER_NAME)
    var tail := SaColorSpace.linear_srgb().to_conversion_push_constant(space)
    var first := Vector2i(floori(rect.position.x / float(SaChunk.SIZE)), floori(rect.position.y / float(SaChunk.SIZE)))
    var last := Vector2i(floori((rect.end.x - 1) / float(SaChunk.SIZE)), floori((rect.end.y - 1) / float(SaChunk.SIZE)))
    for grid_y in range(first.y, last.y + 1):
        for grid_x in range(first.x, last.x + 1):
            var grid_pos := Vector2i(grid_x, grid_y)
            var corner := grid_pos * SaChunk.SIZE
            var inside := rect.intersection(Rect2i(corner, Vector2i(SaChunk.SIZE, SaChunk.SIZE)))
            if not inside.has_area():
                continue
            var target := layer.get_or_create_field(grid_pos)
            # A scene is drawn at the document's own resolution, so a chunk
            # held at another is not one this copy can write texel for texel.
            if target == null or target.size.x != SaChunk.SIZE:
                continue
            var local := Rect2i(inside.position - corner, inside.size)
            _compute.use_storage_format(target.format)
            _compute.set_image("target", target)
            _compute.set_sampler("source", source, RenderingDevice.SAMPLER_FILTER_NEAREST)
            _compute.set_push_constant_float_array(push_constant(inside.position, local, tail))
            _compute.dispatch_kernel(SHADER_NAME, SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)
            copied[grid_pos] = local
    return copied


## The block `scene_copy.gmacs` reads: where the rectangle starts in the
## viewport and in the chunk, its size, and the conversion *tail* from linear
## sRGB into the document, 112 bytes.
static func push_constant(source_origin: Vector2i, local: Rect2i, tail: PackedFloat32Array) -> PackedFloat32Array:
    var packed := PackedFloat32Array(
        [
            float(source_origin.x),
            float(source_origin.y),
            float(local.position.x),
            float(local.position.y),
            float(local.size.x),
            float(local.size.y),
        ]
    )
    packed.append_array(tail)
    while packed.size() % 4 != 0:
        packed.append(0.0)
    return packed


## The chunks a save writes for *source*: none for a scene layer, whose pixels
## are its scene's and come back from the scene, and all of them for any other.
static func stored_chunks(source: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    var none: Dictionary[Vector2i, SaChunk] = {}
    return none if source.is_scene() else source.chunks


## Writes a scene layer's path and parameters into its `.sad` header *entry*,
## and nothing for any other layer. Each parameter is kept as Godot's own text
## for the value, so a colour or a vector comes back as the type it went out.
static func write_header(source: SaLayer, entry: Dictionary[String, Variant]) -> void:
    if not source.is_scene():
        return
    var params: Dictionary[String, Variant] = {}
    for key: String in source.scene_params:
        params[key] = var_to_str(source.scene_params[key])
    entry["scene"] = {"path": source.scene, "params": params}


## Reads back what [method write_header] wrote. A value that decodes to an
## object is dropped, because a file is not trusted to build one.
static func read_header(target: SaLayer, entry: Dictionary[String, Variant]) -> void:
    var saved := SaTyped.strings(entry.get("scene"))
    if saved.is_empty():
        return
    target.scene = SaTyped.text_at(saved, "path", "")
    var params := SaTyped.strings(saved.get("params"))
    for key: String in params:
        var value: Variant = str_to_var(str(params[key]))
        if typeof(value) != TYPE_OBJECT:
            target.scene_params[key] = value
