## The visible heights resolved into one texture for the view.
##
## A canvas item shader cannot walk a dictionary of chunk textures per pixel,
## so the height of every visible layer that carries one is flattened first,
## beside the composite and over the same dirty rectangles: summed, each layer
## weighted by its opacity, its groups' and its mask, into [member heights],
## and a normal derived from that sum into [member texture], which holds the
## normal in `rgb` and the summed height in `a`. The view lights the colour
## with it.
##
## **What it costs.** Nothing, in a document that carries no height: no
## texture is allocated and no cell is dispatched. A cell no visible layer has
## height in is skipped unless an earlier resolve left height there, which it
## writes back to bare once and then forgets. Only the cells the window shows
## are resolved, and the rest are held until it reaches them, as the composite
## holds its own.
##
## **The seam.** A normal reads the height one texel beyond its own, and at a
## chunk's edge that texel belongs to the next chunk. Summing first into a
## dense texture puts it there, so the normal pass reads it like any other,
## and every rectangle of that pass is grown by one texel so the normal beside
## a changed height moves with it.
##
## **The ground.** A layer that stores nothing and has a tooth, the paper,
## answers a height from its own generator, and it is added
## under the paint in the sum, cell by cell, after the paint's heights: its
## generator's `raise_tooth` kernel adds the tooth whole to the paint summed at
## each texel, since a stroke that covered the tooth already holds it filled,
## so the normal the view lights is the surface's, tooth and paint as one. A
## document whose paper shows a tooth has relief everywhere the paper reaches,
## and its cells are resolved the way a raised cell is.
##
## **The surface beneath a layer**, `beneath`, is the same sum over one chunk
## and fewer layers: those below the layer that show, and the grounds below
## it, into a texture of that chunk alone. A stroke stands on it, because a
## stroke reads every visible layer below its own, composited, the ground
## included, and a stroke writes its
## own layer's height as what it changed of that surface, which is why a
## height is signed. It shares the kernels and the weights with the view's
## sum, so what a stroke stands on is what the view shows of the layers under
## it.
class_name SaRelief
extends RefCounted

## The normal of the summed height in `rgb`, in the canvas's axes with z
## towards the viewer, and the summed height in `a`, in millimetres. Canvas
## sized, and null until a layer that shows carries height.
var texture: SaTexture = null

## The summed height alone, one half float a texel, which the normal pass
## reads around each texel it writes.
var heights: SaTexture = null

## Grid position -> true for every cell of the output's grid a resolve has
## written height into, so a cell whose height went away is written back to
## bare once, and a cell that never had any costs nothing.
var _raised: Dictionary[Vector2i, bool] = {}

## Grid position -> Rect2i in chunk-local pixels, what changed where the
## window did not reach and waits for it.
var _held: Dictionary[Vector2i, Rect2i] = {}

## Where weight, keep, present and masked sit in the sum's block.
const WEIGHT: int = 7
const KEEP: int = 8
const PRESENT: int = 9
const MASKED: int = 10

var _sum: SaCompute = null
var _normal: SaCompute = null
## The `blank` kernel both textures are blanked by when they are made.
var _blank: SaCompute = null

## What the sum binds where a layer holds no height or no mask here, which it
## never reads. One texel each, at the height's format and the mask's.
var _no_height: SaTexture = null
var _no_cover: SaTexture = null

## Generator name -> SaCompute of that generator's `.gmacs`, bound to the
## summed height's format, for its `raise_tooth` kernel.
var _teeth: Dictionary[String, SaCompute] = {}


