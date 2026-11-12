## The skeleton's blending mode commands: Krita's Next and Previous Blending
## Mode, and one command for each of Krita's Select ... Blending Mode actions
## whose chord no docker summon already holds, registered through the public
## door (hard rule 6).
##
## **They move the brush's mode and not the layer's**, because Krita's do.
## Krita connects the twenty eight actions to the composite op box of its
## brush tool options (`KisPaintopBox` calls `connectBlendmodeActions` on its
## `KisCompositeOpComboBox`), and its manual says of the chords that they "do
## not change the blending mode of the current layer". The target is the
## `blend_mode` of the brush settings the active tool holds, or the permanent
## tool's when the active one holds none, the resolution the bracket keys use
## for the size. So a press moves exactly the row the Blend Mode control on the
## bar shows.
##
## **A step stops at either end of the list**, as Krita's does:
## `selectNeighbouringBlendMode` moves only while the new index is inside the
## box. The list is the one the bar's menu draws, `SaBlendModeRegistry`'s
## sections in their order with the internal modes left out, so a press walks
## the rows a painter sees and a mode a module adds is walked as well.
##
## Each command takes no chord on Sara's own map. The Krita profile gives them
## Krita's, in `SaShortcutKritaTable`.
extends RefCounted

## The two that step, each with the Krita action it answers and its direction.
const STEPS: Array = [
    [&"blend_mode_next", "Next blending mode", "Next Blending Mode", 1],
    [&"blend_mode_previous", "Previous blending mode", "Previous Blending Mode", -1],
]

## The ones that pick, each the command, its title and the mode it picks.
##
## Krita's fourteen whose letter is free of Sara's docker summons. The other
## twelve, Colour, Colour Burn, Colour Dodge, Difference, Exclusion, Linear
## Burn, Linear Dodge, Pin Light, Saturation, Screen, Soft Light and Vivid
## Light, sit on Alt+Shift and the letter of a docker's summon on Sara's own
## map. The Krita profile leaves those summons unbound, all but the palette's
## on Alt+Shift+W, so the twelve have no command here while it stays open
## whether the Krita profile gives eleven of them Krita's picks.
##
## Krita's Clear lays transparency where the brush passes, which is what Sara's
## Erase does, so its command picks Erase. Krita's Luminosity is the component
## mode that keeps the hue and saturation underneath, Sara's Lightness. Behind,
## Dissolve, Hard Overlay and Linear Light are no mode of Sara's: their
## commands are there, so the Krita chord is held and a module that registers a
## mode under the id makes it work, and until then a press says why it did
## nothing. Hard Mix is the skeleton's own.
const PICKS: Array = [
    [&"blend_mode_behind", "Behind blending mode", &"behind"],
    [&"blend_mode_clear", "Clear blending mode", &"erase"],
    [&"blend_mode_darken", "Darken blending mode", &"darken"],
    [&"blend_mode_dissolve", "Dissolve blending mode", &"dissolve"],
    [&"blend_mode_hard_light", "Hard light blending mode", &"hard_light"],
    [&"blend_mode_hard_mix", "Hard mix blending mode", &"hard_mix"],
    [&"blend_mode_hard_overlay", "Hard overlay blending mode", &"hard_overlay"],
    [&"blend_mode_hue", "Hue blending mode", &"hue"],
    [&"blend_mode_lighten", "Lighten blending mode", &"lighten"],
    [&"blend_mode_linear_light", "Linear light blending mode", &"linear_light"],
    [&"blend_mode_luminosity", "Luminosity blending mode", &"lightness"],
    [&"blend_mode_multiply", "Multiply blending mode", &"multiply"],
    [&"blend_mode_normal", "Normal blending mode", &"normal"],
    [&"blend_mode_overlay", "Overlay blending mode", &"overlay"],
]

## The settings property the brush engines declare their Blend Mode option on.
const PROPERTY := &"blend_mode"


