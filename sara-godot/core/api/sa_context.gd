## What a module is handed at registration. The public API surface.
##
## A context rather than the root node, so a module never reaches into the UI's
## internals, can be tested without a UI tree, and does not break when the
## skeleton is reorganised.
##
## There is deliberately no get_canvas(): a module has no business holding a
## TextureRect. It gets an easel (document + compositor, no UI) and surfaces.
##
## Performance contract: nothing here is called per dab or per chunk. Registries
## are touched at registration, at stroke begin/end, and once per composite -
## a dictionary lookup against a GPU dispatch measured in tens of microseconds.
## Per-dab work goes through SaPaintContext, which holds no Callables.
class_name SaContext
extends RefCounted

## Bumped when this API changes incompatibly. ModuleLoader refuses a module built
## against a newer one.
const API_VERSION: int = 1
## The noun the Transform tool's pass hands [method refuse_paint], untranslated,
## the one gesture a smart layer whose contents are open turns away.
const TRANSFORM_GESTURE := "transform"

var tools: SaToolRegistry
var blend_modes: SaBlendModeRegistry
var commands: SaCommandRegistry
var layer_types: SaLayerTypeRegistry
var ui: SaUIRegistry
## The sixth, the seventh, what the Filter menu offers, and the eighth, the
## engines the skeleton constructs by role. Optional in `create()` so a fixture
## that builds a context for a tool test need not know about them.
var view_transforms: SaViewTransformRegistry = null
var filters: SaFilterRegistry = null
var roles: SaRoleRegistry = null
## The preset converters by engine pair, built with the context rather than
## optional, so a bare one registers a converter as well as the app's does.
var converters := SaConverterRegistry.new()
## The ninth to the fourteenth, each built with the context like the
## converters, so a bare one takes a registration, and replaced by
## `SaRegistries` with the app's own: the fields a brush engine paints
## through, where the pen's state comes from when a module reads it outside
## Godot, the rules a simulation steps a paint layer by, the kinds of
## projection a document can be a picture of, the catalogues a module
## translates Sara with, and the picture formats Sara opens and exports.
var brush_fields := SaBrushFieldRegistry.new()
var pens := SaPenRegistry.new()
var simulation_rules := SaSimulation.Rules.new()
var projections := SaProjection.Kinds.new()
var translations := SaTranslationRegistry.new()
var image_formats := SaImageFormatRegistry.new()
## The fifteenth, where input comes from when Godot does not hand it to a
## control by itself, a MIDI controller the first, built and replaced the same
## way.
var input_sources := SaInputSourceRegistry.new()
## The codecs a save asks for by name, built and replaced the same way, and
## held by a module's context as a view that files what it registers under the
## module, `codecs.register(name, encode, decode)` the door's call.
var codecs := SaCodecRegistry.new()
## The sensors a module adds to `SaSensor`'s own, which a preset's curve reads,
## held by a module's context as a view that files what it registers under the
## module, `sensors.register(key, reading)` the door's call.
var sensors := SaSensorRegistry.new()
## The sixteenth, the registries a module brings of its own for the search F3
## and the loupe open, which a module announces with `searches.register(it)`.
## The skeleton's registries are walked without it, so a tool, a docker, a
## filter, a command or a kind of layer registered through this door is found
## with no call at all. The context makes it itself, since `SaRegistries` has
## nothing to hand it, and a module's context holds a view of it that files
## what it announces under the module.
var searches := SaSearchRegistry.new()
## What a bound control drives: the app's values, presets and filters, which a
## module's bindings move with no window of the app named. The app hands its
## own to [method SaRegistries.build_context], and a bare one, as a suite's
## context holds, moves nothing.
var drive := SaControlDrive.new()

## Resolves an easel by id. Injected by the host so core/ does not reach into
## render/ or ui/. The three below are read by a module that builds a context
## beside this one, and are set by the constructor alone. [method for_module]
## builds its second instance through the constructor rather than writing them
## into it.
var easel_provider: Callable = Callable()
var surface_provider: Callable = Callable()
var module_id: StringName = &""


