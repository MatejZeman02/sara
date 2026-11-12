## A simulation on a paint layer: a rule a module registered, stepping the
## layer's own paint where it lies, on any paint layer.
##
## A rule is what a module registers through `SaContext.register_simulation_rule`:
## a key, a label, a kernel in a `.gmacs` of its own, its reach (how many texels
## a cell reads from itself in a step) and its parameters with their defaults.
## The base module's Spread registers through that call like a stranger's (hard
## rule 6). The kernel keeps the contract of [SaNeighbourhoodPass]: the previous
## state padded by the reach at binding 0, the mask at 1 (one everywhere, since a
## step takes no selection), and the next state at 2. A kernel that declares
## `int step` is told the number of the step it takes, the first being nought,
## and one that imports `simulation` reads `sa_step_random`, a hash of the cell
## and that number. The step binds no buffer, so no atomic's order could differ
## between two runs and a step is the same picture every time.
##
## A record, [SaSimulationRecord], is the rule on one layer, held at
## `SaLayer.simulation`: the rule's key, its parameters, the seed, the step count
## and the second copy of the state. A rule whose state is not a colour declares
## a [State] field of its own, which the record puts into the layer's schema
## beside an `albedo` worked out from it ([SaSimulationField]). Taking the record
## off frees the seed and the second copy, takes the field out of every chunk and
## of the schema, and leaves `albedo` painted again at the colour last resolved.
##
## A step reads every allocated chunk the window reaches with its halo from the
## previous state of its neighbours, writes the next state into the second copy,
## and swaps the two once every chunk is written. It stays in VRAM (hard rule 1)
## and covers those chunks and nothing else (hard rule 2). Before it the layer
## grows by the rule's light cone, the ring of empty chunks round the ones it
## holds, as often as paint could cross a chunk, inside the record's domain (the
## canvas unless the painter set a rectangle), so a pattern spreads into chunks
## nobody painted with nothing read back. Paint carried past the domain is lost.
## Past the canvas the halo reads the nearest texel inside it, so the edge holds
## paint rather than draining it.
##
## Reset copies the seed back, which is what was last painted, drops the chunks
## a ring grew into, and counts from nought again. Neither Step nor Reset is a
## history step. Both are commands on the active layer of the primary easel, so a
## chord, the door and a scenario's `simulation` step run the same code.
##
## [method play_frame] steps the layer on its own, each frame running the steps
## its speed owes, counted in steps rather than clock time. A stroke pressed on
## the layer pauses it before the first dab, so no step lands between what the
## stroke read and what it wrote, and painting while paused is the seed from then
## on. `SaSadLayerEntry` keeps the record in the layer's `.sad` entry, and
## [method reopen] puts it back whether or not the rule is registered. A run
## exports as numbered frames, [SaSimulation.Frames], never a video.
class_name SaSimulation
extends RefCounted

## The two commands, by id, under `layer_` so the Shortcuts page lists them
## in its Layer section.
const STEP_COMMAND := &"layer_simulation_step"
const RESET_COMMAND := &"layer_simulation_reset"

## The speed a record starts at, and the range the panel offers, in steps a
## second. Ten shows a rule's motion step by step, and sixty is a step a frame
## at 60 Hz, past which the steps of a frame are no longer seen one by one.
const DEFAULT_SPEED := 10.0
const SLOWEST := 1.0
const FASTEST := 60.0


