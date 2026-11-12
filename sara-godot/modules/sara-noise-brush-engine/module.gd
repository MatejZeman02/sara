## Sara's noise brush engine, a stroke the paper decides.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A module of its own repository, registered through the door the way a third
## party's would be. The module is a plain stroke from its own kernel with its
## own page and presets, the texture that decides where paint lands, the three
## fields that texture can be, registered on the door's brush field registry
## and read by `noise_fields.gd`, the height the field's lightness deposits
## through the door's `height_deposit` library, and the Randomness row that
## rolls the stroke's seed. The first shelf of presets is
## `presets/noise_presets.gd`.
##
## **It is an engine of the Brush, not a tool of its own.** It registers
## through `SaContext.register_brush_engine`, and a painter picks the Brush and
## chooses a noise preset, the way Krita has one freehand brush and many
## engines behind its presets.
##
## **It sees the door and nothing else.** The tip, the dynamics and the dab
## placement live in the door rather than in the stamp brush, so
## this module names `core/api`, `core/custom-shader` and the kernel libraries
## in `shaders/compute/libs/`, and never the base modules. The suite
## `tests/test_the_noise_brush_sees_the_door_only.gd` fails on any path into
## them.
extends SaModule

const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
## The shelf of presets the module ships, its own bundle and licence.
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
## The painter's own fields, one `.gmacs` file each in the door's folder.
const FieldFolderScript = preload("res://modules/sara-noise-brush-engine/field_folder/noise_field_folder.gd")
## The Tip row with its Image choice, its Tip Image list and its Load Tip action.
const TipRowScript = preload("res://modules/sara-noise-brush-engine/tip/tip_row.gd")
## The Look page, the rows a flat fill with a texture in its tone is made of.
const LookRowsScript = preload("res://modules/sara-noise-brush-engine/noise_look_rows.gd")

## The role the shelf is registered under: `shipped_presets_` and the engine's
## word, which is the name the presets bar asks for while a tool of that
## engine is active. Not the stamp's `shipped_presets`, since a role holds one
## script and a second claim would take the stamp's recipes away.
const PRESETS_ROLE: StringName = &"shipped_presets_noise"

## The engine's id, which the tool machine keys it by, a scenario's `tool` step
## names and the toolbox rows of an older profile held, so it never changes once
## a painter has used it.
const TOOL_ID: StringName = &"noise_brush"

## The icon by path, which `SaUI.get_icon` takes beside a bare name, because
## a module's icon lives in the module rather than in the skeleton's folder.
const ICON: String = "res://modules/sara-noise-brush-engine/icons/noise_brush.svg"

## The brush editor's page the rows sit on, the editor's default page, so the
## window opens on them.
const PAGE: String = "General"

## Strength's curve option by key, and the brush editor's page it makes.
const STRENGTH_OPTION: StringName = &"strength_option"
const STRENGTH_PAGE: String = "Strength"
## Thickness's curve option by key, and its page, where pressure drives it.
const THICKNESS_OPTION: StringName = &"thickness_option"
const THICKNESS_PAGE: String = "Thickness"
## The lean's stretch of the tip and the speed's carry of the field, by key,
## each on a page of its own.
const STRETCH_OPTION: StringName = &"stretch_option"
const DRIFT_OPTION: StringName = &"drift_option"
## The tip's turn by key, the stamp's, on a page of its own.
const ROTATION_OPTION: StringName = &"rotation_option"
## The Tilt Thickness row's key and its curve option's, the lean's share of
## more height on the side the pen leans to.
const THICKNESS_LEAN_KEY: StringName = &"thickness_lean"
const THICKNESS_LEAN_OPTION: StringName = &"thickness_lean_option"
## The Thickness row's ceiling in virtual millimetres a stroke. Four times the
## default, so a single stroke still stays well inside the ten millimetres the
## relief is tuned for.
const THICKNESS_MAX: float = 2.0

## The Chroma variation row's key, the settings' field the press binds from.
const CHROMA_KEY: StringName = &"chroma_variation"

## Each slider's key and the curve option its randomise control binds, in
## the settings' names. Every numeric row of the page is here but the ones in
## [constant UNROLLED].
const RANDOMISED: Dictionary = {
    &"radius": &"size_option",
    &"opacity": &"opacity_option",
    &"hardness": &"hardness_option",
    &"strength": &"strength_option",
    &"thickness": THICKNESS_OPTION,
}

