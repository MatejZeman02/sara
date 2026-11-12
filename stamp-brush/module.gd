## Sara's stamp brush engine.
##
## The module holding the brush and the eraser, so the engine lives in one
## place: the two tools, their settings resource, the stabilizer, the options
## bar they declare, the dab pipeline and the dynamics are all here.
##
## The tool ids stay `&"brush"` and `&"eraser"` and every `SaOptionSpec.key`
## stays what it was, because a settings profile records the active tool by id
## and `ui/tool_options/tool_options_bar.gd` names its stored controls by key. A rename here
## is a settings migration for every painter, for no gain a painter can see.
##
## A shader added here shares an owner name with `base/`'s, because
## `core/custom-shader/compiler/sa_shader_index.gd` reads the directory under `modules/`
## and that is the repository rather than the module. So a kernel in this folder
## cannot take a name a kernel in `base/` already has.
extends SaModule

# The settings resource the module hands both tools.
# `stamp_brush_settings.gd`, which is the skeleton's brush fields plus the
# nine curve options the dynamics reads.
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
## The tip loader, for the cursor outline an image tip answers with. By path
## like every other script this module names.
const SaTipImageScript = preload("res://core/api/tip/sa_tip_image.gd")
## The door's `kpp` step reaches the reader through this role rather than by
## naming the class, because the skeleton is kept free of module class names
## and the step table is skeleton.
const SaKppCaptureScript = preload("res://modules/sara-base-modules/stamp-brush/krita/sa_kpp_capture.gd")
## The door's `pattern` step reaches the chooser the same way.
const SaPatternCaptureScript = preload("res://modules/sara-base-modules/stamp-brush/pattern/sa_pattern_capture.gd")
## The stored tag an import writes for what it could not carry, which the
## module registers the reading of.
const SaNotCarriedScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_not_carried.gd")
## The door's `preset_import` step and the presets docker's Import button both
## reach the Krita importer through this role.
const SaKppImportCaptureScript = preload("res://modules/sara-base-modules/stamp-brush/krita/sa_kpp_import_capture.gd")
## The recipes the brush ships, and the rule about which of them a template can
## carry. Through the `shipped_presets` role rather than in `core/`, because
## every path a recipe names is a field of this module's own settings resource.
const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
## The bundle files a module ships in a `bundles/` folder, installed after the
## recipes through the importer this module owns.
const SaShippedBundlesScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_bundles.gd")
const StateEraserScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_eraser.gd")
## The two preset converters, stamp to noise and back.
const NoiseConversionScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_noise_conversion.gd")
## Moves the brush and the presets made under the painter's old pressure curve
## on to the new one.
const SaMakerCurveScript = preload("res://modules/sara-base-modules/stamp-brush/sa_maker_curve.gd")
## For the eraser's blend mode, which is a property of its settings rather than
## of the tool instance.
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")

## The two plain pages of the brush editor, beside the ones that are a
## curve option each, which `SaCurveOptionPages` declares.
##
## `GENERAL_PAGE` matches `SaBrushEditorPages.DEFAULT_PAGE`, which is where a
## option naming no page lands. Named here as well as there because the editor's
## fallback is what keeps that window from opening empty for a tool that has
## declared nothing, and this module has declared: a row on General is on
## General because this file said so, not because it forgot.
const GENERAL_PAGE: String = SaTipPage.GENERAL_PAGE
const TIP_PAGE: String = SaTipPage.PAGE

## The `tip_generator` id that means a picture and the Brush Tip page's two
## headings, which [SaTipPage] says the reason for.
const TIP_IMAGE_ID: int = SaTipPage.TIP_IMAGE_ID
const SECTION_PROCEDURAL: String = SaTipPage.SECTION_PROCEDURAL
const SECTION_MASK: String = SaTipPage.SECTION_MASK

