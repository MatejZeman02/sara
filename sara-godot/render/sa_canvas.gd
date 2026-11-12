## The canvas view.
##
## A TextureRect that displays a SaEasel's composited output. It owns no
## document data: the easel does, so a document can be built and composited
## with no UI at all. The document/compositor/output properties below forward to
## the easel so existing call sites keep reading `canvas.document`.
extends TextureRect

class_name SaCanvas

# --- CONFIGURATION ---
@export var canvas_size := Vector2i(1920, 1080)

# --- VARIABLES ---
var easel: SaEasel
## View-time highlight compression. Never touches `easel.output`, so the
## eyedropper, export and stroke commit all keep reading true values.
var tonemap_shader: Shader = preload("res://shaders/canvas/tonemap.gdshader")

## The view transforms: which mode is showing and which toggles are on. Bound
## by main once the registries exist. A canvas without one, which is every
## test's and the scratchpad's, shows the picture with the rolloff from
## Preferences and nothing else.
var _view_transforms: SaViewTransformRegistry = null

## The document being displayed. Owned by the easel.
var document: SaDocument:
    get:
        return easel.document if easel != null else null

var compositor: SaCompositor:
    get:
        return easel.compositor if easel != null else null

## The flattened output texture this view is bound to.
var canvas: SaTexture:
    get:
        return easel.output if easel != null else null

## Radius of the software brush ring in viewport pixels, or a negative value when
## the active tool does not want one. Written by ToolMachine on every tool switch
## and brush-size change. Read by the CursorOverlay of the window this canvas is in.
var cursor_ring_radius: float = -1.0

## The shape the ring is drawn as, in units of `cursor_ring_radius`, or empty
## for the circle every tool but an image-tipped brush wants. Written by
## ToolMachine beside the radius and read by the same CursorOverlay, so the two
## cannot get out of step: a shape without a radius is nothing to scale it by.
var cursor_outline: PackedVector2Array = PackedVector2Array()

## Every live canvas. The scratchpad in the info docker is a second one, so the
## cursor code must ask "which canvas is under the pointer" rather than assuming.
##
## Here rather than on `SaCursorPolicy`: files outside `render/` read it as
## "every canvas there is", which has nothing to do with the pointer. They go
## through `live_canvases()`, so the list is private to the two functions below
## and the loops in the policy, and no reader repeats the liveness check this
## class already makes.
static var _live_canvases: Array = []

## The relief this view's material samples, `SaRelief.texture`, held so
## its RID outlives the Texture2DRD bound to it, and the one it replaced, kept
## for a frame for the reason `SaEasel` keeps a displaced output.
var _relief_source: SaTexture = null
var _relief_displaced: SaTexture = null

## What the interface draws over a canvas, as factories the boot registers
## before the first canvas is built and takes off again when the window that
## registered them is freed. `render` names nothing under `ui`, so the
## symmetry axes, the selection's ants and the grid arrive here as
## `func(canvas: SaCanvas)` and every canvas calls each one in `_ready`, the
## scratchpads too. A canvas built with none registered, which is most suites',
## shows its picture bare.
static var overlay_factories: Array[Callable] = []

## The same for the window-space control of a main surface, as
## `func(host: Control, canvas: SaCanvas)`. The quick mask's banner and the
## environment view are the two today, and an embedded surface calls none,
## because a scratchpad has no selection a painter edits.
static var surface_overlay_factories: Array[Callable] = []


## runs once on start
func _ready() -> void:
    assert(canvas_size.x > 0 and canvas_size.y > 0, "Canvas size must be positive")

    stretch_mode = TextureRect.STRETCH_KEEP
    size = canvas_size
    pivot_offset = Vector2.ZERO
    expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    mouse_filter = Control.MOUSE_FILTER_PASS
    # After the easel, which is this node's child and would otherwise come
    # second: `view_changed` asks whether a composite happened this frame,
    # and the answer has to be read after the easel's own `_process`.
    process_priority = 1

    _center_canvas()
    _half_size = SaHalfSizeView.new()
    get_viewport().size_changed.connect(_on_viewport_resized)
    EventBus.document_resized.connect(_on_document_resized)
    _content_scale = get_window().content_scale_factor
    EventBus.ui_scale_changed.connect(_on_ui_scale_changed)

    ensure_easel()
    easel.shown_rect = SaWrapRepeat.attach_to(self).folded
    easel.pixels_per_texel = pixels_per_texel
    _redraw_on_return = SaRedrawOnReturn.new(queue_redraw, _window_can_draw, func() -> int: return easel.composite_count)
    add_child(_redraw_on_return)

    var output_texture := Texture2DRD.new()
    output_texture.texture_rd_rid = easel.output.rid
    self.texture = output_texture

    # --- TONEMAPPER ---
    sync_tonemap()

    _behind = SaGroundBeyond.place_under(self, canvas_size)
    # After the two drawn behind the canvas and before every overlay.
    _detail = SaDetailDraw.new()
    add_child(_detail.holder)

    # Axes and, later, marching ants: a child, so it follows the view's zoom,
    # pan and rotation and draws in document pixels.
    for factory in overlay_factories:
        factory.call(self)

    request_composite()

    # The window's CursorOverlay finds this canvas through the registry. Attaching
    # the overlay itself is left to the UI layer, so render/ does not depend on ui/.
    if not _live_canvases.has(self):
        _live_canvases.append(self)