func _init(easel_source: Callable = Callable(), surface_source: Callable = Callable(), owning_id: StringName = &"") -> void:
    easel_provider = easel_source
    surface_provider = surface_source
    module_id = owning_id


static func create(
    tool_registry: SaToolRegistry,
    blend_registry: SaBlendModeRegistry,
    command_registry: SaCommandRegistry,
    layer_type_registry: SaLayerTypeRegistry,
    ui_registry: SaUIRegistry,
    view_transform_registry: SaViewTransformRegistry = null,
    easel_source: Callable = Callable(),
    surface_source: Callable = Callable(),
    filter_registry: SaFilterRegistry = null,
    role_registry: SaRoleRegistry = null
) -> SaContext:
    var context := SaContext.new(easel_source, surface_source)
    context.tools = tool_registry
    context.blend_modes = blend_registry
    context.commands = command_registry
    context.layer_types = layer_type_registry
    context.ui = ui_registry
    context.view_transforms = view_transform_registry
    context.filters = filter_registry
    context.roles = role_registry
    return context


## The door's version. Static, so a module can ask it before it holds a
## context, and so the door stays inside gdlint's 32 public methods with the
## input sources' registration beside the pen's.
static func api_version() -> int:
    return API_VERSION


## A view of this context bound to one module, so registrations are attributed
## and unregister() can remove exactly what that module added.
func for_module(owning_module: StringName) -> SaContext:
    var scoped := SaContext.new(easel_provider, surface_provider, owning_module)
    scoped.tools = tools
    scoped.blend_modes = blend_modes
    scoped.commands = commands
    scoped.layer_types = layer_types
    scoped.ui = ui
    scoped.view_transforms = view_transforms
    scoped.filters = filters
    scoped.roles = roles
    scoped.converters = converters
    scoped.brush_fields = brush_fields
    scoped.pens = pens
    scoped.simulation_rules = simulation_rules
    scoped.projections = projections
    scoped.translations = translations
    scoped.image_formats = image_formats
    scoped.input_sources = input_sources
    scoped.codecs = codecs.for_module(owning_module)
    scoped.sensors = sensors.for_module(owning_module)
    scoped.searches = searches.for_module(owning_module)
    scoped.drive = drive
    return scoped


## The front document's easel: its document, compositor and output texture, no
## UI. The host passes `SaDocuments.front_easel`, so this follows the surface
## the painter brought forward and `EventBus.active_document_changed` says when.
func get_easel() -> SaEasel:
    if not easel_provider.is_valid():
        return null
    var held: Variant = easel_provider.call()
    return held if held is SaEasel else null


## Every paintable surface: the main canvas plus embedded ones such as the info
## docker's scratchpad. A tool is instantiated per surface.
func list_surfaces() -> Array:
    if not surface_provider.is_valid():
        return []
    return surface_provider.call()


## Every open document, once each: the one on every surface, the info docker's
## scratchpad among them, and the front easel's when no surface is known.
## Sara runs more than one easel, so a change that reaches documents reaches
## all of them rather than the front one.
func open_documents() -> Array[SaDocument]:
    var documents: Array[SaDocument] = []
    for surface: Variant in list_surfaces():
        if surface is SaSurface:
            var typed: SaSurface = surface
            var document := typed.get_document()
            if document != null and not documents.has(document):
                documents.append(document)
    var front := _document_of(get_easel())
    if front != null and not documents.has(front):
        documents.append(front)
    return documents


## Every layer of every open document. A group is a layer and a child of the
## document like any other, so the walk is flat.
func open_layers() -> Array:
    var layers: Array = []
    for document in open_documents():
        for child in document.get_children():
            if child is SaLayer:
                layers.append(child)
    return layers


## Writable per-module directory for caches and presets. Created on first use.
## Under `module-data` in the data root, not `modules`: that one is where the
## painter drops a module's code, and a data directory beside it would be
## scanned as a module with nothing in it. The root is the one
## `--settings-dir` moves, so a scratch run keeps its module data apart.
func module_data_dir() -> String:
    var base := ProjectSettings.globalize_path(SaDataRoot.path("module-data"))
    var id_part := String(module_id) if not String(module_id).is_empty() else "unknown"
    var path := base.path_join(id_part)
    if not DirAccess.dir_exists_absolute(path):
        DirAccess.make_dir_recursive_absolute(path)
    return path


