## A layer that evaluates a kernel instead of storing pixels, and
## everything the rest of the skeleton asks about one.
##
## The compositor asks for the push constant, the stack walk asks whether any
## is in the document, the document asks what a fill means for one, the
## canvas asks what to draw beyond the document rectangle, and the export
## asks for its parameters as JSON. A sibling of `SaDocument` and `SaLayer`
## rather than more lines in either, because the document is past the length
## gate's advisory band and the layer is what stores.
##
## The parameters are a dictionary the layer owns. `color` is the one every
## generator reads, stored in the document's colour space the way a chunk's
## texels are, so a fill writes what a fill of a stored layer would and the
## view converts to display on the way out.
##
## **A kernel reads them by name.** [method params_of] fills the names a
## generator's `params:` block declares and nothing else, so a module's
## kernel declares the parameters it reads and they arrive, which the
## descriptor's header says in full as the contract a module writes to.
class_name SaGeneratedLayer
extends RefCounted

const PARAM_COLOR := "color"
const PARAM_SECOND := "second"
const PARAM_SCALE := "scale"
## The height of a generator's grain in virtual millimetres.
## A generator whose parameters carry it answers a height through a
## `raise_tooth` kernel beside `generate`, which the relief adds under the
## paint.
const PARAM_TOOTH := "tooth"
## The greatest tooth the slider offers, a millimetre, ten times what the
## lightest relief reads, and past what any paper a painter buys stands.
const TOOTH_MAX := 1.0
## The woven canvas's own three: a thread's width as a share
## of the spacing, which is `scale`, how far the threads wander, and the
## weave's turn in degrees. Its kernel declares them by these names, as a
## module's kernel declares its own.
const PARAM_THICKNESS := "thickness"
const PARAM_IRREGULARITY := "irregularity"
const PARAM_ANGLE := "angle"

## The names in a generator's block the dispatch fills rather than the
## layer's parameters: the chunk's document position, the region of it the
## kernel covers, the two colours under the names Sara's kernels give them,
## and how much of the ground the relief shows.
const FIELD_OFFSET := "offset"
const FIELD_ORIGIN := "region_origin"
const FIELD_SIZE := "region_size"
const FIELD_FIRST := "color_a"
const FIELD_SECOND := "color_b"
const FIELD_WEIGHT := "weight"

## The type of the flat colour that stores nothing, the Solid Colour ground.
## It answers no height, so thick paint sits on it as on a stored background.
const SOLID := &"background"

## What a generator's colour is when its layer carries none.
const GREY := Color(0.5, 0.5, 0.5, 1.0)

## The kinds of value the packer writes, a number, a colour, a vector or the
## array of numbers a colour reads back from a file as. A parameter of any
## other kind goes as nought rather than stopping the dispatch.
const PACKABLE: Array[int] = [
    TYPE_INT,
    TYPE_FLOAT,
    TYPE_COLOR,
    TYPE_VECTOR2,
    TYPE_VECTOR2I,
    TYPE_VECTOR3,
    TYPE_VECTOR4,
    TYPE_ARRAY,
    TYPE_PACKED_FLOAT32_ARRAY,
]


## What a new layer of *descriptor*'s type starts with, converted into
## *space* where a value is a colour.
static func defaults_for(descriptor: SaLayerTypeDescriptor, space: SaColorSpace) -> Dictionary[String, Variant]:
    var params: Dictionary[String, Variant] = {}
    if descriptor == null or not descriptor.is_generated():
        return params
    for key: String in descriptor.generator_defaults:
        var value: Variant = descriptor.generator_defaults[key]
        if value is Color and space != null:
            var shown: Color = value
            value = space.from_display(shown)
        params[key] = value
    return params


## What *layer*'s kernel reads over *region* of the chunk at *offset*, by the
## names its `params:` block declares, for `SaCompute.set_params`. The six
## `FIELD_` names come from the dispatch, `scale` counts as one when the layer
## has none and `tooth` is [method tooth_of], and every other name is the
## layer's parameter of that name, nought when it has none, which is what
## [method set_param] counts a missing one as. *weight* is how much of the
## ground the relief shows, and one for the colour.
##
## By name rather than as one positional block every generator shares, where
## the built-in grounds would keep their parameters in each other's padding
## and a module's own kernel would have no slot for a parameter of its own.
## Empty when the kernel declares no block, or is not
## compiled, which is when there is no device.
static func params_of(layer: SaLayer, offset: Vector2, region: Rect2i, weight: float = 1.0) -> Dictionary[String, Variant]:
    var values: Dictionary[String, Variant] = {}
    for field: Dictionary in GlobalShaderCompiler.push_constant_layout(layer.generator):
        var field_name := str(field.get("name", ""))
        if field_name.is_empty() or SaTyped.bool_at(field, "pad", false):
            continue
        values[field_name] = _value_of(layer, field_name, offset, region, weight)
    return values


