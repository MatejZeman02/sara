## The selection on the canvas: marching ants along its edge, the red tint of
## the quick mask over what is not selected, and the shape a selection tool is
## dragging.
##
## A child of the canvas view like the symmetry overlay, so it draws in
## document pixels and follows the zoom, the pan and the rotation. Each mask
## chunk is drawn as its own texture through a shader that finds the edge by
## sampling a screen pixel either way, so the ants stay one pixel wide at any
## zoom. The ants walk on the shader's clock, so nothing here redraws for the
## animation, only when the selection changes. Under the capture harness the
## clock is taken out of the walk, see [method hold_the_ants].
##
## **A chunk is drawn with the chunks around it**, by a [ChunkDraw] of its own
## whose material carries their eight textures, so a sample past a seam reads
## the texel beside it and a chunk the selection does not hold reads as
## unselected. A sample clamped to the texel itself at a seam would draw no
## ants along the side of a selection whose edge lay on the first texel past
## one, with nothing selected in the chunk before it. The overlay's own
## material is the one the uniforms are written to, and every chunk's copies
## it.
##
## The same shader reads which way the edge runs, from the mask around each
## fragment, and lays its dashes across that rather than along a fixed diagonal.
## A fixed one makes a dash as long as the orientation lets it be, which on the
## same outline ran from 2.8 screen pixels to a stretch with no dash in it at
## all.
##
## **A preview** is a selection that is not the document's, drawn in the quick
## mask's tint in place of the ants while it is set. Colour Range's dialog sets
## one and fills it as the painter moves its rows, so the canvas shows what
## Apply would choose before it is chosen.
##
## The tint over chunks the selection does not hold, the dim over what the crop
## tool would cut away, and the tool's shape, are drawn by a child without the
## material, because a control draws every command through one material.
##
## **What a tool drags is a vocabulary of shapes and not of tools**. A tool
## hands over polylines (`lines`), points (`knots`), boxes with a shape in
## each (`cells`) and round handles (`rings`), and this file draws those four,
## the squares at a size on screen when the tool names one (`handle_side`). It
## knows no tool's meshes or modes, because an overlay that did would be the
## skeleton holding a module's engine and the module reaching up into the
## skeleton.
class_name SaSelectionOverlay
extends Control

const SHADER_PATH := "res://shaders/canvas/selection.gdshader"

## How much of the paint outside the crop rectangle is left showing. Dark enough
## that the rectangle reads at a glance, light enough that a painter can still
## judge what the cut would throw away.
const CROP_DIM := Color(0.0, 0.0, 0.0, 0.45)

## How large a round handle is drawn, in screen pixels at every zoom: a hair
## larger than the mirror axes' five, since a ramp's end sits on paint of any
## colour where an axis sits on a line of its own.
const RING_RADIUS: float = 6.0

## The selection drawn as the quick mask's tint in place of the document's own,
## or null. Written by whoever previews, which is Colour Range's dialog, and
## followed here on the next frame the way the document's selection is. Not
## `preview`, which is what this file calls a tool's dragged shape.
var selection_preview: SaSelection = null

var _canvas: SaCanvas = null
var _watched: SaSelection = null
## The preview this overlay listens to, which trails [member selection_preview]
## by at most a frame.
var _watched_preview: SaSelection = null
## RID -> [Shown], so a chunk keeps its texture between redraws and the mask's
## texture lives as long as a material here can name it.
var _textures: Dictionary = {}
## The parent of every [ChunkDraw], built in `_init` before the plain child so
## the tool's shape and the tint draw over the ants. It takes the pending
## transform while a piece is in the air.
var _marks: Node2D = null
## Grid position -> [ChunkDraw], the chunks drawn now.
var _drawn: Dictionary = {}
## Whether the chunks' draws are to be laid out again on this frame, which a
## change of the selection, of the preview or of the pending transform asks.
var _marks_due: bool = true
## The canvas size the chunks were last cut to.
var _marks_canvas := Vector2i.ZERO
## The child the tool shapes and the quick mask draw on, built and adopted in
## `_init` so that it is this overlay's own field and freed with it.
var _plain: Control = null
var _last_preview: Dictionary = {}
## Document pixels per screen pixel when the tool's shape was last drawn, since
## a zoom moves no shape and the rings, the cells and a `handle_side` are sized
## on screen.
var _drawn_pixel: float = 0.0


