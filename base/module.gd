## Sara's built-in tools.
##
## One repository, two modules: this is `base/`, the tools, and `stamp-brush/`
## beside it is the engine. The repository is the submodule, a module is a
## folder inside it holding a `module.gd`, and `ModuleLoader` reads both
## shapes.
##
## It describes tools rather than instantiating them, and the registry creates
## one instance per surface, which is what makes the info docker's scratchpad
## work without a duplicated registration block.
extends SaModule

# The fill's settings resource lives with the brush now, and this is the one
# path in this repository that crosses from one module to the other.
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const StatePanScript = preload("res://modules/sara-base-modules/base/tools/state_pan.gd")
const StateZoomScript = preload("res://modules/sara-base-modules/base/tools/state_zoom.gd")
const StateMarqueeScript = preload("res://modules/sara-base-modules/base/tools/state_marquee.gd")
const StateEllipseSelectScript = preload("res://modules/sara-base-modules/base/tools/state_ellipse_select.gd")
const StateLassoScript = preload("res://modules/sara-base-modules/base/tools/state_lasso.gd")
const StatePolygonalLassoScript = preload("res://modules/sara-base-modules/base/tools/state_polygonal_lasso.gd")
const StateWandScript = preload("res://modules/sara-base-modules/base/wand/state_wand.gd")
const StateMagneticLassoScript = preload("res://modules/sara-base-modules/base/magnetic/state_magnetic_lasso.gd")
const SaMagneticOptions = preload("res://modules/sara-base-modules/base/magnetic/sa_magnetic_options.gd")
const StatePatchScript = preload("res://modules/sara-base-modules/base/patch/state_patch.gd")
const StateGradientScript = preload("res://modules/sara-base-modules/base/gradient/state_gradient.gd")
const StateCropScript = preload("res://modules/sara-base-modules/base/tools/state_crop.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")
## The two engines registered under a role in `register`.
const SaWandScript = preload("res://modules/sara-base-modules/base/wand/sa_wand.gd")
const SaGradientScript = preload("res://modules/sara-base-modules/base/gradient/sa_gradient.gd")
const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")
## The transform tool's engine, which lives beside its tool.
const SaTransformScript = preload("res://modules/sara-base-modules/base/transform/sa_transform.gd")
## Liquify, an engine of the Brush in a feature folder of its own, reached through its facade.
const SaLiquifyScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify.gd")
## The filters and the Filter menu's sections, registered from a class of their own.
const FilterRegistrations = preload("res://modules/sara-base-modules/base/filter_registrations.gd")
## Invert on Ctrl+I, the mask or the layer, registered after the filter it bakes.
const InvertCommand = preload("res://modules/sara-base-modules/base/invert_command.gd")
const SaColorize = preload("res://modules/sara-base-modules/base/colorize/sa_colorize.gd")
const SaColorizeDocker = preload("res://modules/sara-base-modules/base/colorize/sa_colorize_docker.gd")

## The fill's own copy of the brush settings, kept only for what still reads it.
##
## **The fill itself does not**: it paints `SaColors.foreground`, the way the
## Edit menu's own fill command does, so a colour picked any way at all reaches
## it. The resource stays because `EventBus.color_picked` writes `settings.color`
## through it and that connection is this module's to undo in `unregister`.
var fill_settings: Resource = null

## The Colourise layer's facade, which its resolve hook, its Auto updates and
## its docker share.
var colorize: SaColorize = null


func get_id() -> StringName:
    return &"sara-base-modules"


func get_name() -> String:
    return "Sara Base Tools"


