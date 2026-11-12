## A paint layer's height: the step that gives a layer one, and the height half
## of the operations that put one layer's paint onto another.
##
## Built the way `SaMaskOps` is, `SaHeightOps.new(document).gain(layer)`, and
## beside `SaLayerOps` rather than inside it, because a height is a thing of
## its own.
##
## **Gaining.** A layer carries no height until a height-writing dab lands on
## it, rather than by a switch a painter would miss, and a layer painted flat
## spends no memory on height. The engine that writes height asks `gain` first,
## and the layer's schema gains `SaFieldSpec.HEIGHT` as one history step that
## undo takes back whole, the way a mask is added. The step allocates nothing:
## height is a lazy field, so a chunk gains its texture on the first write
## there, through `SaLayer.get_or_create_field`, and a chunk no height reached
## holds none. Every step after it that writes height snapshots the chunks it
## writes, so by the time this step is undone they have put every chunk back
## to holding none.
##
## **Merging.** Merge Down and flatten composite colour through the compositor,
## which knows nothing of height, and ask here for the height half: the layer
## that receives the paint gains the field when any layer given to it carries
## one, and the upper height is added to the one below, weighted by its
## opacity and its mask the way the relief's sum weights it, `height_added`
## of `height.gmacs`. A height is signed, negative where a stroke levelled a
## lower layer's bump, and the view adds the heights of the layers that show, so adding is what
## leaves the surface the view showed. A flatten that adds every layer onto
## bare is that sum, and a Merge Down onto a lower layer that shows whole is
## too. A lower layer at part opacity has its height weighted by it first,
## `SaOpacityBake`, and holds that and the upper's at full opacity after.
## Duplicate and crop need nothing from here, because they copy every field a
## chunk holds.
##
## **The mix it replaced** covered the height below by the upper paint's alpha
## times its opacity, so a flat layer merged onto one with height gave zero
## where it had paint. With signed heights that loses a negative height's
## levelling the moment its layer is merged, and the view never showed a mix.
## The transform's landing keeps the mix, `height_over`, because it is a
## layer's own paint moved over itself.
class_name SaHeightOps
extends RefCounted

## The history step's name, which the Edit menu's Undo row reads.
const GAIN_NAME := "Add Height"

var _document: SaDocument
var _compute: SaCompute = null
## What the kernel binds as the upper layer's mask where it has none: one
## texel of the mask's format at one, so the layer shows whole.
var _whole: SaTexture = null
## The `blank` kernel that writes the stand-in once.
var _blank: SaCompute = null


func _init(document: SaDocument) -> void:
    _document = document


## Whether *layer* can gain a height now: a layer that stores paint and does
## not carry one yet. A group and a background store nothing to thicken.
static func can_gain(layer: SaLayer) -> bool:
    return layer != null and not layer.is_group and not layer.is_generated() and not layer.carries_height()


## Gives *layer* its height as one step, and answers whether it gained one. A
## layer that already carries one answers false and no step is committed, so
## an engine asks this before every stroke that writes height.
func gain(layer: SaLayer) -> bool:
    if not can_gain(layer):
        return false
    _carry(layer, true)
    if _document.history != null:
        _document.history.commit_pair(GAIN_NAME, _carry.bind(layer, true), _carry.bind(layer, false))
    return true


## Puts the field on *layer* or takes it off, and tells the docker, whose mark
## reads the schema.
func _carry(layer: SaLayer, carries: bool) -> void:
    if not is_instance_valid(layer):
        return
    if carries:
        layer.add_field(SaFieldSpec.height())
    else:
        layer.drop_field(SaFieldSpec.HEIGHT)
    _document.modified = true
    _document.document_changed.emit()


## Gives *lower* the height field when any of *givers* carries one and it does
## not, before their paint goes into it. *shape* is the merge's record of the
## members of *lower* it changed, and its schema goes in there unless the mask
## already put it there, so undo takes the field back off with the rest.
func give_schema(lower: SaLayer, givers: Array[SaLayer], shape: Dictionary[StringName, Variant]) -> void:
    if lower.carries_height():
        return
    var spec := spec_among(givers)
    if spec == null:
        return
    if not shape.has(&"schema"):
        shape[&"schema"] = lower.schema
    lower.add_field(SaFieldSpec.sparse(spec.id, spec.format))


