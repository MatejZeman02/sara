## Sara's filter brush, an engine of the Brush: where it passes, the chosen
## filter's result is painted onto the layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside Liquify, which moves paint, this is Krita's filter brush, which
## paints any filter the registry offers with the parameters its own dialog
## sets. The engine is
## `filter_brush_stroke.gd`, the gesture `state_filter_brush.gd`, the filter's
## own rows in the Tool Options `filter_rows.gd`, and the shelf of four
## presets `presets/filter_brush_presets.gd`. This file names those and
## nothing else of the folder.
##
## **An engine of the Brush, registered through the door.** It registers with
## `SaContext.register_brush_engine` exactly as the noise brush, a module of
## another repository, does (hard rule 6), and reads the filters through the
## context's registry, so a filter a student's module adds is on the list the
## moment it registers.
##
## A module of its own beside the stamp brush rather than a folder of `base/`,
## because it is a brush and `base/` is the tools. A kernel here shares its
## owner with the rest of the repository's, as `stamp-brush/module.gd` says,
## so its one kernel is named after the folder.
extends SaModule

const FilterBrushSettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const StateFilterBrushScript = preload("res://modules/sara-base-modules/filter-brush/state_filter_brush.gd")
const FilterRowsScript = preload("res://modules/sara-base-modules/filter-brush/filter_rows.gd")
const FilterBrushPresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")

## The engine's id, which the tool machine keys it by and a scenario's `tool`
## step names, so it never changes once a painter has used it.
const TOOL_ID: StringName = &"filter_brush"

## The role the shelf is registered under, `shipped_presets_` and the engine's
## word, which the presets bar asks for of every engine the Brush paints with.
const PRESETS_ROLE: StringName = &"shipped_presets_filter"

## The Radius row's floor, soft ceiling and ceiling, as fractions of the
## canvas's smaller side, the tool machine's numbers, which its bracket keys
## and shift drag clamp to.
const RADIUS_MIN: float = 0.0001
const RADIUS_SOFT_MAX: float = 0.5
const RADIUS_MAX: float = 1.0

## The settings every surface's tool is handed.
var settings: Resource = null
## The brush's descriptor and the context whose filters it lists, held so a
## filter another module registers later reaches the Filter row.
var _tool: SaToolDescriptor = null
var _context: SaContext = null


func get_id() -> StringName:
    return &"sara-filter-brush"


func get_name() -> String:
    return "Sara Filter Brush"


func register(ctx: SaContext) -> void:
    settings = FilterBrushSettingsScript.new().made_now()
    # A bare context carrying only the filters. The module's own holds the tool
    # registry, which holds these settings through the descriptor, so settings
    # holding it back closed a cycle no reference count frees, and a full run
    # of the suites ended on the pen's reader threads it kept alive.
    var door := SaContext.new()
    door.filters = ctx.filters
    settings.context = door
    var brush := SaToolDescriptor.create(TOOL_ID, StateFilterBrushScript)
    brush.display_name = "Filter Brush"
    brush.icon_name = "paint"
    brush.category = &"paint"
    brush.is_painting = true
    # The Info docker's pressure row reads `last_pressure`, which the gesture
    # writes at every motion.
    brush.reads_pressure = true
    brush.wants_brush_cursor = true
    brush.cursor_shape = Control.CURSOR_CROSS
    # The Brush's right press, which opens the presets under every engine.
    brush.opens_presets_on_right_click = true
    brush.shared_settings = settings
    brush.preset_engine = FilterBrushSettingsScript.PRESET_ENGINE
    brush.options = options(ctx)
    ctx.register_brush_engine(brush)
    _tool = brush
    _context = ctx
    if ctx.filters != null and not ctx.filters.changed.is_connected(_on_filters_changed):
        ctx.filters.changed.connect(_on_filters_changed)
    ctx.register_role(PRESETS_ROLE, FilterBrushPresetsScript)


func unregister(_ctx: SaContext) -> void:
    if _context != null and _context.filters != null and _context.filters.changed.is_connected(_on_filters_changed):
        _context.filters.changed.disconnect(_on_filters_changed)


## Lists the filters again when a module adds or drops one.
func _on_filters_changed() -> void:
    if _tool != null:
        _tool.options.assign(options(_context))