## What the ants are being drawn from, for the capture harness: the selection's
## own shape and the constants the shader snaps against.
##
## The dash lengths themselves are not here and cannot be. They exist only in
## the frame the GPU drew, and reading them back is `texture_get_data`, which
## hard rule 1 allows in export and the eyedropper and nowhere else. So the
## dashes are measured off the shot, and this block is what says which picture
## a measurement belongs to: the zoom, the kind of edge and how many chunks the
## mask spans, which are the three things that change the look of the ants.
func capture_state() -> Dictionary:
    var selection := _watched
    if selection == null:
        return {"present": false}
    var bounds := Rect2i()
    var side := 0
    for grid_pos: Vector2i in selection.chunks:
        var chunk := selection.chunks[grid_pos] as SaChunk
        side = chunk.pixel_size() if side == 0 else side
        var at := Rect2i(Vector2i(grid_pos) * side, Vector2i(side, side))
        bounds = at if bounds.size == Vector2i.ZERO else bounds.merge(at)
    return {
        "present": true,
        # Whether anything is selected. `present` says only that a selection is
        # watched, and a capture of an empty selection was once read as this.
        "active": selection.active,
        "chunks": selection.chunks.size(),
        # Whether the brush is painting the mask rather than the layer.
        "quick_mask": selection.editing,
        "bounds": {"x": bounds.position.x, "y": bounds.position.y, "w": bounds.size.x, "h": bounds.size.y},
        # The box the selection itself carries, which is not the one above.
        # `bounds` here is the union of the chunk rectangles, which is what the
        # overlay draws over. `SaSelection.bounds` is the tight box a copy or a
        # cut dispatches inside, and the two differ by up to a chunk on every
        # edge, so a scenario asking whether a subtract moved the box has to be
        # able to see the second one.
        "selection_bounds":
        {
            "x": selection.bounds.position.x,
            "y": selection.bounds.position.y,
            "w": selection.bounds.size.x,
            "h": selection.bounds.size.y,
        },
        # The view's own scale, which is where the dump reads the zoom from:
        # `SaCanvas` is a `TextureRect` and has no zoom of its own to ask for.
        "zoom": absf(_canvas.scale.x) if _canvas != null else 0.0,
        "ant_period": _ant_uniform("ant_period", 8.0),
        "ant_speed": _ant_uniform("ant_speed", 16.0),
        # Not a uniform, so a scenario that wants it has to read it from the
        # shader source. Written here so a dump says which value drew the shot
        # it sits beside, which is the whole point of a sweep over it.
        "ant_sectors": 12,
        # What the quick mask's tint reaches over, in document pixels, and how
        # many rectangles the plain child draws it as. The rectangle is the
        # union of the tinted quads and the clipped chunk draws, so a scenario
        # can ask that it equals the canvas and nothing more, since the tint must not run past the canvas edge across the
        # last partial row and column of chunks.
        "tint": _tint_report(),
        # Whether a preview is drawn in place of the selection, and over how
        # many chunks, so a dump beside a shot of Colour Range's tint says the
        # tint is the preview's.
        "preview":
        {
            "on": selection_preview != null,
            "chunks": selection_preview.chunks.size() if selection_preview != null else 0,
        },
    }


## The rectangle the quick mask's tint covers, or an empty one when the mask is
## off, and the quads the plain child draws it as.
func _tint_report() -> Dictionary:
    var selection := _shown()
    var document := _document()
    var canvas_size: Vector2i = document.canvas_size if document != null else Vector2i.ZERO
    if selection == null or not _tinted(selection) or canvas_size == Vector2i.ZERO:
        return {"on": false}
    var quads := tint_quads(canvas_size, selection.chunks.keys())
    var covered := Rect2()
    for quad: Rect2 in quads:
        covered = quad if covered.size == Vector2.ZERO else covered.merge(quad)
    for grid_pos: Vector2i in selection.chunks:
        var clipped := clip_chunk(grid_pos, canvas_size)
        if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
            continue
        covered = clipped if covered.size == Vector2.ZERO else covered.merge(clipped)
    return {
        "on": true,
        "quads": quads.size(),
        "rect": {"x": covered.position.x, "y": covered.position.y, "w": covered.size.x, "h": covered.size.y},
    }


