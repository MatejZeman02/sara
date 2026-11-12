## Converting a filter's texture between the document's space and a named one.
##
## A filter is handed pixels in the document's space, which is deliberate: it is
## what a student should meet, and a document that is not sRGB is
## the normal case in Sara rather than the exotic one. A lab whose formula was
## written for sRGB, or one that wants linear light, asks for it here and gets
## a new texture back.
##
## Every conversion goes through `sara-godot/shaders/compute/convert_color_space.gmacs`,
## the same kernel File > Colour Space runs over a whole document, so a filter
## cannot pick up a second opinion about what a colour means. Nothing is read
## back: the copy is `texture_copy` and the conversion is one dispatch.
##
## Static, and given its kernel rather than holding one. An `SaCompute` cached
## in a static outlives the rendering device it was made on, the reason the
## clipboard is held by the document, and the filter
## context already caches kernels by name.
class_name SaFilterColorSpaces
extends RefCounted

## The conversion kernel, qualified, because a module may well provide a kernel
## called `convert_color_space` of its own and this one is Sara's.
const KERNEL: String = "sara/convert_color_space"


## *space* by name, or an empty string when there is none.
static func name_of(space: SaColorSpace) -> String:
    return SaColorSpace.display_name(space.id) if space != null else ""


## sRGB at *space*'s depth.
##
## The depth has to be carried across, because a conversion rewrites a texture
## in place and a target that named another depth would describe a texture that
## does not exist. The conversion pass never changes depth either, for the same
## reason.
static func srgb_like(space: SaColorSpace) -> SaColorSpace:
    return SaColorSpace.srgb() if space == null else SaColorSpace.srgb().with_depth(space.depth)


## Linear sRGB at *space*'s depth, for a filter that wants linear light.
static func linear_like(space: SaColorSpace) -> SaColorSpace:
    return SaColorSpace.linear_srgb() if space == null else SaColorSpace.linear_srgb().with_depth(space.depth)


## *texture* read as *source* and answered as a new texture in *target*.
##
## Always a new texture, even where source and target are the same space and
## the conversion is skipped. A helper that sometimes answers the texture it was
## handed and sometimes a fresh one is one whose caller cannot know whether
## writing to the answer also writes to the input.
static func converted(compute: SaCompute, texture: SaTexture, source: SaColorSpace, target: SaColorSpace) -> SaTexture:
    if texture == null or source == null or target == null:
        SaProblems.report("SaFilterColorSpaces", "a conversion needs a texture and two spaces.")
        return null
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return null
    var out := SaTexture.new(texture.size, texture.format)
    var extent := Vector3(texture.size.x, texture.size.y, 1)
    rd.texture_copy(texture.rid, out.rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
    if source.matches(target) or compute == null:
        return out
    compute.use_storage_format(out.format)
    compute.set_texture(0, out.rid)
    compute.set_push_constant_float_array(source.to_conversion_push_constant(target))
    compute.dispatch_kernel("convert_color_space", SaCompute.groups_for(out.size.x), SaCompute.groups_for(out.size.y), 1)
    return out