## Registers *factory*, `func(canvas: SaCanvas)`, to be called by every canvas
## built from now on. Once, however often the boot runs, and true when this
## call is the one that added it. The lists are static and outlive whoever
## filled them, so the caller that added a factory takes it off again with
## `remove_overlay_factory` when it goes.
static func add_overlay_factory(factory: Callable) -> bool:
    if overlay_factories.has(factory):
        return false
    overlay_factories.append(factory)
    return true


## Takes *factory* off the canvases' list, for the caller that added it.
static func remove_overlay_factory(factory: Callable) -> void:
    overlay_factories.erase(factory)


## Registers *factory*, `func(host: Control, canvas: SaCanvas)`, for the main
## surface's window-space control, and says whether this call added it, as
## `add_overlay_factory` does.
static func add_surface_overlay_factory(factory: Callable) -> bool:
    if surface_overlay_factories.has(factory):
        return false
    surface_overlay_factories.append(factory)
    return true


## Takes *factory* off the main surface's list, for the caller that added it.
static func remove_surface_overlay_factory(factory: Callable) -> void:
    surface_overlay_factories.erase(factory)


## Viewport size as of the last time the canvas was placed, so a resize can move
## the canvas by the change rather than re-deriving where it should go.
var _last_viewport_size: Vector2 = Vector2.ZERO

## The window's interface scale when the canvas last looked.
var _content_scale: float = 1.0

## The one view `SaCanvasView.for_canvas` hands back, so a Fit is remembered.
var _view: SaCanvasView = null

## The checkerboard and the ground drawn behind the page. Built in `_ready`.
var _behind: SaGroundBeyond = null
const BACKGROUND_REACH: float = SaGroundBeyond.REACH

## The view drawn at half size while it moves, when Preferences asks for it.
## Built in `_ready`, so a canvas that never enters a tree has none.
var _half_size: SaHalfSizeView = null
## Draws the window again when it comes back from behind another. Built in
## `_ready`, like the half size.
var _redraw_on_return: SaRedrawOnReturn = null
## The canvas's own draw while the half size stands in for it: the texture it
## let go of, and each background rectangle it hid with whether it showed.
var _texture_while_half: Texture2D = null
var _hidden_while_half: Array[Dictionary] = []

## The easel's display chunks drawn over the canvas's own texture. Built in
## `_ready`, beside the half size view.
var _detail: SaDetailDraw = null
## The selection overlay's `capture_state`, or empty while none has attached.
var _selection_report: Callable = Callable()


## Keeps the view where the user left it when the window changes size.
##
## Rather than re-fitting the canvas to the window on `size_changed`, which
## would throw away the zoom and the pan at every resize and snap back to "whole
## document, centred". Dragging a window edge is not a request to lose your
## place in the drawing.
##
## What is kept is the point under the middle of the viewport. Growing the window
## reveals more around it rather than moving what you were looking at.
func _on_viewport_resized() -> void:
    if not is_inside_tree() or is_queued_for_deletion():
        return
    var vp := get_viewport()
    if vp == null or not vp.is_inside_tree() or vp.is_queued_for_deletion():
        return

    var window_size := vp.get_visible_rect().size
    if _last_viewport_size == Vector2.ZERO:
        _center_canvas()
        return
    position += (window_size - _last_viewport_size) * 0.5
    _last_viewport_size = window_size


## The view over this canvas, the same one every time.
func view() -> SaCanvasView:
    if _view == null:
        _view = SaCanvasView.new()
        _view.canvas = self
    return _view


## The main canvas follows a scale change through `SaView.follow_scale`, and a
## fitted view fits once more a frame later, once the dockers have their sizes.
## A scratchpad's docker grows with the scale, and its picture should too.
func _on_ui_scale_changed(_scale: float) -> void:
    if not is_inside_tree() or is_queued_for_deletion() or get_viewport() != get_tree().root:
        return
    var before := _content_scale
    _content_scale = get_window().content_scale_factor
    view().follow_scale(canvas_size, before, _content_scale)
    if view()._fitted:
        await get_tree().process_frame
        if is_inside_tree() and not is_queued_for_deletion() and view()._fitted:
            view().fit_into(canvas_size, view().get_free_rect(), view()._fit_share)


