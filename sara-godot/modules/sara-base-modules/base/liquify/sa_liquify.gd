## Liquify, the feature's one door: the Brush's liquify engine, its rows, its
## settings, its shelf of presets, its session's role and the Liquify command,
## registered through the context the way a third-party module registers an
## engine (hard rule 6).
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A folder of its own beside `base/tools`, which is large enough already.
## Inside it are the tool state, `state_liquify.gd`, its settings,
## `liquify_settings.gd`, its shelf, `liquify_presets.gd`, the ground a
## preset's picture is drawn on, `liquify_picture.gd`, its session engine,
## `sa_liquify_session.gd`, and the three kernels, `liquify.gmacs` for a dab
## into the displacement field, `liquify_draw.gmacs` for the layer drawn
## through it and `liquify_smooth.gmacs` for smooth's reading of where the
## strokes run.
## `base/module.gd` names this file and nothing else of the folder.
##
## **An engine of the Brush**, as the noise brush is: it is in neither the
## toolbox nor the Tools menu, a painter
## reaches it by picking a liquify preset with the Brush in hand, and Save As...
## keeps the four rows as a preset of the engine. A stamp preset picked over an
## open session switches the engine, which commits the session the way leaving
## the tool does.
##
## Six modes: push, twirl, shrink and grow, the smooth that takes back a push
## under the name Reconstruct, and a Smooth beside it that straightens wobbly
## strokes as a stabiliser would.
extends RefCounted

const StateLiquifyScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")
const SaLiquifySessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")
const LiquifySettingsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_settings.gd")
const LiquifyPresetsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_presets.gd")

## The engine's id, which the tool machine keys it by and a scenario's `tool`
## step names.
const TOOL_ID: StringName = &"liquify"
## The role the shelf is registered under, `shipped_presets_` and the engine's
## word, which the presets bar asks for of every engine the Brush paints with.
const PRESETS_ROLE: StringName = &"shipped_presets_liquify"
## The Liquify command, `brush_` so the Keyboard Shortcuts page files it under
## Brush beside the slots.
const COMMAND_ID: StringName = &"brush_liquify"
## The module preference the last liquify preset used is kept under, so the
## command picks it after a restart as well.
const LAST_PRESET_KEY: StringName = &"liquify_last_preset"

## A context carrying the module's id alone, for its preferences, set by the
## last [method register]. Nothing else, so it holds nothing alive.
static var _preferences: SaContext = null


## Registers the engine, its shelf, its session's role and the command on
## *ctx*.
static func register(ctx: SaContext) -> void:
    var liquify := SaToolDescriptor.create(TOOL_ID, StateLiquifyScript)
    liquify.display_name = "Liquify"
    liquify.icon_name = "liquify"
    liquify.category = &"transform"
    liquify.cursor_shape = Control.CURSOR_CROSS
    # The ring every painting tool draws, at the Size row's width, without
    # `is_painting`, which would put the brush group on the bar: liquify moves
    # paint and lays none.
    liquify.wants_brush_cursor = true
    # The Brush's right press, which opens the presets under every engine.
    liquify.opens_presets_on_right_click = true
    # One resource every surface's tool is handed, which a preset loads into
    # and Save As... reads.
    liquify.shared_settings = LiquifySettingsScript.new()
    liquify.preset_engine = LiquifySettingsScript.PRESET_ENGINE
    liquify.options = options()
    ctx.register_brush_engine(liquify)
    ctx.register_role(PRESETS_ROLE, LiquifyPresetsScript)
    # Under a role, so another module's subclass replaces the engine the way
    # the transform's can be.
    ctx.register_role(&"liquify", SaLiquifySessionScript)
    _preferences = SaContext.new(Callable(), Callable(), ctx.module_id)
    _register_command(ctx)


## The Liquify command, which picks the last liquify preset used, with no chord
## of its own: the tool never had one, only its toolbox button and its row in
## the Tools menu, which an engine leaves. A painter binds one on the Keyboard
## Shortcuts page, and a chord in the shipped shortcuts file would be a row in
## a file that is not this module's.
static func _register_command(ctx: SaContext) -> void:
    # Bound to a context carrying the surfaces alone, as the stamp brush binds
    # its eraser toggle, since the module's own holds the registry that holds
    # this handler.
    var surfaces := SaContext.new(Callable(), ctx.surface_provider)
    var pick := SaCommandDescriptor.create(COMMAND_ID, "Liquify", _pick_last.bind(surfaces))
    pick.category = &"brush"
    pick.sentence = "Put liquify in hand with the liquify preset used last, Liquify Push before any was."
    ctx.register_command(pick)
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)
    if not EventBus.preset_store_changed.is_connected(_on_preset_saved):
        EventBus.preset_store_changed.connect(_on_preset_saved)