## What a rule steps when its state is not the paint: a field of its own, which
## the layer's schema carries beside `albedo` for as long as the record is on
## it, and the two kernels that join the field to the paint. Written by its
## constructor alone.
##
## The kernels lie in one `.gmacs` that declares three images by name, `paint`,
## `field` and `tint`. The seed kernel reads the paint as last painted at
## `paint` and writes the field's first state at `field`, and the colour kernel
## reads `field` and writes the layer's `albedo` at `paint`, which is the
## layer's resolve hook. Both read at `tint` the painted colour, one texel of
## straight colour, the mean of the seed weighted by its cover, so a pattern
## that spreads into chunks nobody painted shows in the colour the painter
## chose. A kernel that declares `vec2 chunk` and `int step` reads where the
## chunk starts in the layer's texels and nought, so it can import `simulation`.
class State:
    extends RefCounted

    ## The field the step reads and writes in place of `albedo`.
    var field: SaFieldSpec = null
    ## `<owner>/<name>` of the `.gmacs` that holds the two kernels.
    var shader: String = ""
    var seed_kernel: String = ""
    var colour_kernel: String = ""

    func _init(state_field: SaFieldSpec, shader_key: String, seed_name: String, colour_name: String) -> void:
        field = state_field
        shader = shader_key
        seed_kernel = seed_name
        colour_kernel = colour_name

    ## Why a rule cannot keep this state, or empty when it can: the field has
    ## to be one of its own, at a depth a kernel can store, and both kernels
    ## named.
    func refusal() -> String:
        if field == null or field.id.is_empty() or field.is_derived() or field.lazy:
            return "a field of its own needs an id and has to be stepped rather than worked out"
        if field.id in [SaFieldSpec.ALBEDO, SaFieldSpec.MASK, SaFieldSpec.HEIGHT]:
            return "the field '%s' is the layer's already" % field.id
        if not GlobalShaderCompiler.STORAGE_FORMAT_NAMES.has(field.format):
            return "the field '%s' is at a depth no kernel stores" % field.id
        if shader.is_empty() or seed_kernel.is_empty() or colour_kernel.is_empty():
            return "a field of its own needs a shader with a seed kernel and a colour kernel"
        return ""


## One rule as a module registered it. Written by its constructor alone.
class Rule:
    extends RefCounted

    var key: StringName = &""
    var label: String = ""
    ## `<owner>/<name>` of the `.gmacs` that holds the kernel.
    var shader: String = ""
    var kernel: String = ""
    ## How many texels a cell reads from itself in one step, the halo the step
    ## gathers.
    var reach: int = 1
    var defaults: Dictionary[String, Variant] = {}
    ## The id of the module that registered the rule, which a record on a
    ## layer keeps and a file stores, so a document opened where the module
    ## is missing can say which one it needs.
    var module: StringName = &""
    ## The field the rule steps in place of the paint, or null for a rule that
    ## steps the paint itself.
    var state: State = null

    func _init(
        rule_key: StringName,
        rule_label: String,
        shader_key: String,
        kernel_name: String,
        rule_reach: int,
        rule_defaults: Dictionary[String, Variant] = {},
        rule_module: StringName = &"",
        rule_state: State = null
    ) -> void:
        key = rule_key
        label = rule_label
        shader = shader_key
        kernel = kernel_name
        reach = maxi(rule_reach, 0)
        defaults = rule_defaults.duplicate(true)
        module = rule_module
        state = rule_state


## The eleventh registry: the simulation rules modules offer, by key.
class Rules:
    extends RefCounted

    ## Registration and removal.
    signal changed

    var _rules: Dictionary[StringName, Rule] = {}
    var _owners: Dictionary[StringName, StringName] = {}

    ## Registers *added* for *module_id*. Refused for no rule, one with no key,
    ## shader or kernel, or a key already registered.
    func register(added: Rule, module_id: StringName = &"") -> bool:
        if added == null or added.key == &"" or added.shader.is_empty() or added.kernel.is_empty():
            push_error("SaSimulation.Rules: a rule needs a key, a shader and a kernel.")
            return false
        var unkept := added.state.refusal() if added.state != null else ""
        if not unkept.is_empty():
            push_error("SaSimulation.Rules: '%s' is refused, %s." % [added.key, unkept])
            return false
        if _rules.has(added.key):
            push_error("SaSimulation.Rules: '%s' is registered already, by '%s'." % [added.key, _owners[added.key]])
            return false
        _rules[added.key] = added
        _owners[added.key] = module_id
        changed.emit()
        return true

    ## Removes every rule *module_id* registered.
    func unregister_module(module_id: StringName) -> void:
        var gone := _owners.keys().filter(func(rule_key: StringName) -> bool: return _owners[rule_key] == module_id)
        for rule_key: StringName in gone:
            _rules.erase(rule_key)
            _owners.erase(rule_key)
        if not gone.is_empty():
            changed.emit()

    ## The rule called *rule_key*, or null.
    func find(rule_key: StringName) -> Rule:
        return _rules.get(rule_key, null)

    ## Every key, in the order the rules were registered.
    func keys() -> Array[StringName]:
        var out: Array[StringName] = []
        out.assign(_rules.keys())
        return out