## A preference of this module's own, remembered between sessions, or *default*
## when the profile holds none.
##
## Kept in the painter's `settings.cfg` under a section named for the module,
## `module.<id>`, so a reset of the profile forgets it with everything else and
## a module never adds a property to the skeleton's settings to remember a
## value. The value is anything a `ConfigFile`
## holds, and the module that reads it decides what it may be.
##
## *formerly* is `[section, key]` where the skeleton kept the value before the
## module took it over, MIDI's Listen under `input` for one.
## A value found there is moved under the module's section before the answer,
## once, and the old key leaves the profile. Until then the profile keeps it,
## since a save writes every key a load read.
func preference(key: StringName, default: Variant = null, formerly: Array = []) -> Variant:
    return SaSettings.module_preference(module_id, key, default, formerly)


## Stores a preference of this module's own and saves the profile, the way
## every other preference is saved. `SaSettings.changed` announces it as the
## module id, a slash and *key*. A null forgets the key.
func set_preference(key: StringName, value: Variant) -> void:
    SaSettings.set_module_preference(module_id, key, value)


## Convenience: register everything a module owns, attributed to it.
func register_tool(descriptor: SaToolDescriptor) -> bool:
    return tools.register(descriptor, module_id)


## An engine of the Brush rather than a tool of its own: described the way a
## tool is, and picked by choosing one of its presets while the Brush is in
## hand. See [method SaToolRegistry.register_brush_engine].
func register_brush_engine(descriptor: SaToolDescriptor) -> bool:
    return tools.register_brush_engine(descriptor, module_id)


func register_blend_mode(descriptor: SaBlendModeDescriptor) -> bool:
    return blend_modes.register(descriptor, module_id)


func register_command(descriptor: SaCommandDescriptor) -> bool:
    return commands.register(descriptor, module_id)


func register_layer_type(descriptor: SaLayerTypeDescriptor) -> bool:
    return layer_types.register(descriptor, module_id)


## A view transform: a toggle that stacks or a mode that replaces the ordinary
## view. Refused when the context was built without the registry.
func register_view_transform(descriptor: SaViewTransformDescriptor) -> bool:
    if view_transforms == null:
        push_error("SaContext: this context has no view transform registry.")
        return false
    return view_transforms.register(descriptor, module_id)


## A filter: one entry in the Filter menu under this module's name, and one
## command so the palette and a shortcut reach the same dialog.
##
## The command is registered here rather than in the filter registry, because
## the two registries are siblings and neither should have to know the other.
## Its handler asks the registry to invoke the filter, and the host that owns
## the dialog answers that signal, so a menu row, a chord and a test all open
## the dialog through one call.
##
## Refused when the context was built without the registry, the way a view
## transform is.
func register_filter(filter: SaFilter) -> bool:
    if filters == null:
        push_error("SaContext: this context has no filter registry.")
        return false
    var key := SaFilterRegistry.key_for(module_id, filter)
    # The name the filter asked for, or the one its key spells. Asked before
    # anything is registered, so a refused command cannot leave a filter in the
    # menu that no chord and no palette can reach.
    var command_id := SaFilterRegistry.command_for(key, filter)
    if commands.has(command_id):
        # Both claimants, because a filter that declares its own action name can
        # meet a command it has never heard of, and "already registered" on its
        # own sends the reader looking in the wrong module's file.
        var held := commands.get_descriptor(command_id)
        push_error(command_clash_line(module_id, filter.title(), command_id, held.owner_module))
        return false
    if not filters.register(filter, module_id):
        return false
    var registry := filters
    var command := SaCommandDescriptor.create(command_id, filter.title(), func() -> bool: return registry.invoke(key))
    command.category = &"filter"
    # d17. Written here so the menu, the palette and the browser all read one
    # string off the command rather than each asking the filter again.
    command.sentence = filter.sentence()
    # Empty for every filter that declared none. Set before the command is
    # registered, because registering is what creates the InputMap action from
    # these events, and an action created without them has no chord.
    command.default_events = filter.chord()
    return commands.register(command, module_id)