func register(ctx: SaContext) -> void:
    fill_settings = BrushSettingsScript.new()

    var fill := SaToolDescriptor.create(&"bucket_fill", StateBucketFillScript)
    fill.display_name = "Fill"
    fill.icon_name = "bucket"
    fill.category = &"paint"
    fill.toolbox_group = &"fill"
    fill.is_painting = true
    fill.cursor_shape = Control.CURSOR_POINTING_HAND
    fill.activate_action = &"tool_bucket_fill"
    fill.preset_engine = BrushSettingsScript.PRESET_ENGINE
    fill.options = fill_options()
    ctx.register_tool(fill)

    var gradient := SaToolDescriptor.create(&"gradient", StateGradientScript)
    gradient.display_name = "Gradient"
    gradient.icon_name = "gradient"
    gradient.category = &"paint"
    gradient.toolbox_group = &"fill"
    gradient.is_painting = true
    gradient.cursor_shape = Control.CURSOR_CROSS
    gradient.activate_action = &"tool_gradient"
    # One end rule for every surface's gradient and for the ramp row, and it
    # keeps the remembered alphas in this module's own preferences.
    var ends := SaGradientEnds.new(ctx)
    gradient.shared_settings = ends
    gradient.options = gradient_options(ends)
    ctx.register_tool(gradient)

    var crop := SaToolDescriptor.create(&"crop", StateCropScript)
    crop.display_name = "Crop"
    crop.icon_name = "crop"
    crop.category = &"transform"
    crop.cursor_shape = Control.CURSOR_CROSS
    crop.activate_action = &"tool_crop"
    # A detour from painting, as the Transform, the Eyedropper, Pan, Zoom and
    # the four selection tools below are: its chord pressed again goes back to
    # the tool before it. The Fill and the Gradient above are not, because a
    # painter goes back to them, as to the Brush.
    crop.is_detour = true
    crop.options = crop_options()
    ctx.register_tool(crop)

    var transform := SaToolDescriptor.create(&"transform", StateTransformScript)
    transform.display_name = "Transform"
    transform.icon_name = "transform"
    transform.category = &"transform"
    transform.cursor_shape = Control.CURSOR_MOVE
    transform.activate_action = &"tool_transform"
    transform.is_detour = true
    # Ctrl and an edge handle shears, so Ctrl holds no Eyedropper over the box.
    transform.reads_keys = [KEY_CTRL]
    transform.options = transform_options()
    ctx.register_tool(transform)
    StateTransformScript.SaTransformShapeScript.register(ctx)
    SaLiquifyScript.register(ctx)

    var eyedropper := SaToolDescriptor.create(&"eyedropper", StateEyedropperScript)
    eyedropper.display_name = "Eyedropper"
    eyedropper.icon_name = "colorpick"
    eyedropper.category = &"sample"
    # A cross, not CURSOR_HELP. A question mark reads as "the app does not know
    # what this tool is", and a sampler points at one pixel, which is what
    # every other picking tool here shows.
    eyedropper.cursor_shape = Control.CURSOR_CROSS
    # And a picture over the crosshair, which is the fallback rather than the
    # answer: a `Control.CursorShape` is one of Godot's stock arrows and cannot
    # carry a drawing, and the descriptor can. The hotspot is the tip at the
    # bottom left of `colorpick.svg`, in fractions of the picture, because the
    # cursor is resized to the display's own size and pixels would drift off the tip.
    eyedropper.cursor_texture = SaUI.get_icon("colorpick")
    eyedropper.cursor_hotspot = Vector2(0.25, 0.75)
    eyedropper.activate_action = &"tool_eyedropper"
    eyedropper.is_detour = true
    eyedropper.picks_colour = true
    eyedropper.quick_action = &"tool_eyedropper_quick"
    eyedropper.quick_priority = 10
    eyedropper.options = eyedropper_options()
    ctx.register_tool(eyedropper)
    # Every surface's eyedropper keeps its Sample choice in this module's own
    # preferences, so the painter's choice outlives the session.
    StateEyedropperScript.keep_choice_in(ctx)

    # Navigation tools outrank the eyedropper when several modifiers are held:
    # Ctrl+Space is zoom even though Space alone is pan.
    var pan := SaToolDescriptor.create(&"pan", StatePanScript)
    pan.display_name = "Pan"
    pan.icon_name = "toolpan"
    pan.category = &"navigate"
    pan.cursor_shape = Control.CURSOR_POINTING_HAND
    pan.activate_action = &"tool_pan"
    pan.is_detour = true
    pan.quick_action = &"tool_pan_quick"
    pan.quick_priority = 20
    pan.turns_view_on_shift_drag = true
    ctx.register_tool(pan)

    var zoom := SaToolDescriptor.create(&"zoom", StateZoomScript)
    zoom.display_name = "Zoom"
    zoom.icon_name = "zoom"
    zoom.category = &"navigate"
    zoom.cursor_shape = Control.CURSOR_VSIZE
    zoom.activate_action = &"tool_zoom"
    zoom.is_detour = true
    zoom.quick_action = &"tool_zoom_quick"
    zoom.quick_priority = 30
    zoom.options = StateZoomScript.options()
    ctx.register_tool(zoom)

    # The selection tools, after the navigation pair so the toolbox keeps
    # its order for anyone used to it.
    var marquee := SaToolDescriptor.create(&"marquee", StateMarqueeScript)
    marquee.display_name = "Marquee"
    marquee.icon_name = "marquee"
    marquee.category = &"select"
    marquee.toolbox_group = &"select"
    marquee.cursor_shape = Control.CURSOR_CROSS
    marquee.activate_action = &"tool_marquee"
    marquee.is_detour = true
    marquee.reads_keys = [KEY_SHIFT, KEY_ALT]
    marquee.options = marquee_options()
    ctx.register_tool(marquee)

    # The ellipse beside the rectangle, a tool of its own as Krita's is, so the
    # toolbox's selection group shows it where a painter looks for it.
    var ellipse := SaToolDescriptor.create(&"ellipse_select", StateEllipseSelectScript)
    ellipse.display_name = "Ellipse Select"
    ellipse.icon_name = "ellipse_select"
    ellipse.category = &"select"
    ellipse.toolbox_group = &"select"
    ellipse.cursor_shape = Control.CURSOR_CROSS
    ellipse.activate_action = &"tool_ellipse_select"
    ellipse.is_detour = true
    ellipse.reads_keys = [KEY_SHIFT, KEY_ALT]
    ellipse.options = ellipse_options()
    ctx.register_tool(ellipse)

    var lasso := SaToolDescriptor.create(&"lasso", StateLassoScript)
    lasso.display_name = "Lasso"
    lasso.icon_name = "lasso"
    lasso.category = &"select"
    lasso.toolbox_group = &"lasso"
    lasso.cursor_shape = Control.CURSOR_CROSS
    lasso.activate_action = &"tool_lasso"
    lasso.is_detour = true
    lasso.reads_keys = [KEY_SHIFT, KEY_ALT]
    lasso.options = lasso_options()
    ctx.register_tool(lasso)

    # The polygon beside the freehand outline, a tool of its own as Krita's and
    # Photoshop's are, with the lasso's rows and their keys, so the
    # Anti-aliasing and the mode the painter set are one setting for both. The
    # three lassos share a button, so Shift with L steps through them.
    var polygonal := SaToolDescriptor.create(&"polygonal_lasso", StatePolygonalLassoScript)
    polygonal.display_name = "Polygonal Lasso"
    polygonal.icon_name = "polygonal_lasso"
    polygonal.category = &"select"
    polygonal.toolbox_group = &"lasso"
    polygonal.cursor_shape = Control.CURSOR_CROSS
    polygonal.activate_action = &"tool_polygonal_lasso"
    polygonal.is_detour = true
    polygonal.reads_keys = [KEY_SHIFT, KEY_ALT]
    polygonal.options = lasso_options()
    ctx.register_tool(polygonal)

    # The trace that clings to an edge, the third lasso, with its own rows
    # before the lassos' shared three. Its icon lives with the tool.
    var magnetic := SaToolDescriptor.create(&"magnetic_lasso", StateMagneticLassoScript)
    magnetic.display_name = "Magnetic Lasso"
    magnetic.icon_name = "res://modules/sara-base-modules/base/magnetic/magnetic_lasso.svg"
    magnetic.category = &"select"
    magnetic.toolbox_group = &"lasso"
    magnetic.cursor_shape = Control.CURSOR_CROSS
    magnetic.is_detour = true
    magnetic.reads_keys = [KEY_SHIFT, KEY_ALT]
    var magnetic_rows := SaMagneticOptions.rows()
    magnetic_rows.append_array(lasso_options())
    magnetic.options = magnetic_rows
    ctx.register_tool(magnetic)

    var wand := SaToolDescriptor.create(&"wand", StateWandScript)
    wand.display_name = "Magic Wand"
    wand.icon_name = "wand"
    wand.category = &"select"
    # Named so a module's subject and object selection tools can join it by
    # naming the same group, which makes Shift with W step through them.
    wand.toolbox_group = &"wand"
    wand.cursor_shape = Control.CURSOR_CROSS
    wand.activate_action = &"tool_wand"
    wand.is_detour = true
    wand.reads_keys = [KEY_SHIFT, KEY_ALT]
    wand.options = wand_options()
    ctx.register_tool(wand)

    # Last in the selection group: it acts on a selection the other three made
    # rather than making one, so it reads as the thing to do next.
    var patch := SaToolDescriptor.create(&"patch", StatePatchScript)
    patch.display_name = "Patch"
    patch.icon_name = "patch"
    patch.category = &"select"
    patch.cursor_shape = Control.CURSOR_CROSS
    # A circle under the pointer, which is the software ring every painting
    # tool draws, sized by the tool's own Size row. Without `is_painting`
    # beside it, deliberately: that flag is what puts the whole brush group on
    # the top bar and what blocks a tool mid-stroke, and the patch is neither a
    # brush nor blocked.
    patch.wants_brush_cursor = true
    # J, Photoshop's key for the healing group. The row in `project.godot` and
    # the Photoshop default are the app's, this is only the tool naming the
    # action, as the Marquee does.
    patch.activate_action = &"tool_patch"
    patch.options = patch_options()
    ctx.register_tool(patch)

    # The engines live beside their tools, under the roles the skeleton asks
    # for: the capture's wand step asks `flood`, and the gradient tool asks
    # `gradient` the way the crop tool asks `crop`, so another module's
    # subclass replaces any of them.
    ctx.register_role(&"flood", SaWandScript)
    ctx.register_role(&"gradient", SaGradientScript)
    ctx.register_role(&"patch", SaPatchScript)
    ctx.register_role(&"transform", SaTransformScript)
    ctx.register_role(&"color_ramp_control", SaColorRampControl)  # the ramp editor, for a row of another module

    # Hard rule 6, for the Filter menu: the adjustments come through the door a
    # stranger's filter uses. The class holds the list, so a filter added later
    # is a line there and not here, and it skips a context with no filter registry.
    FilterRegistrations.register(ctx)
    InvertCommand.register(ctx)
    SaAssistants.register(ctx)

    # The Colourise layer through the door a stranger's layer type takes, and
    # its docker, handed the one facade so an update from either is the same.
    colorize = SaColorize.new(ctx)
    ctx.register_layer_type(colorize.descriptor())
    var facade := colorize
    ctx.register_docker(
        SaColorizeDocker.DOCKER_ID,
        "Colourise",
        func() -> Window: return SaColorizeDocker.new(facade),
        &"",
        SaColorizeDocker.SENTENCE
    )

    # Hard rule 6 for a simulation: Spread, the first rule, through the call a
    # stranger's rule makes. Each step a cell takes a weighted average of itself
    # and its four neighbours, so its reach is one texel, and `flow` is what it
    # gives each neighbour.
    ctx.register_simulation_rule(&"spread", "Spread", "sara-base-modules/spread", "spread", 1, {"flow": 0.2})
    # And Life, its kernel in `simulation/`: a cell reads its eight neighbours,
    # a reach of one, and the counts it is born and lives on are Conway's, B3/S23,
    # written as the rulestring's digits.
    ctx.register_simulation_rule(&"life", "Life", "sara-base-modules/life", "life", 1, {"birth": 3, "survival": 23})
    # And Gray-Scott, its kernels in `simulation/`, the first rule whose state
    # is not a colour: a substrate and a catalyst in a field of its own, which
    # the layer's schema carries while the rule is on it, seeded from the
    # paint's cover and coloured into `albedo` by a ramp from the painted
    # colour. Karl Sims's rates for spots that split are the defaults.
    var gray_scott_rates := {"feed": 0.0367, "kill": 0.0649, "diffusion_u": 1.0, "diffusion_v": 0.5}
    var gray_scott_field := {
        "field": SaFieldSpec.create(&"gray_scott", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false),
        "shader": "sara-base-modules/gray_scott_colour",
        "seed": "gray_scott_seed",
        "colour": "gray_scott_colour",
    }
    ctx.register_simulation_rule(
        &"gray_scott", "Gray-Scott", "sara-base-modules/gray_scott", "gray_scott", 1, gray_scott_rates, gray_scott_field
    )

    if not EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.connect(_on_color_picked)