## Hands *compute*, *layer*'s kernel, what [method params_of] answers. The one
## door each dispatcher of a generator goes through: the walk's step below,
## the clip base, the impasto rasteriser and the relief's tooth.
static func bind_params(compute: SaCompute, layer: SaLayer, offset: Vector2, region: Rect2i, weight: float = 1.0) -> void:
    var values := params_of(layer, offset, region, weight)
    if not values.is_empty():
        compute.set_params(values)


## The value of *field_name* for *layer*'s kernel, as [method params_of] says.
static func _value_of(layer: SaLayer, field_name: String, offset: Vector2, region: Rect2i, weight: float) -> Variant:
    var params := layer.generator_params
    match field_name:
        FIELD_OFFSET:
            return offset
        FIELD_ORIGIN:
            return Vector2(region.position)
        FIELD_SIZE:
            return Vector2(region.size)
        FIELD_FIRST:
            return params.get(PARAM_COLOR, GREY)
        FIELD_SECOND:
            return params.get(PARAM_SECOND, params.get(PARAM_COLOR, GREY))
        FIELD_WEIGHT:
            return weight
        PARAM_SCALE:
            return SaTyped.float_at(params, PARAM_SCALE, 1.0)
        PARAM_TOOTH:
            return tooth_of(layer)
    var value: Variant = params.get(field_name, 0.0)
    if value is bool:
        return 1.0 if value else 0.0
    return value if typeof(value) in PACKABLE else 0.0


## How high *layer*'s grain stands, in virtual millimetres: 0 for a layer
## that stores paint or whose generator answers no height.
static func tooth_of(layer: SaLayer) -> float:
    if layer == null or not layer.is_generated():
        return 0.0
    return maxf(SaTyped.float_at(layer.generator_params, PARAM_TOOTH, 0.0), 0.0)


## Whether a layer of *descriptor*'s type answers a height, which is whether
## its generator's defaults carry a tooth. A paper saved before it had one
## opens flat, at a tooth of 0, and keeps the look it was saved with.
static func answers_height(descriptor: SaLayerTypeDescriptor) -> bool:
    return descriptor != null and descriptor.is_generated() and descriptor.generator_defaults.has(PARAM_TOOTH)


## Sets *layer*'s tooth to *value*, as one history step a slider's drag
## merges into one, and redraws the document, whose relief it moves.
static func set_tooth(document: SaDocument, layer: SaLayer, value: float) -> void:
    if layer == null or not layer.is_generated():
        return
    set_param(document, layer, PARAM_TOOTH, clampf(value, 0.0, TOOTH_MAX), "Ground Tooth")


## Sets *layer*'s parameter *key* to *value* under *action_name*, as one
## history step a slider's drag merges into one, and redraws the document. The
## caller clamps, because the range is the slider's and a module's ground has
## parameters this file never heard of. A parameter the layer never had
## counts as nought, so the undo of a first write puts nought back.
static func set_param(document: SaDocument, layer: SaLayer, key: String, value: float, action_name: String) -> void:
    if document == null or layer == null or not layer.is_generated():
        return
    var previous := SaTyped.float_at(layer.generator_params, key, 0.0)
    if is_equal_approx(previous, value):
        return
    _apply_param(document, layer, key, value)
    if document.history != null:
        document.history.commit_pair(
            action_name,
            _apply_param.bind(document, layer, key, value),
            _apply_param.bind(document, layer, key, previous),
            0,
            0,
            UndoRedo.MERGE_ENDS
        )