## A section of the Filter menu and the filter browser: a submenu headed
## *label*, holding every filter whose `family()` answers *section_id*, from
## any module. *place* orders the sections, lower first, and the base module's
## own are a hundred apart so a stranger's can sit between two of them. Other
## is always last. Dropped with this module's filters when it unloads.
##
## Refused when the context was built without the registry, the way a filter
## is, and for an id somebody already registered.
func register_filter_section(section_id: StringName, label: String, place: int) -> bool:
    if filters == null:
        push_error("SaContext: this context has no filter registry.")
        return false
    return filters.register_section(section_id, label, place, module_id)


## The console line for one command id two things want, in the form
## [method register_filter] prints. A function rather than a literal in the
## refusal, for the reason `SaRoleRegistry.claim_line` gives: GDScript hands no
## caller the text of a pushed error, so a test reads the same words it asserts
## rather than the words as the diff happened to leave them.
static func command_clash_line(asking: StringName, title: String, command_id: StringName, holder: StringName) -> String:
    return (
        "SaContext.register_filter: '%s' from %s asked for the command '%s', which %s already registered."
        % [
            title,
            _module_named(asking, "an unnamed module"),
            command_id,
            _module_named(holder, "a command with no module"),
        ]
    )


## A module id as that sentence reads it, or *unnamed* when there is none. A
## command the skeleton registered carries no module, and one that says so is
## worth more than one naming the asker as the holder.
static func _module_named(named: StringName, unnamed: String) -> String:
    return "'%s'" % named if not String(named).is_empty() else unnamed


## Whether *layer* turns away a tool that writes pixels, and when it does, the
## painter is told why on `EventBus.paint_refused`, the corner a refused stroke
## already used. *gesture* is the translated noun for what did nothing, the
## stroke, the fill or the gradient, and it goes into the sentence.
##
## The one call a tool's guard makes, in place of a bare `refuses_paint`, so a
## tool from a module and a built-in say the same thing in the same place. The
## lock is named first, because a locked layer is one the painter can unlock
## and a generated one is not. A tool that refuses a generated layer with
## nowhere to say so leaves a pen that does nothing, which reads as a broken
## pen.
##
## Static, because the guards live in engines like the transform pass and the
## patch pass that hold a document and no context. The line is said on the bus,
## so core names no window.
static func refuse_paint(layer: SaLayer, gesture: String) -> bool:
    var open := contents_refusal_line(layer, gesture)
    if not open.is_empty():
        EventBus.paint_refused.emit(open)
        return true
    if layer == null or not layer.refuses_paint():
        return false
    EventBus.paint_refused.emit(paint_refusal_line(layer, gesture))
    return true


## The sentence the Transform tool's pass says over a smart layer whose
## contents are open, empty for every other gesture and layer. The view draws
## the layer through no map, so a box there would move paint
## the map shows elsewhere, while every other tool paints into it as into an
## ordinary layer. The pass names its gesture [constant TRANSFORM_GESTURE].
static func contents_refusal_line(layer: SaLayer, gesture: String) -> String:
    if gesture != TranslationServer.translate(TRANSFORM_GESTURE) or not SaLocalView.untransformed(layer):
        return ""
    var line := (
        "The contents of '%s' are open for painting, so the transform did nothing."
        + " Close them with Layer > Edit Smart Layer Contents first."
    )
    return TranslationServer.translate(line) % layer.name


## What the Transform tool says when it is asked more of *layer* than a move
## of the whole of it, a text layer's scale, turn, skew or selected part,
## translated with the layer's name, or empty for a layer with no such line.
static func reshape_refusal_line(layer: SaLayer) -> String:
    return SaLayerRefusals.reshape_sentence(layer)


