## Blend modes, keyed by kernel *name* rather than by ordinal.
##
## An integer kernel would have to match the position of the #kernel directive
## in composite.gmacs, and inserting a kernel would remap every mode after it in
## silence. Names are resolved through the compiler at registration, and a mode
## whose kernel does not exist is refused loudly instead of quietly compositing
## as something else.
##
## `register` asks the compiler itself rather than leaving it to `validate()`,
## which reports rather than refuses, so a typo in a module's kernel name is no
## layer compositing as Normal with a line in a terminal, and the line goes to
## `SaProblems` where the painter's problems window picks it up.
class_name SaBlendModeRegistry
extends RefCounted

signal changed

var _modes: Dictionary[StringName, SaBlendModeDescriptor] = {}
var _order: Array[StringName] = []

## Former id -> the id that mode is registered under now, filled from each
## descriptor's `former_ids` at registration. What `canonical` reads.
var _former: Dictionary[StringName, StringName] = {}


func register(descriptor: SaBlendModeDescriptor, module_id: StringName = &"") -> bool:
    if descriptor == null or String(descriptor.id).is_empty():
        push_error("SaBlendModeRegistry: refusing a blend mode with no id.")
        return false
    if descriptor.kernel_name.is_empty():
        push_error("SaBlendModeRegistry: blend mode '%s' names no kernel." % descriptor.id)
        return false
    if _modes.has(descriptor.id):
        push_error("SaBlendModeRegistry: blend mode '%s' is already registered." % descriptor.id)
        return false
    if not _kernel_is_there(descriptor, module_id):
        return false

    descriptor.owner_module = module_id
    _modes[descriptor.id] = descriptor
    _order.append(descriptor.id)
    _file_former_ids(descriptor)
    changed.emit()
    return true


## Files each of *descriptor*'s former ids as an alias for its current one.
##
## A clash refuses the alias and never the mode, because the mode is what a
## painter picks and an alias only answers for documents already on disk:
## dropping the mode would take a working blend away to protect a file that may
## not exist. The line names both ends, since a clash is a fault in a module's
## own declaration and its author is the one who can repair it.
##
## Through `SaProblems` rather than `push_error` alone, for the reason the
## kernel refusal above gives and for one more: the fault is a painting that
## opens as Normal, so the person at the keyboard has to see it, and a suite
## that provokes it on purpose can silence the echo where a bare `push_error`
## would turn the whole run red.
func _file_former_ids(descriptor: SaBlendModeDescriptor) -> void:
    for former_id: StringName in descriptor.former_ids:
        if String(former_id).is_empty():
            continue
        var taken_by: StringName = former_id if _modes.has(former_id) else _former.get(former_id, &"")
        if taken_by == descriptor.id or String(taken_by).is_empty():
            _former[former_id] = descriptor.id
            continue
        SaProblems.report(
            "SaBlendModeRegistry",
            (
                TranslationServer.translate(
                    "Blend mode '%s' claims former id '%s', which '%s' answers for. Keeping the mode, dropping the alias."
                )
                % [descriptor.id, former_id, taken_by]
            )
        )


## Whether the compiler holds the kernel this descriptor names, refusing and
## reporting the mode when it does not.
##
## The report goes through `SaProblems` rather than to `push_error` alone,
## because the person at the keyboard is the one who has to see it: a module
## whose kernel name is one letter wrong is a layer that silently paints as
## Normal otherwise, and the module's author is not the one watching the
## screen. A fault rather than a refusal, because nothing the painter did
## caused it and the line is the one a bug report needs.
func _kernel_is_there(descriptor: SaBlendModeDescriptor, module_id: StringName) -> bool:
    if not _compiler_can_answer(descriptor.shader_name):
        return true
    if GlobalShaderCompiler.get_kernel_index(descriptor.shader_name, descriptor.kernel_name) >= 0:
        return true
    var from := "" if module_id.is_empty() else " from module '%s'" % module_id
    SaProblems.report(
        "SaBlendModeRegistry",
        (
            TranslationServer.translate("Refusing blend mode '%s'%s: kernel '%s' is not in shader '%s'.")
            % [descriptor.id, from, descriptor.kernel_name, descriptor.shader_name]
        )
    )
    return false


