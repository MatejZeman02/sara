## What a kernel declares at each binding, and what is bound into those slots.
##
## Every `layout( ..., binding = N )` in a `.gmacs` preamble names its variable,
## and `sa_bindings.gd` keeps that name when it parses the declaration, rather
## than throwing it away at the door: with `set_texture(0, rid)` alone the
## caller counts the slot, so a binding renumbered in the GLSL is silent on both
## sides and shows up as a wrong picture.
##
## So this class holds the declarations and answers by name: which slot a name
## lives at, whether a slot takes what is being bound to it, what the kernel
## declares when the caller got the name wrong, and the RID inside whatever was
## passed. The three binds hand what they bind to the descriptor set cache as
## three numbers, and the cache makes the `RDUniform`s only for a set it
## builds. It is a collaborator given in the constructor rather than an owner
## passed back on every call.
##
## The declarations are copied when the kernels load rather than asked of the
## compiler per chunk per dab, which is what `relearn()` is for.
##
## Reached by path rather than by a `class_name`, the way every half of the
## compiler is, because a class name resolves only after the editor rescans its
## class cache.
@tool
extends RefCounted

## The descriptor set cache's script, so the cache is held by its type.
const UniformSets := preload("res://core/custom-shader/sa_uniform_sets.gd")

## The layout reader, which lays out a moved field inside its buffer.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## What the shader declares at each binding, as binding index -> `{kind, name,
## instance, format}`. Empty until the kernels have loaded, so a run with no
## RenderingDevice never learns a layout and lets every bind
## through, because the dispatch will say what really went wrong.
var declared: Dictionary[int, Dictionary] = {}

## The shader whose bindings these are, for the compiler lookup and the errors.
var _shader_name: String = ""

## The descriptor set cache the binds go into. Held, not owned: it is `SaCompute`'s
## and it is handed over here so that a bind is one call rather than two.
var _uniforms: UniformSets = null

## Bindings already refused once, so a wrong bind in a per-dab loop is said once.
var _refused: Dictionary[int, bool] = {}


func _init(shader_name: String, uniforms: UniformSets) -> void:
    _shader_name = shader_name
    _uniforms = uniforms


## Re-reads what the shader declares. What the owner calls after its pipelines
## load, because a recompile can move a binding.
func relearn() -> void:
    declared = GlobalShaderCompiler.binding_layout(_shader_name)


## Whether *binding* wrote the storage-format token, so it may be given a format
## of its own.
##
## A sampler has no qualifier and a literal one is the kernel's decision, so
## neither can be overridden. A binding the shader does not declare at all reads
## as having written the token, which is what an uncompiled shader leaves behind.
func declares_storage_token(binding: int) -> bool:
    var layout: Dictionary = declared.get(binding, {})
    var format := str(layout.get("format", GlobalShaderCompiler.STORAGE_FORMAT_TOKEN))
    return format == GlobalShaderCompiler.STORAGE_FORMAT_TOKEN


## Binds a storage image: what a `layout( SA_STORAGE_FORMAT, ... ) uniform image2D`
## declaration takes. Read and written by integer coordinate, at the format the
## kernel was compiled with for this binding.
func bind_image(binding: int, texture_rid: RID) -> void:
    if _uniforms.holds(binding, RenderingDevice.UNIFORM_TYPE_IMAGE, texture_rid):
        return
    if not accepts(binding, "image"):
        return
    _uniforms.put(binding, RenderingDevice.UNIFORM_TYPE_IMAGE, texture_rid)


## Binds a sampled texture: what a `uniform sampler2D` declaration takes.
##
## The kernel reads it with `texture(name, uv)` by normalised coordinate, and the
## value between four texels is what a transform, a warp, a scaled brush tip and a
## lookup table all need and a storage image cannot give. The filter and the
## address mode are the caller's to name rather than assumed, because a table
## wants nearest and an image wants linear, and both want to say so. The sampler
## itself is shared device state the compiler owns, so nothing here is freed.
func bind_sampler(
    binding: int,
    texture_rid: RID,
    filter: int = RenderingDevice.SAMPLER_FILTER_LINEAR,
    repeat: int = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
) -> void:
    var sampler := GlobalShaderCompiler.sampler_rid(filter, repeat)
    if _uniforms.holds(binding, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, sampler, texture_rid):
        return
    if not accepts(binding, "sampler"):
        return
    _uniforms.put(binding, RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, sampler, texture_rid)


