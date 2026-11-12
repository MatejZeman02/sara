## What kind of layer this is: which fields it stores, and how it turns them into
## the colour the compositor reads.
##
## The module-facing door to the field mechanism. Without it `SaFieldSpec`,
## `SaLayer.schema`, `resolve_hook` and the unresolved set could only be driven
## by code reaching into `SaLayer` directly, duck typing the door exists to
## keep out: a module could not declare a layer type without doing what
## `skeleton_module.gd` is forbidden to do.
##
## Its shape comes from two independent real cases rather than one imagined
## one. Impasto ships `[albedo, height]` and
## a mixing layer ships `[concentrations, thickness, albedo*]` with the albedo derived.
## Two consumers is the point at which the shared shape is knowable rather than
## guessed.
##
## Deliberately mirrors SaToolDescriptor and SaBlendModeDescriptor: stable id,
## display name, the data, and an owner the registry fills in.
##
## **A generator a module ships** is a `.gmacs` in the
## module's own tree, named on [member generator] as `<module id>/<file>`.
## The shader index files a module's kernel under the folder it lives in, so a
## qualified name never meets another module's file of the same name. Its
## first image is the target, and its `generate` kernel writes the region of
## one chunk the dispatch names, at the document position `offset` plus the
## texel, so the pattern holds still under a pan and across a chunk's edge.
## `tests/fixtures/noise-ground` is one, a procedural noise.
##
## **Its parameters reach it through the push constant, by name.**
## `SaGeneratedLayer.params_of` reads the kernel's `params:` block and fills
## each name it declares: `offset`, `region_origin` and `region_size` from the
## dispatch, `color_a` and `color_b` from the layer's two colours, `scale`,
## `tooth`, and `weight`, how much of the ground the relief shows, one for the
## colour. Every other name is the layer's parameter of that name, a number, a
## colour or a vector, nought when the layer has none. The push constant
## rather than a buffer, because a generator's parameters are a few numbers
## per layer, read alike by every texel and changed between the dispatches of
## one composite, which a push constant carries with no allocation and no
## upload. The 128 bytes every Vulkan device guarantees are thirty-two floats,
## six of them the dispatch's place, and a generator that needs a table is one
## this door does not carry yet. By name rather than at fixed places, because
## the three built-in grounds kept their parameters in each other's padding
## so that one block served all of them, and a module's own had no place to
## go.
##
## **It answers a height on the paper's terms, or reads flat.** A `tooth`
## among its [member generator_defaults] is a promise of a `raise_tooth`
## kernel beside `generate`, which adds the tooth times `weight` times its
## grain to the height in its image, and the relief then lays that under the
## paint. Without a tooth the relief passes the layer by and never asks for
## `raise_tooth`. A tooth with no `raise_tooth` is a kernel the relief cannot
## dispatch, so the two go together.
##
## **Its view** is the canvas shader [member generator_view] names, which
## `SaGeneratedLayer.apply_view` hands `color_a` and `color_b` in display
## colour with the layer's opacity in their alpha, `rect_origin`,
## `rect_size`, `texels_per_pixel`, and every number among the layer's
## parameters under its own name.
@tool
class_name SaLayerTypeDescriptor
extends RefCounted

## The type every document has, and what a layer is when nobody says otherwise.
const PLAIN: StringName = &"plain"
## The input of a type that stores nothing and adjusts instead: the backdrop
## the walk has built when it reaches the layer, which is an adjustment layer.
const INPUT_BELOW: StringName = &"below"
## The input of an effect layer: the node of the tree its layer names in
## `SaLayer.source`, a layer or a group, wherever it sits.
const INPUT_NAMED: StringName = &"named"