## The rectangles the quick mask tints where the selection holds no chunk: one
## per chunk of the canvas's grid that *held* does not name, each cut to the
## canvas.
##
## Per chunk rather than one canvas rectangle with holes in it, because a
## rectangle with holes is a polygon and the chunks the selection holds are
## tinted by the shader instead, texel by texel. Each is cut to the canvas,
## because the grid's last row and column reach past a canvas whose side is not
## a multiple of the chunk, and the tint would reach with them.
static func tint_quads(canvas_size: Vector2i, held: Array) -> Array[Rect2]:
    var quads: Array[Rect2] = []
    for grid_pos: Vector2i in SaLayer.grid_positions(canvas_size):
        if held.has(grid_pos):
            continue
        var clipped := clip_chunk(grid_pos, canvas_size)
        if clipped.size.x > 0.0 and clipped.size.y > 0.0:
            quads.append(clipped)
    return quads


## The chunk at *grid_pos* cut to the canvas, in document pixels. Empty when
## the chunk lies wholly outside it.
static func clip_chunk(grid_pos: Vector2i, canvas_size: Vector2i) -> Rect2:
    var side := float(SaChunk.SIZE)
    var chunk := Rect2(Vector2(grid_pos) * side, Vector2(side, side))
    return chunk.intersection(Rect2(Vector2.ZERO, Vector2(canvas_size)))


## Stops the ants at the phase they have at time zero, for the capture harness
## and nothing else.
##
## The ants walk on the shader's clock, so two runs of one scenario shot the
## outline at two phases and `scripts/shot_diff.py` counted the walk as a
## difference, which hid the real one beside it. A
## speed of zero takes the clock out of the phase, so the dashes are a function
## of the screen pixel and the edge alone and every shot of them is the same.
##
## A call rather than a preference, because the painter must not be able to
## reach it: `SaCapture` makes it on every overlay that enters the tree while a
## scenario or a door session runs, and nothing else does. The state dump's
## `ant_speed` reads the uniform back, so a shot's dump says it was held.
func hold_the_ants() -> void:
    var shader_material := material as ShaderMaterial
    if shader_material != null:
        shader_material.set_shader_parameter("ant_speed", 0.0)
        _share()


## Takes back [method hold_the_ants], so the ants walk at the shader's own
## speed again. `SaCapture` calls it when a node that held them leaves the tree
## and after a shot it held them for.
func let_the_ants_march() -> void:
    var shader_material := material as ShaderMaterial
    if shader_material != null:
        shader_material.set_shader_parameter("ant_speed", null)
        _share()


## Whether the ants walk, which is false once [method hold_the_ants] ran.
func ants_march() -> bool:
    return _ant_uniform("ant_speed", 16.0) != 0.0


func _ant_uniform(which: StringName, fallback: float) -> float:
    var shader_material := material as ShaderMaterial
    if shader_material == null:
        return fallback
    var value: Variant = shader_material.get_shader_parameter(which)
    return float(value) if value != null else fallback


## The canvas and the plain child are constructor arguments rather than
## assignments, because a class writes its own members only. The child is built
## here and not by the factory for the same reason: it is this overlay's own
## field. Defaulted so that `.new()` still works the way Godot expects of a
## Control.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas
    _marks = Node2D.new()
    _marks.name = "SelectionMarks"
    add_child(_marks)
    _plain = Control.new()
    add_child(_plain)


static func attach_to(canvas: SaCanvas) -> SaSelectionOverlay:
    var overlay := SaSelectionOverlay.new(canvas)
    overlay.name = "SelectionOverlay"
    if canvas != null:
        canvas.attach_selection_report(overlay.capture_state)
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
    var shader_material := ShaderMaterial.new()
    shader_material.shader = load(SHADER_PATH)
    overlay.material = shader_material
    overlay._plain.name = "SelectionPlain"
    overlay._plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Sized like its parent, and not left at the default zero. A Control with an
    # empty rect is culled with its draw commands, so the tool's drag shape and
    # the quick mask's tint were being drawn and thrown away, which is what a
    # crop rectangle noticed: the marching ants come from the overlay itself,
    # which has always had a size, so nothing looked broken.
    overlay._plain.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay._plain.draw.connect(overlay._draw_plain)
    canvas.add_child(overlay)
    return overlay