## Shared so brush size and colour follow the user between the main canvas and
## the info docker's scratchpad, which are two surfaces of one brush rather than
## two brushes.
var brush_settings: Resource = null

## The one pattern store, made in [method register] and handed out from there.
var pattern_store: SaPatternStore = null
var eraser_settings: Resource = null
## The stamp and noise preset converters, registered in [method register].
var noise_conversion: RefCounted = null
## The listener that re-stamps the brush when the painter's curve changes,
## made in [method register] and let go in [method unregister].
var maker_curve: RefCounted = null


func get_id() -> StringName:
    return &"sara-stamp-brush"


func get_name() -> String:
    return "Sara Stamp Brush"


func register(ctx: SaContext) -> void:
    brush_settings = BrushSettingsScript.new()
    # One pattern store for the module, onto both settings resources so every
    # brush and eraser the machine builds reads the same one, and into the
    # Texture page's rows below, so the chooser draws from it too. A store per
    # chooser and per brush could remember nothing between rebuilds, which is
    # what re-read three unreadable papers 13872 times.
    pattern_store = SaPatternStore.new()
    brush_settings.pattern_store = pattern_store
    ctx.register_role(&"kpp_capture", SaKppCaptureScript)
    ctx.register_role(&"pattern_capture", SaPatternCaptureScript)
    ctx.register_role(&"preset_import", SaKppImportCaptureScript)
    # The fourth role beside the three: the recipes the brush ships, so the
    # skeleton's preset group installs what the build's brush can carry and a
    # build without this module installs nothing.
    ctx.register_role(SaShippedPresetsScript.ROLE, SaShippedPresetsScript)
    # The fifth: the `.bundle` files every loaded module holds, which only
    # this module's importer can read.
    ctx.register_role(SaShippedBundlesScript.ROLE, SaShippedBundlesScript)
    eraser_settings = BrushSettingsScript.new()
    eraser_settings.pattern_store = pattern_store
    # The eraser's mode belongs to the settings the descriptor hands out, not to
    # the tool instance. `StateEraser._init` sets it on the object the instance
    # was born with, and `ToolMachine._rebuild_tools` then replaces that whole
    # object with this one, so the mode was thrown away every time a machine was
    # built and the Eraser laid the foreground colour down instead.
    eraser_settings.blend_mode = SaLayerScript.BLEND_MODE.ERASE
    var held: Array[Resource] = [brush_settings, eraser_settings]
    maker_curve = SaMakerCurveScript.new(held)

    var brush := SaToolDescriptor.create(&"brush", StateBrushScript)
    brush.display_name = "Brush"
    brush.icon_name = "paint"
    brush.category = &"paint"
    brush.is_painting = true
    brush.wants_brush_cursor = true
    brush.cursor_shape = Control.CURSOR_CROSS
    # The brush ring copies the shape of an image tip. A closure over the settings this module hands the brush,
    # because the shape is whatever tip the painter has loaded and a descriptor
    # is registered once at startup. A procedural tip answers nothing, which is
    # what leaves the ring a circle.
    brush.cursor_outline = SaTipImageScript.outline_of.bind(brush_settings)
    brush.activate_action = &"tool_brush"
    brush.shared_settings = brush_settings
    brush.preset_engine = BrushSettingsScript.PRESET_ENGINE
    # The brush takes the right press for the presets, as the eraser below does,
    # and is the tool a hand-back with nowhere else to go lands on. It reads pressure, as the
    # eraser below does, which is what the Info docker's Pressure row shows.
    brush.opens_presets_on_right_click = true
    brush.is_fallback = true
    brush.reads_pressure = true
    # And it is the Brush every brush engine paints under, the noise engine's
    # among them, so its button, its B and its count in the usage tally stand
    # for all of them, and choosing a preset chooses the engine.
    brush.takes_brush_engines = true
    brush.options = brush_options(pattern_store)
    ctx.register_tool(brush)

    var eraser := SaToolDescriptor.create(&"eraser", StateEraserScript)
    eraser.display_name = "Eraser"
    eraser.icon_name = "eraser"
    eraser.category = &"paint"
    eraser.is_painting = true
    eraser.wants_brush_cursor = true
    eraser.cursor_shape = Control.CURSOR_CROSS
    eraser.activate_action = &"tool_eraser"
    eraser.shared_settings = eraser_settings
    eraser.preset_engine = BrushSettingsScript.PRESET_ENGINE
    eraser.reads_pressure = true
    eraser.erases = true
    # The Brush's presets, so a right press lends them as there.
    eraser.opens_presets_on_right_click = true
    # The same list, so Size on the bar is one control that follows whichever
    # of the two is active, each writing its own settings.
    eraser.options = brush_options(pattern_store)
    ctx.register_tool(eraser)

    # E toggles the brush's own eraser mode when the brush is active and picks
    # the Eraser tool otherwise. The chord names this module's two tools, so it
    # is a command of this module's rather than a branch of the skeleton's
    # router. `tool_eraser`, the pair's other name, stays paired to the same key
    # in sa_shortcut_store.gd and still switches the Eraser tool on its own
    # through the generic descriptor loop every tool answers to, so this command
    # only has to run first, which the router already does by trying its
    # commands before that loop. The handler is bound to a context holding the
    # easel and surface providers and no registry, because binding *ctx* itself
    # closes a ring, registry to descriptor to Callable to ctx and back to the
    # registry, which leaks every machine a suite builds.
    var surfaces := SaContext.new(ctx.easel_provider, ctx.surface_provider)
    var toggle_eraser := SaCommandDescriptor.create(&"brush_toggle_eraser", "Toggle eraser", _toggle_eraser.bind(surfaces))
    toggle_eraser.label = "Toggle Eraser"
    toggle_eraser.category = &"brush"
    ctx.register_command(toggle_eraser)

    # The flagship's presets are the other engines' to convert, so this module
    # registers both directions. Held here, because a method's callable does not
    # keep its object alive.
    noise_conversion = NoiseConversionScript.new(ctx.tools)
    var stamp_to_noise := Callable(noise_conversion, &"stamp_to_noise")
    var noise_to_stamp := Callable(noise_conversion, &"noise_to_stamp")
    ctx.register_converter(NoiseConversionScript.STAMP, NoiseConversionScript.NOISE, stamp_to_noise)
    ctx.register_converter(NoiseConversionScript.NOISE, NoiseConversionScript.STAMP, noise_to_stamp)

    # The tags an import or a conversion writes read in the painter's language
    # wherever the presets chooser shows them, through the door.
    SaTagLabels.register(SaNotCarriedScript.PREFIX, Callable(SaNotCarriedScript, &"label"), ctx.module_id)

    if not EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.connect(_on_color_picked)
    # The pair's other half, for Mix to blend towards. Seeded from the store
    # rather than waited for, because the bus only speaks when the colour changes
    # and a painter who never touches the background still has one.
    if not EventBus.background_color_changed.is_connected(_on_background_color_changed):
        EventBus.background_color_changed.connect(_on_background_color_changed)
    _on_background_color_changed(SaColors.background if SaColors != null else SaColorStore.DEFAULT_BACKGROUND)