## The paper's presets, at ten pixels to the millimetre, a sheet worked at
## 254 dpi, the resolution a fibre a millimetre and a half long and a felt
## cell of one to three reads at. Cartridge is the plain sheet a new paper
## has always been, its settings as they were, with a few fibres. Hot Pressed
## is smooth and white with fibres and a low tooth, Cold Pressed carries the
## felt's cells at 1.6 mm, and Rough deeper ones at 2.8 mm. The colours are
## close off-whites, so the grain's spread over its mean stands within twice
## the spread of ambientCG's Paper001 and Paper003 either way, which the
## ground's suite holds.
const PAPER_PRESETS: Array[Dictionary] = [
    {
        "name": "Cartridge",
        "params":
        {
            "color": Color(0.93, 0.91, 0.86, 1.0),
            "second": Color(0.82, 0.79, 0.72, 1.0),
            "scale": 20.0,
            "tooth": 0.9,
            "fibre": 0.35,
            "felt": 0.0,
            "felt_size": 16.0,
            "laid": 0.0,
        },
    },
    {
        "name": "Hot Pressed",
        "params":
        {
            "color": Color(0.95, 0.94, 0.91, 1.0),
            "second": Color(0.86, 0.84, 0.79, 1.0),
            "scale": 10.0,
            "tooth": 0.3,
            "fibre": 0.5,
            "felt": 0.0,
            "felt_size": 16.0,
            "laid": 0.0,
        },
    },
    {
        "name": "Cold Pressed",
        "params":
        {
            "color": Color(0.94, 0.92, 0.87, 1.0),
            "second": Color(0.80, 0.77, 0.70, 1.0),
            "scale": 16.0,
            "tooth": 0.8,
            "fibre": 0.4,
            "felt": 0.6,
            "felt_size": 16.0,
            "laid": 0.0,
        },
    },
    {
        "name": "Rough",
        "params":
        {
            "color": Color(0.94, 0.92, 0.87, 1.0),
            "second": Color(0.85, 0.82, 0.75, 1.0),
            "scale": 24.0,
            "tooth": 1.0,
            "fibre": 0.4,
            "felt": 1.0,
            "felt_size": 28.0,
            "laid": 0.0,
        },
    },
]

## The canvas's presets, their thread spacing the reference scan's in
## millimetres at ten pixels to the millimetre: Medium Linen is Poly Haven's
## `rough_linen` at 0.64 mm, Coarse Linen its `hessian_380` at 1.49 mm and
## Hessian its `hessian_230` at 3.2 mm, each measured as the strongest peak of
## the scan's spectrum along either axis. Fine Cotton at 0.4 mm has no scan of
## a known size behind it, because ambientCG's fabrics carry none. The finer
## the cloth the more it is primed, as a painter buys it, and hessian comes
## raw.
const CANVAS_PRESETS: Array[Dictionary] = [
    {
        "name": "Fine Cotton",
        "params":
        {
            "color": Color(0.93, 0.91, 0.87, 1.0),
            "second": Color(0.72, 0.69, 0.63, 1.0),
            "scale": 4.0,
            "thickness": 0.55,
            "irregularity": 0.25,
            "slub": 0.2,
            "fuzz": 0.3,
            "crimp": 0.5,
            "priming": 0.7,
            "tooth": 0.6,
        },
    },
    {
        "name": "Medium Linen",
        "params":
        {
            "color": Color(0.88, 0.84, 0.76, 1.0),
            "second": Color(0.58, 0.52, 0.42, 1.0),
            "scale": 6.4,
            "thickness": 0.6,
            "irregularity": 0.45,
            "slub": 0.6,
            "fuzz": 0.5,
            "crimp": 0.25,
            "priming": 0.4,
            "tooth": 0.9,
        },
    },
    {
        "name": "Coarse Linen",
        "params":
        {
            "color": Color(0.82, 0.76, 0.64, 1.0),
            "second": Color(0.50, 0.44, 0.34, 1.0),
            "scale": 14.9,
            "thickness": 0.62,
            "irregularity": 0.5,
            "slub": 0.7,
            "fuzz": 0.6,
            "crimp": 0.7,
            "priming": 0.15,
            "tooth": 1.0,
        },
    },
    {
        "name": "Hessian",
        "params":
        {
            "color": Color(0.74, 0.62, 0.44, 1.0),
            "second": Color(0.30, 0.24, 0.16, 1.0),
            "scale": 32.0,
            "thickness": 0.55,
            "irregularity": 0.6,
            "slub": 0.8,
            "fuzz": 0.8,
            "crimp": 0.8,
            "priming": 0.0,
            "tooth": 1.0,
        },
    },
]