## Whether the compiler can be asked about *shader_name* at all, which is a
## different question from whether the kernel is in it.
##
## False before anything has been compiled, and that is not a rare corner: a
## machine whose driver refused a RenderingDevice leaves the compiler with no
## device and no scan at all, and so does the
## `--headless --rendering-driver dummy` run the pure-logic suites take. The
## compiler knows no kernel of any shader there, so a refusal would take Sara's
## own seventeen modes away along with the one that is broken. `resolve_kernel`
## asks the same question and answers -1 for the same reason.
##
## Read off the compiled names rather than off the node, because an autoload is
## present in every run of the project and compiling nothing is the condition
## that actually matters.
func _compiler_can_answer(shader_name: String) -> bool:
    if not Engine.has_singleton("GlobalShaderCompiler") and GlobalShaderCompiler == null:
        return false
    return GlobalShaderCompiler.compute_shader_kernel_names.has(GlobalShaderCompiler.resolve_shader_name(shader_name))


## Removes one mode, whoever registered it, so a module can take a built-in
## away. A layer set to the mode composites as Normal, which is the fallback
## `resolve_kernel` has always had for a name it does not know.
func unregister(mode_id: StringName) -> void:
    if not _modes.has(mode_id):
        return
    _drop_former_ids(mode_id)
    _modes.erase(mode_id)
    _order.erase(mode_id)
    changed.emit()


func unregister_module(module_id: StringName) -> void:
    var doomed: Array[StringName] = []
    for mode_id: StringName in _order:
        if _modes[mode_id].owner_module == module_id:
            doomed.append(mode_id)
    for mode_id in doomed:
        _drop_former_ids(mode_id)
        _modes.erase(mode_id)
        _order.erase(mode_id)
    if not doomed.is_empty():
        changed.emit()


## Forgets every alias pointing at *mode_id*, so a mode taken away answers for
## its old documents no more than for its current id.
func _drop_former_ids(mode_id: StringName) -> void:
    var doomed: Array = []
    for former_id: StringName in _former:
        if _former[former_id] == mode_id:
            doomed.append(former_id)
    for former_id: StringName in doomed:
        _former.erase(former_id)


## The id *mode_id* is registered under today: itself for a mode this registry
## holds, the current id for one of its former ids, and the argument unchanged
## for anything else.
##
## A registered mode answers for itself first, so a module that ships a mode
## under an id another mode once used keeps its own, and the alias loses. That
## way round because the live mode is the one a painter can pick right now.
func canonical(mode_id: StringName) -> StringName:
    if _modes.has(mode_id):
        return mode_id
    return _former.get(mode_id, mode_id)


## [method canonical] over a list, in order, with a second copy of an id the
## list already holds dropped.
##
## The duplicate matters because two entries can canonicalize onto one mode: the
## favourites keep both the old id and the new when a painter pinned Hard Mix
## on either side of the rename, and a menu drawing the same row twice is the
## fault this drops.
func canonical_list(ids: Array) -> Array:
    var out: Array = []
    for entry: Variant in ids:
        var current: Variant = entry
        if entry is StringName or entry is String:
            current = canonical(StringName(str(entry)))
        # The favourites are Strings on disk and mode ids are StringNames, so
        # the answer goes back in the shape it arrived in or a comparison in
        # any caller stops matching.
        if entry is String:
            current = str(current)
        if out.has(current):
            continue
        out.append(current)
    return out


