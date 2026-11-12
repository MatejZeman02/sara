## What a surface's option controls follow: the tool machine and its registry,
## the blend registry, and the document whose colour space names the blend
## row's plain Normal.
##
## Written once here rather than in each surface, so a surface hands its
## controls' binding the machine and the blend registry and listens to
## `tools_changed`, and none follows the machine's registry, the blend registry
## and the document's colour space for itself.
##
## Its own class because none of it builds a control. `ToolOptionControls`
## builds a control from a spec and reads and writes the value behind it, and
## this decides when a tool's controls are built or dropped and when the blend
## row is filled again. The controls own one binding each, and hand it the four
## things it drives as callables rather than themselves: a binding holding its
## controls would be a cut reaching back, and two `RefCounted` holding each
## other are never freed, where a callable on a method holds no reference.
extends RefCounted

class_name ToolOptionBinding

## What the controls offer moved under the surface: a tool was registered or
## dropped, or the blend modes were rebuilt for a new registry or colour space.
## *rebuilt* is true when a control was added or dropped, which is when a
## surface has rows to lay out again. Either way the tool's values are read
## again.
signal tools_changed(rebuilt: bool)

## `func(descriptor: SaToolDescriptor) -> bool`, which builds a tool's
## controls and says whether one was added.
var _build: Callable
## `func(registry: SaToolRegistry) -> bool`, which drops the controls of the
## tools *registry* no longer holds and says whether one went.
var _drop: Callable
## `func(tool_id: StringName) -> bool`, whether a tool's controls are built.
var _built: Callable
## `func() -> Control`, the blend dropdown when a tool declared one.
var _blend_button: Callable

## The machine whose registry the controls are built from, handed over by
## `follow`, and the registry that was last connected, so a machine that swaps
## its registry is followed onto the new one.
var _machine: ToolMachine = null
var _bound_registry: SaToolRegistry = null
var blend_registry: SaBlendModeRegistry = null

## The document the rows are about, handed over with the blend registry by a
## surface that has no machine to read one from.
##
## The brush editor is the first: it is handed the tool and not the easel, so
## its blend row's plain Normal showed no bracket while the bar's showed
## `Normal (Oklab)`, and both rows are the one mode.
var _document: SaDocument = null


func _init(build: Callable, drop: Callable, built: Callable, blend_button: Callable) -> void:
    _build = build
    _drop = drop
    _built = built
    _blend_button = blend_button


## Builds the controls of every tool *machine*'s registry holds, once each, and
## follows the registry so a module loaded later still gets its row.
##
## Called again on every tool change, because a surface is handed the machine
## before the modules have loaded and the machine has a registry, so the first
## call gives up early. Announces `tools_changed` only when a control came or
## went, since the caller reads the tool again anyway.
func follow(machine: ToolMachine) -> void:
    _machine = machine
    if _bind_tools():
        tools_changed.emit(true)


## `follow` a slice at a time, for the boot: builds the controls of the tools
## *machine* holds that have none yet until *slice_usec* has run, at least one
## tool a call, and says whether every tool has them. No slice builds them all.
## A `follow` after the last slice builds nothing.
##
## The docker's controls for every tool built at once hold a frame far past its
## budget, the brush's ninety-six options alone half of it, so the brush is a
## frame and the other tools one more.
func build_a_slice(machine: ToolMachine, slice_usec: int) -> bool:
    _machine = machine
    if machine == null or machine.registry == null:
        return true
    var began := Time.get_ticks_usec()
    var tools := 0
    var added := false
    var every_tool := true
    for descriptor: SaToolDescriptor in machine.registry.list_descriptors():
        if _built.call(descriptor.id):
            continue
        if slice_usec > 0 and tools > 0 and Time.get_ticks_usec() - began >= slice_usec:
            every_tool = false
            break
        if _build.call(descriptor):
            added = true
        tools += 1
    if added:
        _refresh_blend_modes()
        tools_changed.emit(true)
    return every_tool


## Points the blend dropdown at *blend_registry* and at the *document* its
## plain Normal's bracket names, and keeps both in step with a module that
## registers a mode later and with a document that changes colour space.
##
## The document is the second half of the one binding rather than a seam of its
## own, because the row it serves is the row the registry fills, and a surface
## with no machine has no other way to name the space. Called again on
## every tool change by the bar, whose machine answers [method document] with
## the document it is painting.
func follow_blend_modes(registry: SaBlendModeRegistry, doc: SaDocument = null) -> void:
    blend_registry = registry
    _document = doc
    if blend_registry != null and not blend_registry.changed.is_connected(_on_blend_modes_changed):
        blend_registry.changed.connect(_on_blend_modes_changed)
    if not EventBus.document_color_space_changed.is_connected(_on_document_space_changed):
        EventBus.document_color_space_changed.connect(_on_document_space_changed)
    _on_blend_modes_changed()


## The document the rows are about: the one handed over with the blend
## registry, or the machine's own, through its surface rather than a view.
func document() -> SaDocument:
    if _document != null:
        return _document
    if _machine == null or _machine.surface == null:
        return null
    return _machine.surface.get_document()


## The side a spec flagged `scale_by_canvas` turns its fraction into pixels
## with, `SaDocument.brush_side`, which a crop keeps. 1000 with no document
## behind the machine, so both surfaces show the same numbers there.
func canvas_min_dimension() -> float:
    var doc := document()
    if doc == null:
        return 1000.0
    return doc.brush_side


## True when a control was added or dropped.
func _bind_tools() -> bool:
    if _machine == null or _machine.registry == null:
        return false
    var registry := _machine.registry
    if registry != _bound_registry:
        if _bound_registry != null and _bound_registry.changed.is_connected(_on_registry_changed):
            _bound_registry.changed.disconnect(_on_registry_changed)
        _bound_registry = registry
        if not registry.changed.is_connected(_on_registry_changed):
            registry.changed.connect(_on_registry_changed)
    var changed: bool = _drop.call(registry)
    for descriptor: SaToolDescriptor in registry.list_descriptors():
        if _build.call(descriptor):
            changed = true
    if changed:
        _refresh_blend_modes()
    return changed


func _on_registry_changed() -> void:
    tools_changed.emit(_bind_tools())


## Only the document the machine is painting rebuilds the rows, so a document
## behind another tab, or the scratchpad, leaves them alone.
func _on_document_space_changed(changed: SaDocument) -> void:
    var own := document()
    if own != null and changed != own:
        return
    _on_blend_modes_changed()


func _on_blend_modes_changed() -> void:
    _refresh_blend_modes()
    tools_changed.emit(false)


func _refresh_blend_modes() -> void:
    var blend_btn := _blend_button.call() as BlendModeButton
    if blend_btn == null:
        return
    var doc := document()
    # The button keeps its own choice across a rebuild, so nothing here has to
    # remember it the way the OptionButton's index once did.
    blend_btn.registry = blend_registry
    blend_btn.include_hidden_in_layers = true
    blend_btn.space = doc.color_space if doc != null else null
    blend_btn.refresh()