## Sets *layer*'s colour parameter *key*, `color` or `second`, to *stored*
## under *action_name*, as one history step a swatch's drag merges into one,
## and redraws the document. *stored* is in the document's space, as `fill`
## takes it, so a picker's triple goes through `from_display` first. A
## parameter the layer never had counts as the first colour, which is what the
## kernel reads for a missing second, so the undo of a first write puts that
## back.
##
## A colour that differs from the one held in the last digit or so is the same
## colour, and writes nothing. The swatch shows the stored colour through
## `to_display` and hands back what it shows through `from_display`, and under
## Oklab that round trip leaves a few parts in a hundred million behind, so
## the swatch's popup closed by Escape added a Ground Colour row that changed
## nothing.
static func set_color(document: SaDocument, layer: SaLayer, key: String, stored: Color, action_name: String) -> void:
    if document == null or layer == null or not layer.is_generated():
        return
    var first: Color = layer.generator_params.get(PARAM_COLOR, Color(0.5, 0.5, 0.5, 1.0))
    var previous: Color = layer.generator_params.get(key, first)
    if previous.is_equal_approx(stored):
        return
    _apply_param(document, layer, key, stored)
    if document.history != null:
        document.history.commit_pair(
            action_name,
            _apply_param.bind(document, layer, key, stored),
            _apply_param.bind(document, layer, key, previous),
            0,
            0,
            UndoRedo.MERGE_ENDS
        )


## Sets every parameter *preset* names on *layer*, one of its descriptor's
## [member SaLayerTypeDescriptor.generator_presets], as one history step, and
## leaves the rest as they stand. The preset's colours are display-referred
## and go into the document's space as a fill's do. The undo puts back what
## the layer held and takes away what it never had.
static func apply_preset(document: SaDocument, layer: SaLayer, preset: Dictionary) -> void:
    if document == null or layer == null or not layer.is_generated():
        return
    var wanted: Dictionary = preset.get("params", {})
    var after: Dictionary[String, Variant] = {}
    var before: Dictionary[String, Variant] = {}
    for key: String in wanted:
        var value: Variant = wanted[key]
        if value is Color and document.color_space != null:
            var shown: Color = value
            value = document.color_space.from_display(shown)
        after[key] = value
        before[key] = layer.generator_params.get(key)
    _apply_params(document, layer, after)
    if document.history != null:
        document.history.commit_pair(
            "Ground Preset", _apply_params.bind(document, layer, after), _apply_params.bind(document, layer, before)
        )


## Writes each of *values* into *layer*'s parameters, a null taking the
## parameter away, and redraws the document once.
static func _apply_params(document: SaDocument, layer: SaLayer, values: Dictionary[String, Variant]) -> void:
    for key: String in values:
        if values[key] == null:
            layer.generator_params.erase(key)
        else:
            layer.generator_params[key] = values[key]
    document.modified = true
    document.request_cache_update()
    document.document_changed.emit()


## Makes *layer* a ground of *descriptor*'s type, a paper a canvas or a
## canvas a paper, as one history step. The layer keeps its
## place, opacity, blend mode and visibility, and takes the new type's
## generator and its defaults, since a paper's grain and a canvas's threads
## share no meaning a value could carry across. It stores nothing either way,
## so no paint above it moves, and the undo gives the old parameters back as
## they were left.
##
## A layer still called what its kind named it, Paper or Paper 2, takes the
## new kind's name with it, so the row does not go on saying Paper over a
## canvas. A name the painter wrote is kept. *types* is where the old kind's
## name is read, and without it the name is kept whatever it is.
##
## *keep_colors* carries over every colour the old ground holds under a name
## the new kind's defaults also give a colour, so a Paper toned to a warm
## grey is a Canvas of the same grey. The Layer menu's Ground choice asks for
## it, because a painter who picks another ground there is changing the
## surface and not the tone they chose for it.
static func swap(
    document: SaDocument,
    layer: SaLayer,
    descriptor: SaLayerTypeDescriptor,
    types: SaLayerTypeRegistry = null,
    keep_colors: bool = false
) -> void:
    if document == null or layer == null or not layer.is_generated():
        return
    if descriptor == null or not descriptor.is_generated() or descriptor.id == layer.layer_type:
        return
    var named := str(layer.name)
    var old_kind := types.get_descriptor(layer.layer_type) if types != null else null
    if old_kind != null and is_kind_name(named, kind_name(old_kind)):
        named = free_name(document, kind_name(descriptor))
    var before := [layer.layer_type, layer.generator, layer.generator_params.duplicate(), str(layer.name)]
    var params := defaults_for(descriptor, document.color_space)
    for key: String in params if keep_colors else {}:
        if params[key] is Color and layer.generator_params.get(key) is Color:
            params[key] = layer.generator_params[key]
    var after := [descriptor.id, descriptor.generator, params, named]
    _apply_ground(document, layer, after)
    if document.history != null:
        document.history.commit_pair(
            "Swap Ground", _apply_ground.bind(document, layer, after), _apply_ground.bind(document, layer, before)
        )