## Stable identity. Persisted in `.sad`, so it must not change meaning.
var id: StringName

var display_name: String = ""

## The fields a layer of this type carries, as a **template**.
##
## Not used verbatim: see [method schema_for]. A colour field's storage format is
## the document's business, not the layer type's.
var schema: Array[SaFieldSpec] = []

## Recomputes this type's derived fields for one chunk, called as
## `resolve.call(layer, grid_pos, chunk)`. Becomes the layer's `resolve_hook`.
##
## Empty for a type with no derived fields, which is every type that stores the
## colour it composites.
var resolve: Callable = Callable()

## The blend mode a new layer of this type starts on.
var default_blend_mode: StringName = &"normal"

## Name resolved through SaUI.get_icon(), not a path. Shown in the layers
## docker's add-layer list.
var icon_name: String = ""

## What a layer of this type does, in a sentence a painter reads on the hover of
## its row in the layers docker's add list and in the Layer menu. Empty shows
## no hover, so a module's type says what it is the way a built-in's does.
var hint: String = ""

## A kind that is a picture to paint over, such as a frame another program
## sends: a new one goes under the paint, above the Background and the grounds
## as a ground does, and the brush stays on the layer it was on, since a
## stroke on a layer the next frame writes over is lost.
var under_paint: bool = false

## A type that evaluates a kernel instead of storing pixels: the name of a
## `.gmacs` whose `generate` kernel fills a chunk-local region from the
## layer's `generator_params`, by the names its push constant declares, as the
## header says. Sara's own are under `shaders/compute/`, and a module's is
## `<module id>/<file>`. Such a layer holds no chunks, is never folded into a
## cache, and contributes over every dirty region of the document rectangle.
## Empty for a type that stores.
var generator: String = ""

## The path of the canvas shader that draws the same generator in view space
## behind the document, so the background reaches the viewport edges without
## a view-sized compute target. Takes the uniforms `SaGeneratedLayer.apply_view`
## sets. Empty draws nothing beyond the document. A path rather than the
## Shader itself: a descriptor lives in a registry that outlives a test run,
## and a Resource held there is one the runner reports as leaked at exit.
var generator_view: String = ""

## What a new layer of a generated type starts with, in display-referred
## colour where a value is a colour: `apply_to` converts into the document.
var generator_defaults: Dictionary[String, Variant] = {}

## The settings a painter picks in one go from the ground's Preset row, each
## `{"name": String, "params": Dictionary}`, its colours display-referred as
## [member generator_defaults]'s are. A pick writes every parameter the
## preset names and leaves the others, the edge among them, as they stand.
var generator_presets: Array[Dictionary] = []

## Where a generated ground's grain stands at its median, as a share of the
## way from its first colour to its second. New Document lays the colour a
## painter asks for there, so the grain lies about that colour rather than to
## one side of it. Nought, the default, lays the colour asked as the first,
## which suits a ground whose first colour is most of what shows.
var grain_median: float = 0.0

## A type that stores nothing and reads an input instead, which its layer's
## attached filters run over: [constant INPUT_BELOW] for an adjustment layer,
## the backdrop at its place in the walk, and [constant INPUT_NAMED] for an
## effect layer, the node its layer names. Copied onto the layer as
## [member generator] is, so the walk asks the layer and never the type id.
## Empty for a type that stores or generates.
var input: StringName = &""

## A type whose pixels come from a Godot scene rather than from a brush: the
## `res://` path of a `PackedScene` that `SaSceneLayer` instantiates into an
## offscreen viewport at the document's size and copies into the layer's chunks
## once a frame. Empty for every other type. A path rather than the scene, for
## the reason `generator_view` gives.
var scene: String = ""

## What a new layer of a scene type starts with, set onto the scene's root by
## property name, so a scene's parameters are its root's exported properties.
var scene_defaults: Dictionary[String, Variant] = {}

## A type whose pixels are drawn from a recipe rather than painted: a script
## extending `SaDrawnRecipe`, a fresh instance of which `SaDrawnLayer` gives
## every layer of the type, a vector layer's objects or a text layer's block.
## Such a layer keeps the plain schema and ordinary chunks, a cache every
## reader of a layer's chunks reads as paint, and the `.sad` keeps the recipe
## in their place. Null for every other type. A script rather than an
## instance, because every layer needs its own.
var recipe: Script = null