## Resolves the cells *dirty* and *late* name, both grid position -> Rect2i in
## chunk-local pixels on the output's grid, where *window* reaches them. A
## *full* resolve adds every cell a layer holds height in, and every cell
## raised before, which is what a composite of every chunk asks of it.
func resolve(
    document: SaDocument, dirty: Dictionary[Vector2i, Rect2i], late: Dictionary[Vector2i, Rect2i], full: bool, window: Rect2
) -> void:
    if document == null or GlobalShaderCompiler.get_rd() == null:
        return
    var layers := _showing(document)
    var grounds := _grounds(document)
    if texture != null and texture.size != document.canvas_size:
        _drop()
    if layers.is_empty() and grounds.is_empty() and _raised.is_empty():
        # Nothing has height and nothing was left raised, so nothing is owed,
        # and a held cell would only be written back to the bare it holds.
        _held.clear()
        return

    var cells: Dictionary[Vector2i, Rect2i] = _held
    _held = {}
    for source: Dictionary[Vector2i, Rect2i] in [dirty, late]:
        for grid_pos: Vector2i in source:
            _merge(cells, grid_pos, source[grid_pos])
    if full:
        var whole := Rect2i(Vector2i.ZERO, Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
        for grid_pos: Vector2i in _raised:
            _merge(cells, grid_pos, whole)
        for layer: SaLayer in layers:
            var paint := SaLiveTransform.paint_of(layer)
            for grid_pos: Vector2i in paint.chunks:
                if paint.chunks[grid_pos].has_field(SaFieldSpec.HEIGHT):
                    _merge(cells, grid_pos, whole)
        if not grounds.is_empty():
            for grid_pos: Vector2i in SaLayer.grid_positions(document.canvas_size):
                _merge(cells, grid_pos, whole)

    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    var normals: Array[Rect2i] = []
    for grid_pos: Vector2i in cells:
        var cell := Rect2(Vector2(grid_pos * SaLayer.CHUNK_SIZE), Vector2(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
        if not window.intersects(cell):
            _held[grid_pos] = cells[grid_pos]
            continue
        var region: Rect2i = cells[grid_pos]
        var rect := Rect2i(grid_pos * SaLayer.CHUNK_SIZE + region.position, region.size).intersection(canvas)
        if not rect.has_area():
            continue
        if _sum_cell(document, layers, grounds, grid_pos, rect):
            normals.append(rect.grow(1).intersection(canvas))
    if normals.is_empty():
        return
    var pixel_mm := 25.4 / (document.dpi if document.dpi > 0.0 else SaDocument.DEFAULT_DPI)
    _normal.set_texture(0, texture.rid)
    _normal.set_texture(1, heights.rid)
    for rect: Rect2i in normals:
        _normal.set_push_constant_float_array(
            PackedFloat32Array([rect.position.x, rect.position.y, rect.size.x, rect.size.y, pixel_mm])
        )
        _normal.dispatch_kernel("derive_normal", SaCompute.groups_for(rect.size.x), SaCompute.groups_for(rect.size.y), 1)


## How high above the canvas the relief's light stands, in degrees. Fixed, as
## an art director would fix it: low enough that a tenth of a millimetre casts a
## visible shade, high enough that a flat face is not in the dark. Here rather
## than on the view, because the view and a flat export light the same relief
## and must stand the light in one place.
const LIGHT_ELEVATION: float = 45.0


## The direction from the surface to the light at *bearing_degrees*, which is
## Preferences' Light direction, in the canvas's axes, x right, y down and z
## towards the viewer, at [constant LIGHT_ELEVATION] above the canvas.
static func light_toward(bearing_degrees: float) -> Vector3:
    var bearing := deg_to_rad(bearing_degrees)
    var elevation := deg_to_rad(LIGHT_ELEVATION)
    return Vector3(sin(bearing) * cos(elevation), -cos(bearing) * cos(elevation), sin(elevation))


## Whether any layer of *document* the view shows carries a height, which is
## what turns a flat export's Include impasto lighting on by default.
static func shows_height(document: SaDocument) -> bool:
    return document != null and not _showing(document).is_empty()


## The surface beneath *layer* over the chunk at *grid_pos*, what a stroke on
## it stands on: the height of every layer of *document* below *layer* that
## the view shows, summed and weighted as the view sums them, with the tooth
## of every ground below it added the way the view adds it. A layer above
## *layer*, one that does not show, and *layer*'s own height are left out.
##
## A new texture of the one chunk at the document's resolution, one half float
## a texel, whose texel lies at the chunk's corner plus its own position in
## document pixels, so a kernel on a layer held at another resolution reads it
## where its own texel lies across the chunk. Written whole by its first
## dispatch, so it needs no clear, and nought where nothing lies below. Null
## with no rendering device, or for a layer that is not one of *document*'s.
func beneath(document: SaDocument, layer: SaLayer, grid_pos: Vector2i) -> SaTexture:
    if document == null or layer == null or layer.get_parent() != document or GlobalShaderCompiler.get_rd() == null:
        return null
    var at := layer.get_index()
    var holding: Array[SaLayer] = []
    for below: SaLayer in _showing(document):
        if below.get_index() < at and _height(below, grid_pos) != null:
            holding.append(below)
    var grounds: Array[SaLayer] = []
    for ground: SaLayer in _grounds(document):
        if ground.get_index() < at:
            grounds.append(ground)
    _make_kernels()
    var edge := SaLayer.CHUNK_SIZE
    var surface := SaTexture.new(Vector2i(edge, edge), RenderingDevice.DATA_FORMAT_R16_SFLOAT)
    _sum_into(surface, holding, grounds, grid_pos, Rect2i(0, 0, edge, edge), Vector2i.ZERO)
    return surface


## The paint beneath *layer* over the chunk at *grid_pos*, what a stroke on it
## can push the colour of: its colour first and its height second, or nothing
## where no paint below has a height to push. The paint is every layer of
## *document* below *layer* that stores paint and shows, the Background and
## every ground left out, since a stroke pushes paint and not the sheet it lies
## on. A group, a generated, adjustment, effect or scene layer stores no paint
## of its own and is left out with them.
##
## The colour is those layers composited as the view composites them, each
## through its filters, its mask and its clip, by its mode and its opacity and
## its groups', over nothing, at the format of their chunks. A group that
## isolates is composited through rather than as one, which is as near as one
## chunk of colour comes. The height is theirs alone, summed as `beneath` sums
## it but with no ground's tooth, so a stroke weighs the colour by the paint's
## own body and never by the grain of the paper.
##
## Two new textures of the one chunk at the document's resolution, read where
## `beneath` is read. Empty with no rendering device, for a layer that is not
## one of *document*'s, and where no layer below holds a height in the chunk,
## which is where the colour below would weigh nothing.
func paint_beneath(document: SaDocument, layer: SaLayer, grid_pos: Vector2i) -> Array[SaTexture]:
    var none: Array[SaTexture] = []
    if document == null or layer == null or layer.get_parent() != document or GlobalShaderCompiler.get_rd() == null:
        return none
    var paint := _paint_below(document, layer.get_index())
    var holding: Array[SaLayer] = []
    for below: SaLayer in paint:
        if below.carries_height() and _height(below, grid_pos) != null:
            holding.append(below)
    if holding.is_empty():
        return none
    var edge := SaLayer.CHUNK_SIZE
    var whole := Rect2i(0, 0, edge, edge)
    var colour := _composite_below(document, paint, grid_pos, whole)
    if colour == null:
        return none
    _make_kernels()
    var height := SaTexture.new(Vector2i(edge, edge), RenderingDevice.DATA_FORMAT_R16_SFLOAT)
    var no_grounds: Array[SaLayer] = []
    _sum_into(height, holding, no_grounds, grid_pos, whole, Vector2i.ZERO)
    var found: Array[SaTexture] = [colour, height]
    return found


## Every layer below the index *at* that stores paint and shows, bottom first,
## leaving out the Background, the stored layer a document is made with at the
## bottom of its stack under that name, the way `SaGeneratedLayer.ground_index`
## knows it.
static func _paint_below(document: SaDocument, at: int) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer.get_index() >= at or layer.is_group or layer.is_generated():
            continue
        if layer.is_adjustment() or layer.is_effect() or layer.is_scene():
            continue
        if layer.get_index() == 0 and str(layer.name) == SaDocumentBackground.LAYER_NAME:
            continue
        if SaLayerStack.shows(document, layer):
            found.append(layer)
    return found


## The layers of *paint* at *grid_pos* composited over nothing into a new
## texture of the chunk, as the view composites each, or null where none of
## them shows anything there.
func _composite_below(document: SaDocument, paint: Array[SaLayer], grid_pos: Vector2i, whole: Rect2i) -> SaTexture:
    var compositor := document.compositor
    if compositor == null:
        return null
    var colour: SaTexture = null
    for below: SaLayer in paint:
        var source := compositor.shown(below, below, below.get_field(grid_pos), grid_pos, whole, below)
        if source == null:
            continue
        var base := SaLayerStack.clip_base(document, below)
        if base != null:
            var alpha := compositor.clip_alpha(base, grid_pos, whole)
            if alpha == null:
                continue
            source = compositor.clip_chunk(source, alpha, whole)
        if colour == null:
            colour = SaTexture.new(whole.size, source.format)
            if _blank == null:
                _blank = SaCompute.new("blank")
            _blank_whole(colour, Color(0, 0, 0, 0))
        compositor.composite_chunk(
            colour,
            source,
            below.get_blend_mode_name(),
            SaHeightOps.opacity_of(below),
            Vector2.ZERO,
            document.color_space,
            document.blend_reference_white,
            whole
        )
    return colour


## *layer*'s height at *grid_pos* where the view shows it, which for a layer
## drawn through a live transform is its cache's, `SaLiveTransform.paint_of`,
## so the relief moves with the colour. Null where it holds none there.
static func _height(layer: SaLayer, grid_pos: Vector2i) -> SaTexture:
    return SaLiveTransform.paint_of(layer).get_field(grid_pos, SaFieldSpec.HEIGHT)


## What hides *layer*'s height at *grid_pos*: its mask, or nothing for a layer
## drawn through a live transform, whose cache holds the mask folded in.
static func _cover(layer: SaLayer, grid_pos: Vector2i) -> SaTexture:
    return SaCompositor.coverage_at(layer, grid_pos) if SaLiveTransform.paint_of(layer) == layer else null


## Every layer whose height the view shows: one that stores paint, carries a
## height, and draws, its groups and its clip base with it.
static func _showing(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer.is_group or layer.is_generated() or not layer.carries_height():
            continue
        if SaLayerStack.shows(document, layer):
            found.append(layer)
    return found


## Every layer that stores nothing, shows, and has a tooth: the grounds whose
## height goes under the paint.
static func _grounds(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or not layer.is_generated() or SaGeneratedLayer.tooth_of(layer) <= 0.0:
            continue
        if SaLayerStack.shows(document, layer):
            found.append(layer)
    return found


## Sums every layer of *layers* holding height at *grid_pos* over *rect*, in
## canvas pixels, adds every ground of *grounds* under it, and answers whether
## anything was written. A cell with none is written back to bare when an
## earlier resolve raised it, and skipped when none did.
func _sum_cell(document: SaDocument, layers: Array[SaLayer], grounds: Array[SaLayer], grid_pos: Vector2i, rect: Rect2i) -> bool:
    var holding: Array[SaLayer] = []
    for layer: SaLayer in layers:
        if _height(layer, grid_pos) != null:
            holding.append(layer)
    if holding.is_empty() and grounds.is_empty() and not _raised.has(grid_pos):
        return false
    _allocate(document.canvas_size)
    _sum_into(heights, holding, grounds, grid_pos, rect, grid_pos * SaLayer.CHUNK_SIZE)
    if holding.is_empty() and grounds.is_empty():
        # Written back to bare, the cell is forgotten.
        _raised.erase(grid_pos)
        return true
    _raised[grid_pos] = true
    return true


## Sums the height each layer of *holding* holds at *grid_pos* into *total*
## over *rect*, in *total*'s own pixels, each weighted by its opacity, its
## groups' and its mask, and adds the tooth of every ground of *grounds* under
## it. *corner* is where the chunk at *grid_pos* starts in *total*'s pixels:
## the chunk's own corner in the view's canvas sized sum, and nought in a
## texture of the chunk alone. The first dispatch writes where the rest add,
## so *total* needs no clear, and with no layer to sum it writes nought.
func _sum_into(
    total: SaTexture, holding: Array[SaLayer], grounds: Array[SaLayer], grid_pos: Vector2i, rect: Rect2i, corner: Vector2i
) -> void:
    # The block as `relief_sum.gmacs` declares it: the rectangle, the cell's
    # corner and span, then weight, keep, present and masked.
    var params := PackedFloat32Array(
        [rect.position.x, rect.position.y, rect.size.x, rect.size.y, corner.x, corner.y, SaLayer.CHUNK_SIZE, 0.0, 0.0, 0.0, 0.0]
    )
    _sum.set_texture(0, total.rid)
    if holding.is_empty():
        _dispatch_sum(rect, params, _no_height, _no_cover)
    for layer: SaLayer in holding:
        var cover := _cover(layer, grid_pos)
        params[WEIGHT] = SaHeightOps.opacity_of(layer)
        params[PRESENT] = 1.0
        params[MASKED] = 1.0 if cover != null else 0.0
        _dispatch_sum(rect, params, _height(layer, grid_pos), cover if cover != null else _no_cover)
        params[KEEP] = 1.0
    # The document position of *total*'s first texel, which is where the
    # ground reads its grain.
    var offset := Vector2(grid_pos * SaLayer.CHUNK_SIZE - corner)
    for ground: SaLayer in grounds:
        _add_ground(ground, total, offset, rect)


## Adds *ground*'s tooth under the paint summed into *total* over *rect*, by
## its generator's own kernel at the document position, *offset* plus the
## texel, so the grain in the light is the grain in the colour.
func _add_ground(ground: SaLayer, total: SaTexture, offset: Vector2, rect: Rect2i) -> void:
    var compute: SaCompute = _teeth.get(ground.generator)
    if compute == null:
        compute = SaCompute.new(ground.generator)
        compute.use_storage_format(RenderingDevice.DATA_FORMAT_R16_SFLOAT)
        _teeth[ground.generator] = compute
    # The view's sum is dense and canvas sized, so its offset is nought and
    # the texel is the document position. The surface beneath a layer is one
    # chunk, offset by the chunk's corner.
    compute.set_texture(0, total.rid)
    SaGeneratedLayer.bind_params(compute, ground, offset, rect, SaHeightOps.opacity_of(ground))
    compute.dispatch_kernel("raise_tooth", SaCompute.groups_for(rect.size.x), SaCompute.groups_for(rect.size.y), 1)


## One layer's height, or the stand-in, summed over *rect* by *params*.
func _dispatch_sum(rect: Rect2i, params: PackedFloat32Array, height: SaTexture, cover: SaTexture) -> void:
    _sum.set_texture(1, height.rid)
    _sum.set_texture(2, cover.rid)
    _sum.set_push_constant_float_array(params)
    _sum.dispatch_kernel("sum_height", SaCompute.groups_for(rect.size.x), SaCompute.groups_for(rect.size.y), 1)


## Allocates both textures at *size*, bare, the first time a cell has height
## to show. Blanked once here and never again: every texel after this is
## written by a dispatch over a dirty rectangle.
##
## Blanked by the `blank` kernel rather than a transfer clear,
## because the same resolve sums into `heights` and derives the normal from it
## next, and a transfer is not ordered against the compute that follows it.
## The normal pass reads a texel beyond what it writes, so on the rim of a
## raised cell it would light the neighbour's texels from whatever the
## allocation held. Once per canvas size, the work a clear would do, and never
## a pass of a stroke's.
func _allocate(size: Vector2i) -> void:
    if texture != null:
        return
    heights = SaTexture.new(size, RenderingDevice.DATA_FORMAT_R16_SFLOAT)
    texture = SaTexture.new(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
    if _blank == null:
        _blank = SaCompute.new("blank")
    _blank_whole(heights, Color(0, 0, 0, 0))
    _blank_whole(texture, Color(0, 0, 1, 0))
    _make_kernels()


## Makes the sum's and the normal's kernels and the sum's stand-ins, once.
func _make_kernels() -> void:
    if _sum != null:
        return
    _sum = SaCompute.new("relief_sum")
    _sum.use_storage_format(RenderingDevice.DATA_FORMAT_R16_SFLOAT)
    _normal = SaCompute.new("relief_normal")
    _normal.use_storage_format(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
    _normal.use_binding_format(1, RenderingDevice.DATA_FORMAT_R16_SFLOAT)
    _no_height = SaTexture.new(Vector2i(1, 1), RenderingDevice.DATA_FORMAT_R16_SFLOAT)
    _no_cover = SaTexture.new(Vector2i(1, 1), RenderingDevice.DATA_FORMAT_R32_SFLOAT)


## Writes *value* over the whole of *target* on the compute queue.
func _blank_whole(target: SaTexture, value: Color) -> void:
    var size := target.size
    _blank.use_storage_format(target.format)
    _blank.set_texture(0, target.rid)
    _blank.set_push_constant_float_array(PackedFloat32Array([value.r, value.g, value.b, value.a, 0.0, 0.0, size.x, size.y]))
    _blank.dispatch_kernel("blank_region", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)


## Lets go of both textures and what they held, for a canvas that changed its
## size. The full composite a resize schedules resolves everything again.
func _drop() -> void:
    texture = null
    heights = null
    _raised.clear()
    _held.clear()


## Merges *region* into what *into* holds at *grid_pos*.
static func _merge(into: Dictionary[Vector2i, Rect2i], grid_pos: Vector2i, region: Rect2i) -> void:
    into[grid_pos] = (into[grid_pos] as Rect2i).merge(region) if into.has(grid_pos) else region
