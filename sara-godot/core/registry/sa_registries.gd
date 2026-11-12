## The seventeen registries plus the context handed to modules.
##
## Owning them in one small object keeps the wiring order explicit and testable:
## build registries, register the skeleton's own built-ins through the public
## API, load modules, and only then build UI from what is registered. The old
## order ran ModuleLoader on the last line of Main._ready(), after every docker
## already existed - which is precisely why the toolbox had to hardcode buttons.
class_name SaRegistries
extends RefCounted

const SkeletonModuleScript = preload("res://core/loader/skeleton_module.gd")

var tools := SaToolRegistry.new()
var blend_modes := SaBlendModeRegistry.new()
var layer_types := SaLayerTypeRegistry.new()
var ui := SaUIRegistry.new()
## After `ui`, which it asks whether the docker a command acts in is showing.
var commands := SaCommandRegistry.new(ui)
var view_transforms := SaViewTransformRegistry.new()
## The seventh: the filters a module offers, which the Filter menu and one
## command per filter read.
var filters := SaFilterRegistry.new()
## The eighth: the engines the skeleton constructs, by role, so a module's
## subclass is what a construction site gets.
var roles := SaRoleRegistry.new()
## The ninth: the fields a brush engine paints through, so a module adds one.
var brush_fields := SaBrushFieldRegistry.new()
## The tenth: where the pen's state comes from when a module reads it outside
## Godot, which the tool machine asks before it presumes a button held.
var pens := SaPenRegistry.new()
## The eleventh: the rules a simulation steps a paint layer by.
var simulation_rules := SaSimulation.Rules.new()
## The twelfth: the kinds of projection a document can be a picture of.
var projections := SaProjection.Kinds.new()
## The thirteenth: the catalogues a module translates Sara with, which the
## Languages page in Preferences lists.
var translations := SaTranslationRegistry.new()
## The fourteenth: the picture formats File > Open and Export read, which
## `register_builtins` installs as the one a static reader asks.
var image_formats := SaImageFormatRegistry.new()
## The fifteenth: where input comes from when Godot does not hand it to a
## control by itself, which the settings, the door's `midi` step and the state
## dump ask by id.
var input_sources := SaInputSourceRegistry.new()
## The sixteenth: the codecs a save asks for by name, which a module such as
## the JPEG XL one registers and `register_builtins` installs as the one a
## static save asks.
var codecs := SaCodecRegistry.new()
## The seventeenth: the sensors a module adds to `SaSensor`'s own, which
## `register_builtins` installs as the one a dab asks.
var sensors := SaSensorRegistry.new()

var context: SaContext = null
var skeleton_module: SaModule = null


## `easel_provider` returns the primary SaEasel, `surface_provider`
## returns every paintable surface. Both are injected so core/ never reaches into
## render/ or ui/, and so is *drive*, what a bound control moves, the app's own
## where it hands one and a bare one that moves nothing otherwise.
func build_context(easel_provider: Callable, surface_provider: Callable, drive: SaControlDrive = null) -> SaContext:
    context = SaContext.create(
        tools, blend_modes, commands, layer_types, ui, view_transforms, easel_provider, surface_provider, filters, roles
    )
    context.brush_fields = brush_fields
    context.pens = pens
    context.simulation_rules = simulation_rules
    context.projections = projections
    context.translations = translations
    context.image_formats = image_formats
    context.input_sources = input_sources
    context.codecs = codecs
    context.sensors = sensors
    if drive != null:
        context.drive = drive
    return context


## Registers the skeleton's built-ins (the 17 blend modes and the plain layer
## type) through the same API a module uses.
func register_builtins() -> void:
    if context == null:
        push_error("SaRegistries: build_context() must run before register_builtins().")
        return
    skeleton_module = SkeletonModuleScript.new()
    var scoped := context.for_module(skeleton_module.get_id())
    skeleton_module.context = scoped
    skeleton_module.register(scoped)
    SaImageFormatRegistry.install(image_formats)
    SaCodecRegistry.install(codecs)
    SaSensorRegistry.install(sensors)
    # It is a module by every measure that matters, so it is listed as one and
    # unloaded like one. Registering it here rather than through discovery only
    # reflects that it ships inside the skeleton instead of under res://modules.
    ModuleLoader.loaded_modules[skeleton_module.get_id()] = skeleton_module


## Every registered blend mode resolves to a real kernel and every layer type
## names formats that can be allocated. Returns the problems, empty when healthy.
## Worth calling once after modules load, so nothing falls back to Normal in
## silence.
func validate() -> Array[String]:
    var problems := blend_modes.validate()
    problems.append_array(layer_types.validate())
    return problems