## The gradient's rows, which [SaGradientOptions] declares beside the tool.
static func gradient_options(ends: SaGradientEnds = null) -> Array[SaOptionSpec]:
    return SaGradientOptions.rows(ends)


## The crop's three rows: what the crop takes, the ratio the drag is locked to
## and the button that does it. The rectangle itself is the drag, and Enter
## reaches the same method, so the button is for a painter who would rather
## click than remember a key. The Crop row is the document keeping what
## falls outside, the document deleting it, or the active layer alone, and it
## is saved as a preference of the tool as the ratio is.
static func crop_options() -> Array[SaOptionSpec]:
    var apply := SaOptionSpec.make(
        &"crop_apply",
        "Crop",
        SaOptionSpec.Kind.ACTION,
        {
            "on_tool": true,
            "property": ^"crop_now",
            "bar": false,
            "tooltip": "Crop to the rectangle, as the Crop row above says. Enter does the same, and Escape drops the rectangle."
        }
    )
    var modes := StateCropScript.Mode
    var takes := (
        SaOptionSpec
        . make_enum(
            &"crop_mode",
            "Crop",
            [modes.LAYER, modes.CANVAS, modes.CANVAS_DELETE],
            ["Layer", "Canvas", "Canvas and Delete Outside"],
            {
                "on_tool": true,
                "property": ^"mode",
                "width": 110,
                # Off the bar for the reason the ratio below is.
                "bar": false,
                "tooltip":
                (
                    "Canvas crops the document and keeps what falls outside in the layers, for Canvas Size to show again. "
                    + "Canvas and Delete Outside deletes it. Layer crops the active layer only."
                )
            }
        )
    )
    # The ids are the tool's own Ratio enum rather than the numbers, so a
    # ratio added there appears here by name and neither list can drift from
    # the other. Read inside the function because a const holding another
    # class's enum is not a constant expression.
    var shapes := StateCropScript.Ratio
    var ids: Array = [
        shapes.FREE,
        shapes.DOCUMENT,
        shapes.SQUARE,
        shapes.R3_2,
        shapes.R2_3,
        shapes.R4_3,
        shapes.R3_4,
        shapes.R16_9,
        shapes.R9_16,
    ]
    var labels: Array = ["Free", "Document", "1:1", "3:2", "2:3", "4:3", "3:4", "16:9", "9:16"]
    var locked := (
        SaOptionSpec
        . make_enum(
            &"crop_ratio",
            "Ratio",
            ids,
            labels,
            {
                "on_tool": true,
                "property": ^"ratio",
                "width": 110,
                # Off the bar, like the Crop button beside it. The first row is already
                # measured full at 1920, and a dropdown of this width pushes it over, which
                # `ui/top_bar/tests/test_top_bar_rows.gd` catches. The Tool Options docker and the
                # canvas right-click menu both show it.
                "bar": false,
                "tooltip": "Lock the rectangle's shape. Every drag keeps it, past the canvas edge too."
            }
        )
    )
    return [takes, locked, apply]