## Binds a storage buffer: what a `buffer` block declaration takes. See
## `SaCompute.Buffer` for the RAII wrapper that owns one.
func bind_buffer(binding: int, buffer_rid: RID) -> void:
    if _uniforms.holds(binding, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, buffer_rid):
        return
    if not accepts(binding, "buffer"):
        return
    _uniforms.put(binding, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, buffer_rid)


## Whether the shader declares *binding* as *kind*, said once per binding when it
## does not. A binding the shader does not declare at all is let through, because
## a shader that failed to compile has no layout and the dispatch will say so.
func accepts(binding: int, kind: String) -> bool:
    var layout: Dictionary = declared.get(binding, {})
    var kind_here := str(layout.get("kind", kind))
    if kind_here == kind:
        return true
    if not _refused.has(binding):
        _refused[binding] = true
        push_error(
            (
                "SaCompute('%s'): binding %d is declared as a %s, and a %s was bound to it."
                % [_shader_name, binding, kind_here, kind]
            )
        )
    return false


## The slot this kernel declares for *name* as *kind*, or -1 with an error that
## lists the names it does declare of that kind.
##
## Nothing is bound on -1: a negative binding would index the uniform cache from
## its end.
func slot_for(name: String, kind: String) -> int:
    var slot := slot_of(declared, name, kind)
    if slot < 0:
        push_error(
            (
                "SaCompute('%s'): no %s is declared as '%s'. It declares %s."
                % [_shader_name, kind, name, declared_names(declared, kind)]
            )
        )
    return slot


## The binding *binding_layout* declares for *wanted* as *kind*, or -1 when it
## declares no such thing.
##
## `sa_bindings.gd` reads the name out of every declaration, so this is a lookup
## rather than a guess. The kind is part of the question because a kernel may well
## have an `image2D mask` and a `sampler2D mask` in one preamble, and because
## binding a buffer where a sampler was declared is the refusal `accepts()` already
## makes by slot.
##
## A buffer answers to either of its two names. `buffer Table { ... } table;`
## declares a block and an instance, the kernel body writes the second, and a
## caller should not have to know which half the parser kept.
static func slot_of(binding_layout: Dictionary[int, Dictionary], wanted: String, kind: String) -> int:
    for binding: int in binding_layout:
        var entry: Dictionary[String, String] = binding_layout[binding]
        if str(entry.get("kind", "")) != kind:
            continue
        if wanted == str(entry.get("name", "")) or wanted == str(entry.get("instance", "")):
            return binding
    return -1


## The params fields the dialect moved out of the push constant into storage
## buffers, in binding order, each `{name, block, layout}`: the field's own name,
## the buffer's block name to bind it under, and the field laid out inside the
## buffer the way `SaKernelSource.extract_push_constant_layout` lays out a block,
## so `SaPushConstants.pack` fills one like the other.
##
## Empty for a kernel that moved nothing, which is every kernel whose params fit
## the 128 bytes Vulkan guarantees.
static func moved_params(binding_layout: Dictionary[int, Dictionary]) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var bindings: Array = binding_layout.keys()
    bindings.sort()
    for binding: int in bindings:
        var entry: Dictionary[String, String] = binding_layout[binding]
        var param := str(entry.get("param", ""))
        if param.is_empty():
            continue
        var layout := KernelSource.block_layout(str(entry.get("fields", "")))
        if layout.size() < 2:
            continue
        var moved: Dictionary[String, Variant] = {"name": param, "block": str(entry.get("name", "")), "layout": layout}
        out.append(moved)
    return out