## The sentence for a lock the painter set, said by [method paint_refusal_line]
## and by a tool whose stroke a lock turns away from a mask, where a group's
## mask takes paint and the group's own line would be wrong.
static func lock_refusal_line(gesture: String) -> String:
    return TranslationServer.translate("This layer is locked, so the %s did nothing. Unlock it in the Layers docker.") % gesture


## The sentence [method refuse_paint] says for *layer*, empty when the layer
## takes paint. A function of its own so a test reads the words it asserts.
static func paint_refusal_line(layer: SaLayer, gesture: String) -> String:
    if layer == null or not layer.refuses_paint():
        return ""
    var opening := SaSadFile.opening_refusal(layer.get_parent() as SaDocument, gesture)
    if not opening.is_empty():
        return opening
    # A group answers locked whatever was set, so it is asked for first and
    # gets the line that says what it is rather than a lock it does not have.
    if layer.is_group:
        var group := "This group holds no paint, so the %s did nothing. Select a layer inside it or add one to paint on."
        return TranslationServer.translate(group) % gesture
    if layer.is_locked:
        return lock_refusal_line(gesture)
    if layer.is_adjustment():
        var line := "This layer adjusts what is below it and holds no paint, so the %s did nothing. Add a layer to paint on."
        return TranslationServer.translate(line) % gesture
    if layer.is_effect():
        var shows := "This layer shows its input through its filters and holds no paint, so the %s did nothing."
        return TranslationServer.translate(shows) % gesture
    var own := SaLayerRefusals.paint_sentence(layer, gesture)
    if not own.is_empty():
        return own
    if layer.live_transform != null:
        var moved := (
            "This smart layer is drawn through its transform, so the %s did nothing."
            + " Use Layer > Convert to Ordinary Layer first."
        )
        return TranslationServer.translate(moved) % gesture
    return (
        TranslationServer.translate(
            "This layer is drawn by its generator and holds no paint, so the %s did nothing. Add a layer to paint on."
        )
        % gesture
    )


## The line an eraser on an alpha-locked layer says.
const ALPHA_LOCKED_ERASE := "This layer's alpha is locked, so the eraser did nothing. Unlock alpha in the Layers docker."

## The line an eraser says when it ended on a layer holding no paint where it
## went, with the name of the layer below that holds the paint it crossed.
const EMPTY_ERASE_BELOW := "The eraser found nothing on '%s'. The paint you rubbed is on '%s', so pick that layer to erase it."

## The same line where no layer below holds paint where the eraser went.
const EMPTY_ERASE := "The eraser found nothing on '%s', which holds no paint where you rubbed."

## The line a stroke, an erase, a fill or a gradient says when its press is
## turned away because the layer it would paint is hidden.
const HIDDEN_STROKE := "'%s' is hidden, so the %s was not made. Show it with its eye in the Layers docker."


## The sentence an erase stroke says when it changed no texel because *layer*
## holds nothing under it. *below* is the nearest layer under it holding paint
## where the stroke went, or null when there is none.
static func empty_erase_line(layer: SaLayer, below: SaLayer) -> String:
    if layer == null:
        return ""
    if below == null:
        return TranslationServer.translate(EMPTY_ERASE) % layer.name
    return TranslationServer.translate(EMPTY_ERASE_BELOW) % [layer.name, below.name]


## The sentence a *gesture* on *layer* says when the layer is hidden, itself or
## by a group it sits in, and the press was turned away.
static func hidden_layer_line(layer: SaLayer, gesture: String) -> String:
    if layer == null:
        return ""
    return TranslationServer.translate(HIDDEN_STROKE) % [layer.name, gesture]


## Whether *layer* turns away a paint tool's press because it is hidden, by its
## own eye or by a group it sits in, and when it does, the painter is told on
## `EventBus.paint_refused` with [method hidden_layer_line].
##
## Asked at the press, before anything is drawn, so a stroke the painter could
## not see is never drawn under the pen and never committed, and no undo step is
## made. Kept apart from [method refuse_paint], which the transform, the flip and
## the cut ask as well, because those move paint that is already there and stay
## as they were on a hidden layer.
static func refuse_hidden(layer: SaLayer, gesture: String) -> bool:
    if layer == null or not hidden(layer):
        return false
    EventBus.paint_refused.emit(hidden_layer_line(layer, gesture))
    return true


