## What a kernel can be handed: the binding kinds a `.gmacs` preamble may declare,
## the per-binding storage format, and the samplers a sampled binding needs.
##
## A file of its own because what a kernel may declare is a subject apart from
## compiling it. Preloaded by path from the compiler rather than reached
## through a `class_name`, because a class name resolves only after the editor
## rescans its class cache.
##
## A kernel declares its bindings in its own preamble, in plain GLSL:
##
##   layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;
##       A storage image, read and written by integer coordinate. The token is
##       replaced per binding: by the instance's storage format unless
##       `SaCompute.use_binding_format()` named this binding, so a mask can be
##       `r32f` beside an `rgba16f` canvas. Bound with `SaCompute.set_texture()`.
##   layout( set = 0, binding = 1 ) uniform sampler2D tip;
##       A sampled texture, read by normalised coordinate through a filter the
##       caller chose. No format qualifier, because sampling converts. Bound
##       with `SaCompute.set_sampled_texture()`.
##   layout( std430, set = 0, binding = 2 ) buffer Table { float values[]; } table;
##       A storage buffer the kernel indexes: a curve, a palette, a lookup
##       table, a per-dab array. Bound with `SaCompute.set_buffer()`. Declare it
##       std430 and keep `vec3` out of it, which std430 pads to 16 bytes apiece.
##       This is the one kind with two names, the block's and the instance's,
##       and `extract_layout()` keeps both so that either binds it by name.
##
## The declarations are parsed out of the source, so a bind of the wrong kind is
## refused by name rather than by a Vulkan error at the first dispatch.
@tool
extends RefCounted

## The layout reader, for the name the dialect gives a buffer it moved a params
## field into. Reached by path, the way every half of the compiler reaches another.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## The placeholder every document-following storage-image binding writes instead
## of a format. Mirrored by GlobalShaderCompiler.STORAGE_FORMAT_TOKEN, which is
## the name every shader and test already uses.
const TOKEN := "SA_STORAGE_FORMAT"

## Samplers already created, keyed by (filter, repeat mode).
##
## A sampler is immutable device state with nothing per texture in it, so one per
## filter and address pair serves every kernel and every texture. Held here, and
## handed back to the compiler to free with the shaders, so that a SaCompute holds
## no RID of its own for one and this file frees none.
static var _samplers: Dictionary[Vector2i, RID] = {}


## Replaces the storage-format placeholder binding by binding.
##
## Each `layout( SA_STORAGE_FORMAT, ..., binding = N )` gets the qualifier
## *binding_qualifiers* names for N, or *default_qualifier* when it names none.
## Binding by binding rather than one global substitution, under which every
## image a kernel binds would inherit the canvas's format, and a single-channel
## mask bound that way is undefined across the whole image, which looks like a
## driver bug rather than a mistake in the kernel.
##
## A token outside any `layout()` still takes the default, so a shader that
## names no binding's format compiles at one format throughout.
static func substitute(clean_text: String, default_qualifier: String, binding_qualifiers: Dictionary[int, String]) -> String:
    var layout_regex := RegEx.new()
    layout_regex.compile("layout\\s*\\(([^)]*)\\)")
    var binding_regex := RegEx.new()
    binding_regex.compile("binding\\s*=\\s*(\\d+)")

    var out := ""
    var read_from := 0
    for found in layout_regex.search_all(clean_text):
        var args := found.get_string(1)
        if not args.contains(TOKEN):
            continue
        var qualifier := default_qualifier
        var binding_match := binding_regex.search(args)
        if binding_match != null:
            qualifier = str(binding_qualifiers.get(int(binding_match.get_string(1)), default_qualifier))
        out += clean_text.substr(read_from, found.get_start(0) - read_from)
        out += found.get_string(0).replace(TOKEN, qualifier)
        read_from = found.get_end(0)
    out += clean_text.substr(read_from)
    return out.replace(TOKEN, default_qualifier)


## The key one assignment of qualifiers compiles under: the default, then each
## override as `binding=qualifier` in binding order.
##
## Written as qualifiers rather than as format numbers so that two callers naming
## the same format through different enum values, and an unknown one that fell
## back to the default, land on the same compiled variant.
static func variant_key(default_qualifier: String, binding_qualifiers: Dictionary[int, String]) -> String:
    var key := default_qualifier
    var bindings: Array[int] = binding_qualifiers.keys()
    bindings.sort()
    for binding: int in bindings:
        key += ";%d=%s" % [binding, String(binding_qualifiers[binding])]
    return key