## The rows: the filter, among those that can be a brush, its own rows, the
## sentence that refuses one the brush cannot paint, then the radius, the
## opacity and the softness. The
## radius and the opacity are the noise brush's and the stamp's keys, so the
## bar's one slider of each follows whichever engine is in hand.
static func options(door: SaContext = null) -> Array[SaOptionSpec]:
    var ids: Array = []
    var labels: Array = []
    if door != null and door.filters != null:
        # Only the filters that say a brush can paint them, so a painter never
        # picks one only to read why it paints nothing.
        for key: StringName in door.filters.list_keys():
            var listed := door.filters.get_filter(key)
            if listed.can_be_a_brush():
                ids.append(String(key))
                labels.append(listed.title())
    var filter := SaOptionSpec.make_enum(
        &"filter_key",
        "Filter",
        ids,
        labels,
        {
            "bar": false,
            "tooltip": "The filter the brush paints. Its result is laid where the brush passes, as much as the opacity says."
        }
    )

    # The chosen filter's own rows, under its choice where a painter looks for
    # how strong the filter is. Shown while a filter is chosen, and naming the
    # filter's key, which makes the docker draw its rows again when the choice
    # moves, so these rows and the note below follow the choice.
    var rows := SaOptionSpec.make_custom(
        &"filter_rows",
        "",
        _build_rows,
        _bind_rows,
        {"property": ^"filter_page", "bar": false, "shown_when": {"key": &"filter_key", "value": "", "equals": false}}
    )

    var note := SaOptionSpec.make_custom(
        &"filter_note",
        "",
        _build_note,
        _bind_note,
        {
            "on_tool": true,
            "property": ^"filter_note",
            "bar": false,
            "shown_when": {"key": &"filter_note", "value": "", "equals": false}
        }
    )

    var size := SaOptionSpec.make_float(
        &"radius",
        "Radius",
        RADIUS_MIN,
        RADIUS_MAX,
        0.001,
        {
            "soft_max": RADIUS_SOFT_MAX,
            "tooltip":
            (
                "Brush radius in pixels of this document (the stroke is twice this wide). "
                + "Double-click to type a value, and Left or Right steps it by 1 pixel."
            ),
            "scale_by_canvas": true,
            "suffix": "px",
            "logarithmic": true,
            "decimals": 2,
            "steps_by_whole_units": true,
            "bar_after": "opacity"
        }
    )

    var opacity := SaOptionSpec.make_float(
        &"opacity",
        "Opacity",
        0.0,
        1.0,
        0.01,
        {
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "tooltip":
            (
                "The stroke's strength over the filter's result: how much of it the stroke lays, at 100% the result whole. "
                + "The filter's own settings, a blur's radius among them, are the rows under Filter. "
                + "Crossing the stroke again takes it no further."
            ),
            "bar_after": "blend_mode"
        }
    )

    var softness := SaOptionSpec.make_float(
        &"softness",
        "Softness",
        0.0,
        1.0,
        0.01,
        {
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip":
            "How much of the radius the edge fades over. 0 is a hard edge, 100% fades from the centre as a soft brush does."
        }
    )

    var by_pressure := SaOptionSpec.make(
        &"opacity_by_pressure",
        "Opacity by pressure",
        SaOptionSpec.Kind.BOOL,
        {
            "icon": "opacity_pressure",
            "bar": false,
            "tooltip":
            (
                "The pen's pressure sets how much of the filter each touch lays, through the curve under it: "
                + "a light touch a little, a full press the opacity."
            )
        }
    )

    # The curve the switch above reads, shown while it is on, as the stamp
    # brush's opacity shows the curve its pressure goes through.
    var curve := SaOptionSpec.make(
        &"pressure_curve",
        "Pressure Curve",
        SaOptionSpec.Kind.CURVE,
        {
            "bar": false,
            "shown_when": {"key": &"opacity_by_pressure", "value": true},
            "tooltip": "The pen's pressure along the bottom and the share of the opacity laid up the side."
        }
    )
    return [filter, rows, note, size, opacity, softness, by_pressure, curve]


## The filter's rows, built empty and drawn by the binder. A settled change is
## handed to *write*, the docker's write of the option, so it lands on the
## brush's `filter_page` as a slider's move lands on its key.
static func _build_rows(_spec: SaOptionSpec, write: Callable) -> Control:
    return FilterRowsScript.new(write)


static func _bind_rows(control: Control, value: Variant) -> void:
    if control != null and control.has_method(&"show_page") and value is Dictionary:
        control.call(&"show_page", value)


## The note's control, a label that wraps, since a refusal is a sentence. It is
## held in a container because a Tool Options row takes the first child that is
## not a label for its control, and a bare label is given no width at all.
static func _build_note(_spec: SaOptionSpec, _write: Callable) -> Control:
    var holder := MarginContainer.new()
    var label := Label.new()
    label.name = "FilterNote"
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    holder.add_child(label)
    return holder


static func _bind_note(control: Control, value: Variant) -> void:
    var label := control.get_node_or_null("FilterNote") as Label if control != null else null
    if label != null:
        label.text = str(value)