func _process(_delta: float) -> void:
    var document := _document()
    var selection: SaSelection = document.selection if document != null else null
    if selection != _watched:
        if _watched != null and _watched.changed.is_connected(_redraw):
            _watched.changed.disconnect(_redraw)
        _watched = selection
        if _watched != null:
            _watched.changed.connect(_redraw)
        _redraw()
    if selection_preview != _watched_preview:
        if _watched_preview != null and _watched_preview.changed.is_connected(_redraw):
            _watched_preview.changed.disconnect(_redraw)
        _watched_preview = selection_preview
        if _watched_preview != null:
            _watched_preview.changed.connect(_redraw)
        _redraw()
    # The ants walk on the shader's clock, and at rest the engine renders only a
    # frame something asked for, so an active selection asks for one every
    # frame. A Sara with a selection on screen is animating, and that is the one
    # idle it is allowed.
    if _watched != null and _watched.active:
        queue_redraw()
    var preview := _tool_preview()
    if preview != _last_preview:
        var ants_moved: bool = preview.get("ants") != _last_preview.get("ants")
        _last_preview = preview
        _plain.queue_redraw()
        # The ants are on the material and this control redraws only when the
        # selection changes, which a drag does not do. So a moved outline needs
        # asking for by name, and only when the map itself moved: a drag is one
        # of these a frame and the mask is a texture per chunk.
        if ants_moved:
            _marks_due = true
            queue_redraw()
    elif _last_preview.has("rings") or _last_preview.has("cells") or _last_preview.has("handle_side"):
        var pixel := _screen_pixel()
        if pixel != _drawn_pixel:
            _drawn_pixel = pixel
            _plain.queue_redraw()
    var canvas_size: Vector2i = document.canvas_size if document != null else Vector2i.ZERO
    if _marks_due or canvas_size != _marks_canvas:
        _marks_due = false
        _marks_canvas = canvas_size
        _process_marks()


## The document the canvas shows, or null with no canvas or no document.
func _document() -> SaDocument:
    return _canvas.document if _canvas != null else null


func _redraw() -> void:
    _marks_due = true
    queue_redraw()
    _plain.queue_redraw()


## What is drawn: the preview while one is set, else the document's selection.
func _shown() -> SaSelection:
    return selection_preview if selection_preview != null else _watched


## Whether *selection* is drawn as the quick mask's tint rather than as ants,
## which a preview always is.
func _tinted(selection: SaSelection) -> bool:
    return selection.editing or selection == selection_preview