## Shows the document the way Ctrl+0 does, `SaView.reset`: the whole picture at
## the Size Preferences names, or actual pixels, centred in the free rectangle.
## Used when the canvas first appears and when a new document replaces it, not
## on every resize.
##
## The fit is into what the view's covers leave, the rectangle View > Fit to View
## uses, and not into the whole window: the main canvas reaches under the top
## bar, and a fit into the whole window puts the picture's top rows under the
## menus. The window's size is still what the resize handler
## remembers, because a resize moves the pan by the change in the whole area and
## the bar does not change with it.
func _center_canvas() -> void:
    if not is_inside_tree() or is_queued_for_deletion():
        return
    var vp := get_viewport()
    if vp == null or not vp.is_inside_tree() or vp.is_queued_for_deletion():
        return
    view().reset(canvas_size)
    _last_viewport_size = vp.get_visible_rect().size


## Keeps the zoom across a document resize and moves the pan under it, so the
## document point that was under the middle of the viewport is still there.
##
## Cropping does not change the zoom. `_center_canvas` writes the fit outright,
## and calling it after every crop would throw the zoom and the pan away for the
## reason `_on_viewport_resized` gives.
##
## *source* is the part of the old document the new one is made of, in the old
## coordinates, so a point p of the old document is now
## `(p - source.position) * new_size / source.size`. For a crop that ratio is
## one and the whole correction is the rectangle's origin, which is why every
## texel that survived stays on its screen pixel rather than only the middle one.
##
## Read off the Control's own transform rather than off `scale` and `position`,
## because the view mirrors on the sign of the scale and rotates about a pivot
## pinned at the origin, and both have to come out right. Only `position` is
## written, and a translation adds, so the correction lands exactly whatever the
## rotation is.
func _keep_view_over(source: Rect2i) -> void:
    if not is_inside_tree() or is_queued_for_deletion():
        return
    var vp := get_viewport()
    if vp == null or not vp.is_inside_tree() or vp.is_queued_for_deletion():
        return
    var centre := vp.get_visible_rect().size * 0.5
    var shown := get_transform()
    var before := shown.affine_inverse() * centre
    var ratio := Vector2(canvas_size) / Vector2(source.size)
    var after := (before - Vector2(source.position)) * ratio
    position += centre - (shown * after)


## The cursor policy, `render/cursor/sa_cursor_policy.gd`.
##
## Where the pointer is, what is drawn in its place and when the OS cursor is
## hidden all moved there: none of it is about displaying a texture. This class
## keeps no forwarders for it, so a caller names `SaCursorPolicy` directly
## rather than reading this file to find out where the answer went.


## A crop or its undo changed the size of the document behind this view.
## Ignored for any other document, because a scratchpad has its own.
##
## `document_resized` carries the size and no more, so where the picture went
## comes from `SaDocument.resize_source`, which is set for exactly the length of
## this emit and is an empty rectangle for a resize nobody described.
func _on_document_resized(which: SaDocument, new_size: Vector2i) -> void:
    if which != null and which == document:
        resize_canvas(new_size, which.resize_source)


## Points this view at a document of *new_size*.
##
## *source* is which part of the document that was the document that is now is
## made of, in the old coordinates. Given one, the view keeps its zoom and
## re-derives its pan so the document point under the middle of the viewport
## stays under it, which for a crop leaves every surviving texel on the screen
## pixel it was already on and the picture does not move at all. An empty
## rectangle means nobody said, and the document is shown the way a new one
## opens, at 100% shown or fitted when it is larger: File > New, File > Open, a
## recovered autosave and the boot all want that.
##
## The order is load-bearing: the easel hands back the texture it displaced, this
## rebinds the Texture2DRD to the new one, and only then does the old texture go
## out of scope and free its RID. Rebinding after the free would leave a frame
## drawing from a dangling RID.
func resize_canvas(new_size: Vector2i, source: Rect2i = Rect2i()) -> void:
    if easel == null or new_size.x <= 0 or new_size.y <= 0:
        return
    # The local is the point, not a leftover: holding this reference is what
    # keeps the displaced texture's RID alive across the rebind below. The
    # analyser sees a variable that is never read and says so, hence the ignore.
    @warning_ignore("unused_variable")
    var displaced := easel.resize_output(new_size)
    canvas_size = new_size
    # The full size first, so the texture bound below is the one drawn.
    _end_half_size()
    var output_texture := Texture2DRD.new()
    output_texture.texture_rd_rid = easel.output.rid
    self.texture = output_texture
    self.size = canvas_size
    # File > New resets the document before resizing the view, so the colour
    # space and the blend reference white may both be different now.
    sync_tonemap()
    if _behind != null:
        _behind.resize(canvas_size)
    if source.size.x > 0 and source.size.y > 0:
        _keep_view_over(source)
    else:
        _center_canvas()
    displaced = null


## Creates this canvas's easel if it does not have one yet.
##
## Callable before _ready, because whoever binds tools needs a document to bind
## them to and cannot depend on tree-entry order. A easel injected from
## outside (a shared canvas, a test) is left alone.
func ensure_easel() -> SaEasel:
    if easel == null:
        easel = SaEasel.create_default(canvas_size)
        add_child(easel)
    return easel


func _on_tonemap_changed(_enabled: bool) -> void:
    sync_tonemap()