## The page's sliders with no randomise control. Randomness is the roll itself,
## so a control that rolled it would be a roll of a roll. Chroma variation is a
## swing the press binds into two options, Hue and Saturation, so it has no
## curve option of its own for a roll to sit under. Exposure is the colour's
## stops rather than the brush's, so nothing of the brush rolls it. Tilt
## Thickness picks which edge of a leaning pen's mark is the heavier as much as
## how much, a choice set once rather than a quantity to wobble, and its curve
## page takes a roll for a painter who wants one. Angle's roll is Rotation's.
## Paint and Smudge is Colour Rate's strength, and its roll is that page's.
const UNROLLED: Array[StringName] = [
    &"randomness",
    CHROMA_KEY,
    &"exposure",
    TipRowScript.EDGE_KEY,
    TipRowScript.ANGLE_KEY,
    THICKNESS_LEAN_KEY,
    &"paint_and_smudge",
]

## The Radius row's floor, soft ceiling and ceiling, as fractions of the
## canvas's smaller side. The tool machine's own numbers, which its bracket
## keys and shift drag clamp to, written here because the machine is not the
## door. A tenth of a pixel's radius on the default document is the smallest
## size that still paints.
const RADIUS_MIN: float = 0.0001
const RADIUS_SOFT_MAX: float = 0.5
const RADIUS_MAX: float = 1.0

## The settings the tool is handed, kept so the colour from the bus reaches
## them.
var settings: Resource = null
## The brush's descriptor and the door's field registry, held so a field
## another module registers later reaches the Texture row as well as a stroke.
var _tool: SaToolDescriptor = null
var _field_registry: SaBrushFieldRegistry = null
## The painter's own fields, read after the shipped three so the Texture row
## lists them after.
var _folder: FieldFolderScript = null


func get_id() -> StringName:
    return &"sara-noise-brush"


func get_name() -> String:
    return "Sara Noise Brush"


func register(ctx: SaContext) -> void:
    settings = NoiseBrushSettingsScript.new()
    # The store the Picture field reads, the door's own class and one per
    # module, the way the stamp makes its own. Made here so the Pattern row's
    # choices and the stroke read the same folders.
    settings.pattern_store = SaPatternStore.new()
    # Through the door like another module's field, which the brush then
    # reads beside these three.
    for field: SaBrushFieldRegistry.Field in NoiseFieldsScript.shipped(settings.pattern_store):
        ctx.register_brush_field(field)
    # Before the settings are handed the fields, so a stored choice of one of
    # the painter's is still there when the settings ask.
    _folder = FieldFolderScript.new(ctx, get_id())
    _folder.reread()
    var fields: RefCounted = NoiseFieldsScript.new(ctx.brush_fields, _folder)
    settings.fields = fields

    var brush := SaToolDescriptor.create(TOOL_ID, StateNoiseBrushScript)
    brush.display_name = "Noise Brush"
    brush.icon_name = ICON
    # The paint group, where the Brush it paints under is. The toolbox draws no
    # button for an engine, and a build with no Brush lists it there as a tool.
    brush.category = &"paint"
    brush.is_painting = true
    brush.wants_brush_cursor = true
    brush.cursor_shape = Control.CURSOR_CROSS
    # The Brush's right press, which opens the presets under either engine.
    brush.opens_presets_on_right_click = true
    brush.shared_settings = settings
    brush.preset_engine = NoiseBrushSettingsScript.PRESET_ENGINE
    brush.options = options(fields)
    ctx.register_brush_engine(brush)
    _tool = brush
    _field_registry = ctx.brush_fields
    if not _field_registry.changed.is_connected(_on_fields_changed):
        _field_registry.changed.connect(_on_fields_changed)
    if not _field_registry.reread_asked.is_connected(_on_reread_asked):
        _field_registry.reread_asked.connect(_on_reread_asked)
    var window := _window()
    if window != null and not window.focus_entered.is_connected(_on_focus_back):
        window.focus_entered.connect(_on_focus_back)
    # The shelf, under the role the presets bar asks of each engine the Brush
    # paints with, so it is written the first time a painter holds the Brush.
    ctx.register_role(PRESETS_ROLE, NoisePresetsScript)

    if not EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.connect(_on_color_picked)
    if not EventBus.background_color_changed.is_connected(_on_background_color_changed):
        EventBus.background_color_changed.connect(_on_background_color_changed)
    # No read of the colour store here: it is not the door, and the store
    # announces the pair on the bus once every module has registered.