## The transform's rows, which [SaTransformOptions] declares.
static func transform_options() -> Array[SaOptionSpec]:
    return SaTransformOptions.rows()


## This module's own words for `SaOptionSpec.bar_group`, for the two errands
## the skeleton's three do not name: what the eyedropper reads, and what a
## selection tool makes. A word of their own rather than none, because a row
## with no group draws no break beside it, so the eyedropper's two shown after
## the stabiliser toggle would have read as two more stroke switches. The
## wand's Merged is the wand's, so it is a selection row like its tolerance.
const BAR_GROUP_SAMPLE := &"sample"
const BAR_GROUP_SELECT := &"select"


## The eyedropper's two: the square it averages and what it reads, the view
## or the active layer as painted. Both on the tool.
static func eyedropper_options() -> Array[SaOptionSpec]:
    # A slider rather than a choice list of 1, 3, 5 and 9, which the bar sizes
    # to its row and cuts to "S...". Steps of two from one keep the
    # side odd, so the picked texel is the centre, the way Krita's sample
    # radius is a slider.
    var size := (
        SaOptionSpec
        . make_float(
            &"sample_size",
            "Sample",
            float(StateEyedropperScript.MIN_SAMPLE_SIZE),
            float(StateEyedropperScript.MAX_SAMPLE_SIZE),
            2.0,
            {
                "decimals": 0,
                "suffix": "px",
                "on_tool": true,
                # These options, and every other `bar_hidden` in this file, stay off a fresh
                # bar, and `bar_hidden` is what keeps them off rather than this flag.
                # `bar = false` builds no control at all, so the Preferences > Top Menu Bar
                # row the option's key draws would have nothing to show or hide and its
                # switch would move nothing. `bar_after` puts the eyedropper's and the selection tools'
                # rows after the stabiliser toggle, one after the other, where the
                # skeleton's default order would otherwise list them.
                "bar": true,
                "bar_hidden": true,
                "bar_after": "Stabilizer Toggle",
                "bar_group": BAR_GROUP_SAMPLE,
                "width": 96,
                "tooltip": "Eyedropper: size of the square averaged under the pointer, in pixels."
            }
        )
    )
    # In place of the Merged switch the wand still has. A choice rather than a
    # tick, so that both answers to what is sampled are named, rather than one
    # of them being the absence of the other.
    # The eyedropper's own key, so the wand's Merged keeps its own control.
    var from := SaOptionSpec.make_enum(
        &"sample_from",
        "Sample",
        [StateEyedropperScript.SampleFrom.VIEW, StateEyedropperScript.SampleFrom.LAYER],
        ["View", "Layer"],
        {
            "on_tool": true,
            "bar": true,
            "bar_hidden": true,
            "bar_after": "sample_size",
            "bar_group": BAR_GROUP_SAMPLE,
            "width": 64,
            "tooltip":
            (
                "Eyedropper: View picks the colour the picture shows, every filter applied. "
                + "Layer picks the active layer as it was painted."
            )
        }
    )
    return [size, from]


