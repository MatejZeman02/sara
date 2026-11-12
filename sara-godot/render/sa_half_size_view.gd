## The view drawn at half the window's size while the canvas moves.
##
## **Where the half size is made.** Never in the composite: `SaEasel.output` is
## the document's size, not the window's, and the easel composites only the
## chunks the window reaches, so a pan composites the chunks it uncovers and
## nothing else. What does run at the window's size on every frame the view
## moves is the view's own draw: the canvas's material, the roll-off, the display
## fill and the proof, over every pixel the picture covers, and the checkerboard
## behind it. So the half size is made there.
##
## While the view moves the canvas draws nothing of its own. A `SubViewport` half
## the size of the canvas's host, in physical pixels, draws a mirror of it, the
## same texture under the same material over copies of the same background, and a
## `TextureRect` just before the canvas in its parent scales that up. The overlays
## the canvas carries, the axes, the ants and a tool's boxes, still draw at full
## size over it, because they are lines and cost next to nothing. Once the view
## has rested for [constant REST_FRAMES] frames the canvas draws itself again,
## which is the one full-size draw the rest pays for.
##
## **The canvas decides, this draws.** `SaCanvas` works out where the view is
## each frame, asks [method moved], and hides and shows its own draw. This class
## holds no canvas: what it is handed is a transform, a rectangle, a texture and
## the rectangles to copy, and what it owns is the viewport, the mirror in it
## and the proxy that shows it.
##
## **Never during a stroke.** The painter is judging the mark, so a stroke open
## on the document, a dab in the stroke buffer or an erase painting straight into
## the layer, keeps the full size, and a stroke that opens while the half size is
## up puts the full size back that frame. [method stroke_open] is the reading.
##
## Nothing here touches a texel: the document, the output and the composite are
## what they were, nothing is read back and nothing is dispatched, and only the
## draw that shows them is smaller. The mirror samples the output as the canvas
## does, so a float value reaches the material unclamped. Only the scaled-up
## picture is 8-bit, which the window it lands in already was.
class_name SaHalfSizeView
extends RefCounted

## How many frames the view has to stand still before the full size comes back.
## Four is a fifteenth of a second at the refresh rate the light mode caps a
## stroke at, short enough that the sharp picture is there by the time an eye
## has settled on it, and long enough that a pan made of motion events a frame
## or two apart does not flicker between the sizes.
const REST_FRAMES: int = 4

## What the step table answers with, the run log's prefix first.
const LINE: String = "SaCapture: half_size_view %s"

## Whether the half size is up. Read by the canvas, written here.
var active: bool = false
## Drawn where the canvas was, the half-size picture scaled up.
var _proxy: TextureRect = null
## Where the half-size picture is drawn, under the proxy.
var _viewport: SubViewport = null
## The canvas's texture and material, inside the viewport.
var _mirror: TextureRect = null
## Each background rectangle of the canvas's with the copy the mirror draws.
var _behind: Array[Dictionary] = []
## Where the view was last frame, and how many frames in a row it has stayed
## there. Empty until the first frame, which is no motion.
var _last_key: Array = []
var _still_frames: int = REST_FRAMES
## The area the picture fills in physical pixels, as of the last frame.
var _area: Rect2 = Rect2()
## Frames drawn at half size since the canvas was built, for a report.
var _frames_at_half: int = 0

## The measuring window of the `half_size_view` step: frames counted and the GPU
## time the root viewport and every half-size viewport reported for them.
static var _measuring: bool = false
static var _measured: Dictionary = {}
static var _root_rid: RID = RID()
static var _live: Array[WeakRef] = []


func _init() -> void:
    _live.append(weakref(self))


## Notes where the view is this frame, *to_pixels* the canvas's transform into
## the viewport's physical pixels and *area* the rectangle it fills there, and
## answers whether it has moved within the last [constant REST_FRAMES] frames.
## A pan, a zoom, a turn and a window resize all move one of the two.
func moved(to_pixels: Transform2D, area: Rect2) -> bool:
    _area = area
    var key := [to_pixels, area]
    if _last_key.is_empty():
        _last_key = key
    elif key != _last_key:
        _last_key = key
        _still_frames = 0
    else:
        _still_frames = mini(_still_frames + 1, REST_FRAMES)
    return _still_frames < REST_FRAMES