func unregister(_ctx: SaContext) -> void:
    if _field_registry != null and _field_registry.changed.is_connected(_on_fields_changed):
        _field_registry.changed.disconnect(_on_fields_changed)
    if _field_registry != null and _field_registry.reread_asked.is_connected(_on_reread_asked):
        _field_registry.reread_asked.disconnect(_on_reread_asked)
    var window := _window()
    if window != null and window.focus_entered.is_connected(_on_focus_back):
        window.focus_entered.disconnect(_on_focus_back)
    if _folder != null:
        _folder.forget()


## The main window, whose focus coming back reads the painter's fields again,
## or null in a host with no tree.
static func _window() -> Window:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.root if tree != null else null


## The door's `brush_field` step wrote a file into an engine's folder.
func _on_reread_asked(engine: StringName) -> void:
    if engine == NoiseFieldsScript.ENGINE and _folder != null:
        _folder.reread()


## The painter is back from another program, perhaps the editor a field was
## saved in.
func _on_focus_back() -> void:
    if _folder != null:
        _folder.reread()


## Lists the fields again when a module adds or drops one, refilling the
## descriptor's array, which the pages read once every module has registered.
func _on_fields_changed() -> void:
    if _tool != null and settings != null and settings.fields != null:
        _tool.options.assign(options(settings.fields))