## The mode both selection tools share, so the bar shows one dropdown that
## follows whichever is active.
##
## *held* is the sentence the marquee and Ellipse Select add, on what Shift held
## after the press does to their drag, empty for the lasso and
## the wand, whose drags have no box to hold square.
static func selection_mode_option(held: String = "") -> SaOptionSpec:
    var option := (
        SaOptionSpec
        . make_enum(
            &"selection_mode",
            "Selection",
            [SaSelection.Mode.REPLACE, SaSelection.Mode.ADD, SaSelection.Mode.SUBTRACT, SaSelection.Mode.INTERSECT],
            ["Replace", "Add", "Subtract", "Intersect"],
            {
                "on_tool": true,
                "property": ^"mode",
                "width": 84,
                # Hidden on a fresh bar rather than unbuilt.
                "bar": true,
                "bar_hidden": true,
                "bar_after": "sample_merged",
                "bar_group": BAR_GROUP_SELECT,
                "tooltip":
                (
                    "What the next shape does to the selection. Shift adds, Alt subtracts and both intersect while dragging. "
                    + "In Replace, dragging inside a selection with Marquee or Ellipse Select moves its outline. Deselect first, "
                    + "or hold Shift, to start a new shape inside an old one."
                    + held
                )
            }
        )
    )
    return option