## The grounds *layer* could be swapped to, in the registry's order: every
## registered type that stores nothing and answers a height, the paper, the
## canvas and any a module registers, and the flat colour of [constant
## SOLID], which answers none.
static func grounds(registry: SaLayerTypeRegistry) -> Array[SaLayerTypeDescriptor]:
    var found: Array[SaLayerTypeDescriptor] = []
    if registry == null:
        return found
    for descriptor: SaLayerTypeDescriptor in registry.list_descriptors():
        if is_ground_kind(descriptor):
            found.append(descriptor)
    return found


## Whether a layer of *descriptor*'s type is a ground: one that answers a
## height, or the flat colour of [constant SOLID]. The flat colour is named by
## its id rather than found by its shape, because a module's generated layer
## that carries only a colour is a fill of its own and not a ground.
static func is_ground_kind(descriptor: SaLayerTypeDescriptor) -> bool:
    return answers_height(descriptor) or (descriptor != null and descriptor.id == SOLID and descriptor.is_generated())


## What a ground of *descriptor*'s kind is called when it is made, the name
## the Add menu shows it under.
static func kind_name(descriptor: SaLayerTypeDescriptor) -> String:
    return descriptor.display_name if not descriptor.display_name.is_empty() else String(descriptor.id)


## Whether *named* is still what a ground of the kind called *kind* was named
## when it was made, the kind's name alone or with a number after it.
static func is_kind_name(named: String, kind: String) -> bool:
    if named == kind:
        return true
    var number := named.trim_prefix(kind + " ")
    return number != named and number.is_valid_int() and number.to_int() >= 2


## *kind* when no layer of *document* is called that, and otherwise the
## first of *kind* 2, *kind* 3 and on that is free, so a second paper is
## Paper 2.
static func free_name(document: SaDocument, kind: String) -> String:
    var taken := {}
    for child in document.get_children():
        taken[str(child.name)] = true
    var candidate := kind
    var number := 2
    while taken.has(candidate):
        candidate = "%s %d" % [kind, number]
        number += 1
    return candidate


## Names *layer*, a new ground of *descriptor*'s kind, for that kind, takes it
## out of any group, and answers where in *document*'s stack it goes in.
static func lay(document: SaDocument, layer: SaLayer, descriptor: SaLayerTypeDescriptor) -> int:
    layer.name = free_name(document, kind_name(descriptor))
    layer.group = null
    return ground_index(document)


## Where a new ground goes in *document*'s stack: under every layer that holds
## the painting, at the top level, so a paper added over two painted layers
## leaves both in sight.
##
## Under the paint rather than at the very bottom, because a document New laid
## out starts on an opaque Background, and a paper put beneath that is a paper
## the canvas never shows. The run at the bottom it goes above is the grounds
## already laid and the Background New made, which only its name tells apart,
## so a second ground lands over the first and is the one in sight. A bottom
## layer the painter renamed counts as paint, and the ground goes under it.
static func ground_index(document: SaDocument) -> int:
    var index := 0
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer.is_group or SaLayerStack.parent_of(layer) != null:
            break
        var laid := index == 0 and str(layer.name) == SaDocumentBackground.LAYER_NAME
        if not (layer.is_generated() or laid):
            break
        index += 1
    return index


static func _apply_ground(document: SaDocument, layer: SaLayer, state: Array) -> void:
    layer.layer_type = state[0]
    layer.generator = state[1]
    layer.generator_params = SaTyped.strings(state[2]).duplicate()
    layer.name = str(state[3])
    document.modified = true
    document.request_cache_update()
    document.document_changed.emit()


## Whether any layer the compositor walks stores nothing.
static func any_in(document: SaDocument) -> bool:
    for layer in SaLayerStack.layers(document):
        if layer.is_generated():
            return true
    return false