## Rewrites every layer whose blend mode is a former id to the id that mode is
## registered under now, the shape `SaLayerTypeRegistry.rebind` has.
##
## A layer whose mode this registry knows nothing about is left exactly as it
## is, for the reason the layer types leave an unknown type alone: the module
## that owns it may be installed next time, and a mode silently turned into
## Normal is a painting the next save destroys.
##
## Kept is not unsaid, though: such a layer draws as Normal, so each mode no
## module registers is named in the problems once, with the layers set to it.
## A public build carries no mixing module, and a document painted
## with its blend opens there as any document from a missing module does. A
## registry holding no mode at all is a run with nothing loaded yet, where
## every layer would be named, so it says nothing.
func rebind(layers: Array) -> void:
    var unplaced: Dictionary[StringName, PackedStringArray] = {}
    for layer: SaLayer in layers:
        if layer == null:
            continue
        var current := canonical(layer.blend_mode)
        if current != layer.blend_mode:
            layer.blend_mode = current
        if not _modes.has(current) and not String(current).is_empty() and not _modes.is_empty():
            if not unplaced.has(current):
                unplaced[current] = PackedStringArray()
            unplaced[current].append(String(layer.name))
    for mode_id: StringName in unplaced:
        SaProblems.report(
            "SaBlendModeRegistry",
            (
                TranslationServer.translate(
                    "The blend mode '%s' of %s is from a module this Sara has not loaded, so it draws as Normal."
                )
                % [mode_id, ", ".join(Array(unplaced[mode_id]).map(func(name: String) -> String: return "'%s'" % name))]
            )
        )


func has(mode_id: StringName) -> bool:
    return _modes.has(mode_id)


func get_descriptor(mode_id: StringName) -> SaBlendModeDescriptor:
    return _modes.get(mode_id, null)


## Kernel index for a mode, resolved by name through the compiler.
## Returns -1 when the mode or its kernel is unknown. Callers fall back to Normal.
func resolve_kernel(mode_id: StringName) -> int:
    var descriptor: SaBlendModeDescriptor = _modes.get(mode_id, null)
    if descriptor == null:
        return -1
    if not _compiler_can_answer(descriptor.shader_name):
        return -1
    return GlobalShaderCompiler.get_kernel_index(descriptor.shader_name, descriptor.kernel_name)


func list_ids() -> Array[StringName]:
    return _order.duplicate()


## Every entry a menu shows, in sort order, flat. `list_sections` groups these,
## and both the layer docker and the tool options bar go through it, so a
## module's mode appears in both without either of them knowing it exists.
func list_ui_entries(include_hidden_in_layers: bool = true) -> Array:
    var entries: Array = []
    for mode_id in _order:
        var descriptor: SaBlendModeDescriptor = _modes[mode_id]
        if descriptor.internal:
            continue
        if not include_hidden_in_layers and descriptor.hidden_in_layer_list:
            continue
        entries.append(descriptor)
    entries.sort_custom(
        func(a: SaBlendModeDescriptor, b: SaBlendModeDescriptor) -> bool:
            return a.sort_order < b.sort_order if a.sort_order != b.sort_order else String(a.id) < String(b.id)
    )
    return entries


## The same entries grouped into the menu's sections, as
## `[{ "id": StringName, "title": String, "modes": Array }]`, in the order
## SaBlendModeDescriptor.SECTIONS gives and with the empty ones dropped.
##
## A mode whose category names no section is in the last one, Other, which is
## where every mode a module registers without a category of its own lands.
func list_sections(include_hidden_in_layers: bool = true) -> Array:
    var by_section: Dictionary[StringName, Array] = {}
    for descriptor: SaBlendModeDescriptor in list_ui_entries(include_hidden_in_layers):
        var section := descriptor.section()
        if not by_section.has(section):
            by_section[section] = []
        by_section[section].append(descriptor)

    var sections: Array = []
    for entry: Array in SaBlendModeDescriptor.SECTIONS:
        if not by_section.has(entry[0]):
            continue
        sections.append({"id": entry[0], "title": entry[1], "modes": by_section[entry[0]]})
    return sections


## Every registered kernel name resolves against its shader. Called by the
## contract test.
func validate() -> Array[String]:
    var problems: Array[String] = []
    for mode_id in _order:
        var descriptor: SaBlendModeDescriptor = _modes[mode_id]
        var index := GlobalShaderCompiler.get_kernel_index(descriptor.shader_name, descriptor.kernel_name)
        if index < 0:
            problems.append(
                (
                    "blend mode '%s' names kernel '%s' in shader '%s', which does not exist"
                    % [descriptor.id, descriptor.kernel_name, descriptor.shader_name]
                )
            )
    return problems
