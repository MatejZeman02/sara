## The pop-up palette's brush HUD: the shown tool's Radius, Opacity and Flow as
## three sliders under the ring, so a painter moves size or opacity without
## leaving the pointer's place.
##
## Krita's pop-up palette carries a few of the brush's own sliders beside its
## ring, and this is that half of it.
##
## **The rows are the tool's own option specs, found by key.** A tool that
## declares `radius`, `opacity` or `flow` gets the row with nothing added, a
## module's tool as much as the stamp brush, and a tool without one shows the
## rows it has: the noise engine declares no Flow and shows two. Each slider
## takes its range, its words and its scale off the spec the way the options
## bar's does, so a radius reads in pixels of the document here as it does
## there.
##
## **A move writes the setting and says so on the bus**, through
## `ToolOptionControls.write_spec` and then `EventBus.tool_options_moved`, the
## path the canvas menu and the bracket keys already take, so the bar and the
## Tool Options docker read the value again. The HUD reads the tool again each
## time the palette is shown and whenever the bus says the tool or its options
## moved while it is up, so a change made elsewhere is what it shows.
##
## **Two rows, not three.** Radius takes the whole width, the slider a painter
## moves most and the one with the longest range, and Opacity and Flow share
## the row under it. Three rows would make the docker 477 tall, and the
## shipped layouts' room for it under the Info docker stops at 467 above the
## status line, so the fit would cut the palette short at the very host its
## layout was written for.
##
## Its own sliders rather than a `ToolOptionControls` of its own. That class
## builds a control for every option of every tool it is handed and counts a
## move as the bar's, the docker's or the brush editor's on the usage tally,
## where the HUD wants three sliders by key, made through `SaMake` so a scenario's
## `control` step moves them, and its moves counted as the palette's.
class_name PaletteBrushHud
extends MarginContainer

## The option keys the HUD shows, in the order it shows them.
const KEYS: Array[StringName] = [&"radius", &"opacity", &"flow"]

## What the sliders are called, by key, which is what a scenario's `control`
## step names. Prefixed, because the walker finds a control by its name across
## the whole tree and the bar has a Radius of its own.
const NAMES: Dictionary = {&"radius": "PaletteHudRadius", &"opacity": "PaletteHudOpacity", &"flow": "PaletteHudFlow"}

## The smaller side of a document, in pixels, when there is none behind the
## machine, the figure `ToolOptionControls.canvas_min_dimension` answers then, so
## a radius reads the same number on both.
const NO_DOCUMENT_SIDE: float = 1000.0

## The machine whose tool the sliders show. Null means the main canvas's, found
## each time the HUD reads the tool. A suite hands a bound machine in here,
## because a docker built in no tree has no canvas to find.
var machine: ToolMachine = null

## The three sliders, by key. Hidden for a key the shown tool does not declare.
var sliders: Dictionary = {}

## The tool the sliders show and the spec of each key it declares, as the last
## `refresh` read them, so a move writes to the tool it was read from.
var _tool: ToolState = null
var _tool_id: StringName = &""
var _specs: Dictionary = {}

## True while `refresh` puts a value on a slider, so the slider's own signal
## does not write it straight back to the tool.
var _quiet: bool = false

## The row Opacity and Flow share, hidden when the tool declares neither, so
## an empty row adds no gap under the Radius. It stands the two one over the
## other when either's words are wider than its half, see `_words_width`.
var _pair: SaTurningRow = null


func _init() -> void:
    name = "BrushHud"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_SHRINK_END
    for side: String in ["left", "right"]:
        add_theme_constant_override("margin_" + side, SaUI.px(SaTheme.PAD))
    for side: String in ["top", "bottom"]:
        add_theme_constant_override("margin_" + side, 0)
    var rows := SaMake.column(self, "Rows", SaTheme.GAP_TIGHT)
    for key: StringName in KEYS:
        var parent: Container = rows
        if key != &"radius":
            if _pair == null:
                _pair = SaMake.turning_row(rows, "OpacityAndFlow", SaTheme.GAP_TIGHT, _words_width)
            parent = _pair
        var slider := SaMake.slider(parent, NAMES[key], 0.0, 1.0, 0.01, 0.0)
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # As wide as its share of the docker, so it asks for no more than the
        # docker's floor and cuts a long text rather than widening the palette.
        # Two halves at the slider's usual 170 asked the palette 368 wide.
        slider.fits_its_text = false
        slider.preferred_width = 0
        slider.custom_minimum_size.x = 0.0
        slider.value_changed.connect(_on_moved.bind(key))
        sliders[key] = slider
    EventBus.tool_options_moved.connect(_on_tool_moved)
    EventBus.tool_changed.connect(_on_tool_switched)
    EventBus.preset_loaded.connect(_on_tool_switched)