## Registers every row of `STEPS` and `PICKS` on *ctx*. A weak reference in
## each handler, because the context holds the registries that hold the command.
static func register(ctx: SaContext) -> void:
    var ref: WeakRef = weakref(ctx)
    for entry: Array in STEPS:
        var step_id: StringName = entry[0]
        var step_title: String = entry[1]
        var direction: int = entry[3]
        var command := SaCommandDescriptor.create(step_id, step_title, _step.bind(ref, direction))
        command.category = &"brush"
        command.sentence = (
            "Move the brush to the blending mode after the one it has, in the order the Blend Mode menu lists them."
            if direction > 0
            else "Move the brush to the blending mode before the one it has, in the order the Blend Mode menu lists them."
        )
        ctx.register_command(command)
    for entry: Array in PICKS:
        var command_id: StringName = entry[0]
        var title: String = entry[1]
        var mode: StringName = entry[2]
        var command := SaCommandDescriptor.create(command_id, title, _pick.bind(ref, mode))
        command.category = &"brush"
        command.sentence = "Give the brush this blending mode, the way picking it from the Blend Mode menu does."
        command.enabled = _has_mode.bind(ref, mode)
        ctx.register_command(command)


## The brush settings a press moves, or null with no surface or no brush.
##
## The machine is the one of the document in front, the surface whose easel is
## `ctx.get_easel()`, as the E press takes it. Each document holds a machine of
## its own, so the first surface listed would move a brush the painter cannot
## see. The first surface that is not embedded stands in only while no easel is
## in front. The scratchpad is skipped by `is_embedded` either way.
static func target_settings(ctx: SaContext) -> Resource:
    var front := ctx.get_easel()
    var machine: Object = null
    for candidate: SaSurface in ctx.list_surfaces():
        if not candidate.is_embedded and (front == null or candidate.easel == front):
            machine = candidate.tool_machine
            break
    if machine == null:
        return null
    # The machine is the tools package's, which core reads by name only.
    var permanent: Variant = machine.call(&"get_tool", machine.get(&"default_tool_name"))
    for tool: Object in [machine.get(&"active_tool"), permanent]:
        var settings: Variant = tool.get(&"settings") if tool != null else null
        if settings is Resource and PROPERTY in settings:
            return settings
    return null


## The modes a press walks, in the order the bar's menu draws them.
static func walk_order(registry: SaBlendModeRegistry) -> Array[StringName]:
    var out: Array[StringName] = []
    for section: Dictionary in registry.list_sections(true):
        for descriptor: SaBlendModeDescriptor in section["modes"]:
            out.append(descriptor.id)
    return out


static func _has_mode(ref: WeakRef, mode: StringName) -> bool:
    var ctx: SaContext = ref.get_ref()
    return ctx != null and ctx.blend_modes != null and walk_order(ctx.blend_modes).has(mode)


## One step along the list. At either end the mode stays, and the press is
## still taken, so the chord reaches nothing else.
static func _step(ref: WeakRef, direction: int) -> bool:
    var ctx: SaContext = ref.get_ref()
    var settings := target_settings(ctx) if ctx != null else null
    if settings == null or ctx.blend_modes == null:
        return false
    var order := walk_order(ctx.blend_modes)
    if order.is_empty():
        return false
    var current: StringName = settings.get(PROPERTY)
    var at := order.find(ctx.blend_modes.canonical(current))
    var next := at + direction
    if at < 0:
        next = 0 if direction > 0 else order.size() - 1
    if next < 0 or next >= order.size():
        return true
    _write(settings, order[next])
    return true


static func _pick(ref: WeakRef, mode: StringName) -> bool:
    var ctx: SaContext = ref.get_ref()
    var settings := target_settings(ctx) if ctx != null else null
    if settings == null:
        return false
    if not _has_mode(ref, mode):
        EventBus.paint_refused.emit(
            TranslationServer.translate("No blending mode called %s is installed, so the brush keeps its own.") % mode
        )
        return false
    _write(settings, mode)
    return true


## Writes the mode and tells every surface showing the option to read it again,
## the way the bar's own menu and the brackets do.
static func _write(settings: Resource, mode: StringName) -> void:
    settings.set(PROPERTY, mode)
    EventBus.tool_options_moved.emit()
