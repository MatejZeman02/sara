## The rows of the layers docker that belong to a ground, a layer that stores
## nothing and answers a height or is the flat Solid Colour: which ground it
## is, how high its grain stands, its two colours, how coarse a paper's grain
## is, and, for a woven canvas, its threads. A Solid Colour has one colour and
## no grain, so it shows the choice and its first swatch alone.
##
## Out of `layers_docker.gd` because these rows answer one question the rest
## of the docker never asks, what the active ground is and how it is tuned,
## and the docker's own rows are the ones every layer has. The docker hands
## the active layer over on every sync and reads nothing back.
##
## **The swap** is the Ground choice, every registered type
## `SaGeneratedLayer.grounds` finds, so a module's ground joins the list the
## way it joins the add button. A pick is `SaGeneratedLayer.swap`, one history
## step, and the paint above is never touched because a ground stores nothing.
##
## **The colours** are two swatches that open the picker, shown for any ground
## whose parameters carry a colour. The picker speaks display colour and the
## parameters are the document's space, so a swatch converts both ways the way
## a fill does. A drag is one history step, as the tooth's is.
##
## **The grain's scale** is the paper's Scale row, the width of one noise cell
## in document pixels. A ground with thread rows has its own Spacing among
## them, which is the same parameter, so the two never show together.
##
## **The weave's rows** show while the ground's parameters carry a thread
## thickness, which is the canvas and any ground a module writes to the same
## keys. Each drag is one history step, as the tooth's is.
##
## **The parts of a sheet and of a cloth** are the paper's Fibre, Felt, Felt
## Size and Laid and the canvas's Slubs, Fuzz, Crimp and Priming, each shown
## while the ground's type or the layer carries its parameter, so a paper saved
## before they existed shows them at nought, which draws what it always drew.
##
## **A preset** writes a sheet or a cloth whole, one history step, from the
## type's [member SaLayerTypeDescriptor.generator_presets]. The row names the
## preset the ground matches and reads Custom once a slider moves it off one.
##
## **The edge** is how the sheet ends beyond the page, drawn by the view and
## never over the painting: none, a cut, a deckle or a torn edge for a paper,
## and a cut or a canvas wrapped over its stretcher for a cloth.
##
## **The rows open in a dialog window, `SaGroundDialog`**, from the Ground
## button under the list, rather than in the docker's column, where a Canvas's
## seven rows would push the buttons up the moment a ground is active, or in a
## popup over the docker, which closes on any press outside it.
@tool
class_name SaGroundRows
extends VBoxContainer

## One weave row: the parameter it writes, the words on the bar, its range
## and step, the decimals shown, the unit and the history step's name.
const WEAVE_ROWS: Array[Dictionary] = [
    {
        "key": "scale",
        "label": "Spacing",
        "min": 2.0,
        "max": 48.0,
        "step": 0.5,
        "places": 1,
        "unit": " px",
        "tip": "How far apart the threads run",
        "step_name": "Canvas Spacing"
    },
    {
        "key": "thickness",
        "label": "Thickness",
        "min": 0.3,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How wide a thread is, as a share of the spacing",
        "step_name": "Canvas Thickness"
    },
    {
        "key": "irregularity",
        "label": "Irregularity",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How far the threads wander in place, width, twist and tone, so the weave never repeats",
        "step_name": "Canvas Irregularity"
    },
    {
        "key": "angle",
        "label": "Angle",
        "min": -45.0,
        "max": 45.0,
        "step": 0.5,
        "places": 1,
        "unit": "°",
        "tip": "Rotation of the weave, in degrees.",
        "step_name": "Canvas Angle"
    },
]