## Reads the shown tool and its options onto the sliders: the permanent tool,
## never the held one, which is the rule the bar and the docker follow. A key
## the tool does not declare, or declares with nowhere to keep it, hides its
## row.
func refresh() -> void:
    var tools := _machine()
    _tool_id = _shown_tool_id(tools)
    _tool = tools.get_tool(_tool_id) if tools != null and not String(_tool_id).is_empty() else null
    var descriptor := tools.get_descriptor(_tool_id) if _tool != null else null
    _specs.clear()
    var side := _document_side(tools)
    _quiet = true
    for key: StringName in KEYS:
        var slider: FactorSlider = sliders[key]
        var spec := _spec_of(descriptor, key)
        var value: Variant = ToolOptionControls.read_spec(spec, _tool) if spec != null else null
        slider.visible = value != null
        if value == null:
            continue
        _specs[key] = spec
        _apply(slider, spec, side)
        slider.value = float(value)
    _pair.visible = sliders[&"opacity"].visible or sliders[&"flow"].visible
    _quiet = false
    _pair.fit()


## The width *slider*'s words draw at, through its own label's font and frame,
## the measure the label's own minimum would be if it did not trim. The pair
## turns Opacity over Flow by it, see `SaTurningRow`, side by side as English
## stands at the docker's shipped width. Read at each refresh and each resize,
## and not while a slider is dragged, so the row never jumps under the hand.
static func _words_width(slider: Control) -> float:
    var label := slider.get_node_or_null(^"Label") as Label
    if label == null:
        return 0.0
    var font := label.get_theme_font(&"font")
    var font_size := label.get_theme_font_size(&"font_size")
    if label.label_settings != null:
        if label.label_settings.font != null:
            font = label.label_settings.font
        font_size = label.label_settings.font_size
    var words := font.get_string_size(label.atr(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    return words + label.get_theme_stylebox(&"normal").get_minimum_size().x + float(DockerUtils.px(FactorSlider.TEXT_PADDING))


## The tool the HUD shows and each row as it stands, for the state dump.
## *offset* is where the docker's own viewport starts in the space a scenario's
## press is measured in.
func report(offset: Vector2) -> Dictionary:
    var rows: Array = []
    for key: StringName in KEYS:
        var slider: FactorSlider = sliders[key]
        var r := Rect2(slider.get_global_rect().position + offset, slider.size)
        var row := {
            "key": String(key),
            "name": String(slider.name),
            "visible": slider.visible,
            "value": slider.value,
            "shows": slider.editing_text(),
            "rect": [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)],
        }
        rows.append(row)
    return {"tool": String(_tool_id), "rows": rows}


## The spec *descriptor* declares for *key* as a number, or null.
static func _spec_of(descriptor: SaToolDescriptor, key: StringName) -> SaOptionSpec:
    if descriptor == null:
        return null
    for spec: SaOptionSpec in descriptor.options:
        if spec != null and spec.key == key and (spec.kind == SaOptionSpec.Kind.FLOAT or spec.kind == SaOptionSpec.Kind.INT):
            return spec
    return null


## The range, the words and the display of *slider* from *spec*, the fields
## `ToolOptionControls` gives the bar's slider for the same spec, with a spec
## flagged `scale_by_canvas` shown in pixels of a document *side* pixels across.
func _apply(slider: FactorSlider, spec: SaOptionSpec, side: float) -> void:
    var whole := spec.kind == SaOptionSpec.Kind.INT
    slider.min_value = spec.min_value
    slider.max_value = spec.max_value
    slider.soft_max_value = spec.soft_max
    slider.logarithmic = spec.logarithmic
    slider.step = 1.0 if whole else spec.step
    slider.prefix = tr(spec.label) + ": "
    slider.suffix = spec.suffix
    slider.normalized_display = spec.percent
    slider.decimal_places = 0 if whole else spec.decimals
    slider.trim_trailing_zeros = spec.trim_trailing_zeros
    slider.steps_by_whole_units = spec.steps_by_whole_units
    slider.display_value_multiplier = spec.display_scale * (side if spec.scale_by_canvas else 1.0)
    slider.tooltip_text = tr(spec.tooltip)


func _machine() -> ToolMachine:
    if machine != null:
        return machine
    if not is_inside_tree():
        return null
    var canvas := SaCanvasView.front_canvas()
    return canvas.tool_machine() if canvas != null else null


static func _shown_tool_id(tools: ToolMachine) -> StringName:
    if tools == null:
        return &""
    var id := tools.default_tool_name
    return id if not String(id).is_empty() else tools.active_tool_name


## The side of the document the machine paints that a radius is a fraction of,
## `SaDocument.brush_side`.
static func _document_side(tools: ToolMachine) -> float:
    var doc: SaDocument = tools.surface.get_document() if tools != null and tools.surface != null else null
    if doc == null:
        return NO_DOCUMENT_SIDE
    return doc.brush_side


## A slider moved under the hand: the value goes to the tool it was read from,
## the tally counts it as the palette's, and the bus tells the bar and the
## docker to read it again.
func _on_moved(value: float, key: StringName) -> void:
    if _quiet or not _specs.has(key):
        return
    if ToolOptionControls.write_spec(_specs[key], value, _tool):
        SaUsageTally.option_set(key, SaUsageTally.PALETTE)
        EventBus.tool_options_moved.emit()


## Something else moved the tool's options, the bar, a bracket or the HUD's own
## move echoed back. Read again only while the HUD can be seen, since it reads
## again each time it is shown.
func _on_tool_moved() -> void:
    if is_visible_in_tree():
        refresh()


func _on_tool_switched(_name: String) -> void:
    _on_tool_moved()