## The brush's options bar, declared rather than duck-typed. The order is the
## order a fresh profile shows them in, and each key is the name the stored
## layout keeps, so renaming one is a settings migration.
##
## `bar = false`: the option is in the Tool Options docker and not on the top
## bar. What stays on the bar is the mode, the erase toggle and the four a
## painter named, size, opacity, hardness and flow, because those are what a
## painter reaches for mid-stroke. Everything else, and every option of the
## eyedropper, the wand and the two selection tools, is a docker row.
##
## **A reduced option a painter can ask for again is `bar = true` plus
## `bar_hidden`, never `bar = false`**. The flag decides whether a control is
## built at all, so a false one leaves the Preferences row with nothing behind
## it and its switch moving nothing in either direction. Hardness and the
## stabilizer mode took that route already. `bar_hidden` is not an entry in
## `SaSettingsLayout.DEFAULT_HIDDEN`, and each row's `bar_after` is the place
## in that file's default order.
##
## Each bar row names its group, `bar_group`, so the bar draws a break between
## what the dab is and how the line is laid down. The pressure toggles are the
## second kind, since they say what the pen does to a stroke, and Exposure the
## first, since it is the colour the dab carries.
static func brush_options(store: SaPatternStore = null) -> Array[SaOptionSpec]:
    var blend := SaOptionSpec.make(
        &"blend_mode",
        "Blend Mode",
        SaOptionSpec.Kind.BLEND_MODE,
        {"page": GENERAL_PAGE, "width": 70, "bar_after": "Brush Presets", "bar_group": SaOptionSpec.BAR_GROUP_BRUSH}
    )

    # On the tool rather than on the settings: the toggle is this surface's
    # brush, and the scratchpad's brush keeps its own.
    var erase := SaOptionSpec.make(
        &"eraser_toggled",
        "Erase",
        SaOptionSpec.Kind.BOOL,
        {
            "page": GENERAL_PAGE,
            "on_tool": true,
            "icon": "eraser",
            "tooltip": "Erase with the brush (E)",
            "bar_after": "Keep Blend Mode",
            "bar_group": SaOptionSpec.BAR_GROUP_BRUSH
        }
    )

    # The radius is a fraction of the canvas's smaller dimension, shown as
    # pixels of the document under the bar. The drag stops at the soft
    # ceiling and a typed value at the hard one, the machine's constants so
    # the shift-drag and the brackets agree with the row.
    #
    # Labelled Radius rather than Size, because the number is the radius: a
    # painter read "30.34 px" and found a ring 57 across. The key stays
    # `radius`, so a stored bar layout and a saved preset still find it.
    var size := (
        SaOptionSpec
        . make_float(
            &"radius",
            "Radius",
            ToolMachine.BRUSH_RADIUS_MIN,
            ToolMachine.BRUSH_RADIUS_MAX,
            0.001,
            {
                "page": GENERAL_PAGE,
                "soft_max": ToolMachine.BRUSH_RADIUS_SOFT_MAX,
                "tooltip":
                (
                    "Brush radius in pixels of this document (the stroke is twice this wide). "
                    + "Double-click to type a value, and Left or Right steps it by 1 pixel."
                ),
                "scale_by_canvas": true,
                "suffix": "px",
                # Geometric rather than linear, so the drag gives every octave of size the
                # same room. A linear box spends nine tenths of its travel on sizes a
                # painter never uses, and the sizes that are a brush share the last sliver.
                # The floor of a tenth of a pixel is what makes the low end reachable at
                # all, since a curve with a zero at its bottom has no ratio to divide by.
                "logarithmic": true,
                # Two decimals, because the row reaches below one pixel: at one decimal
                # every size between 0.05 and 0.95 reads "Radius: 0 px" or "Radius: 1 px",
                # and half a pixel would be indistinguishable from nothing. The row
                # always shows both, so a drag from "25.00 px" to "112.37 px" keeps one
                # width of text and the bar after the slider stays where it was.
                "decimals": 2,
                # The decimals are a scale rather than a precision, so Left and Right still
                # step a whole pixel rather than a hundredth of one.
                "steps_by_whole_units": true,
                # After Opacity, on the right of it, where a painter on a tablet reaches
                # for it most.
                "bar_after": "opacity",
                "bar_group": SaOptionSpec.BAR_GROUP_BRUSH
            }
        )
    )

    var opacity := (
        SaOptionSpec
        . make_float(
            &"opacity",
            "Opacity",
            0.0,
            1.0,
            0.01,
            {
                "page": GENERAL_PAGE,
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                # Build-up multiplies every dab by it and Wash stops the stroke at it, which
                # is the one difference from Flow a painter can see, so the tooltip says both.
                "tooltip": "How much colour a stroke lays down, and in Wash the most it reaches however often it crosses itself.",
                "bar_after": "eraser_toggled",
                "bar_group": SaOptionSpec.BAR_GROUP_BRUSH
            }
        )
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
                "page": GENERAL_PAGE,
                "property": ^"hardness:value",
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "tooltip":
                # Off a fresh bar, which holds only the preset button, the blend mode, the
                "How far the dab stays solid before its edge fades, from soft all the way in at 0 to a crisp edge at 100.",
                # erase toggle, Opacity, Radius and Edit Brush.
                "bar_hidden": true,
                "bar_after": "radius",
                "bar_group": SaOptionSpec.BAR_GROUP_BRUSH
            }
        )
    )

    var flow := (
        SaOptionSpec
        . make_float(
            &"flow",
            "Flow",
            0.0,
            1.0,
            0.01,
            {
                "page": GENERAL_PAGE,
                "property": ^"flow:value",
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "tooltip": "How much paint each dab adds, so a low flow builds the stroke up gently where its dabs overlap.",
                # The bar shows Opacity and not Flow, one slider where a painter reaches for
                # one, and the brush editor keeps both, whose two numbers reach the kernel
                # apart.
                "bar_hidden": true,
                "bar_after": "hardness",
                "bar_group": SaOptionSpec.BAR_GROUP_BRUSH
            }
        )
    )

    # The paint exposure in stops, the foreground's own in `SaColors`: a pick
    # moves it and it moves the colour, and the dab paints the foreground as it
    # stands. The door builds the row for every engine, since it is the
    # colour's rather than this brush's.
    var exposure := SaPaintExposure.option_spec({"page": GENERAL_PAGE, "bar_group": SaOptionSpec.BAR_GROUP_BRUSH})

    # Both on the bar and both hidden there by a profile default, for the reason
    # exposure above carries.
    var size_pressure := SaOptionSpec.make(
        &"size_by_pressure",
        "Size by pressure",
        SaOptionSpec.Kind.BOOL,
        {
            "page": GENERAL_PAGE,
            "icon": "size_pressure",
            "bar": true,
            "bar_hidden": true,
            "bar_after": "exposure",
            "bar_group": SaOptionSpec.BAR_GROUP_STROKE
        }
    )
    var opacity_pressure := SaOptionSpec.make(
        &"opacity_by_pressure",
        "Opacity by pressure",
        SaOptionSpec.Kind.BOOL,
        {
            "page": GENERAL_PAGE,
            "icon": "opacity_pressure",
            "bar": true,
            "bar_hidden": true,
            "bar_after": "size_by_pressure",
            "bar_group": SaOptionSpec.BAR_GROUP_STROKE
        }
    )

    # Each mode carries the sentence its own row shows, in the Tools menu and in
    # the docker's list, so the words are the tool's and neither surface keeps a
    # second copy of them. The three rows were the only ones in the Tools menu
    # that said nothing on hover.
    var stabilizer := (
        SaOptionSpec
        . make(
            &"stabilizer_mode",
            "Stabilizer",
            SaOptionSpec.Kind.ENUM,
            {
                "page": GENERAL_PAGE,
                "choices":
                [
                    {"id": 0, "label": "No Stabilizer", "tooltip": "No smoothing at all."},
                    {"id": 1, "label": "Average", "tooltip": "Follows a short distance behind the pen."},
                    {"id": 2, "label": "Rope", "tooltip": "Follows on a longer, springier line."},
                ],
                "width": 84,
                "tooltip": "Steadies the line: Average follows a short way behind the pen, and Rope on a longer, springier line.",
                # On the bar, and hidden there by a profile default rather than by a false
                # here. `bar = false` means the control is never built, so nothing could
                # offer it in Preferences > Top Menu Bar and the painter had no way to ask
                # for it. `bar_hidden` keeps it off a fresh bar and one tick away, and it
                # opens on the second row after the canvas rotation's two.
                "bar": true,
                "bar_hidden": true,
                "bar_after": "Reset Rotation",
                "bar_group": SaOptionSpec.BAR_GROUP_STROKE
            }
        )
    )
    var smoothing := (
        SaOptionSpec
        . make_float(
            &"stabilizer_amount",
            "Smoothing",
            0.0,
            1.0,
            0.01,
            {
                "page": GENERAL_PAGE,
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "tooltip": "How strongly the line is smoothed. Does nothing with No Stabilizer.",
                # The stabilizer's comment above says why. `bar = false` is the wrong way
                # to keep a reduced option off the bar here, since the profile's defaults
                # already hide it, so the Preferences row would read off and its tick
                # would build nothing.
                "bar": true,
                "bar_hidden": true,
                "bar_after": "stabilizer_mode",
                "bar_group": SaOptionSpec.BAR_GROUP_STROKE
            }
        )
    )

    var rows: Array[SaOptionSpec] = [
        blend,
        erase,
        size,
        opacity,
        hardness,
        flow,
        # Paint and Smudge, drawn only while the brush smudges.
        SaSmudgePage.slider({"page": GENERAL_PAGE}),
        exposure,
        size_pressure,
        opacity_pressure,
        stabilizer,
        smoothing,
    ]
    # **The declaration order is the editor's page order**: a page appears where
    # its first row is declared. A list of this module's titles in the editor
    # would be one agreement written twice. So the pages are declared in the
    # order Brush Tip, General, Size, Opacity, Flow, Spacing, Softness,
    # Rotation, Ratio, Scatter, Airbrush Rate: the tip first, the dashboard
    # next, then the numbers in the order a painter reaches for them, with the
    # pages that list does not name after it.
    #
    # The two previews come first because they open the two plain pages, then
    # the curve pages, then every plain row. The Masking Brush page is the one
    # plain page the order puts among the curve pages, between Texture and
    # Airbrush Rate, so its switch alone is declared there and opens the page,
    # and its other rows keep their place.
    #
    # The Tool Options docker lists rows in the same order. The previews are not
    # in it, and the switch is `advanced`, so a docker with the advanced rows off
    # is unchanged, and with them on the mask's switch sits among the curve doors.
    var tip_rows := tip_options()
    var curves := SaCurveOptionPages.rows()
    var cut := curves.size()
    for index in curves.size():
        if curves[index].key == SaCurveOptionPages.AFTER_MASKING:
            cut = index
            break
    # The Brush Tip page's rows a second time, over the second tip. Handed
    # `tip_options()` rather than reaching for it, because a page file naming
    # this module that this module names back is a cycle at parse time.
    var masking := SaMaskingPage.rows(tip_options())
    var switch: Array[SaOptionSpec] = []
    for spec: SaOptionSpec in masking:
        if spec.page_switch:
            switch.append(spec)
            masking.erase(spec)
            break
    var pages := tip_previews()
    pages.append_array(curves.slice(0, cut))
    pages.append_array(switch)
    pages.append_array(curves.slice(cut))
    pages.append_array(rows)
    pages.append_array(tip_rows)
    pages.append_array(SaTexturePage.rows(store))
    # The smudge stage's plain rows, on the pages its colour rate and pickup
    # options already name. The door declares them, because the noise brush
    # paints the same stage, and the stamp's dab moves height with the colour.
    pages.append_array(SaSmudgePage.rows(true, true))
    pages.append_array(masking)
    # The Colour Source row, under the five colour options above, which named this
    # page in `SaCurveOptionPages.rows` and therefore already made it. Declared
    # here beside the Texture page's rows because both are a page's plain rows and
    # both are the module's, not the editor's.
    pages.append_array(SaColorPage.rows())
    return pages