## Points the view at the registry, and follows it from then on.
func bind_view_transforms(registry: SaViewTransformRegistry) -> void:
    if _view_transforms != null and _view_transforms.changed.is_connected(_on_view_transforms_changed):
        _view_transforms.changed.disconnect(_on_view_transforms_changed)
    _view_transforms = registry
    if registry != null and not registry.changed.is_connected(_on_view_transforms_changed):
        registry.changed.connect(_on_view_transforms_changed)
    sync_tonemap()


func _on_view_transforms_changed() -> void:
    sync_tonemap()


## Re-reads everything the view shader needs from the settings and the document.
##
## Called on setup, on the View-menu toggle and after a resize, rather than every
## frame: none of these values changes during a stroke, and a stroke is where the
## per-frame cost would land.
## Builds the material on first call, so a canvas can be set up without a
## viewport. _ready() needs one, this does not.
func sync_tonemap() -> void:
    if not material is ShaderMaterial:
        # A material on the view itself. With the toggle off the shader leaves
        # COLOR alone but for its half-level dither, so a number already on a
        # display step is drawn as having no material at all would draw it.
        var fresh := ShaderMaterial.new()
        fresh.shader = tonemap_shader
        self.material = fresh
        # Subscribed here rather than in _ready, so a canvas that has a
        # tonemapper is always a canvas that hears about it. Both signals
        # disconnect themselves when this Node is freed.
        if not EventBus.tonemap_changed.is_connected(_on_tonemap_changed):
            EventBus.tonemap_changed.connect(_on_tonemap_changed)
    var mat := material as ShaderMaterial
    # Assign and convert both change what the stored numbers mean, and either can
    # change the blend reference white with them. Not emitted per dab.
    #
    # Subscribed on every call rather than only when the material is built: File
    # New and File Open put a *different* SaDocument behind this view, and
    # connecting only the first one left the view deaf to a colour space change
    # in every document after the first.
    var doc_now := document
    if doc_now != null and not doc_now.document_changed.is_connected(sync_tonemap):
        doc_now.document_changed.connect(sync_tonemap)
    # The relief's light is the document's, moved by View > Relief Light.
    if doc_now != null and not doc_now.relief_light.changed.is_connected(sync_tonemap):
        doc_now.relief_light.changed.connect(sync_tonemap)
    # The setting and the document both: a filter that forms the picture has
    # already rolled the highlights off, and one over the other would transform
    # the picture twice. `picture_carries_its_tonemap` says how a filter says so.
    mat.set_shader_parameter("tonemap_enabled", SaSettings.tonemap_highlights and not picture_carries_its_tonemap())
    mat.set_shader_parameter("knee", SaSettings.tonemap_knee)
    mat.set_shader_parameter("desaturation", SaSettings.tonemap_desaturation)
    # Whether a colour outside the display's cube is clipped or gives up chroma
    # with its hue held. Written with the rolloff's three and read whether or
    # not the rolloff runs.
    mat.set_shader_parameter("gamut_mapping", SaGamutMapping.uniform_value(SaSettings.gamut_mapping))
    # The shape check's options, by the uniform names the settings give them.
    var shape := SaSettings.shape_check_uniforms()
    for uniform: String in shape:
        mat.set_shader_parameter(uniform, shape[uniform])
    _sync_view_transforms(mat)
    _sync_display_profile(mat)
    _sync_proof_profile(mat)
    var doc := document
    mat.set_shader_parameter("blend_white", doc.blend_reference_white if doc != null else 1.0)
    _sync_display_space(mat, doc.color_space if doc != null else null)
    _sync_relief_light(mat)


## Whether a filter of the document forms the picture the screen shows, so the
## view's own highlight roll-off has nothing left to roll off.
##
## A Tonemap on the picture, or on a filter layer with nothing visible above it,
## already writes the display-referred picture, and the roll-off over it would
## be a second transform. Asked through the filter chain
## and never of the Tonemap by name: a filter says `forms_the_picture` and this
## reads whoever says it.
##
## The uniform is the setting and this answer both, so a painter who turns the
## roll-off on sees it come back the moment the covering filter goes.
func picture_carries_its_tonemap() -> bool:
    var doc := document
    if doc == null or compositor == null:
        return false
    return compositor.filter_chain.covers_the_picture(doc)


## The relief's switch, light and strength onto the material.
## The switch is the setting and a bound texture both, so a document without
## height never reads the sampler. The light is the document's own,
## `SaReliefLight`, pointing from the surface to where it stands, in the
## canvas's axes, x right and y down, at `SaRelief.LIGHT_ELEVATION` above the
## canvas, the light a flat export bakes.
func _sync_relief_light(mat: ShaderMaterial) -> void:
    var doc := document
    mat.set_shader_parameter("relief_enabled", SaSettings.show_relief and _relief_source != null and doc != null)
    if doc == null:
        return
    mat.set_shader_parameter("relief_light", doc.relief_light.toward())
    mat.set_shader_parameter("relief_strength", doc.relief_light.strength)
    mat.set_shader_parameter("relief_gloss", SaSettings.relief_gloss)


