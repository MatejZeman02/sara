## The relief pass of a flat export: the light the view shines
## on thick paint, baked into the colour a PNG, JPEG, TIFF or EXR writes, so a
## file of a painting with relief looks like the painting. Flat exports bake it
## by default, with an Export row to leave it off. The
## `.sad` keeps the raw height, and OpenRaster writes colour only.
##
## **Tiles, not the picture.** The pass rides the cell walk
## [method SaExportGamut.encoded_image] already makes: every chunk cell of the
## picture is copied into one scratch and put through its kernels, and this is
## the first of them, so it lights one cell at a time and allocates nothing the
## size of the canvas. The relief it reads is `SaRelief.texture`, which the
## view already holds, resolved over the whole picture once by
## [method prepare] before the walk starts.
##
## **The same light as the view.** The bearing is Preferences' Light direction
## through `SaRelief.light_toward`, the strength is Preferences' Relief strength,
## the shine is Preferences' Gloss, and `relief_bake.gmacs` carries the view's
## shading word for word. What it lights is the stored numbers, decoded out of
## *space* into linear light and encoded back, so the conversion into the file's space runs after it as it
## runs after the view's light. A texel with no slope under it is not touched.
class_name SaExportRelief
extends RefCounted

const KERNEL: String = "bake_relief"

## The resolved relief, normal in rgb and height in a, canvas sized.
var _relief: SaTexture = null
## The space the cells hold when the pass reaches them, which is the
## document's own.
var _space: SaColorSpace = null
var _light: Vector3 = Vector3.BACK
var _strength: float = 0.0
## Preferences' Gloss, read once when the pass is made, so a slider moved while
## a long export walks its cells never lights half the file one way.
var _gloss: float = 0.0
var _compute: SaCompute = null


## *relief* is `SaRelief.texture`, *space* the space the picture's numbers are
## stored in, null for sRGB, *light* the direction from the surface to the
## light and *strength* the scale on the slope, both as the view takes them.
func _init(relief: SaTexture, space: SaColorSpace, light: Vector3, strength: float) -> void:
    _relief = relief
    _space = space if space != null else SaColorSpace.srgb()
    _light = light
    _strength = strength
    _gloss = SaSettings.relief_gloss


## The pass for the picture *easel* shows, or null when there is nothing to
## bake: *enabled* is false, the strength is zero, or no layer the picture
## shows carries a height. *light* and *strength* are what Preferences says,
## which the caller reads, because a pass is built for one export.
##
## The relief is resolved over the whole picture first, what the window left
## held included, because the view resolves only the cells it shows and a file
## holds every one. A resolve with nothing new to take writes only those held
## cells, so this costs nothing where the view has already been.
static func prepare(easel: SaEasel, enabled: bool, light: Vector3, strength: float) -> SaExportRelief:
    if not enabled or strength <= 0.0 or easel == null or easel.document == null:
        return null
    if not SaRelief.shows_height(easel.document):
        return null
    SaLocalView.flush_whole(easel)
    var whole := Rect2(Vector2.ZERO, Vector2(easel.document.canvas_size))
    easel.relief.resolve(easel.document, {}, {}, false, whole)
    if easel.relief.texture == null:
        return null
    return SaExportRelief.new(easel.relief.texture, easel.document.color_space, light, strength)


## Lights the cell of the picture at *cell*, in canvas pixels, held in
## *scratch* from its corner. One dispatch the size of the cell. *density* is
## the texels of *scratch* a canvas pixel, which Rasterize Impasto gives for a
## chunk of a layer at another resolution, whose *cell* is then sized in its
## texels.
func light_cell(scratch: SaTexture, cell: Rect2i, density: float = 1.0) -> void:
    if _relief == null or not _relief.rid.is_valid():
        return
    if _compute == null:
        _compute = SaCompute.new("relief_bake")
    _compute.use_storage_format(scratch.format)
    _compute.use_binding_format(1, _relief.format)
    _compute.set_texture(0, scratch.rid)
    _compute.set_texture(1, _relief.rid)
    _compute.set_push_constant_float_array(_params(cell, density))
    _compute.dispatch_kernel(KERNEL, SaCompute.groups_for(cell.size.x), SaCompute.groups_for(cell.size.y), 1)


## The block as `relief_bake.gmacs` declares it: the cell's corner, the
## strength, the coordinates and the curve of the space held, then the light,
## the density and the gloss.
func _params(cell: Rect2i, density: float) -> PackedFloat32Array:
    var params := PackedFloat32Array([cell.position.x, cell.position.y, _strength, float(_space.coordinates)])
    params.append_array(_curve())
    params.append_array(PackedFloat32Array([_light.x, _light.y, _light.z, density, _gloss]))
    return params


## The four numbers of the stored curve, the identity for a space that has none.
func _curve() -> PackedFloat32Array:
    if _space.transfer == null:
        return SaTransferFunction.linear().to_params()
    return _space.transfer.to_params()