## The rows of a sheet's and a cloth's parts, in the shape of a weave row,
## each shown while the ground carries its key.
const PART_ROWS: Array[Dictionary] = [
    {
        "key": "fibre",
        "label": "Fibre",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How many short curling fibres show in the sheet, lighter and darker than the pulp",
        "step_name": "Paper Fibre"
    },
    {
        "key": "felt",
        "label": "Felt",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How deep the cells the felt pressed into a cold pressed or rough sheet stand",
        "step_name": "Paper Felt"
    },
    {
        "key": "felt_size",
        "label": "Felt Size",
        "min": 4.0,
        "max": 64.0,
        "step": 0.5,
        "places": 1,
        "unit": " px",
        "tip": "How wide one cell of the felt is",
        "step_name": "Paper Felt Size"
    },
    {
        "key": "laid",
        "label": "Laid Lines",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How strongly the ribbed lines of a laid sheet show",
        "step_name": "Paper Laid Lines"
    },
    {
        "key": "slub",
        "label": "Slubs",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How often and how far a thread swells into a thicker lump",
        "step_name": "Canvas Slubs"
    },
    {
        "key": "fuzz",
        "label": "Fuzz",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How many loose fibres stand off the threads and cross the gaps",
        "step_name": "Canvas Fuzz"
    },
    {
        "key": "crimp",
        "label": "Crimp",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How far a thread bends over and under the threads it crosses",
        "step_name": "Canvas Crimp"
    },
    {
        "key": "priming",
        "label": "Priming",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "places": 2,
        "unit": "",
        "tip": "How much primer fills the hollows of the weave, none for raw linen",
        "step_name": "Canvas Priming"
    },
]

## The edges by the number the ground's `edge` holds, with the words on the
## row, for a sheet and for a cloth.
const PAPER_EDGES: Array[Dictionary] = [
    {"id": 0, "label": "None"},
    {"id": 1, "label": "Cut"},
    {"id": 2, "label": "Deckle"},
    {"id": 3, "label": "Torn"},
]
const CLOTH_EDGES: Array[Dictionary] = [
    {"id": 0, "label": "None"},
    {"id": 1, "label": "Cut"},
    {"id": 4, "label": "Wrapped"},
]

## The parameter the edge row writes.
const PARAM_EDGE := "edge"

## The swatch rows' parameters, the words on them and the history step each
## drag is named for.
const COLOR_ROWS: Array[Dictionary] = [
    {
        "key": "color",
        "title": "First",
        "tip": "The ground's first colour: a paper's where the grain is low, a canvas's threads",
        "step_name": "Ground Colour"
    },
    {
        "key": "second",
        "title": "Second",
        "tip": "The ground's second colour: a paper's where the grain stands, a canvas's gaps",
        "step_name": "Ground Second Colour"
    },
]

## The paper's scale row, in the shape of a weave row. A cell is two pixels at
## the least, below which the grain is a shimmer rather than a texture, and a
## quarter of a thousand at the most, a cloud a document hardly holds twice.
const SCALE_ROW: Dictionary = {
    "key": "scale",
    "label": "Scale",
    "min": 2.0,
    "max": 256.0,
    "step": 1.0,
    "places": 0,
    "unit": " px",
    "tip": "How wide one cell of the grain is, so a bigger number is a coarser paper",
    "step_name": "Ground Scale"
}

## Which ground the active layer is, shown while more than one is registered.
var ground_choice: SaChoiceButton
## The height of the active ground's grain, the paper's tooth and the
## canvas's threads alike.
var tooth_slider: FactorSlider
## The paper's grain scale, the one row of a ground without threads that
## writes `scale`.
var scale_slider: FactorSlider
## The ground's presets, shown while its type has any.
var preset_choice: SaChoiceButton
## How the sheet ends beyond the page.
var edge_choice: SaChoiceButton
## The sliders of a sheet's and a cloth's parts, by the parameter each writes.
var part_sliders: Dictionary = {}
## The two colour swatches, by the parameter each writes.
var swatches: Dictionary = {}
## The weave's sliders, by the parameter each writes.
var weave_sliders: Dictionary = {}

var _document: SaDocument = null
var _layer: SaLayer = null
var _registry: SaLayerTypeRegistry = null
var _syncing: bool = false


