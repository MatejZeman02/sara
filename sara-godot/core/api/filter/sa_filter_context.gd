## What a filter's `run` is handed: the layer's pixels on the GPU, a blank
## beside them, its module's own kernels, and somewhere to put the result.
##
## Nothing here reads a texel back to the CPU. A filter
## asks for [method layer_pixels], dispatches over it and hands the result to
## [method show], and the pixels never leave VRAM between those three calls.
## [method read_pixels] is the one readback the rule permits, and a filter has
## to ask for it by name.
##
## A point filter, one whose every output pixel reads only the same input pixel,
## answers the other way: it calls [method point_pass] in place of the three
## calls above, and nothing is copied, allocated or shown. The pass is recorded,
## the dialog hands it to the compositor for the preview on the canvas, and
## Apply walks it once over the chunks.
##
## Made for one document, one layer and one module, and dropped when the dialog
## closes. Deliberately not reusable across layers: the rectangle it answers is
## a fact about the layer it was built for, and a context that outlived its
## layer would hand a filter pixels from somewhere else.
class_name SaFilterContext
extends RefCounted

## The reach [method neighbourhood_pass] takes for a filter whose texel reads
## anywhere on the layer, a kaleidoscope folding a wedge from across the canvas.
## The pass's own value, named here so a filter's `run` asks the door for it.
const WHOLE_NODE: int = SaNeighbourhoodPass.WHOLE_NODE
## Where a whole-layer pass writes, the option [method neighbourhood_pass]
## takes last: the chunks the layer holds and nothing else, the default.
const WRITES_LAYER: int = SaNeighbourhoodPass.WRITES_NODE
## A whole-layer pass that may write anywhere on the canvas, so paint lands
## where the layer held no chunk and a chunk is allocated for it.
const WRITES_CANVAS: int = SaNeighbourhoodPass.WRITES_CANVAS

## The most texels one dispatch of a filter's preview covers, the bound chosen
## for it: 256 by 256, the texels of a chunk on a plain layer.
##
## A long piece of work is what a weak integrated GPU's Vulkan driver meets its
## own limit on, and the app vanishes with it. A point pass's preview runs a
## chunk at a time, so the bound cuts what is larger: the chunk of a layer at
## twice the document's resolution, 512 texels on a side, and the dialog's
## thumbnail, 400 texels on a side. A texel budget and not a chunk's
## size, so it stays put when the chunk's size changes.
const SUBMIT_TEXELS: int = 65536
## The side of the square pieces [method submits] cuts, whose area is
## [const SUBMIT_TEXELS]. A multiple of every workgroup a kernel declares, so a
## piece inside a region ends on a group's edge and no texel is dispatched by
## two pieces, which a kernel rewriting its texture in place would run twice.
const SUBMIT_SIDE: int = 256

## How many pieces [method run_point_in_submits] and the neighbourhood runner
## have dispatched, and the texels of the largest, since
## [method count_submits_from_zero]. Read by a suite, which holds them against
## the kernel's own tally in `SaCompute`, and written through
## [method note_submit] alone.
static var submitted: int = 0
static var largest_submit: int = 0

## The rectangle the last [method layer_pixels] covered, in document pixels.
##
## Public because it is the run's frame of reference: the dialog draws the
## preview over it and apply writes back into it. Written here alone.
var rect: Rect2i = Rect2i()

## The texels a document pixel of the layer holds on a side, 1.0 on a plain
## layer and 2.0 on one at twice the document's resolution.
##
## Read by a filter that measures something in the texture it is handed, which
## is in the layer's texels while [member rect] stays in document pixels. A
## length a filter declares to [method neighbourhood_pass], its radius, is in
## document pixels and multiplied by this in the pass, so a filter that never
## reads it still blurs the same distance on the canvas. Written here alone,
## from the layer the context was made for.
var scale: float = 1.0

## The last texture handed to [method show], and the rectangle it covers.
##
## Apply is the only thing that consumes them, and it consumes the pair: a
## texture without the rectangle it belongs to is pixels with no place to go.
var shown: SaTexture = null
var shown_rect: Rect2i = Rect2i()

## The pass the last run recorded through [method point_pass] or
## [method neighbourhood_pass], or null for a filter that shows a texture
## instead. Written here alone.
var point: SaPointPass = null