## Every grid position a generated layer has drawn on: the whole document
## rectangle when there is one, nothing otherwise.
static func covered_positions(document: SaDocument) -> Array[Vector2i]:
    if not any_in(document):
        return []
    return SaLayer.grid_positions(document.canvas_size)


## Sets *layer*'s colour, as one history step, and redraws the document,
## because a background has drawn on every chunk.
static func fill(document: SaDocument, layer: SaLayer, color: Color) -> void:
    if document == null or layer == null or not layer.is_generated():
        return
    var previous: Color = layer.generator_params.get(PARAM_COLOR, Color(0.5, 0.5, 0.5, 1.0))
    if previous == color:
        return
    _apply_color(document, layer, color)
    if document.history != null:
        document.history.commit_pair(
            "Fill Background", _apply_color.bind(document, layer, color), _apply_color.bind(document, layer, previous)
        )


static func _apply_color(document: SaDocument, layer: SaLayer, color: Color) -> void:
    _apply_param(document, layer, PARAM_COLOR, color)


static func _apply_param(document: SaDocument, layer: SaLayer, key: String, value: Variant) -> void:
    layer.generator_params[key] = value
    document.modified = true
    document.request_cache_update()
    document.document_changed.emit()


## The layer the view draws beyond the document rectangle: the bottom-most
## top-level layer that stores nothing and contributes, or null. Beyond the
## rectangle nothing else is drawn, so whatever a background at any height
## would show through is the honest thing to show there.
static func view_source(document: SaDocument) -> SaLayer:
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or not layer.is_generated():
            continue
        if SaLayerStack.parent_of(layer) != null or not SaLayerStack.shows(document, layer):
            continue
        return layer
    return null


## What `apply_view` would set, as a comparable array, so the canvas syncs
## only when something moved, the zoom included.
static func view_state(document: SaDocument, pixels_per_texel: float = 1.0) -> Array:
    var source := view_source(document)
    if source == null:
        return []
    var light := document.relief_light
    return [
        source.get_instance_id(),
        source.generator,
        source.generator_params.duplicate(),
        source.opacity,
        pixels_per_texel,
        SaSettings.show_relief,
        light.angle,
        light.strength,
        SaSettings.relief_gloss,
        document.dpi,
        document.canvas_size
    ]


## Points *rect* at the view source's generator shader with its parameters
## in display colour, or hides the rect when there is none.
##
## *pixels_per_texel* is how many screen pixels one document pixel covers, the
## zoom taken with the window's interface scale, which the rect cannot say for
## itself. The shader gets its reciprocal as `texels_per_pixel` and the paper
## fades the grain it cannot resolve by it, so the paper beyond the document is
## as smooth as the paper inside at the same zoom. One is 100 percent.
static func apply_view(rect: ColorRect, document: SaDocument, pixels_per_texel: float = 1.0) -> void:
    var source := view_source(document)
    if source == null:
        rect.visible = false
        return
    var descriptor_shader: Shader = _view_shader_for(source.generator)
    if descriptor_shader == null:
        rect.visible = false
        return
    var material := rect.material as ShaderMaterial
    if material == null or material.shader != descriptor_shader:
        material = ShaderMaterial.new()
        material.shader = descriptor_shader
        rect.material = material
    # A uniform the layer has no parameter for goes back to the shader's own
    # default, or a ground saved without an edge would draw the edge of the
    # ground this rect showed before it.
    for uniform: Dictionary in descriptor_shader.get_shader_uniform_list():
        if not source.generator_params.has(str(uniform["name"])):
            material.set_shader_parameter(str(uniform["name"]), null)
    var space := document.color_space
    var color: Color = source.generator_params.get(PARAM_COLOR, Color(0.5, 0.5, 0.5, 1.0))
    var second: Color = source.generator_params.get(PARAM_SECOND, color)
    if space != null:
        color = space.to_display(color)
        second = space.to_display(second)
    color.a *= source.opacity
    second.a *= source.opacity
    material.set_shader_parameter("color_a", color)
    material.set_shader_parameter("color_b", second)
    material.set_shader_parameter("scale", SaTyped.float_at(source.generator_params, PARAM_SCALE, 1.0))
    # Every other number under its own name, the canvas's threads and a
    # module's own parameters alike, as the kernel reads them. A shader that
    # declares no uniform of the name keeps the value and never reads it.
    for key: String in source.generator_params:
        var value: Variant = source.generator_params[key]
        if key != PARAM_SCALE and (value is float or value is int):
            material.set_shader_parameter(key, SaTyped.real(value, 0.0))
    material.set_shader_parameter("rect_origin", rect.position)
    material.set_shader_parameter("rect_size", rect.size)
    material.set_shader_parameter("page_size", Vector2(document.canvas_size))
    material.set_shader_parameter("texels_per_pixel", 1.0 / maxf(absf(pixels_per_texel), 0.001))
    # The tooth lit as the relief lights it inside: the same switch, light and
    # resolution, and the opacity the relief weighs the tooth by.
    material.set_shader_parameter("relief_enabled", SaSettings.show_relief)
    material.set_shader_parameter("relief_light", document.relief_light.toward())
    material.set_shader_parameter("relief_strength", document.relief_light.strength)
    material.set_shader_parameter("relief_gloss", SaSettings.relief_gloss)
    material.set_shader_parameter("tooth_weight", source.opacity)
    material.set_shader_parameter("pixel_mm", 25.4 / (document.dpi if document.dpi > 0.0 else SaDocument.DEFAULT_DPI))
    rect.visible = true