## The guard a brush asks at its press, once the pointer says which end of the
## pen is down: [method refuse_erase] for an *erasing* press that paints no
## mask, then [method refuse_hidden], with the noun for what was not made.
static func refuse_press(layer: SaLayer, erasing: bool, on_mask: bool) -> bool:
    if erasing and not on_mask and refuse_erase(layer):
        return true
    var gesture := TranslationServer.translate("erase") if erasing else TranslationServer.translate("stroke")
    return refuse_hidden(layer, gesture)


## The guard a paint tool asks at its press: [method refuse_paint] for the lock
## and the kind of layer, then [method refuse_hidden], so one line is said for
## whichever turned the press away.
static func refuse_stroke(layer: SaLayer, gesture: String) -> bool:
    return refuse_paint(layer, gesture) or refuse_hidden(layer, gesture)


## Whether *layer* is hidden, by its own eye or by a group it sits in.
static func hidden(layer: SaLayer) -> bool:
    var at := layer
    var count := 0
    while at != null and count < 64:
        if not at.visible:
            return true
        at = SaLayerStack.parent_of(at)
        count += 1
    return false


## Whether *layer* turns away an eraser because its alpha is locked, and when
## it does, the painter is told why on `EventBus.paint_refused`, where
## [method refuse_paint] says its own line.
##
## Alpha lock keeps every pixel's coverage, and an erase moves coverage and
## nothing else, so the stroke would paint nothing. A paint stroke on the same
## layer still tints, which is why this is a question of its own and not part
## of `refuses_paint`. Read through `in`, because the scratchpad in the brush
## editor paints into a layer of another type.
static func refuse_erase(layer: Object) -> bool:
    if layer == null or not ("alpha_locked" in layer) or layer.get("alpha_locked") != true:
        return false
    EventBus.paint_refused.emit(TranslationServer.translate(ALPHA_LOCKED_ERASE))
    return true


## An engine under a role name: `crop`, `transform`, `resample`,
## `selection_filters`, `flood` or `gradient` today, or a role of the
## module's own. The skeleton registers its engines through this door at
## boot, and a module that registers a subclass under the same role is what
## every construction site gets from then on, in the dialogs, the commands
## and the tools alike. The console names both modules when that happens.
##
## Refused when the context was built without the registry, the way a view
## transform is.
func register_role(role: StringName, script: Script) -> bool:
    if roles == null:
        push_error("SaContext: this context has no role registry.")
        return false
    return roles.register(role, script, module_id)


## A field a brush engine paints through, *added.engine* naming which, held
## for this module and dropped when it unloads. Refused for a field with no id
## or no engine, or an id its engine already has. The noise module's grain,
## bristle and picture register here like a stranger's field would.
func register_brush_field(added: SaBrushFieldRegistry.Field) -> bool:
    return brush_fields.register(added, module_id)


## A pen read outside Godot, held for this module and dropped when it unloads.
## The tool machine asks the newest source which of the pen's buttons are held
## before it presumes one, and the Tablet page shows what the source says.
func register_pen_source(source: SaPenSource) -> bool:
    return pens.register(source, module_id)


## A picture format File > Open and Export read, held for this module and
## dropped when it unloads. Refused for an id another module holds.
func register_image_format(format: SaImageFormat) -> bool:
    return image_formats.register(format, module_id)


## Where input comes from, a MIDI controller for one, held for this module and
## released when it unloads. Applied at once, and again whenever a setting it
## names moves. Refused for an id another source holds.
func register_input_source(source: SaInputSource) -> bool:
    return input_sources.register(source, module_id)