var document: SaDocument = null
var layer: SaLayer = null
var module_id: StringName = &""
## What one history step this run records is called, which is the filter's own
## title. A constructor argument rather than something the host writes
## afterwards, so the name a `write_pixels` records and the name the dialog's
## apply records are one string given once.
var _step_name: String = "Filter"

## Kernel name as the filter wrote it -> the SaCompute built for it.
##
## Held because `run` is called again on every widget change, and building an
## SaCompute reloads pipelines. A filter that asks for the same kernel on every
## rerun gets the same instance rather than a recompile per keystroke.
var _kernels: Dictionary[String, SaCompute] = {}

## Whether this run is a preview a dialog will ask for again.
##
## The GPU door needs no such thing: `show` writes nothing and Apply is the only
## writer, so a rerun costs a dispatch and no history. The CPU door's
## `write_pixels` writes, and the dialog calls `run` when it opens and after
## every widget change, so without this, opening a CPU filter would write the
## layer before the painter touched anything, every slider frame would write it
## again, and Cancel would undo none of it.
##
## A constructor argument and not a flag written from outside, because a
## private member is written by its own class only. The dialog passes `true`
## and nothing else does, so a `write_pixels` from a script or a suite still
## writes on the spot.
var _previewing: bool = false


func _init(
    in_doc: SaDocument, on_layer: SaLayer, for_module: StringName = &"", step_name: String = "Filter", previewing: bool = false
) -> void:
    document = in_doc
    layer = on_layer
    module_id = for_module
    _step_name = step_name
    _previewing = previewing
    scale = SaFilterDensity.scale_of(layer)


## The document's canvas in pixels, what a filter measures a centre or an
## offset against. A question of the document asked when the run needs it, so a
## context a dialog keeps open answers the canvas as it is now. Zero with no
## document.
func canvas_size() -> Vector2i:
    return document.canvas_size if document != null else Vector2i.ZERO


## The rectangle a run with *margin* covers, in document pixels.
##
## The selection when one is active, the layer's allocated bounds otherwise,
## grown by *margin* on every side so a neighbourhood read stays inside, and
## clamped to the canvas. A layer with nothing allocated and no selection
## answers the whole canvas: a filter that generates rather than transforms has
## no painted bounds to work from, and an empty rectangle is a texture that
## cannot be allocated at all.
func rect_for(margin: int) -> Rect2i:
    if document == null:
        return Rect2i()
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    var base := canvas
    var selection := document.selection
    if selection != null and selection.active:
        base = selection.bounds
    elif layer != null and not layer.chunks.is_empty():
        base = _allocated_bounds()
    var grown := Rect2i(base.position - Vector2i(margin, margin), base.size + Vector2i(margin, margin) * 2)
    return grown.intersection(canvas)


## *region* cut into pieces of at most [const SUBMIT_TEXELS], left to right and
## top to bottom from its corner, every piece *side* on a side but the last of
## a row or a column. Empty for an empty region. *side* is
## [const SUBMIT_SIDE] but for a suite that holds the cut against one dispatch.
static func submits(region: Rect2i, side: int = SUBMIT_SIDE) -> Array[Rect2i]:
    var out: Array[Rect2i] = []
    if region.size.x <= 0 or region.size.y <= 0:
        return out
    var y := region.position.y
    while y < region.end.y:
        var x := region.position.x
        while x < region.end.x:
            out.append(Rect2i(x, y, mini(side, region.end.x - x), mini(side, region.end.y - y)))
            x += side
        y += side
    return out


## *recorded*, a point pass, dispatched on *compute* over *region* of the
## texture already bound, one dispatch a piece of [method submits]. Each piece
## is handed its own corner as the pass's origin, which is the contract on
## [SaPointPass], and *corner* as the chunk's document corner. Every texel of
## *region* is run once, so the result is the one dispatch's texel for texel.
##
## A dispatch and not a `vkQueueSubmit`: the device Sara draws on sends a
## frame's work in one submission, so the pieces are where a driver can stop
## between two kernels, and the frame holds no more of them than the window
## shows.
static func run_point_in_submits(compute: SaCompute, recorded: SaPointPass, region: Rect2i, corner: Vector2i) -> void:
    for piece: Rect2i in submits(region):
        compute.set_push_constant_float_array(recorded.push_for(piece.position, corner))
        compute.dispatch_kernel(recorded.kernel, SaCompute.groups_for(piece.size.x), SaCompute.groups_for(piece.size.y), 1)
        note_submit(piece)