## The tip's dab, drawn at the top of the tip page and of General, as a row
## of each page.
##
## `Kind.CUSTOM`, so the widget is `SaTipPreview` and the editor builds it
## through the factory without naming it. The value is the tool's own
## `tip_loaded`, `on_tool`, which is how the row finds the tool it draws and
## hears the loads it follows. No label, so the page draws the dab across its
## width rather than beside a name, and `in_docker` false, because the Tool
## Options docker is a column of controls and draws no dab.
##
## The Tip Image row is the door's grid, which hears the loads itself, so this
## is not handed it.
static func tip_previews() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    for page: String in [TIP_PAGE, GENERAL_PAGE]:
        var key := &"tip_preview" if page == TIP_PAGE else &"tip_preview_general"
        var spec := SaOptionSpec.make_custom(
            key,
            "",
            _build_tip_preview,
            _bind_tip_preview,
            {"on_tool": true, "property": ^"tip_loaded", "page": page, "bar": false, "in_docker": false}
        )
        out.append(spec)
    return out


## The preview's factory, the door `Kind.CUSTOM` asks for. Here rather than on
## the class, because a static function of a node's own script that builds that
## node is the shape that leaks.
static func _build_tip_preview(_spec: SaOptionSpec, write: Callable) -> Control:
    return SaTipPreview.new(write)