## Binds the easel's relief when it appears, changes or goes, and answers
## whether it did. Asked once a frame, after the easel's composite, because the
## relief allocates its texture inside a resolve and lets it go on a resize.
##
## The same order as the output's in [method resize_canvas]: the material is
## pointed at the new texture first, and the one it drew from is held for one
## more frame, so no frame draws from a freed RID.
func _sync_relief() -> bool:
    _relief_displaced = null
    var wanted: SaTexture = easel.relief.texture if easel != null else null
    if wanted == _relief_source:
        return false
    var mat := material as ShaderMaterial
    if mat == null:
        return false
    _relief_displaced = _relief_source
    _relief_source = wanted
    var bound: Texture2DRD = null
    if wanted != null:
        bound = Texture2DRD.new()
        bound.texture_rd_rid = wanted.rid
    mat.set_shader_parameter("relief_texture", bound)
    _sync_relief_light(mat)
    return true


## The registry's state onto the material: a module's mode brings its own
## shader, which is swapped in for as long as the mode is active and handed
## the same uniforms, and every toggle sets what it owns.
func _sync_view_transforms(mat: ShaderMaterial) -> void:
    if _view_transforms == null:
        mat.set_shader_parameter("view_mode", 0)
        return
    var wanted: Shader = _view_transforms.mode_shader()
    if wanted == null:
        wanted = tonemap_shader
    if mat.shader != wanted:
        mat.shader = wanted
    _view_transforms.apply_to(mat)


## The display's own gamut from Preferences, filled the way the Display page's
## Wider display row says. The matrix is linear sRGB into the display's primaries
## under Correct, the document's own linear RGB under Native and a stretch of it
## under Even, see [SaDisplayFill]. An identity matrix is said outright, so an
## sRGB display under Correct keeps its bit-identical passthrough.
func _sync_display_profile(mat: ShaderMaterial) -> void:
    var doc := document
    var space := doc.color_space if doc != null else null
    var to_display := SaDisplayFill.matrix(SaSettings.display_fill, space, SaSettings.display_profile_space())
    mat.set_shader_parameter("display_identity", to_display == Basis.IDENTITY)
    var columns := SaColorSpace.basis_columns(to_display)
    mat.set_shader_parameter("display_col0", columns[0])
    mat.set_shader_parameter("display_col1", columns[1])
    mat.set_shader_parameter("display_col2", columns[2])


## The proof gamut from Preferences: linear sRGB into the proof space and
## back, so the shader can clip in between. Only mode 3 reads them.
func _sync_proof_profile(mat: ShaderMaterial) -> void:
    var proof := SaSettings.proof_profile_space()
    var back: Basis = proof.to_linear_srgb_matrix() if proof != null else Basis.IDENTITY
    var into: Basis = back.inverse()
    var into_columns := SaColorSpace.basis_columns(into)
    var back_columns := SaColorSpace.basis_columns(back)
    for i in 3:
        mat.set_shader_parameter("proof_col%d" % i, into_columns[i])
        mat.set_shader_parameter("proof_back_col%d" % i, back_columns[i])


## Tells the view material what the document's stored numbers mean.
##
## Godot's 2D pipeline writes canvas colours to the screen with no encode of its
## own, so a view that ignores the document's colour space displays whatever is
## stored as though it were already sRGB. Image > Convert Colour Space would
## visibly darken a painting, when convert is the operation defined to leave the
## appearance alone, and Assign, the one that is meant to change it, could not.
func _sync_display_space(mat: ShaderMaterial, space: SaColorSpace) -> void:
    # A null descriptor is treated as sRGB, which is what an unspecified document
    # already renders as.
    var is_srgb_encoded: bool = space == null or not space.is_linear()
    var to_display: Basis = space.to_linear_srgb_matrix() if space != null else Basis.IDENTITY
    mat.set_shader_parameter("document_is_srgb", is_srgb_encoded)
    # A document storing perceptual coordinates reaches the screen by the fixed
    # Oklab matrices instead, so the curve and the gamut matrix above describe its
    # RGB view rather than its pixels. The shader consults one path or the other,
    # never both.
    var is_oklab: bool = space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB
    mat.set_shader_parameter("document_is_oklab", is_oklab)
    # Exactly identity for an sRGB-gamut document rather than whatever
    # `M.inverse() * M` rounds to, so this is a real test and the common case
    # keeps its bit-identical passthrough. The same question the brush and the
    # eyedropper ask, so they ask it in the same place.
    mat.set_shader_parameter("display_passthrough", space == null or space.is_display_ready())
    var columns := SaColorSpace.basis_columns(to_display)
    mat.set_shader_parameter("to_display_col0", columns[0])
    mat.set_shader_parameter("to_display_col1", columns[1])
    mat.set_shader_parameter("to_display_col2", columns[2])