## A rule a simulation steps a paint layer by, held for this module and dropped
## when it unloads. *key* names it on the layer and in a file, *kernel* is a
## kernel of the `.gmacs` *shader* names as `<owner>/<name>`, under the
## contract of a neighbourhood pass, *reach* is how many texels a cell reads
## from itself in one step, and *defaults* are its parameters. Refused for a
## key already registered.
##
## *state* is for a rule whose state is not a colour, and empty for one that
## steps the paint. It holds `field`, the [SaFieldSpec] the rule steps, which
## the layer's schema carries while the rule is on it, `shader`, the `.gmacs`
## of the two kernels that join the field to the paint, and their names as
## `seed` and `colour`. `SaSimulation.State` says what each kernel reads and
## writes. Refused for a field the layer has already or a kernel left unnamed.
func register_simulation_rule(
    key: StringName, label: String, shader: String, kernel: String, reach: int, defaults: Dictionary = {}, state: Dictionary = {}
) -> bool:
    var kept: SaSimulation.State = null
    if not state.is_empty():
        var given := SaTyped.strings(state)
        var field: SaFieldSpec = null
        if given.get("field") is SaFieldSpec:
            field = given["field"]
        kept = SaSimulation.State.new(
            field, SaTyped.text_at(given, "shader", ""), SaTyped.text_at(given, "seed", ""), SaTyped.text_at(given, "colour", "")
        )
    var rule := SaSimulation.Rule.new(key, label, shader, kernel, reach, SaTyped.strings(defaults), module_id, kept)
    return simulation_rules.register(rule, module_id)


## A kind of projection, held for this module and dropped when it unloads.
## Refused for a kind with no id or an id already registered. The skeleton's
## flat, equirectangular and polar register here like a stranger's would.
func register_projection(added: SaProjection.Kind) -> bool:
    return projections.register(added, module_id)


## A catalogue of this module's translations for one locale, a `Translation`
## or the path of a `.po` file, installed in `TranslationServer` at once and
## taken out when the module unloads. Where two catalogues carry one sentence
## for one locale, the one registered last is the one shown, and Preferences >
## Languages lists them in that order. Refused for a catalogue of `en`, since
## English is the text every catalogue translates from.
func register_translation(catalogue: Variant) -> bool:
    return translations.register(catalogue, module_id)


## The script registered under *role*, or null when nothing is. This is the
## lookup a `new()` became: the caller builds the instance, because the
## constructor arguments are its own.
func engine_for(role: StringName) -> Script:
    return roles.script_for(role) if roles != null else null


## A converter of presets of *from_engine* into presets of *to_engine*, one per
## pair, a held pair refused. *converter* takes the preset as loaded and answers
## the new settings, which the store saves beside the original.
func register_converter(from_engine: StringName, to_engine: StringName, converter: Callable) -> bool:
    return converters.register(from_engine, to_engine, converter, module_id)


## Adds a layer of *type_id* to *document*, or to the one in front when none
## is given, and returns it. Null when the type is not registered.
##
## The point of this method is that a module never constructs an `SaLayer` and
## pokes its schema. Naming a type that is not registered returns null rather
## than a plain layer, because a caller that silently gets the wrong kind of
## layer finds out at the first dab, in the compositor, with nothing to say why.
func create_layer(type_id: StringName, document: SaDocument = null) -> SaLayer:
    var target := document if document != null else _document_of(get_easel())
    if target == null:
        return null
    if not layer_types.has(type_id):
        push_error("SaContext.create_layer: no layer type '%s' is registered." % type_id)
        return null
    return SaLayerOps.new(target).add(type_id, layer_types)


## The easel's document, or null. A separate function so `create_layer` reads as
## one expression and a null easel is handled in one place.
func _document_of(easel: SaEasel) -> SaDocument:
    return easel.document if easel != null else null