## The height field of the first of *layers* that carries one, or null.
static func spec_among(layers: Array[SaLayer]) -> SaFieldSpec:
    for layer in layers:
        if layer != null and not layer.is_group:
            var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.HEIGHT)
            if spec != null:
                return spec
    return null


## Adds *upper*'s height at *grid_pos* to *target*'s, a chunk of a layer whose
## schema lists *spec*, weighted by *opacity* and by *upper*'s mask there, the
## way the relief's sum weights a layer. Allocates *target*'s height only where
## *upper* holds some, because adding none leaves it as it was.
func add(target: SaChunk, spec: SaFieldSpec, upper: SaLayer, grid_pos: Vector2i, opacity: float) -> void:
    if target == null or spec == null or upper == null:
        return
    var above: SaTexture = upper.get_field(grid_pos, SaFieldSpec.HEIGHT)
    if above == null:
        return
    var below: SaTexture = target.field(SaFieldSpec.HEIGHT)
    if above.format != (below.format if below != null else spec.format):
        push_warning("SaHeightOps: '%s' holds its height at another depth, so it merges as flat paint." % upper.name)
        return
    var compute := _compute_or_null()
    if compute == null:
        return
    if below == null:
        below = target.add_sparse_field(spec)
    var cover := SaCompositor.coverage_at(upper, grid_pos)
    if cover == null:
        cover = _whole_cover()
    compute.use_storage_format(below.format)
    compute.use_binding_format(2, cover.format)
    compute.set_texture(0, below.rid)
    compute.set_texture(1, above.rid)
    compute.set_texture(2, cover.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([opacity, 1.0, 0.0, 0.0]))
    compute.dispatch_kernel("height_added", SaCompute.groups_for(below.size.x), SaCompute.groups_for(below.size.y), 1)


## The height half of a flatten: every layer of *stack* that draws, bottom
## first, added onto the height of the chunk at each position of *flat*, which
## holds the chunks the bottom layer is about to take and no height yet.
## *spec* is the height the bottom carries once the flatten is done.
##
## A layer adds by its own mask and its opacity times its groups', which is
## the relief's sum, so the flattened height is the surface the view showed
## of the paint. A group's own mask and filters and a clip are colour's
## business and not the height's, and the relief reads none of them either. A
## ground's tooth stays out: the ground leaves the stack, and turning its tooth into
## paint is Rasterize Impasto's.
func flatten(spec: SaFieldSpec, stack: Array[SaLayer], flat: Dictionary[Vector2i, SaChunk]) -> void:
    if spec == null:
        return
    for grid_pos: Vector2i in flat:
        for layer in stack:
            if layer.is_group or layer.is_generated() or not SaLayerStack.contributes(_document, layer):
                continue
            add(flat[grid_pos], spec, layer, grid_pos, opacity_of(layer))


## *layer*'s opacity times every group's around it, which is how much of its
## paint the canvas shows.
static func opacity_of(layer: SaLayer) -> float:
    var opacity := layer.opacity
    var group := SaLayerStack.parent_of(layer)
    var guard := 0
    while group != null and guard < 64:
        opacity *= group.opacity
        group = SaLayerStack.parent_of(group)
        guard += 1
    return opacity


func _compute_or_null() -> SaCompute:
    if _compute == null and GlobalShaderCompiler.get_rd() != null:
        _compute = SaCompute.new("height")
    return _compute


## Blanked to one by the `blank` kernel rather than a transfer clear, because
## the add that reads it next is compute and a transfer is not ordered against
## it inside a frame.
func _whole_cover() -> SaTexture:
    if _whole == null:
        _whole = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
        _blank = SaCompute.new("blank")
        _blank.use_storage_format(_whole.format)
        _blank.set_texture(0, _whole.rid)
        _blank.set_push_constant_float_array(PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0]))
        _blank.dispatch_kernel("blank_region", 1, 1, 1)
    return _whole