## The edge the selection tools soften as a shape lands. Separate from the
## Select menu's Feather, which acts on a selection that already exists: this
## one is part of making the selection, which is why it lives on the tool and
## shows in the Tool Options docker.
##
## Stored as a fraction of the canvas's smaller dimension and shown as pixels
## of the current document, the way the brush's Size is, so a document
## upgraded from 1920 to 3840 keeps the softness the painter chose. The value
## itself is `SaSettings.selection_feather`, which the three selection tools
## read and write, so it also survives a restart.
##
## Nothing a painter can open says what feather is, so the tooltip below
## carries the meaning on its own.
static func selection_feather_option() -> SaOptionSpec:
    var option := (
        SaOptionSpec
        . make_float(
            &"feather",
            "Feather",
            0.0,
            SaSettings.MAX_SELECTION_FEATHER,
            FEATHER_STEP,
            {
                "on_tool": true,
                "scale_by_canvas": true,
                "decimals": 0,
                "suffix": "px",
                "width": 96,
                "bar": false,
                # The row says what feather is before it says what the number does. "How
                # far the edge is softened" assumed the painter already knew that a
                # feathered selection is one paint fades across rather than stops at.
                "tooltip":
                (
                    "Feather fades the edge of the shape you draw instead of cutting it off, so paint across that edge "
                    + "lands at part strength. This is how wide the fade is, in pixels of this document, and zero keeps "
                    + "the edge hard."
                )
            }
        )
    )
    return option