## Counts *piece* as one dispatch of [method submits] in [member submitted]
## and [member largest_submit]. Called by this class and by the neighbourhood
## runner, which cuts its steps into the same pieces.
static func note_submit(piece: Rect2i) -> void:
    submitted += 1
    largest_submit = maxi(largest_submit, piece.get_area())


## Puts [member submitted] and [member largest_submit] back to zero, so a
## suite measures one frame rather than a session.
static func count_submits_from_zero() -> void:
    submitted = 0
    largest_submit = 0


## The layer's pixels over [method rect_for], copied GPU to GPU into one texture.
##
## At the layer's own density: [member scale] texels a document pixel on a
## side, so on a layer at twice the document's resolution the texture is twice
## [member rect] on a side and a margin reaches twice as many texels. *margin*
## is in document pixels, like [member rect].
##
## One `texture_copy` per allocated chunk the rectangle reaches, never a
## dispatch and never a readback. What no chunk covers stays transparent, which
## is what a margin past the painted edge has to read as.
func layer_pixels(margin: int = 0) -> SaTexture:
    rect = rect_for(margin)
    # Told here as well as in `kernel()`, because the two are written in either
    # order and a kernel asked for first would otherwise dispatch over the
    # previous rerun's rectangle.
    for compute: SaCompute in _kernels.values():
        compute.use_region(rect)
    if rect.size.x <= 0 or rect.size.y <= 0:
        SaProblems.report("SaFilterContext", "the run's rectangle is empty, so there are no pixels to hand out.")
        return null
    var texture := SaTexture.new(SaFilterDensity.texels(rect, SaFilterDensity.side_of(layer)), field_format())
    # A fresh SaTexture is undefined rather than blank (core/api/gpu/sa_texture.gd),
    # and every texel outside the allocated chunks is one this loop never
    # writes, so the clear is the only thing that makes the margin readable.
    texture.clear(Color(0.0, 0.0, 0.0, 0.0))
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or layer == null:
        return texture
    for grid_pos: Vector2i in layer.chunks.keys():
        var chunk: SaChunk = layer.chunks[grid_pos]
        if chunk == null:
            continue
        var source := chunk.field(SaFieldSpec.ALBEDO)
        if source == null:
            continue
        # The chunk's share in its own texels, placed at the layer's density,
        # so a chunk at 2.0 lands as 512 texels over its 256 pixels.
        SaFilterDensity.copy_share(rd, source, grid_pos, rect, texture)
    return texture


## An empty texture of the same size and depth as *texture*.
##
## Cleared, unlike a bare allocation, because a kernel that writes only where it
## has something to say leaves the rest showing whatever the driver handed back.
func blank_like(texture: SaTexture) -> SaTexture:
    if texture == null:
        return null
    var blank := SaTexture.new(texture.size, texture.format)
    blank.clear(Color(0.0, 0.0, 0.0, 0.0))
    return blank


## The module's own kernel called *name*, compiled the way a built-in's is.
##
## A bare name is qualified with the owner the shader index filed the module's
## `.gmacs` under, which is its folder rather than its id: see
## [method _shader_owner] for why the two are not always the same word. A
## module's shader goes through the door a built-in's does: a student's kernel
## is resolved by the
## same index, at the same depth, through the same compiler as `composite`.
func kernel(name: String) -> SaCompute:
    if _kernels.has(name):
        var known: SaCompute = _kernels[name]
        known.use_region(rect)
        return known
    var compute := SaCompute.new(_qualified(name))
    compute.use_storage_format(field_format())
    compute.use_region(rect)
    _kernels[name] = compute
    return compute