## A run exported as numbered frames, File > Export Frames..., one image per
## step and never a video.
##
## The run steps one layer's simulation over the whole canvas, since a frame is
## the whole picture and not what the window shows, for the [member steps] the
## painter set, and after every [member every] steps hands the path of the next
## picture to the writer it was built with, [member count] pictures in all. A
## count of steps that [member every] does not divide ends at the last step a
## picture was written of. The writer is the caller's, a
## `(path: String) -> Error` that writes the document's picture in a format the
## export dialog offers, so the format and its options are the dialog's and the
## run never names one.
##
## **A few steps a frame, as play runs them.** [method advance] is called once a
## frame of the app and takes at most [constant STEPS_PER_FRAME] steps and
## writes at most one picture, so the window keeps drawing and a progress line
## can say where the run stands.
##
## **The layer stands at the last step written.** The run never steps past its
## last picture, and [method cancel] lets the steps of the picture under way
## finish and write it before the run ends, so a cancelled run leaves the layer
## at a step its folder holds too. A run whose layer was stepped, painted or
## had its rule taken off by anything else while it ran stops there and says so
## in [member problem], since its count would no longer name the pictures.
class Frames:
    extends RefCounted

    ## The most steps one frame of the app takes, as play's speed caps it.
    const STEPS_PER_FRAME := 8
    ## The fewest digits a step number is padded to, so a short run and a long
    ## one from the same seed sort alike.
    const DIGITS := 4

    ## How many steps the painter asked the run for.
    var steps: int = 1
    ## How many steps go between two pictures, never more than [member steps].
    var every: int = 1
    ## How many pictures the run writes, the steps over [member every].
    var count: int = 1
    ## The step count the run started from, which no picture shows.
    var first_step: int = 0
    ## The step count the layer stands at now.
    var at_step: int = 0
    ## Every picture written, in order.
    var written: PackedStringArray = PackedStringArray()
    ## Whether the painter asked the run to stop. Written by [method cancel].
    var cancelled: bool = false
    ## Whether the run has ended, written out, cancelled or stopped.
    var finished: bool = false
    ## Why the run stopped short, empty while it runs and once it wrote all.
    var problem: String = ""
    ## The path the pictures are named from, which [method listed] takes.
    var named_from: String = ""

    var _document: SaDocument = null
    var _layer: SaLayer = null
    var _record: SaSimulationRecord = null
    var _rules: Rules = null
    var _writer: Callable = Callable()
    ## The path every picture's name is made from, with no extension.
    var _stem: String = ""
    var _extension: String = ""
    var _digits: int = DIGITS
    ## Steps taken since the last picture.
    var _taken: int = 0

    ## *step_count* steps of *layer*, a picture every *step_every* of them, each
    ## named from *path* and written by *writer*. *path*'s extension is the
    ## file's. The record stops playing, because the run is what steps it now.
    func _init(
        document: SaDocument, layer: SaLayer, rules: Rules, path: String, step_count: int, step_every: int, writer: Callable
    ) -> void:
        _document = document
        _layer = layer
        _rules = rules
        _writer = writer
        steps = maxi(step_count, 1)
        every = clampi(step_every, 1, steps)
        count = floori(float(steps) / float(every))
        named_from = path
        _extension = path.get_extension()
        _stem = path.get_basename() if not _extension.is_empty() else path
        _record = SaSimulation.record_of(layer)
        if _record == null or document == null:
            _stop(["This layer has no simulation to export."])
            return
        _record.pause()
        first_step = _record.steps
        at_step = first_step
        _digits = maxi(DIGITS, str(first_step + count * every).length())

    ## The path of the picture of step *step*, its number padded so the files
    ## sort in the order they were written.
    func name_for(step: int) -> String:
        var number := str(step).pad_zeros(_digits)
        return "%s_%s.%s" % [_stem, number, _extension] if not _extension.is_empty() else "%s_%s" % [_stem, number]

    ## One frame of the app's share of the run: steps up to the next picture, at
    ## most [constant STEPS_PER_FRAME] of them, and that picture once they are
    ## taken. True while there is more to do.
    func advance() -> bool:
        if finished:
            return false
        if not is_instance_valid(_document) or not is_instance_valid(_layer):
            _stop(["The document was closed, so the run stopped."])
            return false
        if SaSimulation.record_of(_layer) != _record:
            _stop(["The simulation was taken off the layer, so the run stopped."])
            return false
        if _record.steps != at_step:
            _stop(["The layer moved to step %d while the run held it at %d, so the run stopped.", _record.steps, at_step])
            return false
        _record.pause()
        for _i in STEPS_PER_FRAME:
            if not SaSimulation.step(_document, _layer, _rules):
                _stop(["The step was refused, so the run stopped at step %d.", at_step])
                return false
            at_step = _record.steps
            _taken += 1
            if _taken == every:
                _taken = 0
                return _write()
        return true

    ## Stops the run once the picture under way is written, at once when no
    ## step of it is taken yet.
    func cancel() -> void:
        cancelled = true
        if _taken == 0:
            finished = true

    ## Whether the run ended with every picture it was asked for written.
    func wrote_all() -> bool:
        return finished and problem.is_empty() and written.size() >= count

    ## Where the run stands, in the words its progress line shows: the step and
    ## the pictures while it runs, why it stopped short, or what it wrote.
    func said() -> String:
        if not problem.is_empty():
            return problem
        var done := written.size()
        if not finished:
            var running := TranslationServer.translate_plural(
                "Step %d, %d of %d picture written.", "Step %d, %d of %d pictures written.", count
            )
            return running % [at_step, done, count]
        if done == 0:
            return TranslationServer.translate("Cancelled before the first picture.")
        var last := written[done - 1].get_file()
        if done < count:
            return (
                TranslationServer.translate_plural(
                    "Stopped at step %d, %d of %d picture written, the last %s.",
                    "Stopped at step %d, %d of %d pictures written, the last %s.",
                    count
                )
                % [at_step, done, count, last]
            )
        var wrote := TranslationServer.translate_plural("%d picture written, %s to %s.", "%d pictures written, %s to %s.", done)
        return wrote % [done, written[0].get_file(), last]

    ## What the run wrote, for a state dump: each picture read back from the
    ## disk with [method read_back], its file and size, and the files
    ## [method listed] finds beside them in the order their names sort.
    func describe() -> Dictionary:
        var pictures := read_back(written)
        var read: Array[Dictionary] = []
        for index in written.size():
            var picture: Image = pictures[index]
            var size: Array = [picture.get_width(), picture.get_height()] if picture != null else []
            read.append({"file": written[index].get_file(), "size": size})
        var files: Array[String] = []
        for path: String in listed(named_from):
            files.append(path.get_file())
        return {"written": read, "listed": files}

    func _write() -> bool:
        var path := name_for(at_step)
        var error: Error = _writer.call(path)
        if error != OK:
            _stop(["Step %d could not be written to %s: %s.", at_step, path, error_string(error)])
            return false
        written.append(path)
        finished = cancelled or written.size() >= count
        return not finished

    ## Ends the run with a refusal. *why* is the English sentence and then the
    ## values its placeholders take, so the sentence is translated before they
    ## go in.
    func _stop(why: Array) -> void:
        finished = true
        problem = TranslationServer.translate(str(why[0])) % why.slice(1)
        SaProblems.refuse("Simulation", TranslationServer.translate(str(why[0])) % why.slice(1))

    ## The pictures of a run written from *path*, the files beside it named
    ## `<name>_<digits>.<extension>`, in the order their names sort, which is
    ## the order of their steps.
    static func listed(path: String) -> PackedStringArray:
        var folder := path.get_base_dir()
        var stem := path.get_file().get_basename()
        var extension := path.get_extension()
        var named := RegEx.create_from_string("^%s_[0-9]+\\.%s$" % [_escaped(stem), _escaped(extension)])
        var found: Array[String] = []
        for file: String in DirAccess.get_files_at(folder):
            if named.search(file) != null:
                found.append(folder.path_join(file))
        found.sort()
        return PackedStringArray(found)

    ## Each of *paths* read back from the disk, null where it cannot be read.
    static func read_back(paths: PackedStringArray) -> Array[Image]:
        var out: Array[Image] = []
        for path: String in paths:
            out.append(Image.load_from_file(path) if FileAccess.file_exists(path) else null)
        return out

    static func _escaped(text: String) -> String:
        var out := ""
        for character: String in text:
            out += "\\" + character if "\\^$.|?*+()[]{}".contains(character) else character
        return out