## Whether *document* has a stroke open: a dab in the stroke buffer, or an erase
## that paints straight into the layer. The same reading `SaAutosave` waits on.
static func stroke_open(document: SaDocument) -> bool:
    if document == null:
        return false
    if document.stroke_layer != null and not document.stroke_layer.chunks.is_empty():
        return true
    var transaction: RefCounted = document.stroke_transaction
    if transaction == null:
        return false
    # The transaction's class is an inner file of the document package, which
    # render may not name, so its flag is read by name.
    var direct: bool = transaction.get(&"direct_paint")
    return direct


## Starts drawing *texture* under *material* at half size, over copies of the
## *behind* rectangles, in a proxy put into *parent* at *index*, which is the
## canvas's place so the canvas's overlays still draw over it. The canvas hides
## its own draw beside this call.
func take_over(parent: Node, index: int, texture: Texture2D, material: Material, behind: Array[ColorRect]) -> void:
    _build(parent)
    parent.move_child(_proxy, mini(index, parent.get_child_count() - 1))
    _mirror.texture = texture
    _mirror.material = material
    for rect: ColorRect in behind:
        var copy := ColorRect.new()
        copy.show_behind_parent = true
        copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
        copy.position = rect.position
        copy.size = rect.size
        copy.color = rect.color
        copy.visible = rect.visible
        # A copy of the material, because the checkerboard measures its squares
        # in screen pixels and the viewport's pixels are half the size.
        copy.material = rect.material.duplicate() if rect.material is ShaderMaterial else rect.material
        _mirror.add_child(copy)
        _behind.append({"rect": rect, "copy": copy})
    _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _proxy.visible = true
    active = true


## Fits the proxy to *host_rect*, in its parent's coordinates, and the viewport
## to half of the area [method moved] was last handed, and draws the mirror the
## way *to_pixels* places the canvas, scaled by what half of the area comes to.
## *pixels_per_texel* is the canvas's own, for the mirror's filter.
func place(host_rect: Rect2, canvas_size: Vector2, to_pixels: Transform2D, pixels_per_texel: float) -> void:
    if not active or not _area.has_area():
        return
    _frames_at_half += 1
    _proxy.position = host_rect.position
    _proxy.size = host_rect.size
    var half := Vector2i(maxi(1, ceili(_area.size.x / 2.0)), maxi(1, ceili(_area.size.y / 2.0)))
    if _viewport.size != half:
        _viewport.size = half
    var squeeze := Vector2(half) / _area.size
    _viewport.canvas_transform = Transform2D(0.0, squeeze, 0.0, -_area.position * squeeze) * to_pixels
    _mirror.size = canvas_size
    _mirror.texture_filter = SaCanvas.filter_for(pixels_per_texel * squeeze.x)
    for pair: Dictionary in _behind:
        var rect: ColorRect = pair["rect"]
        var copied: ColorRect = pair["copy"]
        var source := rect.material as ShaderMaterial
        var copy := copied.material as ShaderMaterial
        if source == null or copy == null or source == copy:
            continue
        var squares: Variant = source.get_shader_parameter("checker_size")
        if squares != null:
            var checker: float = squares
            copy.set_shader_parameter("checker_size", checker * squeeze.x)


## Stops drawing at half size and lets go of the texture. The canvas shows its
## own draw beside this call, and calls it before it rebinds its texture, so a
## resize during a pan binds the new output rather than drawing the old one.
func rest() -> void:
    if not active:
        return
    active = false
    _proxy.visible = false
    _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    for pair: Dictionary in _behind:
        var copied: ColorRect = pair["copy"]
        copied.queue_free()
    _behind.clear()
    _mirror.texture = null
    _mirror.material = null


## Stops and frees the nodes, for a canvas leaving the tree. The mirror lets go
## of the output's texture first, the order `SaCanvas._cleanup_resources` keeps
## for its own.
func release() -> void:
    rest()
    if is_instance_valid(_proxy):
        _proxy.queue_free()
    _proxy = null
    _viewport = null
    _mirror = null
    _last_key = []
    _still_frames = REST_FRAMES