## Records the run as a point pass: the module's *shader*, the entry point
## *kernel_name* in it, the push constant *push* and *buffers* by binding, with
## the region's origin written into the two floats at *origin_slot* per
## dispatch. What the kernel has to be is written on [SaPointPass].
##
## A kernel whose push constant block names `chunk` gets the chunk's document
## corner there, found by name as a neighbourhood pass finds its `origin` and
## `halo`, so no filter has to know where the field sits.
##
## Nothing is dispatched here. The compute is built now, and kept, so a rerun on
## every slider frame reuses one set of pipelines and Apply dispatches through
## the same instance.
func point_pass(
    shader: String, kernel_name: String, push: PackedFloat32Array, buffers: Dictionary = {}, origin_slot: int = 0
) -> void:
    rect = rect_for(0)
    var qualified := _qualified(shader)
    kernel(qualified)
    var corner_at := GlobalShaderCompiler.source.push_constant_offset(qualified, "chunk")
    var corner_slot := floori(corner_at / 4.0) if corner_at >= 0 else -1
    point = SaPointPass.new(qualified, kernel_name, push, _bound(buffers), origin_slot, corner_slot)


## Records the run as a neighbourhood pass: the module's *shader*, the entry
## point *kernel_name* in it, its *params* by name, and the *radius* in
## document pixels it reads its neighbours within, or [const WHOLE_NODE]. What
## the kernel has to be is written on [SaNeighbourhoodPass].
##
## *writes* is where a pass of [const WHOLE_NODE] writes: [const WRITES_LAYER]
## keeps it to the chunks the layer holds, and [const WRITES_CANVAS] lets it
## write where the layer holds nothing yet. A pass with a radius writes its
## chunks and the ring its halo reaches whatever this says.
##
## The door a blur takes in place of [method layer_pixels], [method blank_like]
## and [method show]: nothing is copied, allocated or shown here. The compositor
## gathers each chunk with its neighbours when the filter is attached or
## previewed, and Apply walks the same record over the layer, so the two forms
## come from one `run`.
func neighbourhood_pass(
    shader: String, kernel_name: String, params: Dictionary, radius: int, buffers: Dictionary = {}, writes: int = WRITES_LAYER
) -> void:
    rect = rect_for(radius)
    var qualified := _qualified(shader)
    kernel(qualified)
    point = SaNeighbourhoodPass.new(qualified, kernel_name, SaTyped.strings(params), radius, _bound(buffers), writes)


## Adds *kernel_name*, a kernel of the file [method neighbourhood_pass] named,
## with its *params* by name, as the next step of the pass it recorded. A
## separable blur is `neighbourhood_pass` with the pass across and this with
## the pass down, and the *radius* given there is the reach of every step
## together. What each step's kernel reads and writes is written on
## [SaNeighbourhoodPass]. Refused with a problem when no neighbourhood pass was
## recorded first, since there is nothing to add a step to.
##
## *coarser* is for a step whose threads count on a level of a pyramid, the
## times the frame is halved there, so its dispatch is cut into
## [const SUBMIT_TEXELS] in that level's own space. 0, the default, is a step
## whose threads count texel for texel.
func neighbourhood_step(kernel_name: String, params: Dictionary, coarser: int = 0) -> void:
    if not point is SaNeighbourhoodPass:
        SaProblems.report(
            "SaFilterContext",
            TranslationServer.translate("%s was added as a step before any neighbourhood pass was recorded.") % kernel_name
        )
        return
    (point as SaNeighbourhoodPass).then(kernel_name, SaTyped.strings(params), coarser)


## *buffers* as a pass holds them. The door's argument stays a plain
## Dictionary, because a module builds it as a literal in its own untyped
## code, and is typed here where it enters.
static func _bound(buffers: Dictionary) -> Dictionary[int, SaCompute.Buffer]:
    var out: Dictionary[int, SaCompute.Buffer] = {}
    out.assign(buffers)
    return out


## Puts *texture* in the preview, and keeps it for apply.
func show(texture: SaTexture) -> void:
    shown = texture
    shown_rect = rect


## The layer's pixels over the run's rectangle, as an `RGBAF` `Image`.
##
## The readback door, and the only one the filter door has: everything above
## keeps the texels in VRAM, and this hands them to the CPU because a lab that
## wants a loop a student can single-step has nowhere else to go. Explicit, once
## per call, and never inside a stroke.
func read_pixels(margin: int = 0) -> Image:
    return SaFilterPixels.read(self, margin)


## Writes *image* back over the region [method read_pixels] answered, as one
## history step named after the filter. Answers whether it wrote.
##
## Through the same apply the GPU door uses, so the two record one shape of
## history and the layer keeps exactly one writer.
func write_pixels(image: Image) -> bool:
    return SaFilterPixels.write(self, image, _step_name)