## The chunks of the mask, each through the shader with the chunks around it.
##
## Laid out here rather than in `_draw`, because a [ChunkDraw] is a node and
## the tree is not changed while it draws. The overlay's own `_draw` puts down
## nothing, and the redraw it is asked for every frame is what makes the
## engine draw the frame the ants walk in.
func _process_marks() -> void:
    var selection := _shown()
    var shader_material := self.material as ShaderMaterial
    if selection == null or not selection.active or shader_material == null:
        _clear_marks()
        return
    shader_material.set_shader_parameter("quick_mask", _tinted(selection))
    # Through the pending transform while a piece is in the air, so the outline
    # is around what the painter is dragging rather than around the hole it came
    # out of. The mask itself is untouched: commit and cancel are what move it,
    # and both already do.
    var ants: Variant = _last_preview.get("ants")
    _marks.transform = ants as Transform2D if ants is Transform2D and selection != selection_preview else Transform2D.IDENTITY
    var document := _document()
    var canvas_size: Vector2i = document.canvas_size if document != null else Vector2i.ZERO
    var live: Dictionary = {}
    var held: Dictionary = {}
    for grid_pos: Vector2i in selection.chunks:
        var texture: SaTexture = (selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        if texture == null:
            continue
        var shown_chunk: Shown = _textures.get(texture.rid, null)
        if shown_chunk == null:
            shown_chunk = Shown.new(texture)
        live[texture.rid] = shown_chunk
        held[grid_pos] = shown_chunk.drawn
    var kept: Dictionary = {}
    for grid_pos: Vector2i in held:
        var side := float((selection.chunks[grid_pos] as SaChunk).pixel_size())
        var whole := Rect2(Vector2(grid_pos) * side, Vector2(side, side))
        # Cut to the canvas. A mask chunk on the canvas's last row or column
        # reaches past the edge, and past the edge its texels are zero, which
        # the quick mask paints as tint. The region is the same cut in the
        # texture's own pixels, so the texels under the canvas land where they
        # always did.
        var shown := clip_chunk(grid_pos, canvas_size) if canvas_size != Vector2i.ZERO else whole
        if shown.size.x <= 0.0 or shown.size.y <= 0.0:
            continue
        var mark: ChunkDraw = _drawn.get(grid_pos, null)
        if mark == null:
            mark = ChunkDraw.new(shader_material.shader)
            _marks.add_child(mark)
        kept[grid_pos] = mark
        var around: Dictionary = {}
        for compass: StringName in ChunkDraw.NEIGHBOURS:
            around[compass] = held.get(grid_pos + ChunkDraw.NEIGHBOURS[compass], null)
        mark.show_chunk(held[grid_pos], shown, Rect2(shown.position - whole.position, shown.size), around)
        mark.share(shader_material)
    for grid_pos: Vector2i in _drawn:
        if not kept.has(grid_pos):
            (_drawn[grid_pos] as ChunkDraw).let_go()
    _drawn = kept
    # Last, once no material names a texture this lets go of.
    _textures = live


## Lets every chunk's draw go, and the textures after them.
##
## **The order is the fix for a GPU error.** A document reset frees the
## selection's chunks, and a material still naming a freed texture is rebuilt
## by the engine at the next texture freed anywhere, which was a Layers row a
## frame later, and fails as "Texture (binding: 2, index 0) is not a valid
## texture". So the masks are held here as long as a material can name them,
## and each material lets go of them before they go.
func _clear_marks() -> void:
    for mark: ChunkDraw in _drawn.values():
        mark.let_go()
    _drawn.clear()
    _textures.clear()


## One mask chunk's texture as the shader takes it, holding the texture itself
## so the engine never draws through a `Texture2DRD` whose texture is gone.
class Shown:
    var texture: SaTexture = null
    var drawn: Texture2DRD = null

    func _init(from: SaTexture) -> void:
        texture = from
        drawn = Texture2DRD.new()
        drawn.texture_rd_rid = from.rid


## Copies the overlay's uniforms onto every chunk's material, which is how a
## held or a released walk reaches the ants already drawn.
func _share() -> void:
    var shader_material := material as ShaderMaterial
    for mark: ChunkDraw in _drawn.values():
        mark.share(shader_material)


## One chunk of the mask through a material of its own, which carries the
## textures of the eight chunks around it for the shader's edge test.
##
## A material per chunk, because a canvas item draws every command through one
## material and the neighbours differ from chunk to chunk.
class ChunkDraw:
    extends Node2D

    ## The shader's neighbour uniforms and the step to the chunk each names.
    const NEIGHBOURS := {
        &"west": Vector2i(-1, 0),
        &"east": Vector2i(1, 0),
        &"north": Vector2i(0, -1),
        &"south": Vector2i(0, 1),
        &"north_west": Vector2i(-1, -1),
        &"north_east": Vector2i(1, -1),
        &"south_west": Vector2i(-1, 1),
        &"south_east": Vector2i(1, 1),
    }

    ## The overlay's uniforms each chunk's material copies.
    const SHARED: Array[StringName] = [&"quick_mask", &"tint", &"ant_dark", &"ant_light", &"ant_period", &"ant_speed"]

    var _texture: Texture2D = null
    var _shown := Rect2()
    var _region := Rect2()
    var _around: Dictionary = {}

    func _init(shader: Shader) -> void:
        name = "SelectionChunk"
        var own := ShaderMaterial.new()
        own.shader = shader
        material = own

    ## Draws *texture*'s *region* over *shown*, in document pixels, with
    ## *around* the textures of the chunks beside it by compass point, null
    ## where the selection holds none. Redraws only what changed.
    func show_chunk(texture: Texture2D, shown: Rect2, region: Rect2, around: Dictionary) -> void:
        if around != _around:
            _around = around
            for compass: StringName in NEIGHBOURS:
                (material as ShaderMaterial).set_shader_parameter(compass, around.get(compass))
        if texture != _texture or shown != _shown or region != _region:
            _texture = texture
            _shown = shown
            _region = region
            queue_redraw()

    ## Drops every texture this chunk's material and draw name, then goes at
    ## the frame's end. Until then the material names nothing that can be freed
    ## under it.
    func let_go() -> void:
        var own := material as ShaderMaterial
        for compass: StringName in NEIGHBOURS:
            own.set_shader_parameter(compass, null)
        _around = {}
        _texture = null
        queue_redraw()
        queue_free()

    ## Takes the overlay's uniforms off *from*, so every chunk walks and tints
    ## as the overlay was told to.
    func share(from: ShaderMaterial) -> void:
        var own := material as ShaderMaterial
        for uniform: StringName in SHARED:
            var value: Variant = from.get_shader_parameter(uniform)
            if own.get_shader_parameter(uniform) != value:
                own.set_shader_parameter(uniform, value)

    ## Without `clip_uv`, which clamps the texture coordinate to the region.
    ## The clamp held the coordinate still in the helper lanes beside a
    ## chunk's edge, so the shader's screen derivative on the chunk's first
    ## column of pixels came out a quarter of a texel at a zoom of 0.88 and the
    ## step meant to reach the texel beside never left the chunk.
    func _draw() -> void:
        if _texture != null:
            draw_texture_rect_region(_texture, _shown, _region, Color.WHITE, false, false)


## The quick mask's tint where the selection holds no chunk, and the shape a
## tool is dragging, without the material.
func _draw_plain() -> void:
    var selection := _shown()
    var document := _document()
    if selection != null and selection.active and _tinted(selection) and document != null:
        var tint := Color(1.0, 0.0, 0.0, 0.5)
        for quad: Rect2 in tint_quads(document.canvas_size, selection.chunks.keys()):
            _plain.draw_rect(quad, tint)
    var preview := _last_preview
    var outline := Color(1.0, 1.0, 1.0, 0.9)
    var shadow := Color(0.0, 0.0, 0.0, 0.6)
    # The plain layer is scaled by the zoom, so a width in document pixels
    # vanishes zoomed out and swells zoomed in. Every outline is sized in
    # screen pixels instead, as the rings and the handles are.
    var per_pixel := _screen_pixel()
    if preview.has("rect"):
        var rect: Rect2 = preview["rect"]
        if preview.get("dim", false):
            for quad: Rect2 in dim_quads(_dim_reach(rect), rect):
                _plain.draw_rect(quad, CROP_DIM)
        if preview.get("ellipse", false):
            var points := _ellipse_points(rect)
            _plain.draw_polyline(points, shadow, 3.0 * per_pixel)
            _plain.draw_polyline(points, outline, per_pixel)
        else:
            _plain.draw_rect(rect, shadow, false, 3.0 * per_pixel)
            _plain.draw_rect(rect, outline, false, per_pixel)
            if preview.get("handles", false):
                _draw_handles(rect, preview, outline, shadow)
            # A Freehand box at rest hands its grid over in place of the eight (d44).
            _draw_fills(preview)
            _draw_lines(preview, outline, shadow)
            _draw_knots(preview, outline, shadow)
        # The strip beside the box, for a painter who is looking at the canvas
        # rather than at the docker.
        _draw_cells(preview, outline, shadow)
    elif preview.has("quad"):
        # A transform can turn its box, and a Rect2 cannot say where a turned
        # box is. The handles are the same eight, found on the quad's own edges
        # rather than on a rectangle's.
        var quad: PackedVector2Array = preview["quad"]
        if quad.size() >= 4:
            var closed := quad.duplicate()
            closed.append(quad[0])
            _plain.draw_polyline(closed, shadow, 3.0 * per_pixel)
            _plain.draw_polyline(closed, outline, per_pixel)
            if preview.get("handles", false):
                _draw_quad_handles(quad, preview, outline, shadow)
            # The freehand warp's grid and its nine points, the cells drawn so a
            # painter sees what a point bends and not only where it is.
            _draw_lines(preview, outline, shadow)
            _draw_knots(preview, outline, shadow)
            _draw_cells(preview, outline, shadow)
    elif preview.has("discs"):
        # A region a tool is painting with a round brush, drawn as the discs the
        # mask is a union of and in the colour the tool names, which is the
        # patch tool's magenta today. Its own branch rather than a width on the
        # polyline below, because a thick polyline notches where a drag turns
        # and a preview that draws a different shape from the one the tool will
        # fill is a preview of nothing.
        var discs: PackedVector2Array = preview["discs"]
        var radius := float(preview.get("radius", 0.0))
        var fill: Color = preview.get("fill", outline)
        for at: Vector2 in discs:
            _plain.draw_circle(at, radius, fill)
    elif preview.has("points"):
        var points: PackedVector2Array = preview["points"]
        if points.size() >= 2:
            var closed := points.duplicate()
            if preview.get("closed", false):
                closed.append(points[0])
            _plain.draw_polyline(closed, shadow, 3.0 * per_pixel)
            _plain.draw_polyline(closed, outline, per_pixel)
        _draw_knots(preview, outline, shadow)
    elif preview.has("rings"):
        _draw_rings(preview, outline, shadow)


## The translucent boxes a tool hands over, such as the text tool's selected
## letters, drawn under the lines so a caret stays readable over them.
func _draw_fills(preview: Dictionary) -> void:
    for box: Rect2 in preview.get("fills", []):
        _plain.draw_rect(box, Color(0.25, 0.55, 1.0, 0.35))


## The polylines a tool hands over, drawn shadow then outline so they read over
## paint of any colour.
func _draw_lines(preview: Dictionary, outline: Color, shadow: Color) -> void:
    if not preview.has("lines"):
        return
    var per_pixel := _screen_pixel()
    for line: PackedVector2Array in preview["lines"]:
        _plain.draw_polyline(line, shadow, 3.0 * per_pixel)
        _plain.draw_polyline(line, outline, per_pixel)


## The points a tool hands over, each the square a handle is drawn as.
func _draw_knots(preview: Dictionary, outline: Color, shadow: Color) -> void:
    for point: Vector2 in preview.get("knots", PackedVector2Array()):
        _draw_square(preview, point, outline, shadow)


## One square a handle or a knot is drawn as, its shadow filled under its
## outline: five of the overlay's own pixels with an outline of one, or the
## preview's `handle_side` in screen pixels with an outline of one screen
## pixel, so a tool that names it keeps its handles one size at every zoom.
func _draw_square(preview: Dictionary, at: Vector2, outline: Color, shadow: Color) -> void:
    var per_pixel := _screen_pixel() if preview.has("handle_side") else 1.0
    var side := float(preview.get("handle_side", 5.0)) * per_pixel
    var box := Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side))
    _plain.draw_rect(box, shadow)
    _plain.draw_rect(box, outline, false, per_pixel)