func _init() -> void:
    name = "GroundRows"
    add_theme_constant_override("separation", SaUI.px(SaUI.BASE_SEPARATOR))
    var choice_box := SaMake.row(self, "GroundBox")
    ground_choice = SaMake.choice(choice_box, "GroundChoice")
    ground_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ground_choice.tooltip_text = tr("The ground under the painting, swapped in one step with the paint above untouched.")
    ground_choice.choice_picked.connect(_on_ground_picked)

    var preset_box := SaMake.row(self, "PresetBox")
    SaMake.label(preset_box, "PresetLabel", tr("Preset:"))
    preset_choice = SaMake.choice(preset_box, "PresetChoice")
    preset_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preset_choice.tooltip_text = tr("A sheet or a cloth set whole in one step: its colours, grain and tooth.")
    preset_choice.choice_picked.connect(_on_preset_picked)

    tooth_slider = _slider("ToothBox", "ToothSlider", 0.0, SaGeneratedLayer.TOOTH_MAX, 0.01, 2)
    tooth_slider.prefix = tr("Tooth") + ": "
    tooth_slider.suffix = " mm"
    tooth_slider.tooltip_text = tr("How high the ground's grain stands: thin paint shows it, thick paint buries it.")
    tooth_slider.value_changed.connect(_on_tooth_changed)

    var scale_row := SCALE_ROW
    scale_slider = _slider(
        "GrainScaleBox", "GrainScaleSlider", scale_row["min"], scale_row["max"], scale_row["step"], scale_row["places"]
    )
    scale_slider.prefix = tr(scale_row["label"]) + ": "
    scale_slider.suffix = scale_row["unit"]
    scale_slider.tooltip_text = tr(scale_row["tip"])
    scale_slider.value_changed.connect(_on_weave_changed.bind(scale_row))

    var colour_box := SaMake.row(self, "ColourBox")
    SaMake.label(colour_box, "ColourLabel", tr("Colours") + ":")
    for row: Dictionary in COLOR_ROWS:
        var swatch := ColorPickerButton.new()
        swatch.name = String(row["title"]) + "Swatch"
        swatch.edit_alpha = false
        swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        swatch.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
        swatch.tooltip_text = tr(row["tip"])
        swatch.color_changed.connect(_on_swatch_changed.bind(row))
        # The engine opens its picker in a transparent window, and nothing of
        # the docker behind may read through it. The ground is the shared
        # theme's `PopupPanel` box.
        var popup := swatch.get_popup()
        popup.transparent = false
        popup.transparent_bg = false
        colour_box.add_child(swatch)
        swatches[row["key"]] = swatch

    for row: Dictionary in WEAVE_ROWS + PART_ROWS:
        var key: String = row["key"]
        var title := key.capitalize().replace(" ", "")
        var bar := _slider(title + "Box", title + "Slider", row["min"], row["max"], row["step"], row["places"])
        bar.prefix = tr(row["label"]) + ": "
        bar.suffix = row["unit"]
        bar.tooltip_text = tr(row["tip"])
        bar.value_changed.connect(_on_weave_changed.bind(row))
        if row in WEAVE_ROWS:
            weave_sliders[key] = bar
        else:
            part_sliders[key] = bar

    var edge_box := SaMake.row(self, "EdgeBox")
    SaMake.label(edge_box, "EdgeLabel", tr("Edge:"))
    edge_choice = SaMake.choice(edge_box, "EdgeChoice")
    edge_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    edge_choice.tooltip_text = tr("How the sheet ends beyond the page. The painting itself is never cut.")
    edge_choice.choice_picked.connect(_on_edge_picked)
    visible = false


func _slider(box_name: String, node_name: String, low: float, high: float, step: float, places: int) -> FactorSlider:
    var box := SaMake.row(self, box_name)
    var bar := SaMake.slider(box, node_name, low, high, step, low)
    bar.decimal_places = places
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    return bar