## One pixel of *image* with the coordinates clamped to its edge.
##
## What a neighbourhood loop reads with, because `Image.get_pixel` outside the
## picture is an error and a loop over a rectangle reads outside it by
## definition.
func pixel(image: Image, at: Vector2i) -> Color:
    return SaFilterPixels.at(image, at.x, at.y)


## What the textures this context hands out are in, by name.
##
## A filter that only wants to branch on the space reads this. One that wants
## the descriptor behind it, its gamut, its white or its depth, reads
## `document.color_space`, which is why there is no second helper for that.
func color_space() -> String:
    return SaFilterColorSpaces.name_of(_space())


## *texture* converted from the document's space into sRGB, as a new texture.
##
## The door for a lab whose formula is written for sRGB. The answer is always a
## fresh texture, so writing to it never writes to what was handed in.
func to_srgb(texture: SaTexture) -> SaTexture:
    return _converted(texture, _space(), SaFilterColorSpaces.srgb_like(_space()))


## *texture* read as sRGB and converted back into the document's space.
func from_srgb(texture: SaTexture) -> SaTexture:
    return _converted(texture, SaFilterColorSpaces.srgb_like(_space()), _space())


## *texture* converted into linear sRGB, for a filter that wants linear light.
##
## The same door as [method to_srgb] and asked for the same way, which is the
## point: light and display are two targets of one conversion, not two ideas.
func to_linear(texture: SaTexture) -> SaTexture:
    return _converted(texture, _space(), SaFilterColorSpaces.linear_like(_space()))


## *texture* read as linear sRGB and converted back into the document's space.
func from_linear(texture: SaTexture) -> SaTexture:
    return _converted(texture, SaFilterColorSpaces.linear_like(_space()), _space())


## The space the document stores its colours in, or null when there is none.
func _space() -> SaColorSpace:
    return document.color_space if document != null else null


## One conversion, through the kernel this context already caches by name.
##
## Asked for through [method kernel] rather than held here, so the conversion
## shares the filter's own instance and its variant: a second `SaCompute` over
## the same shader is a second set of pipelines for nothing.
func _converted(texture: SaTexture, source: SaColorSpace, target: SaColorSpace) -> SaTexture:
    return SaFilterColorSpaces.converted(kernel(SaFilterColorSpaces.KERNEL), texture, source, target)


## The `<owner>/<name>` the shader index knows a module's kernel by.
##
## A name the filter already qualified is taken as written, so a module may
## reach a library kernel of Sara's own by saying `sara/thumbnail`.
func _qualified(name: String) -> String:
    if name.contains("/") or String(module_id).is_empty():
        return name
    return "%s/%s" % [_shader_owner(), name]


## The owner the shader index filed this module's kernels under, which is its
## **folder** and not its id.
##
## The two part wherever a folder's name is not its id: a folder `box-blur`
## with no `module.gd` is the module `&"box_blur"`, because a GDScript
## identifier does not want a hyphen in it and a directory does not want an
## underscore. The index takes a shader's owner from the path,
## so a context that qualified by id asked for a kernel nobody filed.
##
## The rule is `SaShaderIndex.owner_of`'s, read from the other side: the segment
## after `modules`, so a repository holding several modules answers with the
## repository, which is what `sara-base-modules/dab` already is.
func _shader_owner() -> String:
    var dir := SaTyped.text_at(ModuleLoader.module_dirs, module_id, "")
    var parts := dir.simplify_path().split("/")
    var at := parts.find("modules")
    if at >= 0 and at + 1 < parts.size():
        return parts[at + 1]
    return String(module_id)


## The union of the rectangles this layer's allocated chunks cover.
func _allocated_bounds() -> Rect2i:
    var bounds := Rect2i()
    var first := true
    for grid_pos: Vector2i in layer.chunks.keys():
        var covered := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        bounds = covered if first else bounds.merge(covered)
        first = false
    return bounds


## The depth the layer stores colour at, which every texture handed out shares.
##
## Asked of the schema rather than of a chunk, because a layer with nothing
## allocated still has a depth and a filter over it still needs a texture.
func field_format() -> int:
    if layer == null:
        return RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    return spec.format if spec != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