## The cells a tool hands over: a box each, the picked one filled rather than
## outlined, and a glyph of polylines inside it.
##
## The boxes arrive in the overlay's own pixels, which are the document's, so
## this draws them where it is told. The line widths are screen pixels, which is
## the one thing here the tool did not say: a cell's edge is one pixel of the
## display at every zoom, the same rule `_screen_pixel()` gives the ants.
func _draw_cells(preview: Dictionary, outline: Color, shadow: Color) -> void:
    if not preview.has("cells"):
        return
    var per_pixel := _screen_pixel()
    for cell: Dictionary in preview["cells"]:
        var box: Rect2 = cell["box"]
        var on: bool = cell["on"]
        _plain.draw_rect(box, Color(0.0, 0.0, 0.0, 0.65) if not on else Color(1.0, 1.0, 1.0, 0.85))
        _plain.draw_rect(box, shadow if on else outline, false, per_pixel)
        var ink := Color(0.0, 0.0, 0.0, 0.9) if on else outline
        for line: PackedVector2Array in cell["glyph"]:
            _plain.draw_polyline(line, ink, per_pixel)


## The round handles a tool's points are dragged by, the gradient's two ends:
## a light dot in a dark rim, one size on screen at every zoom as the mirror
## axes' handles are, because a handle is reached by the hand and not by the
## picture. With `joined` the line through them goes under, one screen pixel
## over a shadow of three.
func _draw_rings(preview: Dictionary, outline: Color, shadow: Color) -> void:
    var per_pixel := _screen_pixel()
    var rings: PackedVector2Array = preview["rings"]
    if preview.get("joined", false) and rings.size() >= 2:
        _plain.draw_polyline(rings, shadow, 3.0 * per_pixel, true)
        _plain.draw_polyline(rings, outline, per_pixel, true)
    for at: Vector2 in rings:
        _plain.draw_circle(at, RING_RADIUS * per_pixel, shadow, true, -1.0, true)
        _plain.draw_circle(at, (RING_RADIUS - 2.0) * per_pixel, outline, true, -1.0, true)