## This module's own slice of *document*'s stored state, to read and to mutate,
## the document in front when none is named.
##
## Returned by reference, so a module writes to the document simply by writing to
## the dictionary. It is created on first ask, so there is no register-then-use
## dance and no way to ask for a slice that does not exist yet.
##
## Keyed by module id, which is what makes "a module's data" a real boundary
## rather than a convention: a module cannot reach another's slice through this
## call, and Sara never has to understand any of it.
##
## The values must be JSON: dictionaries, arrays, strings, numbers, booleans and
## null. **JSON has one number type**, so a module that writes the integer 3 gets
## 3.0 back after a save and a load. `SaExport` writes the canonical form so a
## file is stable from its first save rather than its second, but it cannot
## invent an integer type that JSON does not have.
func document_data(document: SaDocument = null) -> Dictionary[String, Variant]:
    var target := document if document != null else _document_of(get_easel())
    if target == null:
        return {}
    return _slice_of(target.module_data)


## This module's own slice of *layer*'s stored state, to read and to mutate.
##
## Per layer as well as per document, because Kubelka-Munk is a layer type rather
## than a document mode: what a layer's concentration channels mean is a fact
## about that layer.
func layer_data(layer: SaLayer) -> Dictionary[String, Variant]:
    if layer == null:
        return {}
    return _slice_of(layer.module_data)


## This module's entry in a module-data dictionary, created if absent.
##
## A stored value that is not a Dictionary is replaced rather than returned. Only
## a module's own code reaches its own key, so this is a file that was corrupted
## or hand-edited, and handing back something a module cannot write to would move
## the failure to its first assignment.
##
## A slice a file brought in is a plain Dictionary, and is typed here once and
## put back, so the module mutates the one the document keeps and every later
## call hands back that same object.
func _slice_of(store: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var key := String(module_id)
    var held: Variant = store.get(key)
    var plain: Dictionary = held if held is Dictionary else {}
    if not (held is Dictionary and plain.get_typed_key_builtin() == TYPE_STRING):
        store[key] = SaTyped.strings(held)
    return store[key]


## A docker of this module's own, listed in the Window menu after the ones the
## default layout opens. *sentence* says what it holds and is its row's tooltip
## there, the same argument the skeleton's own dockers fill.
##
## *side*, `&"left"` or `&"right"`, and *order* are where it opens in a layout
## that does not name it, which is every layout Sara ships: at that side of the
## window, stacked under the bar with the module dockers placed there, the
## lower *order* higher. A docker given no side opens closed until the Window
## menu opens it.
func register_docker(
    docker_id: StringName,
    title: String,
    factory: Callable,
    shortcut_action: StringName = &"",
    sentence: String = "",
    side: StringName = &"",
    order: int = 0
) -> bool:
    return ui.register_docker(docker_id, title, factory, shortcut_action, module_id, sentence, side, order)


## A page of this module's own in Preferences, listed after the skeleton's pages
## of its *group*: one of `SaUIRegistry.SETTINGS_GROUPS`, `&"interface"`,
## `&"painting"` or `&"files_and_system"`, and the last when it names none.
## `factory` takes the Preferences window and returns the page's Control.
func register_settings_page(page_id: StringName, title: String, factory: Callable, group: StringName = &"") -> bool:
    return ui.register_settings_page(page_id, title, factory, module_id, group)


## Removes every registration made by this module. Called by ModuleLoader on
## unload, so a module does not have to track its own bookkeeping. *layers* go
## to the layer type registry, which lets go of a hook into this module on each
## one of its types, and are empty everywhere but a reload.
func remove_all_registrations(layers: Array = []) -> void:
    tools.unregister_module(module_id)
    blend_modes.unregister_module(module_id)
    commands.unregister_module(module_id)
    layer_types.unregister_module(module_id, layers)
    ui.unregister_module(module_id)
    if view_transforms != null:
        view_transforms.unregister_module(module_id)
    if filters != null:
        filters.unregister_module(module_id)
    if roles != null:
        roles.unregister_module(module_id)
    converters.unregister_module(module_id)
    SaTagLabels.unregister_module(module_id)
    brush_fields.unregister_module(module_id)
    pens.unregister_module(module_id)
    simulation_rules.unregister_module(module_id)
    projections.unregister_module(module_id)
    translations.unregister_module(module_id)
    image_formats.unregister_module(module_id)
    input_sources.unregister_module(module_id)
    codecs.unregister_module(module_id)
    sensors.unregister_module(module_id)
    searches.unregister_module(module_id)