## The document rectangle this view shows, the viewport's corners taken back
## through the canvas's transform, so a rotation or a mirror gives the box
## around what is on the screen. The easel composites what this reaches and
## holds the rest. Empty out of the tree, and while the Environment view
## shows the canvas as the sky, both of which the easel reads as the whole canvas.
##
## The whole viewport rather than what the covers leave: the top bar is drawn
## over the canvas and what is under it shows through its gaps.
func shown_in_document() -> Rect2:
    if not is_inside_tree() or SaEnvironmentView.shows(self):
        return Rect2()
    var to_document := get_global_transform_with_canvas().affine_inverse()
    var screen := get_viewport_rect()
    var shown := Rect2(to_document * screen.position, Vector2.ZERO)
    for corner: Vector2 in [Vector2(screen.end.x, screen.position.y), screen.end, Vector2(screen.position.x, screen.end.y)]:
        shown = shown.expand(to_document * corner)
    return shown


## Called by the door at the end of every step it answers, so a step that
## changed the document is drawn even while the window is not focused.
static func after_door_step(root: Window) -> void:
    # The front surface's canvas, the document a step acted on, in the run's window.
    var shown := SaCanvasView.front_canvas()
    if shown != null and shown.get_window() == root and shown._redraw_on_return != null:
        shown._redraw_on_return.step_answered()


## Whether the compositor lets this canvas's window draw now, false while it
## is covered and suspended.
func _window_can_draw() -> bool:
    var window := get_window()
    return window != null and DisplayServer.window_can_draw(window.get_window_id())


## Ask the easel to re-composite its dirty chunks on the next frame.
func request_composite() -> void:
    if easel != null:
        easel.request_composite()


func _process(_delta: float) -> void:
    _follow_half_size()
    # The easel runs the compositor itself. The view only needs to repaint,
    # and only when something it shows has moved.
    if view_changed():
        queue_redraw()


## Draws the view at half size while it moves, once a frame
## before the view decides whether it has to be drawn again. The canvas works out
## where it is and whether a stroke is open, and hides its own draw while
## `SaHalfSizeView` draws a smaller one in its place.
func _follow_half_size() -> void:
    if _half_size == null or not is_inside_tree():
        return
    var viewport := get_viewport()
    var host := get_parent() as Control
    var host_rect := Rect2(Vector2.ZERO, host.size) if host != null else viewport.get_visible_rect()
    var host_to_pixels := viewport.get_final_transform()
    if host != null:
        host_to_pixels = host_to_pixels * host.get_global_transform_with_canvas()
    var area := Rect2(host_to_pixels * host_rect.position, Vector2.ZERO).expand(host_to_pixels * host_rect.end).abs()
    var to_pixels := viewport.get_final_transform() * get_global_transform_with_canvas()
    var wanted := (
        _half_size.moved(to_pixels, area)
        and SaSettings.half_size_view_while_moving
        and is_visible_in_tree()
        and not SaHalfSizeView.stroke_open(document)
    )
    if wanted and not _half_size.active:
        var behind: Array[ColorRect] = []
        for child in get_children():
            var rect := child as ColorRect
            if rect != null and rect.show_behind_parent:
                behind.append(rect)
                _hidden_while_half.append({"rect": rect, "visible": rect.visible})
        _half_size.take_over(get_parent(), get_index(), texture, material, behind)
        for rect: ColorRect in behind:
            rect.visible = false
        _texture_while_half = texture
        texture = null
    elif not wanted:
        _end_half_size()
    _half_size.place(host_rect, size, to_pixels, pixels_per_texel())


## Puts the canvas's own draw back where the half size stood in for it.
func _end_half_size() -> void:
    if _half_size == null or not _half_size.active:
        return
    _half_size.rest()
    for pair: Dictionary in _hidden_while_half:
        var held: Variant = pair["rect"]
        if is_instance_valid(held):
            var rect: ColorRect = held
            var was_visible: bool = pair["visible"]
            rect.visible = was_visible
    _hidden_while_half.clear()
    if texture == null:
        texture = _texture_while_half
    _texture_while_half = null


## The composites this view has asked to be drawn, so a frame that composited
## nothing draws nothing.
var _drawn_composites: int = -1


## Whether the view has to be drawn again: the sampling or the background
## changed, or the easel has composited since the last draw or is about to
## this frame.
##
## Asked once a frame rather than queueing a redraw once a frame. A redraw a
## frame is a rendered frame a frame, whatever `low_processor_usage_mode` says,
## so a Sara left alone on a 4K display would draw its window a hundred times a
## second and keep the GPU busy for nothing. The zoom, the pan and the
## material's parameters need no line here: a transform or a material that moves
## marks the item on its own.
##
## The easel composites in its own `_process`, and this view is processed
## after it (`process_priority` in `_ready`), so a composite and the draw that
## shows it share a frame and the count alone is the question.
func view_changed() -> bool:
    var changed := _sync_sampling()
    changed = (_behind != null and _behind.sync(document, pixels_per_texel())) or changed
    changed = _sync_relief() or changed
    if _detail != null and easel != null:
        var shown := not (_half_size != null and _half_size.active) and easel.relief.texture == null
        changed = _detail.sync(easel.detail, canvas_size, pixels_per_texel(), shown) or changed
    if easel != null and easel.composite_count != _drawn_composites:
        _drawn_composites = easel.composite_count
        SaStrokeLedger.redraw_queued()
        changed = true
    return changed