## Why *layer* takes no simulation, or empty when it takes one: a layer that
## stores paint, whose colour is painted rather than worked out from fields a
## rule does not step. A colour worked out from the field of the record on the
## layer is the record's, which a rule put on in its place takes off first.
static func refusal(layer: SaLayer) -> String:
    if layer == null:
        return TranslationServer.translate("There is no layer to run a simulation on.")
    if not _stores_paint(layer):
        return TranslationServer.translate("A simulation runs on a paint layer, and %s stores no paint.") % layer.name
    var albedo := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    var held := record_of(layer)
    if albedo == null or (albedo.is_derived() and (held == null or not held.colours(layer))):
        return (
            TranslationServer.translate("%s gets its colour from its own simulation data, so this rule cannot change it.")
            % layer.name
        )
    return ""


## Puts *found* on *layer* with *values* over its defaults, in place of any rule
## there, and answers the record, or null when the layer refuses, which is
## reported. The seed is the layer as it stands.
static func put_on(layer: SaLayer, found: Rule, values: Dictionary = {}) -> SaSimulationRecord:
    var refused := refusal(layer)
    if refused.is_empty() and found == null:
        refused = TranslationServer.translate("There is no such simulation rule.")
    if not refused.is_empty():
        SaProblems.refuse("Simulation", TranslationServer.translate("No simulation went on. %s") % refused)
        return null
    take_off(layer)
    var record := SaSimulationRecord.new(layer, found.key, SaTyped.strings(values), found.module, {}, [], found.state)
    layer.simulation = record
    return record