## One step of the Feather slider, as a fraction of the smaller dimension. A
## thousandth is about a pixel on the default document, which is the finest
## step a row that shows whole pixels can usefully offer.
const FEATHER_STEP: float = 0.001


## The marquee's rows. No shape among them: the Marquee is the rectangle and
## Ellipse Select the ellipse, so there is one place for each shape and a row
## that turned one tool into the other would be a second. No Anti-aliasing
## either, since a rectangle on whole pixels has no edge for it to grade.
static func marquee_options() -> Array[SaOptionSpec]:
    return [selection_mode_option(" Shift pressed after the press keeps the box square."), selection_feather_option()]


## The marquee's rows and the Anti-aliasing the lasso has, off the bar beside
## the Feather for the lasso's reason.
static func ellipse_options() -> Array[SaOptionSpec]:
    var anti_alias := SaOptionSpec.make(
        &"ellipse_anti_alias",
        "Anti-aliasing",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"anti_alias",
            "bar": false,
            "tooltip":
            (
                "Grade the edge by how much of each pixel the ellipse covers, so a fill inside it has no stair steps. "
                + "Off keeps every pixel wholly in or out."
            )
        }
    )
    var held := " Shift pressed after the press keeps the ellipse a circle."
    return [selection_mode_option(held), selection_feather_option(), anti_alias]


## The rows the Lasso and the Polygonal Lasso share, under the same keys. No
## shape among them: each shape is a tool, as the marquee's are.
static func lasso_options() -> Array[SaOptionSpec]:
    # Off the bar with the Feather beside it, both being how the edge comes out
    # rather than what the next drag makes.
    var anti_alias := SaOptionSpec.make(
        &"lasso_anti_alias",
        "Anti-aliasing",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"anti_alias",
            "bar": false,
            "tooltip":
            (
                "Grade the edge by how much of each pixel the outline covers, so a fill inside a slanted edge has no "
                + "stair steps. Off keeps every pixel wholly in or out."
            )
        }
    )
    return [selection_mode_option(), selection_feather_option(), anti_alias]


## The fill's five rows.
##
## Its own keys rather than the wand's, though three of them do the same job on
## the same numbers: two tools sharing an option key share the value, and a
## painter who widens the wand's tolerance to pick a sky has not asked for the
## fill to spill into it. The wand's own rows say `wand_` for the same reason.
##
## The options of the bucket fill tool, declared beside the tool itself in
## `tools/state_bucket_fill.gd` so `module.gd` stays under the thousand lines.
static func fill_options() -> Array[SaOptionSpec]:
    return StateBucketFillScript.fill_options()