## A kind not ready for every painter. It stays registered, so a document that
## holds one opens and shows it and the door adds one, but the Layer menu, the
## layers docker's arrow and the search stop offering it until Preferences'
## Show experimental tools is on.
var experimental: bool = false

## Set by the registry. Modules never write this.
var owner_module: StringName = &""


## Whether a painter is offered this kind to add: every kind but an
## experimental one, which waits for the setting.
func offered() -> bool:
    return not experimental or SaSettings.experimental_tools


static func create(type_id: StringName, type_schema: Array[SaFieldSpec]) -> SaLayerTypeDescriptor:
    var descriptor := SaLayerTypeDescriptor.new()
    descriptor.id = type_id
    descriptor.schema = type_schema
    descriptor.display_name = String(type_id).capitalize()
    return descriptor


func is_valid() -> bool:
    return not String(id).is_empty() and not schema.is_empty()


## This type's schema as a document in *space* should actually allocate it.
##
## Every **colour** field takes the document's texel format, and every other
## field keeps the format the type declared. That split is not a convenience: a
## colour field's depth is the document's declared choice and the one place it
## may be decided is the descriptor, so a document cannot record
## `"depth": "F16"` while allocating F32 chunks. A height or concentration field is not
## colour, its precision is the layer type's own business, and the document has
## no opinion about it.
##
## A fresh array of fresh specs every call, so two layers of the same type never
## share a spec object one of them could edit.
func schema_for(space: SaColorSpace) -> Array[SaFieldSpec]:
    var color_format: int = space.texel_format() if space != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var resolved: Array[SaFieldSpec] = []
    for spec in schema:
        if spec == null:
            continue
        var format: int = color_format if spec.is_color else spec.format
        resolved.append(SaFieldSpec.create(spec.id, format, spec.is_color, spec.derived_from.duplicate()))
    return resolved


func is_generated() -> bool:
    return not generator.is_empty()


func is_scene() -> bool:
    return not scene.is_empty()


func is_drawn() -> bool:
    return recipe != null


## A layer drawn from a recipe of *script*, registered under *type_id* the way
## a module registers any type. It keeps the plain schema, because its pixels
## are stored in chunks like paint, and only who writes them differs.
static func drawn_layer(type_id: StringName, script: Script) -> SaLayerTypeDescriptor:
    var descriptor := create(type_id, SaFieldSpec.default_schema())
    descriptor.icon_name = "Polygon2D"
    descriptor.recipe = script
    return descriptor


## A layer shown by the scene at *path*, registered under *type_id* the way a
## module registers any type, with *defaults* for its root's properties. It
## keeps the plain schema, because its pixels are stored in chunks like paint,
## and only who writes them differs.
static func scene_layer(type_id: StringName, path: String, defaults: Dictionary[String, Variant] = {}) -> SaLayerTypeDescriptor:
    var descriptor := create(type_id, SaFieldSpec.default_schema())
    descriptor.icon_name = "PackedScene"
    descriptor.scene = path
    descriptor.scene_defaults = defaults.duplicate()
    return descriptor


## The background that stores nothing, the Solid Colour ground: a flat colour
## evaluated by `background.gmacs` over the document rectangle and by
## `background.gdshader` beyond it. Mid grey by default, which is what the
## stored background of a fresh document is filled with. It keeps the plain
## schema so a chunk could be allocated on it, and never is.
static func background() -> SaLayerTypeDescriptor:
    var descriptor := create(&"background", SaFieldSpec.default_schema())
    descriptor.display_name = "Solid Colour"
    descriptor.icon_name = "bucket"
    descriptor.hint = "A ground of one colour to lay under a painting, set under the layer list. It holds no paint."
    descriptor.generator = "background"
    descriptor.generator_view = "res://shaders/canvas/background.gdshader"
    descriptor.generator_defaults = {"color": Color(0.5, 0.5, 0.5, 1.0)}
    return descriptor