## Puts back on *layer* the record a file kept: the rule called *rule_key* of
## the module *module_id*, its *values*, the seed *kept*, grid position to a
## copy of the `albedo` as last painted, and the grid positions the last ring
## left *ringed*. The layer's chunks are the state at the step the file counts,
## which the caller sets with the speed and the domain. The rule need not be
## registered: a document opened without its module keeps the record as data
## and writes it back unchanged. Null for a layer that takes no simulation.
##
## A layer whose colour a rule's field of its own worked out is opened as
## paint, the colour last resolved, with the field beside it as a field of no
## colour, which a brush does not paint and the reader fills from the file. The
## rule takes the field up again on its first step, which the file does not
## name and the reader is handed no registry to find.
static func reopen(
    layer: SaLayer,
    rule_key: StringName,
    module_id: StringName,
    values: Dictionary,
    kept: Dictionary[Vector2i, SaTexture],
    ringed: Array[Vector2i]
) -> SaSimulationRecord:
    if rule_key == &"" or layer == null or not _stores_paint(layer):
        return null
    _paint_again(layer)
    if not refusal(layer).is_empty():
        return null
    take_off(layer)
    var record := SaSimulationRecord.new(layer, rule_key, SaTyped.strings(values), module_id, kept, ringed)
    layer.simulation = record
    return record


## What *layer*'s simulation needs and does not have, the module of a rule
## *rules* does not hold, as the panel says it, or empty when the rule is
## registered or the layer has no record. The layer shows its paint as the
## file left it, and a step is refused until the module is loaded.
static func missing(layer: SaLayer, rules: Rules) -> String:
    var record := record_of(layer)
    if record == null or (rules != null and rules.find(record.rule) != null):
        return ""
    if record.module == &"":
        return TranslationServer.translate("The rule %s is not registered here, so the layer only shows its paint.") % record.rule
    return (
        TranslationServer.translate("The rule %s needs the module %s, which is not loaded, so the layer only shows its paint.")
        % [record.rule, record.module]
    )


## Takes the record off *layer*, and the seed and the second copy with it, and
## a field of its own, which leaves the colour last resolved as the paint.
static func take_off(layer: SaLayer) -> void:
    var record := record_of(layer)
    if record == null:
        return
    record.release(layer)
    layer.simulation = null


## Whether *layer* is of the kind that stores paint, whatever its colour is
## worked out from.
static func _stores_paint(layer: SaLayer) -> bool:
    return not (layer.is_group or layer.is_generated() or layer.is_adjustment() or layer.is_effect() or layer.is_scene())