## Reads the binding declarations out of already-preprocessed source, as
## `binding index -> {kind, name, format}`.
##
## `kind` is `image`, `sampler` or `buffer`. `format` is the token for an image
## that follows the document, the literal qualifier for one that wrote its own,
## and empty for the other two kinds, which carry none. A buffer carries an
## `instance` as well, the name after the block, which is what its kernel writes
## and what a caller reading that kernel would reach for. It carries `fields`,
## the declarations between its braces, and `param`, the name of the params
## field the dialect moved into it, empty for a buffer somebody declared.
static func extract_layout(clean_text: String) -> Dictionary[int, Dictionary]:
    var out: Dictionary[int, Dictionary] = {}
    var binding_regex := RegEx.new()
    binding_regex.compile("binding\\s*=\\s*(\\d+)")
    var qualifier_regex := RegEx.new()
    qualifier_regex.compile("^\\s*(\\w+)\\s*,")

    # GLSL lets a memory qualifier sit on either side of `uniform`.
    var memory := "(?:(?:readonly|writeonly|coherent|restrict|volatile)\\s+)*"
    var image_regex := RegEx.new()
    image_regex.compile("layout\\s*\\(([^)]*)\\)\\s*" + memory + "uniform\\s+" + memory + "(image2D|sampler2D)\\s+(\\w+)")
    var buffer_regex := RegEx.new()
    buffer_regex.compile("layout\\s*\\(([^)]*)\\)\\s*" + memory + "buffer\\s+(\\w+)")

    for found in image_regex.search_all(clean_text):
        var binding_match := binding_regex.search(found.get_string(1))
        if binding_match == null:
            continue
        var is_image := found.get_string(2) == "image2D"
        var format := ""
        if is_image:
            var qualifier_match := qualifier_regex.search(found.get_string(1))
            format = qualifier_match.get_string(1) if qualifier_match != null else ""
        var entry: Dictionary[String, String] = {
            "kind": "image" if is_image else "sampler", "name": found.get_string(3), "format": format
        }
        out[int(binding_match.get_string(1))] = entry
    # A buffer declares two names, the interface block's and the instance's, and
    # the kernel body uses the second. Both are kept, and a caller binding by
    # name may write either, because `buffer Table { ... } table;` reads as one
    # thing to whoever wrote it.
    var body_regex := RegEx.new()
    body_regex.compile("^\\s*\\{([^}]*)\\}\\s*(\\w*)")
    for found in buffer_regex.search_all(clean_text):
        var binding_match := binding_regex.search(found.get_string(1))
        if binding_match == null:
            continue
        var body_match := body_regex.search(clean_text.substr(found.get_end(0)))
        var instance := body_match.get_string(2) if body_match != null else ""
        var block_name := found.get_string(2)
        var moved := block_name.begins_with(KernelSource.MOVED_FIELD_PREFIX)
        var buffer: Dictionary[String, String] = {
            "kind": "buffer",
            "name": block_name,
            "instance": instance,
            "format": "",
            "fields": body_match.get_string(1).strip_edges() if body_match != null else "",
            "param": block_name.trim_prefix(KernelSource.MOVED_FIELD_PREFIX) if moved else "",
        }
        out[int(binding_match.get_string(1))] = buffer
    return out


## The sampler for *filter* and *repeat*, created on *rd* on first use.
##
## Bilinear with clamp to edge is what every waiting customer asked for. Nearest
## is there because a lookup table indexed by texel wants no interpolation at all,
## and a third filter mode is a caller's argument to make, not this file's.
static func sampler_rid(rd: RenderingDevice, filter: int, repeat: int) -> RID:
    var key := Vector2i(filter, repeat)
    var cached: RID = _samplers.get(key, RID())
    if cached.is_valid():
        return cached
    if rd == null:
        return RID()
    var state := RDSamplerState.new()
    state.min_filter = filter as RenderingDevice.SamplerFilter
    state.mag_filter = filter as RenderingDevice.SamplerFilter
    state.mip_filter = filter as RenderingDevice.SamplerFilter
    state.repeat_u = repeat as RenderingDevice.SamplerRepeatMode
    state.repeat_v = repeat as RenderingDevice.SamplerRepeatMode
    state.repeat_w = repeat as RenderingDevice.SamplerRepeatMode
    var created := rd.sampler_create(state)
    _samplers[key] = created
    return created


## Every sampler created so far, and forgets them. The compiler calls this from
## its own teardown and frees what comes back, because it is the one file that
## owns compute RIDs (hard rule 4).
static func take_samplers() -> Array[RID]:
    var out: Array[RID] = []
    for key: Vector2i in _samplers:
        out.append(_samplers[key])
    _samplers.clear()
    return out