## How many physical pixels one texel covers on screen right now.
##
## Two scalings stack: the canvas zoom, and the window's content scale factor,
## which Godot applies as a transform on top of it. At a 1.25 desktop scale a
## 100 percent zoom is 1.25 pixels per texel, and the filter has to be chosen
## for what the screen shows rather than for what the zoom says.
func pixels_per_texel() -> float:
    var window := get_window()
    var content_scale := window.content_scale_factor if window != null else 1.0
    return scale.x * content_scale


## How far under one pixel per texel still counts as one, and past it before
## the detail view draws.
##
## A hundred per cent divides the interface scale out,
## `SaView.actual_pixel_zoom`, and a Control's scale is a float32, so the round
## trip does not always land on one: an interface scale of 1.35 comes back as
## 0.99999998 and 1.1 as 0.99999999. A bare `>= 1.0` reads those as a
## minification and blurs the picture the division has just made square. A tenth
## of a per mille is far below anything an eye can see and far above the round
## trip.
const FILTER_EPSILON: float = SaDetailView.EPSILON


## Nearest once a texel covers a whole pixel, so a texel is a square on screen
## and never a blur between its neighbours. Below that, linear: each tap already
## averages four texels, and the view shader spreads its taps over the pixel's
## footprint, so a painting zoomed out stops shimmering between zoom levels.
static func filter_for(pixels_per_texel_now: float) -> CanvasItem.TextureFilter:
    if pixels_per_texel_now >= 1.0 - FILTER_EPSILON:
        return CanvasItem.TEXTURE_FILTER_NEAREST
    return CanvasItem.TEXTURE_FILTER_LINEAR


## Keeps the sampler in step with the zoom. Per frame, because the zoom is
## written by whichever tool or gesture holds the view and none of them has to
## know the sampler exists. A compare and, rarely, one property write.
func _sync_sampling() -> bool:
    var wanted := filter_for(pixels_per_texel())
    if texture_filter == wanted:
        return false
    texture_filter = wanted
    return true


## Safely release all GPU-backed references before Godot destroys the RenderingDevice.
## Order matters: drop the Texture2DRD first so CanvasItem RIDs are released,
## then let SaDocument free layers (which frees SaTexture RIDs), then the compositor.
func _cleanup_resources() -> void:
    _live_canvases.erase(self)
    # The half-size mirror holds the same Texture2DRD, and lets go of it first.
    _end_half_size()
    if _half_size != null:
        _half_size.release()
    if _detail != null:
        _detail.release()

    # Drop the Texture2DRD first so the RenderingServer releases its Canvas/Texture
    # RIDs while the SaTexture it wraps is still alive. The easel then frees the
    # document, its chunks and the output texture.
    self.texture = null
    # The relief goes the same way, its Texture2DRD before the SaTexture under
    # it. Freed the other way round, the material rebuilds its uniform set over
    # a texture that is already gone, twice at every exit.
    var mat := material as ShaderMaterial
    if mat != null and _relief_source != null:
        mat.set_shader_parameter("relief_texture", null)
    _relief_source = null
    _relief_displaced = null
    easel = null


func _exit_tree() -> void:
    var vp := get_viewport()
    if vp and vp.size_changed.is_connected(_on_viewport_resized):
        vp.size_changed.disconnect(_on_viewport_resized)
    # The tool's picture in the OS cursor slot goes back with the canvas it was
    # put up over, or the display server keeps it past the rendering server's
    # leak count at exit.
    SaCursorPolicy.release_tool_cursor_of(self)
    _cleanup_resources()
    SaTrail.teardown("a canvas released its GPU resources")


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _cleanup_resources()