## *layer*'s `albedo` declared painted again, the same depth and colour space,
## when a file left it worked out from other fields, which stay as they are.
static func _paint_again(layer: SaLayer) -> void:
    var albedo := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    if albedo == null or not albedo.is_derived():
        return
    var painted := SaFieldSpec.create(SaFieldSpec.ALBEDO, albedo.format, albedo.is_color)
    var schema: Array[SaFieldSpec] = []
    for kept in layer.schema:
        if kept != null:
            schema.append(painted if kept == albedo else kept)
    layer.schema = schema


## The record on *layer*, or null.
static func record_of(layer: SaLayer) -> SaSimulationRecord:
    if layer == null:
        return null
    return layer.simulation as SaSimulationRecord


## The layer of *document* a run of frames steps: the active layer when it
## carries a simulation, else the topmost layer that does, groups searched
## through, or null when none does, which is when File > Export Frames... is
## not offered.
static func simulated_layer(document: SaDocument) -> SaLayer:
    if document == null:
        return null
    if record_of(document.active_layer) != null:
        return document.active_layer
    return _topmost_simulated(document)


static func _topmost_simulated(parent: Node) -> SaLayer:
    for index in range(parent.get_child_count() - 1, -1, -1):
        var layer := parent.get_child(index) as SaLayer
        if layer == null:
            continue
        if record_of(layer) != null:
            return layer
        var inside := _topmost_simulated(layer)
        if inside != null:
            return inside
    return null


## One step of *layer*'s rule, found in *rules*, over its chunks *window*
## reaches, in document pixels, the whole canvas when it has no area. True when
## the step was taken. Refused, and reported, for a layer with no record or a
## rule nobody registers now.
static func step(document: SaDocument, layer: SaLayer, rules: Rules, window: Rect2 = Rect2()) -> bool:
    var record := record_of(layer)
    if document == null or record == null:
        SaProblems.refuse("Simulation", TranslationServer.translate("This layer has no simulation to step."))
        return false
    var found: Rule = rules.find(record.rule) if rules != null else null
    if found == null or GlobalShaderCompiler.get_kernel_index(found.shader, found.kernel) < 0:
        SaProblems.refuse(
            "Simulation",
            TranslationServer.translate("The rule %s is not registered now, so the layer did not step.") % record.rule
        )
        return false
    if GlobalShaderCompiler.get_rd() == null:
        return false
    if not window.has_area():
        window = Rect2(Vector2.ZERO, Vector2(document.canvas_size))
    _shown(document, layer, record.step(layer, found, window, document.selection.everything(), document.canvas_size))
    return true


## *layer* back at its seed, and its count at nought. True when the layer has a
## record, reported when it has none.
static func reset(document: SaDocument, layer: SaLayer) -> bool:
    var record := record_of(layer)
    if document == null or record == null:
        SaProblems.refuse("Simulation", TranslationServer.translate("This layer has no simulation to reset."))
        return false
    _shown(document, layer, record.reset(layer))
    return true


## Starts *layer*'s record playing. False for a layer with no record.
static func play(layer: SaLayer) -> bool:
    var record := record_of(layer)
    if record == null:
        return false
    record.play()
    return true


## Pauses *layer*'s record, if it has one.
static func pause(layer: SaLayer) -> void:
    var record := record_of(layer)
    if record != null:
        record.pause()


## One frame of play: the steps *delta* seconds owe *layer*'s record at its
## speed, each taken as [method step] takes one, over *window*. Answers how
## many were taken, none while paused. A step refused pauses the record, so a
## rule taken away is said once and not once a frame.
static func play_frame(document: SaDocument, layer: SaLayer, rules: Rules, window: Rect2, delta: float) -> int:
    var record := record_of(layer)
    if record == null:
        return 0
    var due := record.steps_due(delta)
    for taken in due:
        if not step(document, layer, rules, window):
            record.pause()
            return taken
    return due


## Keeps *layer*'s simulation growing inside the rectangle the selection of
## *document* lies in, kept to the canvas, which the panel's Selection button
## sets. True when it did, refused, and reported, for a layer with no record
## or a document with nothing selected.
static func grow_inside_selection(document: SaDocument, layer: SaLayer) -> bool:
    var record := record_of(layer)
    if document == null or record == null:
        SaProblems.refuse("Simulation", TranslationServer.translate("This layer has no simulation to keep inside a rectangle."))
        return false
    var box := selected_box(document)
    if not box.has_area():
        SaProblems.refuse(
            "Simulation",
            TranslationServer.translate("Select the rectangle the simulation may grow inside, then click Selection.")
        )
        return false
    record.domain = box
    return true


