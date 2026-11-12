## Filter > Apply Again: the filter a dialog applied last, run once more on
## the active layer with the settings its widgets held and the way it was
## applied, with no dialog, as one history step. Krita's Apply Filter Again, on
## Krita's chord, `Ctrl+F`.
##
## **What is kept is data, under the filter registry it came from.** The
## registry key, the filter's title, its parameters as `SaFilter.parameters`
## answered them on Apply, and the way, `bake`, `attach`, `layer` or
## `picture`. Static and keyed by the registry's instance id, because the one
## registry Sara builds at its start lives until it quits, a module reload
## included, so what it keeps is what was applied "since Sara started", and a
## registry a suite builds starts with nothing applied whatever the suites
## before it applied, rather than one record for the whole process, which
## would show the last suite's filter in the next suite's menu. No filter,
## document or registry is held: the registry is asked again on every run,
## so a module reloaded since is met as it is now.
##
## **The run is the dialog's Apply with the dialog left out.** The registry's
## one instance of the filter takes the kept values, runs once in a preview
## context as the dialog's last run did, and is written by the call the
## dialog's Apply makes for that way: `SaFilterOps.one_shot` for a bake,
## `SaFilterOps.attach` on the layer or on the root, and
## `SaFilterConversion.add_holding` for an adjustment layer. The values the
## instance held go back afterwards, the way `SaFilterChain` gives them back
## after evaluating a record.
##
## A filter no loaded module registers any more, one that cannot run, or a way
## the active layer refuses leaves the layer alone and says why on the status
## line, through `SaStrokeNote.say`, the line's one door for why something a
## painter did changed nothing.
class_name SaFilterAgain
extends RefCounted

## The command, which the Filter menu's top row and the chord both run.
const COMMAND := &"filter_apply_again"

## What the status line says when the filter's module is gone, with its title.
const GONE := "%s cannot be applied again, because no loaded module adds it any more."
## What it says with no active layer, the dialog's own sentence.
const NO_LAYER := "There is no active layer to run '%s' on."
## What it says when the way was taken and nothing changed, with the title and
## the layer's name. A refusal the write itself makes is said in the corner as
## well, by the operation that refused.
const UNCHANGED := "%s changed nothing on '%s'."
## What it says for an adjustment layer when nothing registers the kind.
const NO_ADJUSTMENT := "No module registers the adjustment layer."

## What each registry's dialogs applied last, by the registry's instance id.
## Written here alone. One for every document, because Apply Again repeats the
## last filter the painter applied, in whichever document is in front now.
static var _kept: Dictionary[int, Kept] = {}


## One Apply, as data.
class Kept:
    extends RefCounted

    ## The filter's registry key.
    var key: StringName
    ## Its title as the filter answered it, untranslated, so the menu row names
    ## it after the module that added it has gone.
    var title: String
    ## Its parameters on Apply, a copy.
    var values: Dictionary
    ## The way Apply took.
    var way: StringName

    func _init(filter_key: StringName, filter_title: String, parameters: Dictionary, how: StringName) -> void:
        key = filter_key
        title = filter_title
        values = parameters.duplicate(true)
        way = how


## Registers the command through the door a module's takes, under `Ctrl+F`,
## which nothing in Sara Default held. Its row is disabled until a filter has
## been applied. A weak reference, because the context holds the registries
## that hold this command, the cycle `SkeletonModule` gives the same answer.
static func register_command(ctx: SaContext) -> void:
    var held: WeakRef = weakref(ctx)
    var command := SaCommandDescriptor.create(COMMAND, "Apply the last filter again", _run_in.bind(held))
    command.label = "Apply Filter Again"
    var chord := InputEventKey.new()
    chord.keycode = KEY_F
    chord.ctrl_pressed = true
    command.default_events = [chord]
    command.category = &"filter"
    command.sentence = "Run the filter you applied last again on the active layer, with its settings and its way, and no dialog."
    command.enabled = _remembered_in.bind(held)
    ctx.register_command(command)


## Whether a filter from *filters* has been applied, which is whether the
## command can run.
static func remembered(filters: SaFilterRegistry) -> bool:
    return filters != null and _kept.has(filters.get_instance_id())