## The names *binding_layout* declares of one kind, for an error that has to
## suggest what the caller meant. Empty text when it declares none.
static func declared_names(binding_layout: Dictionary[int, Dictionary], kind: String) -> String:
    var names: Array[String] = []
    var bindings: Array = binding_layout.keys()
    bindings.sort()
    for binding: int in bindings:
        var entry: Dictionary[String, String] = binding_layout[binding]
        if str(entry.get("kind", "")) != kind:
            continue
        var instance := str(entry.get("instance", ""))
        names.append(instance if not instance.is_empty() else str(entry.get("name", "")))
    return _quoted(names)


## What is wrong with *bindings* against what *binding_layout* declares, or an
## empty String when nothing is.
##
## Symmetrical with the push constant block's own complaint and for the same
## reason. A name the kernel does not declare is a typo or a rename, and a
## declaration the caller left out is a hole in the uniform set, which surfaces as
## a Vulkan error about a descriptor rather than as the one word that was missing.
##
## *bindings* is what the caller handed `SaCompute.run`, untyped for the reason
## that method gives. A params field the dialect moved into a buffer of its own is
## passed in the params and bound by `SaCompute.run`, so its binding is never
## missing.
static func binding_complaint(binding_layout: Dictionary[int, Dictionary], bindings: Dictionary) -> String:
    var unknown: Array[String] = []
    for key: Variant in bindings:
        var wanted := str(key)
        var found := false
        for binding: int in binding_layout:
            var entry: Dictionary[String, String] = binding_layout[binding]
            if wanted == str(entry.get("name", "")) or wanted == str(entry.get("instance", "")):
                found = true
                break
        if not found:
            unknown.append(wanted)
    if not unknown.is_empty():
        return "the kernel declares no binding named %s. It declares %s." % [_quoted(unknown), all_names(binding_layout)]

    var missing: Array[String] = []
    var slots: Array = binding_layout.keys()
    slots.sort()
    for binding: int in slots:
        var entry: Dictionary[String, String] = binding_layout[binding]
        if value_for(entry, bindings) == null and str(entry.get("param", "")).is_empty():
            missing.append(name_of(entry))
    if not missing.is_empty():
        return "nothing was passed for %s, and a uniform set has to cover every binding the kernel kept." % _quoted(missing)
    return ""


## The value the caller passed for one declared binding, under either of the names
## it answers to, or null when they passed none.
static func value_for(entry: Dictionary[String, String], bindings: Dictionary) -> Variant:
    for key: String in ["name", "instance"]:
        var name := str(entry.get(key, ""))
        if not name.is_empty() and bindings.has(name):
            return bindings[name]
    return null


## The name a declared binding is best called by: the instance for a buffer, which
## is what its kernel writes, and the declared name for the other two.
static func name_of(entry: Dictionary[String, String]) -> String:
    var instance := str(entry.get("instance", ""))
    return instance if not instance.is_empty() else str(entry.get("name", ""))


## Every name the kernel declares, in binding order, for a message that has to say
## what the caller could have meant.
static func all_names(binding_layout: Dictionary[int, Dictionary]) -> String:
    var names: Array[String] = []
    var slots: Array = binding_layout.keys()
    slots.sort()
    for binding: int in slots:
        names.append(name_of(binding_layout[binding]))
    return _quoted(names)


## The RID of an `SaTexture`, an `SaCompute.Buffer` or a bare `RID`.
##
## Public because `SaCompute.set_image` takes what the spec's box blur has in its
## hand, which is the texture rather than the RID inside it, and the rule for
## reading one out belongs with the declarations it is bound against.
static func rid_of(value: Variant) -> RID:
    if value is RID:
        return value
    if value != null and "rid" in value:
        return value.rid
    return RID()


## The storage format of a passed image, or -1 when it carries none. A bare RID
## does, which is why a caller that wants the variant chosen for it passes the
## `SaTexture` rather than its RID.
static func format_of(value: Variant) -> int:
    if value != null and not (value is RID) and "format" in value:
        var format: int = value.format
        return format
    return -1


## Names in quotes and separated by commas, for a message that has to say which.
## The push constant block keeps its own copy of this, because the two classes
## name different things and neither should reach into the other for five lines of
## string join.
static func _quoted(names: Array) -> String:
    var out: Array[String] = []
    for name: Variant in names:
        out.append("'%s'" % str(name))
    return ", ".join(out)