## The view shader for *generator*, from whichever registered type names it.
## The registry is not at hand here, so the skeleton's own is answered
## directly and a module's is looked up through the registries the main
## window holds.
static func _view_shader_for(generator: String) -> Shader:
    var path := ""
    if generator == "background":
        path = SaLayerTypeDescriptor.background().generator_view
    else:
        var registries := _registries()
        if registries == null:
            return null
        for descriptor: SaLayerTypeDescriptor in registries.layer_types.list_descriptors():
            if descriptor.generator == generator:
                path = descriptor.generator_view
    if path.is_empty() or not ResourceLoader.exists(path):
        return null
    return load(path) as Shader


## The application's registries, when a main scene holds them.
static func _registries() -> SaRegistries:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var held: Variant = main_node.get("registries")
    return held if held is SaRegistries else null


## The parameters as JSON can hold them: a colour is its four channels.
static func params_to_json(params: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {}
    for key: String in params:
        var value: Variant = params[key]
        out[key] = [value.r, value.g, value.b, value.a] if value is Color else value
    return out


## The reverse: four numbers under a colour key come back as a colour.
static func params_from_json(data: Variant) -> Dictionary[String, Variant]:
    var params: Dictionary[String, Variant] = {}
    if not data is Dictionary:
        return params
    for key: String in data:
        var value: Variant = data[key]
        var channels: Array = value if value is Array else []
        if channels.size() == 4 and key in [PARAM_COLOR, PARAM_SECOND]:
            params[key] = Color(
                SaTyped.real(channels[0]), SaTyped.real(channels[1]), SaTyped.real(channels[2]), SaTyped.real(channels[3])
            )
        else:
            params[key] = value
    return params


## What a generated layer reads as in the walk: its kernel evaluated over a
## region of one chunk into a scratch this step owns, which the compositor then
## composites like a chunk of paint. The compositor holds one and keeps
## `generate_chunk` as the door the export and the suites call. It moved here
## from `core/composite` when the adjustment layer's calls took that folder
## past its budget, since it is the generated layer's engine.
class Step:
    extends RefCounted

    ## One scratch, reused, so a generated chunk is a chain like a clipped one
    ## and goes through `composite_chunk` one at a time.
    var _scratch: SaTexture = null

    ## *layer*'s kernel evaluated over *region* of the chunk at *offset*, in
    ## the scratch at *format*. The kernel is dispatched over the region alone,
    ## so hard rule 2 holds for a layer that covers the whole document.
    func generate(compositor: SaCompositor, layer: SaLayer, offset: Vector2, region: Rect2i, format: int) -> SaTexture:
        var side := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        if _scratch == null or _scratch.format != format or _scratch.size != side:
            _scratch = SaTexture.new(side, format)
        var covered := region if region.size.x > 0 else Rect2i(Vector2i.ZERO, side)
        var compute: SaCompute = compositor.get_compute(layer.generator)
        compute.use_storage_format(format)
        compute.set_texture(0, _scratch.rid)
        SaGeneratedLayer.bind_params(compute, layer, offset, covered)
        compute.dispatch_kernel("generate", SaCompute.groups_for(covered.size.x), SaCompute.groups_for(covered.size.y), 1)
        return _scratch

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            _scratch = null