## The command's handler: puts the liquify engine in the main canvas's hand,
## then loads the liquify preset used last through the bar's presets group, the
## pick path a cell and a slot's chord take. Liquify first, because a tool that
## takes stamp presets alone, the eraser, refuses a liquify one. A preset
## deleted since gives way to the first of the shelf, and with neither the
## engine keeps the settings it holds. It declines the key when no machine took
## liquify, so the chord is not swallowed.
static func _pick_last(surfaces: SaContext) -> bool:
    var machine: Variant = null
    for candidate: SaSurface in surfaces.list_surfaces():
        if not candidate.is_embedded:
            machine = candidate.tool_machine
            break
    if machine != null and machine.registered_tools.has(TOOL_ID):
        machine.set_active_tool(TOOL_ID)
    var last := last_preset()
    if SaPresetsInHand.has_group() and not SaPresetsInHand.load_preset(last) and last != LiquifyPresetsScript.FIRST:
        SaPresetsInHand.load_preset(LiquifyPresetsScript.FIRST)
    return machine != null and machine.active_tool_name == TOOL_ID


## The liquify preset used last, or the shelf's first before any was.
static func last_preset() -> String:
    var kept: Variant = _preferences.preference(LAST_PRESET_KEY, "") if _preferences != null else ""
    var name := String(kept) if kept is String else ""
    return name if not name.is_empty() else LiquifyPresetsScript.FIRST


## A load that left liquify in hand was of a liquify preset, which is then the
## one the command picks. A load of "" is the hand let go of its preset, which
## keeps the last one used.
static func _on_preset_loaded(preset_name: String) -> void:
    if not preset_name.is_empty() and _liquify_in_hand():
        _remember(preset_name)


## Save As... with liquify in hand keeps the current settings as a preset of
## the engine and puts it in the hand, so it is the one used last.
static func _on_preset_saved(preset_name: String, saved: bool) -> void:
    if saved and not preset_name.is_empty() and _liquify_in_hand():
        _remember(preset_name)


static func _remember(preset_name: String) -> void:
    if _preferences != null:
        _preferences.set_preference(LAST_PRESET_KEY, preset_name)


static func _liquify_in_hand() -> bool:
    return SaPresetsInHand.engine() == LiquifySettingsScript.PRESET_ENGINE


## The mode, the twirl's direction, the size and the strength, all off the
## bar, which is measured full at 1920, and all on the engine's settings, so a
## preset carries them. The keys are the ones the scenarios write.
static func options() -> Array[SaOptionSpec]:
    # Reconstruct beside push, the one it takes back, and smooth beside
    # reconstruct, the two that even something out.
    var modes := [
        StateLiquifyScript.PUSH,
        StateLiquifyScript.RECONSTRUCT,
        StateLiquifyScript.SMOOTH,
        StateLiquifyScript.TWIRL,
        StateLiquifyScript.SHRINK,
        StateLiquifyScript.GROW,
    ]
    var mode := SaOptionSpec.make_enum(
        &"liquify_mode",
        "Mode",
        modes,
        ["Push", "Reconstruct", "Smooth", "Twirl", "Shrink", "Grow"],
        {
            "property": ^"mode",
            "bar": false,
            "tooltip":
            (
                "What the brush does while you hold it down. Push drags the paint along, Reconstruct restores it, "
                + "Smooth straightens wobbly lines as a stabiliser would, "
                + "Twirl turns it the way Direction says (the other way with Alt), "
                + "Shrink pulls it towards the centre and Grow pushes it out (Alt swaps the two)."
            )
        }
    )

    # Which way the twirl turns, as a row rather than Alt alone, which only
    # the Mode row's tooltip can say. Dimmed under the other five modes, which
    # turn nothing.
    var direction := SaOptionSpec.make_enum(
        &"liquify_direction",
        "Direction",
        [StateLiquifyScript.CLOCKWISE, StateLiquifyScript.ANTICLOCKWISE],
        ["Clockwise", "Anticlockwise"],
        {
            "property": ^"direction",
            "bar": false,
            "tooltip": "Which way Twirl turns the paint. Alt held turns it the other way. Dimmed under the other modes.",
            "enabled_when": &"liquify_mode",
            "enabled_when_values": [StateLiquifyScript.TWIRL]
        }
    )

    var size := SaOptionSpec.make_float(
        &"liquify_size",
        "Size",
        StateLiquifyScript.SIZE_MIN,
        StateLiquifyScript.SIZE_MAX,
        1.0,
        {"property": ^"size", "decimals": 0, "suffix": " px", "bar": false, "tooltip": "Width of the brush, in pixels."}
    )

    var strength := SaOptionSpec.make_float(
        &"liquify_strength",
        "Strength",
        0.01,
        1.0,
        0.01,
        {
            "property": ^"strength",
            "percent": true,
            "decimals": 0,
            "suffix": "%",
            "bar": false,
            "tooltip":
            (
                "Strength of the effect at the brush centre. Press Enter to keep the result as one undo step, "
                + "or Escape to undo it all."
            )
        }
    )
    return [mode, direction, size, strength]