## The paper that stores nothing: three octaves of value noise, with fibres,
## felt cells and laid lines by their amounts, between two colours, evaluated by `paper.gmacs` over the document rectangle and by
## `paper.gdshader` beyond it, at a cell width in document pixels. The ground
## a painter puts under a painting, and nothing the brush reads: the brush's
## own paper is a setting on the stamp brush and a different thing.
##
## Two close off-whites by default, because the point of a paper is a tooth the
## eye finds rather than a pattern it reads, and a cell twenty pixels wide,
## which at the sizes a document is worked at is a grain rather than a cloud.
## It keeps the plain schema for the same reason the background does, so a chunk
## could be allocated on it, and never is.
##
## Its tooth is the grain's height, 0.9 of a virtual millimetre, rather than the
## 0.15 of a cold pressed watercolour sheet, which reads as flat paper on screen
## where a tooth near 1.0 shows the grain.
##
## Its grain's median stands half way between the two colours, because value
## noise over hashes spread evenly from 0 to 1 is as likely to fall either side
## of a half: 0.501 over a 1200 by 580 document at the default cell. So
## [member grain_median] is said here, or a paper New Document lays with the
## colour asked as its first would stand half way to its darker second, 5.5 L*
## under a colour of `#f4f2ed`.
static func paper() -> SaLayerTypeDescriptor:
    var descriptor := create(&"paper", SaFieldSpec.default_schema())
    descriptor.display_name = "Paper"
    descriptor.icon_name = "guiminicheckerboard"
    descriptor.hint = "A ground of paper grain to lay under a painting, set under the layer list. It holds no paint."
    descriptor.generator = "paper"
    descriptor.generator_view = "res://shaders/canvas/paper.gdshader"
    descriptor.generator_presets = PAPER_PRESETS
    descriptor.generator_defaults.assign(PAPER_PRESETS[0]["params"])
    descriptor.generator_defaults["edge"] = 0.0
    descriptor.grain_median = 0.5
    return descriptor


## The woven canvas that stores nothing: two sets of threads
## crossing over and under, evaluated by `canvas.gmacs` over the document
## rectangle and by `canvas.gdshader` beyond it. Its spacing, thickness,
## twist and tone wander by noise at the document position, so the weave
## never repeats, and it answers a height as the paper does, which thick
## paint buries.
##
## A primed cotton by default: threads a shade off white over gaps a little
## darker, eight pixels apart, which at a document's working size reads as a
## medium weave, each thread 0.36 of the spacing wide, a third of the way to
## wholly irregular, square to the document, and threads a whole virtual
## millimetre high, a little prouder than the paper's tooth, as a canvas is.
static func canvas() -> SaLayerTypeDescriptor:
    var descriptor := create(&"canvas", SaFieldSpec.default_schema())
    descriptor.display_name = "Canvas"
    descriptor.icon_name = "guiminicheckerboard"
    descriptor.hint = "A ground of woven canvas to lay under a painting, set under the layer list. It holds no paint."
    descriptor.generator = "canvas"
    descriptor.generator_view = "res://shaders/canvas/canvas.gdshader"
    descriptor.generator_defaults = {
        "color": Color(0.92, 0.89, 0.83, 1.0),
        "second": Color(0.66, 0.61, 0.53, 1.0),
        "scale": 8.0,
        "thickness": 0.36,
        "irregularity": 0.35,
        "angle": 0.0,
        "tooth": 1.0,
        "slub": 0.0,
        "fuzz": 0.0,
        "crimp": 0.0,
        "priming": 0.0,
        "edge": 0.0,
    }
    descriptor.generator_presets = CANVAS_PRESETS
    return descriptor


## The plain RGBA layer: one authoritative colour field, nothing derived.
##
## Lives here rather than in the skeleton module so a test, and a module that
## wants a plain layer with one extra field, can start from it.
static func plain() -> SaLayerTypeDescriptor:
    var descriptor := create(PLAIN, SaFieldSpec.default_schema())
    descriptor.display_name = "Paint Layer"
    descriptor.icon_name = "ToolAddNode"
    descriptor.hint = "An empty layer to paint on."
    return descriptor