## The page, in the spec's order: Radius, Opacity, Hardness, Tip with its Tip
## Image and Load Tip under Image, Texture, Strength, Thickness, Tilt
## Thickness, Randomness, Blend mode, Erase and Chroma variation, each slider
## but Tilt Thickness, Randomness and Chroma variation with its randomise
## control under it, and Exposure declared among them for the bar and kept off
## the page, since it is the colour's, then the Texture page with the chosen
## field's own rows, then the Opacity, Saturation, Hue, Strength, Thickness,
## Tilt Stretch, Tilt Thickness and Drift Speed curve options as pages of their
## own. Each key the stamp also has is the
## stamp's name for the same quantity, so the bar's stored layout treats the
## two brushes' rows as one row that follows the active tool. Tip Image is the
## one row under a key of its own, for the reason `tip_row.gd` gives.
##
## *fields* is the registry the Texture row lists, the three shipped fields and
## the store's patterns when none is given.
static func options(fields: RefCounted = null) -> Array[SaOptionSpec]:
    if fields == null:
        fields = NoiseFieldsScript.new()
        fields.register_shipped(SaPatternStore.new())
    # Radius rather than Size, the stamp brush's label for the same row, because
    # the number is the radius and the ring is twice as wide.
    var size := SaOptionSpec.make_float(
        &"radius",
        "Radius",
        RADIUS_MIN,
        RADIUS_MAX,
        0.001,
        {
            "page": PAGE,
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
            "trim_trailing_zeros": true,
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
            "page": PAGE,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "tooltip": "How opaque the stroke gets. It reaches this and stops, however often the stroke crosses itself.",
            "bar_after": "eraser_toggled"
        }
    )

    var hardness := (
        SaOptionSpec
        . make_float(
            &"hardness",
            "Hardness",
            0.0,
            1.0,
            0.01,
            {
                "page": PAGE,
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "bar_hidden": true,
                "bar_after": "radius",
                "tooltip":
                # gdlint:ignore=max-line-length
                "How sharp the edge of the holes the texture leaves is. Low fades paint in around them and thins the grain towards the stroke's edge."
            }
        )
    )

    var texture := SaOptionSpec.make_enum(
        NoiseFieldsScript.FIELD_KEY,
        "Texture",
        fields.ids(),
        fields.labels(),
        {
            "page": PAGE,
            "bar": false,
            "width": 96,
            "tooltip": "What the stroke paints through: a grain, streaks along the stroke, or a pattern."
        }
    )

    var strength := SaOptionSpec.make_float(
        &"strength",
        "Strength",
        -1.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar_hidden": true,
            "bar_after": "hardness",
            "tooltip": "Shifts the texture against the pressure. Above 0 paint needs a firmer press, below 0 a lighter one."
        }
    )

    var randomness := SaOptionSpec.make_float(
        &"randomness",
        "Randomness",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip": "0 paints the same texture and the same random values every stroke. Above 0 each stroke gets its own."
        }
    )
    var thickness := SaOptionSpec.make_float(
        &"thickness",
        "Thickness",
        0.0,
        THICKNESS_MAX,
        0.01,
        {
            "page": PAGE,
            "suffix": "mm",
            "decimals": 2,
            "bar_hidden": true,
            "bar_after": "strength",
            "tooltip": "How much paint the stroke lays in height where the texture is light. Nought lays none."
        }
    )
    var lean := SaOptionSpec.make_float(
        THICKNESS_LEAN_KEY,
        "Tilt Thickness",
        -1.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip":
            (
                "How much more impasto a leaning pen lays on the side it leans to, and less on the other. "
                + "Below 0 the other side lays more. An upright pen lays it evenly."
            )
        }
    )
    # On and Off, as the stamp's Size by Pressure reads, under Thickness, since
    # the push it turns on moves only paint that has a height.
    var push_below := SaOptionSpec.make(
        &"push_colour_below",
        "Push Colour Below",
        SaOptionSpec.Kind.BOOL,
        {
            "page": PAGE,
            "bar": false,
            "tooltip":
            (
                "Pushes the colour of the paint on the layers below along with the stroke, as far as that paint stands in height."
                + " Off pushes only this layer's paint. The Background and the paper are never pushed."
            )
        }
    )
    # The stamp's Exposure row, the foreground's paint exposure in stops, which
    # the door builds for every engine.
    var exposure := SaPaintExposure.option_spec({"page": PAGE})
    var blend := SaOptionSpec.make(
        &"blend_mode", "Blend Mode", SaOptionSpec.Kind.BLEND_MODE, {"page": PAGE, "width": 70, "bar_after": "Brush Presets"}
    )

    # The stamp's Erase button under the stamp's key, so the bar's one button
    # and E erase with the Brush whichever engine it paints with.
    var erase := SaOptionSpec.make(
        &"eraser_toggled",
        "Erase",
        SaOptionSpec.Kind.BOOL,
        {"page": PAGE, "on_tool": true, "icon": "eraser", "tooltip": "Erase with the brush (E)", "bar_after": "Keep Blend Mode"}
    )

    var chroma := SaOptionSpec.make_float(
        CHROMA_KEY,
        "Colour variation",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip": "How far the colour's hue and saturation follow the texture under each dab."
        }
    )

    # Paint and Smudge beside Opacity, drawn only while the brush smudges.
    var rows: Array[SaOptionSpec] = [size, opacity, SaSmudgePage.slider({"page": PAGE}), hardness]
    rows.append_array(TipRowScript.rows(PAGE))
    rows.append_array([texture, strength, thickness, lean, push_below, randomness, blend, erase, exposure, chroma])
    # A randomise control under every slider, each bound to the fuzzy
    # sensor of the slider's curve option, so a row added here gains one by the
    # same call.
    for index in range(rows.size() - 1, -1, -1):
        var option: StringName = RANDOMISED.get(rows[index].key, &"")
        if not option.is_empty():
            rows.insert(index + 1, SaRandomiseControl.beside(rows[index], option))
    rows.append_array(_texture_page(fields))
    rows.append_array(LookRowsScript.rows())
    # The curve option pages, each its own page named by its label, and after
    # General so the window still opens on the rows. Opacity and Saturation
    # because the lift-up sensor is bound on those two, and ticking it on
    # either page binds it through the same control the stamp's pages use.
    # Strength because a sensor a painter binds moves its shift, and
    # Thickness because it drives the deposit.
    rows.append(_curve_page(&"opacity_option", "Opacity", "How the dab's opacity follows the sensors."))
    (
        rows
        . append(
            _curve_page(
                &"saturation_option",
                "Saturation",
                "How far each dab moves the picked colour towards or away from grey, following the sensors.",
            )
        )
    )
    # Hue beside Saturation, the pair Chroma variation binds to the texture
    # sensor, so the binding the row made is on a page a painter can bend.
    (
        rows
        . append(
            _curve_page(
                &"hue_option",
                "Hue",
                "How far each dab turns the picked colour's hue, following the sensors.",
            )
        )
    )
    (
        rows
        . append(
            _curve_page(
                STRENGTH_OPTION,
                STRENGTH_PAGE,
                "How Strength follows the sensors. Off by default, because pressure already sets the threshold.",
            )
        )
    )
    (
        rows
        . append(
            _curve_page(
                THICKNESS_OPTION,
                THICKNESS_PAGE,
                # gdlint:ignore=max-line-length
                "How the Thickness row follows the sensors. Pressure raises it by default, and a pen laid flat or a fast hand lays thinner paint.",
            )
        )
    )
    # Two more for the defaults, the lean that stretches the tip and the speed
    # that carries the field, so a painter sees both bindings and unbinds them.
    (
        rows
        . append(
            _curve_page(
                STRETCH_OPTION,
                "Tilt Stretch",
                "How far the pen's lean stretches the tip along it. A pen laid flat paints a tip twice as long by default.",
            )
        )
    )
    # And the lean's share of Tilt Thickness, on the elevation the same way.
    (
        rows
        . append(
            _curve_page(
                THICKNESS_LEAN_OPTION,
                "Tilt Thickness",
                # gdlint:ignore=max-line-length
                "How the Tilt Thickness row follows the sensors. An upright pen lays evenly and one laid flat lays the row's full difference by default.",
            )
        )
    )
    (
        rows
        . append(
            _curve_page(
                DRIFT_OPTION,
                "Drift Speed",
                # gdlint:ignore=max-line-length
                "How the Drift row follows the sensors. A fast stroke carries the texture further by default, so its streaks draw out.",
            )
        )
    )
    # Rotation, the stamp's option under the stamp's name, off by default so a
    # picture tip lies as drawn. A sensor ticked here turns it with the pen.
    (
        rows
        . append(
            _curve_page(
                ROTATION_OPTION,
                "Rotation",
                # gdlint:ignore=max-line-length
                "How far the tip is turned, following the sensors. Off by default, so a picture tip keeps its own angle whatever the pen does.",
            )
        )
    )
    # The smudge stage's pages, the ones the stamp shows, named in the door.
    # No Move Height row, since the noise dab lays its own height and does
    # not drag the layer's.
    for entry: Array in SaSmudgePage.curve_options():
        rows.append(_curve_page(entry[0], entry[1], entry[2]))
    rows.append_array(SaSmudgePage.rows(false))
    return rows