## Points a preview at the tool behind *value*, the tool's `tip_loaded`.
static func _bind_tip_preview(control: Control, value: Variant) -> void:
    var preview := control as SaTipPreview
    if preview != null:
        preview.follow(value)


## The Brush Tip page's rows, which [SaTipPage] declares.
static func tip_options() -> Array[SaOptionSpec]:
    return SaTipPage.rows()


func unregister(_ctx: SaContext) -> void:
    noise_conversion = null
    if maker_curve != null:
        maker_curve.detach()
        maker_curve = null
    if EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.disconnect(_on_color_picked)
    if EventBus.background_color_changed.is_connected(_on_background_color_changed):
        EventBus.background_color_changed.disconnect(_on_background_color_changed)


func _on_color_picked(color: Color) -> void:
    if brush_settings != null:
        brush_settings.color = color
    if eraser_settings != null:
        eraser_settings.color = color


## The pair's other half onto both settings, the way the pick above lands.
##
## The eraser takes it too, and not because an eraser mixes: the two resources
## are the same class and a field one of them does not answer is a branch in
## every reader of it.
func _on_background_color_changed(color: Color) -> void:
    if brush_settings != null:
        brush_settings.background_color = color
    if eraser_settings != null:
        eraser_settings.background_color = color


## The `brush_toggle_eraser` command's handler, bound at [method register] to a
## context that carries the easel and surface providers alone, because a
## command handler takes no argument of its own.
##
## Takes the tool machine of the document in front, the surface whose
## easel is `ctx.get_easel()`, the scratchpad skipped by `is_embedded`.
func _toggle_eraser(ctx: SaContext) -> bool:
    var front := ctx.get_easel()
    var machine: Variant = null
    for candidate: SaSurface in ctx.list_surfaces():
        if not candidate.is_embedded and (front == null or candidate.easel == front):
            machine = candidate.tool_machine
            break
    if machine == null:
        return false
    var active: ToolState = machine.active_tool
    # The Brush under either engine, so E erases with a noise preset as well.
    # Asked of the descriptor, the door's own class, rather than of the id.
    var descriptor: SaToolDescriptor = machine.get_descriptor(machine.active_tool_name)
    var brush := descriptor != null and (descriptor.takes_brush_engines or descriptor.is_brush_engine)
    if brush and active != null and active.has_method("toggle_eraser"):
        active.toggle_eraser()
    elif machine.registered_tools.has("eraser"):
        machine.set_active_tool("eraser")
    return true