## Shows the rows for *layer* of *document*, or hides them all when it is not
## a ground. *registry* names the grounds the choice offers, and a host with
## none shows the rows the layer's own parameters carry and no choice.
func show_layer(document: SaDocument, layer: SaLayer, registry: SaLayerTypeRegistry) -> void:
    _document = document
    _layer = layer
    _registry = registry
    visible = layer != null and is_ground(layer, registry)
    if not visible:
        return
    _syncing = true
    var grounds := SaGeneratedLayer.grounds(registry)
    var choices: Array = []
    for descriptor: SaLayerTypeDescriptor in grounds:
        choices.append({"id": descriptor.id, "label": tr(descriptor.display_name)})
    ground_choice.get_parent().visible = choices.size() > 1
    if choices.size() > 1:
        ground_choice.set_choices(choices)
        ground_choice.select_value(layer.layer_type)
    tooth_slider.get_parent().visible = layer.generator_params.has(SaGeneratedLayer.PARAM_TOOTH)
    tooth_slider.set_value_no_signal(SaGeneratedLayer.tooth_of(layer))
    var woven := layer.generator_params.has(SaGeneratedLayer.PARAM_THICKNESS)
    scale_slider.get_parent().visible = not woven and layer.generator_params.has(SaGeneratedLayer.PARAM_SCALE)
    if scale_slider.get_parent().visible:
        scale_slider.set_value_no_signal(float(layer.generator_params[SaGeneratedLayer.PARAM_SCALE]))
    _show_swatches(layer)
    _show_parts(layer, woven)
    for key: String in weave_sliders:
        var bar: FactorSlider = weave_sliders[key]
        bar.get_parent().visible = woven
        if woven:
            bar.set_value_no_signal(float(layer.generator_params.get(key, bar.min_value)))
    _syncing = false


## Shows the preset row, the part sliders and the edge row for *layer*, a
## cloth when *woven*.
func _show_parts(layer: SaLayer, woven: bool) -> void:
    var presets := _presets()
    preset_choice.get_parent().visible = not presets.is_empty()
    if not presets.is_empty():
        var choices: Array = []
        for index in presets.size():
            choices.append({"id": index, "label": tr(String(presets[index]["name"]))})
        preset_choice.set_choices(choices)
        var matched := _matching_preset(layer, presets)
        if matched < 0:
            preset_choice.clear_choice(tr("Custom"))
        else:
            preset_choice.select_value(matched)
    for key: String in part_sliders:
        var bar: FactorSlider = part_sliders[key]
        bar.get_parent().visible = _carries(layer, key)
        if bar.get_parent().visible:
            bar.set_value_no_signal(SaTyped.float_at(layer.generator_params, key, 0.0))
    edge_choice.get_parent().visible = _carries(layer, PARAM_EDGE)
    if edge_choice.get_parent().visible:
        var choices: Array = []
        for edge: Dictionary in CLOTH_EDGES if woven else PAPER_EDGES:
            choices.append({"id": edge["id"], "label": tr(String(edge["label"]))})
        edge_choice.set_choices(choices)
        if not edge_choice.select_value(roundi(SaTyped.float_at(layer.generator_params, PARAM_EDGE, 0.0))):
            edge_choice.select_value(0)


## The presets of the shown ground's type, empty in a host with no registry.
func _presets() -> Array[Dictionary]:
    if _registry == null or _layer == null:
        return []
    var descriptor := _registry.get_descriptor(_layer.layer_type)
    return descriptor.generator_presets if descriptor != null else ([] as Array[Dictionary])


## Whether *layer* or its type carries the parameter *key*.
func _carries(layer: SaLayer, key: String) -> bool:
    if layer.generator_params.has(key):
        return true
    var descriptor := _registry.get_descriptor(layer.layer_type) if _registry != null else null
    return descriptor != null and descriptor.generator_defaults.has(key)