## Document pixels per screen pixel, off the canvas's own transform.
##
## The transform's scale rather than `SaCanvas.scale`, for the reason
## `_keep_view_over` gives about reading the transform: the view mirrors on the
## sign of the scale and rotates about a pivot, and the transform is the only
## thing that has both right.
func _screen_pixel() -> float:
    if _canvas == null:
        return 1.0
    var view := _canvas.get_transform().get_scale()
    return 1.0 / maxf(absf(view.x), 0.01)


## The box the dim reaches to, around a rectangle in the overlay's own pixels,
## which are the document's.
##
## The same trick as the canvas's own background beyond the document, and the
## same constant: a box too large for any zoom to show its edge covers the
## viewport whatever the pan and the rotation are, so nothing here has to be
## redrawn when the view moves. Measuring the viewport instead would be exact
## and would go stale on the next pan, because the overlay redraws when the
## shape changes and not when the view does.
static func _dim_reach(around: Rect2) -> Rect2:
    var reach := SaCanvas.BACKGROUND_REACH
    return Rect2(around.get_center() - Vector2(reach, reach), Vector2(reach, reach) * 2.0)


## The four quads between *outer* and *inner*, dropping any the two rectangles
## leave empty. They meet without overlapping, because a quad drawn twice over
## another is twice as dark and the seam shows.
static func dim_quads(outer: Rect2, inner: Rect2) -> Array[Rect2]:
    var kept: Array[Rect2] = []
    var candidates: Array[Rect2] = [
        Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)),
        Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)),
        Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)),
        Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)),
    ]
    for quad: Rect2 in candidates:
        if quad.size.x > 0.0 and quad.size.y > 0.0:
            kept.append(quad)
    return kept