## The patch's three rows: the method, the circle's size, and the button that
## patches. A click inside the selection reaches the same method the button
## does, so the row is for a painter who has a selection already and would
## rather not aim at it.
##
## Off the bar, like the Crop button the button is modelled on. The first row is
## already measured full at 1920, and `ui/top_bar/tests/test_top_bar_rows.gd` catches a row
## that pushes it over.
static func patch_options() -> Array[SaOptionSpec]:
    var method := (
        SaOptionSpec
        . make(
            &"patch_method",
            "Method",
            SaOptionSpec.Kind.ENUM,
            {
                "choices":
                [
                    {
                        "id": SaPatchScript.Method.TEXTURE,
                        "label": "Texture",
                        "tooltip":
                        "Copy patches of the picture from around the region, so a texture or an edge carries on through it",
                    },
                    {
                        "id": SaPatchScript.Method.SMOOTH,
                        "label": "Smooth",
                        "tooltip":
                        "Spread the colour round the region inwards and smooth it, the better answer on a soft gradient",
                    },
                ],
                "on_tool": true,
                "property": ^"method",
                "width": 84,
                "bar": false,
                "tooltip": "How the region is drawn again: copied from the picture's own texture, or smoothed in from its edge"
            }
        )
    )

    # The width of the tool's own circle, which is what a painter with no
    # selection drags over a blemish. Its ceiling is the widest blemish the tool
    # is for rather than a limit of either method: past a few hundred pixels the
    # Smooth fill is a smear, and the Texture fill copies from a surround as
    # wide again on each side.
    var size := SaOptionSpec.make_float(
        &"patch_size",
        "Size",
        StatePatchScript.SIZE_MIN,
        StatePatchScript.SIZE_MAX,
        1.0,
        {
            "on_tool": true,
            "property": ^"region_size",
            "decimals": 0,
            "suffix": "px",
            "bar": false,
            "tooltip": "Brush size for marking the area to fill when nothing is selected."
        }
    )

    var apply := SaOptionSpec.make(
        &"patch_apply",
        "Patch",
        SaOptionSpec.Kind.ACTION,
        {"on_tool": true, "property": ^"patch_now", "bar": false, "tooltip": "Fill the selection from its surroundings."}
    )
    return [method, size, apply]


## The wand's tolerance, whether it keeps to the region joined to the click,
## its merged toggle, and the mode it shares with the other selection tools.
static func wand_options() -> Array[SaOptionSpec]:
    var tolerance := (
        SaOptionSpec
        . make_float(
            &"wand_tolerance",
            "Tolerance",
            0.0,
            1.0,
            0.01,
            {
                "on_tool": true,
                "property": ^"tolerance",
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                # Hidden on a fresh bar rather than unbuilt.
                "bar": true,
                "bar_hidden": true,
                "bar_after": "selection_mode",
                "bar_group": BAR_GROUP_SELECT,
                "tooltip": "How far a colour may be from the clicked one, per channel, and still join the selection"
            }
        )
    )
    # Off the bar as the fill's Contiguous is, its own key for the reason the
    # fill's rows give.
    var contiguous := SaOptionSpec.make(
        &"wand_contiguous",
        "Contiguous",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"contiguous",
            "bar": false,
            "tooltip": "Select only the connected area you click. Off selects that colour wherever it is on the canvas."
        }
    )
    var merged := SaOptionSpec.make(
        &"sample_merged",
        "Sample merged",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "bar": true,
            "bar_hidden": true,
            "bar_after": "sample_from",
            "bar_group": BAR_GROUP_SELECT,
            "tooltip": "Read every layer as shown, rather than the active layer alone."
        }
    )
    return [tolerance, contiguous, merged, selection_mode_option(), selection_feather_option()]


func unregister(_ctx: SaContext) -> void:
    # The loader removes the registry entries. The signal and the eyedropper's
    # door to this module's preferences are ours to undo.
    StateEyedropperScript.keep_choice_in(null)
    SaAssistants.unregister()
    if EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.disconnect(_on_color_picked)


func _on_color_picked(color: Color) -> void:
    if fill_settings != null:
        fill_settings.color = color