## The index of the preset whose every number *layer* holds, colours aside,
## since a colour the painter toned stays the preset's sheet, or -1.
func _matching_preset(layer: SaLayer, presets: Array[Dictionary]) -> int:
    for index in presets.size():
        var wanted: Dictionary = presets[index]["params"]
        var matches := true
        for key: String in wanted:
            var value: Variant = wanted[key]
            if value is Color:
                continue
            if not is_equal_approx(SaTyped.float_at(layer.generator_params, key, 0.0), float(value)):
                matches = false
                break
        if matches:
            return index
    return -1


## Shows the swatches in the colours *layer* holds, as the picker would show
## them, or hides the row when the layer carries no colour at all.
func _show_swatches(layer: SaLayer) -> void:
    var params := layer.generator_params
    var first: Color = params.get(SaGeneratedLayer.PARAM_COLOR, Color(0.5, 0.5, 0.5, 1.0))
    var space := _document.color_space if _document != null else null
    swatches["color"].get_parent().visible = params.has(SaGeneratedLayer.PARAM_COLOR)
    var grained := params.has(SaGeneratedLayer.PARAM_TOOTH)
    swatches["second"].visible = grained or params.has(SaGeneratedLayer.PARAM_SECOND)
    for key: String in swatches:
        var stored: Color = params.get(key, first)
        var swatch: ColorPickerButton = swatches[key]
        swatch.color = space.to_display(stored) if space != null else stored


## Whether *layer* is a ground, `SaGeneratedLayer.is_ground_kind` of its
## descriptor when *registry* is bound, and from its own parameters and type
## in a host without one. The Ground button asks it too, to dim itself on any
## other layer.
static func is_ground(layer: SaLayer, registry: SaLayerTypeRegistry) -> bool:
    if layer == null or not layer.is_generated():
        return false
    if registry == null:
        return layer.generator_params.has(SaGeneratedLayer.PARAM_TOOTH) or layer.layer_type == SaGeneratedLayer.SOLID
    return SaGeneratedLayer.is_ground_kind(registry.get_descriptor(layer.layer_type))


## The ground the dialog and the Ground button stand for: the active layer when
## it is a ground, and otherwise the uppermost ground of *document*, so the
## settings stay in reach while the painter works on a paint layer above it.
## Null when the document has no ground at all.
static func ground_of(document: SaDocument, registry: SaLayerTypeRegistry) -> SaLayer:
    if document == null:
        return null
    if is_ground(document.active_layer, registry):
        return document.active_layer
    var found: SaLayer = null
    for layer: SaLayer in SaLayerOps.new(document).layers():
        if is_ground(layer, registry):
            found = layer
    return found


## Keeps the ground's colours where the new kind has a colour of the same name,
## as the Layer menu's Ground row does, so trying another ground in the dialog
## never throws away the tone the painter gave this one.
func _on_ground_picked(value: Variant) -> void:
    if _syncing or _registry == null or _layer == null:
        return
    SaGeneratedLayer.swap(_document, _layer, _registry.get_descriptor(value), _registry, true)


func _on_preset_picked(value: Variant) -> void:
    var presets := _presets()
    if _syncing or _layer == null or int(value) < 0 or int(value) >= presets.size():
        return
    SaGeneratedLayer.apply_preset(_document, _layer, presets[int(value)])


func _on_edge_picked(value: Variant) -> void:
    if not _syncing:
        SaGeneratedLayer.set_param(_document, _layer, PARAM_EDGE, float(value), "Ground Edge")


func _on_tooth_changed(value: float) -> void:
    if not _syncing:
        SaGeneratedLayer.set_tooth(_document, _layer, value)


func _on_swatch_changed(picked: Color, row: Dictionary) -> void:
    if _syncing or _document == null or _layer == null:
        return
    var space := _document.color_space
    var stored := space.from_display(picked) if space != null else picked
    SaGeneratedLayer.set_color(_document, _layer, row["key"], stored, row["step_name"])


func _on_weave_changed(value: float, row: Dictionary) -> void:
    if _syncing:
        return
    var clamped := clampf(value, float(row["min"]), float(row["max"]))
    SaGeneratedLayer.set_param(_document, _layer, row["key"], clamped, row["step_name"])