## The eight squares the crop tool's rectangle is pulled by, at the corners and
## the middles of the edges.
##
## Sized in the overlay's own pixels, which are the document's, so a handle
## grows with the zoom exactly as the rectangle does, unless the preview names
## a `handle_side`, as the transform's does. The crop tool's own reach is in
## screen pixels, because a grab is a gesture of the hand.
func _draw_handles(rect: Rect2, preview: Dictionary, outline: Color, shadow: Color) -> void:
    var corners := PackedVector2Array(
        [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
    )
    _draw_quad_handles(corners, preview, outline, shadow)


## The same eight squares on a quad rather than on a rectangle: its corners and
## the middles of its edges, which are the corners' own midpoints.
func _draw_quad_handles(quad: PackedVector2Array, preview: Dictionary, outline: Color, shadow: Color) -> void:
    for i in 4:
        _draw_square(preview, quad[i], outline, shadow)
        _draw_square(preview, quad[i].lerp(quad[(i + 1) % 4], 0.5), outline, shadow)


## The shape the active selection tool is dragging, or nothing.
func _tool_preview() -> Dictionary:
    if _canvas == null:
        return {}
    var machine := _canvas.get_node_or_null("ToolMachine") as ToolMachine
    var tool := machine.active_tool if machine != null else null
    if tool == null or not tool.has_method("preview_shape"):
        return {}
    return tool.preview_shape()


static func _ellipse_points(rect: Rect2, segments: int = 64) -> PackedVector2Array:
    var points := PackedVector2Array()
    var centre := rect.get_center()
    var radii := rect.size * 0.5
    for i in segments + 1:
        var angle := TAU * float(i) / float(segments)
        points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
    return points