## The Texture page: Drift for every field, Channels and Relief for a field
## that has two channels, then every registered field's own rows, each shown
## while its field is the chosen one, so the page is the field on screen and
## nothing else.
static func _texture_page(fields: RefCounted) -> Array[SaOptionSpec]:
    # Channels and Relief are enabled for a field with two channels alone.
    var two_channels: Dictionary[String, Variant] = {
        "page": NoiseFieldsScript.PAGE,
        "bar": false,
        "advanced": true,
        "enabled_when": NoiseFieldsScript.FIELD_KEY,
        "enabled_when_values": fields.two_channel_ids()
    }
    var channel_fields: Dictionary[String, Variant] = {
        "tooltip": "One paints colour only. Two also paints impasto, as much as Thickness lays."
    }
    channel_fields.merge(two_channels)
    var channels := SaOptionSpec.make_enum(NoiseFieldsScript.CHANNELS_KEY, "Channels", [1, 2], ["One", "Two"], channel_fields)
    var relief_fields: Dictionary[String, Variant] = {
        "percent": true,
        "suffix": "%",
        "decimals": 0,
        "shown_when": {"key": NoiseFieldsScript.CHANNELS_KEY, "value": 2},
        "tooltip": "How closely the impasto follows the texture's second channel."
    }
    relief_fields.merge(two_channels)
    var relief := SaOptionSpec.make_float(NoiseFieldsScript.RELIEF_KEY, "Impasto", 0.0, 2.0, 0.01, relief_fields)
    var rows: Array[SaOptionSpec] = [_drift_row(), channels, relief]
    rows.append_array(fields.rows())
    return rows


## The Drift row, first on the Texture page because every field shares
## it, so it is enabled whichever field is chosen.
static func _drift_row() -> SaOptionSpec:
    var drift := SaOptionSpec.make_float(
        NoiseFieldsScript.DRIFT_KEY,
        "Drift",
        0.0,
        1.0,
        0.01,
        {
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "page": NoiseFieldsScript.PAGE,
            "bar": false,
            "advanced": true,
            "tooltip": "How far the texture slides with the brush. 0 holds it still, 100% drags it so streaks run the whole way."
        }
    )
    return drift


## One curve option spec on a page of its own, carrying the door's control, its
## binding and its row text, the way any engine declares one.
static func _curve_page(key: StringName, label: String, tooltip: String) -> SaOptionSpec:
    var spec := SaOptionSpec.make(
        key,
        label,
        SaOptionSpec.Kind.CURVE_OPTION,
        {
            "property": NodePath(String(key)),
            "tooltip": tooltip,
            "bar": false,
            "advanced": true,
            "build_control": SaCurveOptionControl.build_control,
            "bind_value": SaCurveOptionControl.bind_control.bind(label),
            "describe_value": SaCurveOptionControl.describe
        }
    )
    return spec


func _on_color_picked(color: Color) -> void:
    if settings != null:
        settings.color = color


func _on_background_color_changed(color: Color) -> void:
    if settings != null:
        settings.background_color = color