## The title of the filter applied last from *filters*, untranslated, or ""
## before any.
static func last_title(filters: SaFilterRegistry) -> String:
    return _kept[filters.get_instance_id()].title if remembered(filters) else ""


## Keeps what a filter dialog's Apply ran from *filters*: the filter under
## *filter_key* called *filter_title*, with *parameters*, the way *how*.
static func remember(
    filters: SaFilterRegistry, filter_key: StringName, filter_title: String, parameters: Dictionary, how: StringName
) -> void:
    if filters == null:
        return
    _kept[filters.get_instance_id()] = Kept.new(filter_key, filter_title, parameters, how)


## Forgets what *filters* kept, which a suite does on the way out so a freed
## registry leaves nothing behind.
static func forget(filters: SaFilterRegistry) -> void:
    if filters != null:
        _kept.erase(filters.get_instance_id())


## The command's enabled check, on the context's registry.
static func _remembered_in(ctx_ref: WeakRef) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    return ctx != null and remembered(ctx.filters)


## The command's handler, on the context's document with its registries.
static func _run_in(ctx_ref: WeakRef) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    if ctx == null:
        return false
    var easel := ctx.get_easel()
    return run(easel.document if easel != null else null, ctx.filters, ctx.layer_types)


## Runs the filter applied last from *filters* on *document*'s active layer,
## the way it was applied, an adjustment layer being made from *layer_types*.
## Answers whether it changed the document. Says on the status line why, when
## it did not, and clears the line when it did, as a stroke that paints does.
static func run(document: SaDocument, filters: SaFilterRegistry, layer_types: SaLayerTypeRegistry) -> bool:
    if not remembered(filters):
        return false
    var kept := _kept[filters.get_instance_id()]
    var filter := filters.get_filter(kept.key)
    var layer := document.active_layer if document != null else null
    var why := _refusal(kept, filter, layer, layer_types)
    if not why.is_empty():
        SaStrokeNote.say(why)
        return false
    var held := filter.parameters()
    filter.set_parameters(kept.values)
    var wrote := _write(kept, document, filter, filters.owner_of(kept.key), layer_types)
    filter.set_parameters(held)
    if wrote:
        SaStrokeNote.say("")
    else:
        var named := TranslationServer.translate(kept.title)
        SaStrokeNote.say(TranslationServer.translate(UNCHANGED) % [named, layer.name])
    return wrote


## Why the filter *kept* names cannot run on *layer* the kept way, or "" when
## it can. *filter* is the registry's, null when no loaded module adds it.
##
## The questions the dialog asks before it lets Apply through, in its order:
## the filter's own problem, which dims every row of it, and the way's, which
## is `SaFilterApply.way_refusal` for a bake and the adjustment layer's kind
## for Layer. Attach and Picture hang a record on any layer.
static func _refusal(kept: Kept, filter: SaFilter, layer: SaLayer, layer_types: SaLayerTypeRegistry) -> String:
    var named := TranslationServer.translate(kept.title)
    if filter == null:
        return TranslationServer.translate(GONE) % named
    if layer == null:
        return TranslationServer.translate(NO_LAYER) % named
    var problem := filter.problem().split("\n")[0].strip_edges()
    if not problem.is_empty():
        return problem
    if kept.way == &"layer" and layer_types == null:
        return TranslationServer.translate(NO_ADJUSTMENT)
    return SaFilterApply.way_refusal(layer, kept.way)


## Writes *filter*, holding the values *kept* names, into *document* the kept
## way, as one history step, and answers whether it did. *module_id* is the
## module that registered it, which a bake's context runs its kernels from.
static func _write(
    kept: Kept, document: SaDocument, filter: SaFilter, module_id: StringName, layer_types: SaLayerTypeRegistry
) -> bool:
    var layer := document.active_layer
    var way := kept.way
    match way:
        &"attach":
            var filed := filter.filed_as(kept.key)
            return SaFilterOps.new(document).attach(layer, filed.key, filed.parameters) != null
        &"layer":
            var filed := filter.filed_as(kept.key)
            var named := filter.translated_title()
            return SaFilterConversion.new(document).add_holding(filed.key, filed.parameters, layer_types, named) != null
    var context := SaFilterContext.new(document, layer, module_id, filter.title(), true)
    return SaFilterApply.call_run(filter, context) and SaFilterOps.one_shot(context, filter)