## Lets *layer*'s simulation grow over the whole canvas again, which the panel's
## Canvas button sets.
static func grow_inside_canvas(layer: SaLayer) -> void:
    var record := record_of(layer)
    if record != null:
        record.domain = Rect2i()


## The rectangle everything selected in *document* lies in, kept to the canvas,
## and no area when nothing is.
static func selected_box(document: SaDocument) -> Rect2i:
    if document == null or not document.selection.active:
        return Rect2i()
    return document.selection.bounds.intersection(Rect2i(Vector2i.ZERO, document.canvas_size))


## *layer*'s record for the state dump: its rule, the count, whether it plays
## and at what speed, and the domain as `[x, y, w, h]`, null for the canvas,
## empty for a layer with none.
static func describe(layer: SaLayer) -> Dictionary:
    var record := record_of(layer)
    if record == null:
        return {}
    var domain: Variant = null
    if record.domain.has_area():
        domain = [record.domain.position.x, record.domain.position.y, record.domain.size.x, record.domain.size.y]
    return {
        "layer": layer.name,
        "rule": String(record.rule),
        "module": String(record.module),
        "steps": record.steps,
        "playing": record.playing,
        "speed": record.speed,
        "domain": domain,
    }


## What the view of *easel* shows grown by a chunk, the window the easel
## composites, or no area when nothing shows it, which a step reads as the
## whole canvas.
static func window_of(easel: SaEasel) -> Rect2:
    if easel == null or not easel.shown_rect.is_valid():
        return Rect2()
    var shown: Rect2 = easel.shown_rect.call()
    return shown.grow(SaChunk.SIZE) if shown.has_area() else Rect2()


## Step and Reset, on the active layer of the primary easel. The context is
## bound weakly, since a strong one would close a cycle through the registry.
static func register_commands(ctx: SaContext) -> void:
    var step_command := SaCommandDescriptor.create(STEP_COMMAND, "Step the simulation", _step_active.bind(weakref(ctx)))
    step_command.label = "Step Simulation"
    step_command.default_events = [_chord(KEY_PERIOD)]
    step_command.category = &"layer"
    step_command.sentence = "Run one step of the simulation on the visible part of the layer."
    ctx.register_command(step_command)
    var reset_command := SaCommandDescriptor.create(RESET_COMMAND, "Reset the simulation", _reset_active.bind(weakref(ctx)))
    reset_command.label = "Reset Simulation"
    reset_command.default_events = [_chord(KEY_COMMA)]
    reset_command.category = &"layer"
    reset_command.sentence = "Put the layer back as it was last painted, at step 0."
    ctx.register_command(reset_command)


## Ctrl+Alt with *key*. Neither Krita nor Photoshop ships a simulation, so
## there is no chord to follow: the full stop steps forwards and the comma
## beside it goes back to the seed, under Ctrl+Alt, which no other command
## holds on either key.
static func _chord(key: Key) -> InputEventKey:
    var chord := InputEventKey.new()
    chord.keycode = key
    chord.ctrl_pressed = true
    chord.alt_pressed = true
    return chord


static func _step_active(ctx_ref: WeakRef) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel: SaEasel = ctx.get_easel() if ctx != null else null
    if easel == null or easel.document == null:
        return false
    return step(easel.document, easel.document.active_layer, ctx.simulation_rules, window_of(easel))


static func _reset_active(ctx_ref: WeakRef) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel: SaEasel = ctx.get_easel() if ctx != null else null
    if easel == null or easel.document == null:
        return false
    return reset(easel.document, easel.document.active_layer)


## Composites *written* of *layer* again. A layer other than the active one is
## in the caches either side of it, so those are rebuilt too.
static func _shown(document: SaDocument, layer: SaLayer, written: Array[Vector2i]) -> void:
    if written.is_empty():
        return
    document.invalidate_chunks(written)
    if layer != document.active_layer:
        document.request_cache_update()
    document.modified = true
    document.document_changed.emit()