## What this canvas tells a capture's state dump about itself.
##
## Here rather than in `sara-godot/ui/`: every number below is this node's own,
## and a file elsewhere would have to reach through `_live_canvases` to a
## private static list to get at them. The view, the ring and the composite
## counters are the picture the painter is looking at, and a screenshot answers
## for none of them: the compositor draws the OS cursor, a mirror rides on the
## sign of a scale, and a composite count is cumulative.
func capture_state() -> Dictionary:
    return {
        "ring_radius": cursor_ring_radius,
        # The shape the active tool asked for. A PNG cannot show it, because the
        # compositor draws the OS cursor.
        "cursor_shape": mouse_default_cursor_shape,
        # Which tool's own picture is standing in that shape's slot, if any.
        "tool_cursor": SaCursorPolicy.tool_cursor_state(),
        # Where the shift-drag resize last asked the pointer back to. Wayland
        # refuses the warp, so the request is all a capture can read.
        "resize_warp": ToolMachine.warp_report(self),
        # How many motion samples handle_input has forwarded since the last reset,
        # for the proof that several hardware samples inside one frame all reach
        # the tool.
        "motion": ToolMachine.motion_report(self),
        # The view, which is the user's and not the window's, so a resize keeps
        # both of these.
        "zoom": absf(scale.x),
        "rotation": rotation,
        # Which way round the view is. A mirror rides on the sign of the same
        # scale the zoom is read from, so a PNG is the only other place it
        # shows.
        "flip": SaReportShapes.vec(SaCanvasView.for_canvas(self).get_flip()),
        "offset": SaReportShapes.vec(position),
        "rect": SaReportShapes.rect(get_global_rect()),
        # What the covers leave, so a fit can be read against the bar.
        "visible_rect": SaReportShapes.rect(SaCanvasView.for_canvas(self).get_visible_rect()),
        # And what the dockers leave of that, which a fit and a centre place the
        # picture in, so a scenario reads the picture's centre against its own.
        "free_rect": SaReportShapes.rect(SaCanvasView.for_canvas(self).get_free_rect()),
        "visible": is_visible_in_tree(),
        # The display chunks of a layer at 2.0 drawn past 100%.
        "detail": _detail.report() if _detail != null else {},
        "window": get_window().title if get_window() != null else "<none>",
        # The three display matrices and the stretch, for the dump: a shot of a
        # stretched picture says it looks different, and these say by how much.
        "display_fill":
        SaDisplayFill.report(
            SaSettings.display_fill, document.color_space if document != null else null, SaSettings.display_profile_space()
        ),
        # The shape check as the dump reports it: the method the Display page
        # names and the uniforms the live material holds, so a shot says which
        # view it is a picture of. Read off the material rather than recomputed
        # from the settings, because what a picture proves is what the shader
        # was handed.
        "shape_check": _shape_check_state(),
        # Cumulative like the GPU counters, and for the same reason: a stroke is
        # the difference between two dumps.
        "composites": easel.composite_count if easel != null else 0,
        "composite_usec_total": easel.composite_usec_total if easel != null else 0,
        "composite_usec_last": easel.composite_usec_last if easel != null else 0,
        # Whether the picture is drawn at half size now, and at what size.
        "half_size_view": _half_size.report() if _half_size != null else {},
        "ground_beyond": _behind.report(document) if _behind != null else {},
    }


## The shape check as a dump reports it: the method the preference names, and
## each uniform the material carries under its name less `shape_check_`, the
## method's number, the switch, the level count, the reach and the count
## across. Nulls, not guesses, for a canvas whose material is not built yet.
func _shape_check_state() -> Dictionary:
    var mat := material as ShaderMaterial
    var state := {"mode": SaSettings.shape_check_method}
    for uniform: String in SaSettings.shape_check_uniforms():
        state[uniform.trim_prefix("shape_check_")] = mat.get_shader_parameter(uniform) if mat != null else null
    return state


## The selection overlay drawn over this canvas, reporting itself, empty when
## there is none.
##
## The overlay hands its `capture_state` over when it attaches, so this file
## names nothing in `ui/`. The dash lengths are measured off the shot beside the
## dump, because reading them back off the frame would bring the GPU's picture
## back to the CPU.
func selection_overlay_report() -> Dictionary:
    if not _selection_report.is_valid():
        return {}
    var report: Dictionary = _selection_report.call()
    return report


## Takes the selection overlay's report, the one [method selection_overlay_report]
## answers with. The overlay calls it when it attaches to this canvas.
func attach_selection_report(report: Callable) -> void:
    _selection_report = report


## The tool machine this canvas routes its input through, or null when it has
## none. What a capture asks for the boxes a tool has pending over the picture.
func tool_machine() -> ToolMachine:
    return get_node_or_null("ToolMachine") as ToolMachine


## Times the half-size view: answered by `SaHalfSizeView`, which is private
## to this package, so the harness names the package's face.
static func capture_half_size_view(tree: SceneTree, spec: Variant) -> String:
    return SaHalfSizeView.capture(tree, spec)


## Every canvas alive and in the tree, each reporting itself.
static func capture_state_all() -> Array:
    var out: Array = []
    for live: SaCanvas in live_canvases():
        out.append(live.capture_state())
    return out


## The first canvas alive in *root*, or null when that window has none. A dump
## takes one window at a time, and every block about the picture wants the canvas
## in the window it is describing. Not a way to find the document the painter
## is working on: [method SaCanvasView.front_canvas] is that lookup.
static func in_window(root: Window) -> SaCanvas:
    for live: SaCanvas in live_canvases():
        if live.get_window() == root:
            return live
    return null


## Every canvas alive and in the tree, oldest first.
##
## The list itself is private, because a canvas adds and removes itself and
## nothing outside may. This is the reading of it: an entry that has been freed or
## taken out of the tree is dropped rather than answered, so no caller does it
## for itself, the cursor package's walks the only ones left outside this file.
static func live_canvases() -> Array:
    var out: Array = []
    for entry: Variant in _live_canvases:
        if not is_instance_valid(entry) or not entry is SaCanvas:
            continue
        var live: SaCanvas = entry
        if live.is_inside_tree():
            out.append(live)
    return out