## What the dump and a suite read: whether the half size is up, and the size the
## picture is drawn at against the size of the area it fills, both in physical
## pixels.
func report() -> Dictionary:
    var drawn := Vector2(_viewport.size) if active else _area.size
    return {
        "setting": SaSettings.half_size_view_while_moving,
        "active": active,
        "drawn_size": [roundi(drawn.x), roundi(drawn.y)],
        "full_size": [roundi(_area.size.x), roundi(_area.size.y)],
        "still_frames": _still_frames,
        "frames_at_half": _frames_at_half,
    }


## Builds the proxy and the viewport the first time they are needed, and again
## when the canvas has moved to another parent.
func _build(parent: Node) -> void:
    if is_instance_valid(_proxy) and _proxy.get_parent() == parent:
        return
    if is_instance_valid(_proxy):
        _proxy.queue_free()
    _viewport = SubViewport.new()
    _viewport.name = "HalfSizeViewport"
    _viewport.transparent_bg = true
    _viewport.disable_3d = true
    _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
    _mirror = TextureRect.new()
    _mirror.name = "Mirror"
    _mirror.stretch_mode = TextureRect.STRETCH_KEEP
    _mirror.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _viewport.add_child(_mirror)

    _proxy = TextureRect.new()
    _proxy.name = "HalfSizeView"
    _proxy.visible = false
    _proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _proxy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _proxy.stretch_mode = TextureRect.STRETCH_SCALE
    _proxy.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    # The viewport is cleared to transparent and the picture blended onto it, so
    # what it holds is premultiplied, and a plain blend would darken the edge of
    # the document a second time.
    var blend := CanvasItemMaterial.new()
    blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
    _proxy.material = blend
    _proxy.add_child(_viewport)
    _proxy.texture = _viewport.get_texture()
    parent.add_child(_proxy)


## The `half_size_view` step: `"begin"` opens a measuring window, `"end"` closes
## it and answers the frames drawn and the GPU time spent drawing them, the
## half-size viewports' share of it apart, `"read"`
## answers what each live canvas reports. The GPU time is what the rendering
## server measured for the root viewport and every half-size viewport, the view's
## draw, which the `perf` window's compute timing does not see.
static func capture(tree: SceneTree, spec: Variant) -> String:
    match str(spec):
        "begin":
            _measuring = true
            _measured = {"frames": 0, "gpu_msec": 0.0, "half_gpu_msec": 0.0, "frames_at_half": 0}
            _root_rid = tree.root.get_viewport_rid()
            RenderingServer.viewport_set_measure_render_time(_root_rid, true)
            if not RenderingServer.frame_post_draw.is_connected(_count_frame):
                RenderingServer.frame_post_draw.connect(_count_frame)
            return LINE % JSON.stringify({"window": "open"})
        "end":
            _measuring = false
            if RenderingServer.frame_post_draw.is_connected(_count_frame):
                RenderingServer.frame_post_draw.disconnect(_count_frame)
            var out := _measured.duplicate()
            var counted: int = out.get("frames", 0)
            var gpu_msec: float = out.get("gpu_msec", 0.0)
            var frames := maxi(1, counted)
            out["gpu_msec_per_frame"] = gpu_msec / frames
            out["setting"] = SaSettings.half_size_view_while_moving
            return LINE % JSON.stringify(out)
    var views: Array = []
    for held: WeakRef in _live:
        var view: SaHalfSizeView = held.get_ref()
        if view != null:
            views.append(view.report())
    return LINE % JSON.stringify({"views": views})


static func _count_frame() -> void:
    if not _measuring:
        return
    var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_root_rid)
    var half_gpu := 0.0
    var at_half := false
    var kept: Array[WeakRef] = []
    for held: WeakRef in _live:
        var view: SaHalfSizeView = held.get_ref()
        if view == null:
            continue
        kept.append(held)
        if view.active and is_instance_valid(view._viewport):
            half_gpu += RenderingServer.viewport_get_measured_render_time_gpu(view._viewport.get_viewport_rid())
            at_half = true
    _live = kept
    var frames: int = _measured["frames"]
    var gpu_msec: float = _measured["gpu_msec"]
    var half_gpu_msec: float = _measured["half_gpu_msec"]
    var frames_at_half: int = _measured["frames_at_half"]
    _measured["frames"] = frames + 1
    _measured["gpu_msec"] = gpu_msec + gpu + half_gpu
    _measured["half_gpu_msec"] = half_gpu_msec + half_gpu
    if at_half:
        _measured["frames_at_half"] = frames_at_half + 1
