## The Colourise docker: the active Colourise layer's options, its Update
## button and the step that turns it into a paint layer of its flats.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A declared page** whose rows bind to this docker's properties, each a
## second hand on the layer's own slice of module data, so every write goes
## through [method SaColorize.choose] and the file keeps what the rows show.
## While the active layer is not a Colourise layer the rows are dimmed and the
## note says how to make one.
##
## **The line art row lists the layers the active one can read**, the nearest
## under it first as the layer reads it when none is named, and is drawn again
## when that list changes, a layer added, removed or renamed.
##
## Registered by the base module through `SaContext.register_docker`, the call
## every module's docker makes (hard rule 6).
@tool
extends DockerWindow

const SaColorize = preload("res://modules/sara-base-modules/base/colorize/sa_colorize.gd")

## The docker's id, which a saved layout holds, so it does not change.
const DOCKER_ID := &"ColorizeDocker"
const SENTENCE := "The options of a Colourise layer, which fills the regions of line art from a few scribbles."
const DEFAULT_SIZE := Vector2i(280, 360)
const PAGE_NAME := "ColorizePage"
## The name the dockers' manager answers to, found by name so this module does
## not name the class of the host that holds it.
const MANAGER_NAME := "MainDockers"
## Set on a layer once the docker has been brought to the painter for it.
const INTRODUCED := &"colorize_introduced"
## The line art row's entry for the layer's own choice of the one under it.
const BELOW := ""

## The rows' bindings. Each setter writes the active Colourise layer's option.
var line_art: String = BELOW:
    set(value):
        line_art = value
        _write("line_art", value)
var gap: float = SaColorize.GAP:
    set(value):
        gap = value
        _write("gap", value)
var transparent_key: Color = SaColorize.TRANSPARENT:
    set(value):
        transparent_key = value
        _write("transparent", value)
var alone: bool = false:
    set(value):
        alone = value
        _write("alone", value)
var auto: bool = true:
    set(value):
        auto = value
        _write("auto", value)
## Whether the active layer is a Colourise layer, which the rows dim on.
var active: bool = false

var page: SaPage = null
## The facade the base module registered the type with.
var colorize: SaColorize = null

## The layer the rows were last read from, and the line art row's names.
var _layer: SaLayer = null
var _names: PackedStringArray = []
## Whether the rows are being read from a layer, when a setter writes nothing.
var _reading: bool = false
var _note: SaPageRow = null
var _howto: SaPageRow = null
var _needs_lines: SaPageRow = null


func _init(facade: SaColorize = null) -> void:
    colorize = facade
    _init_docker(DOCKER_ID, tr("Colourise"), DEFAULT_SIZE, Vector2i(220, 200))
    position = Vector2i(2, 400)
    var column := SaMake.column(_control_node, "VBoxContainer")
    column.set_anchors_preset(Control.PRESET_FULL_RECT)
    drag_handle = DockerUtils.make_drag_bar(tr("Colourise"))
    column.add_child(drag_handle)
    var margin := SaMake.margin(column, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var scroll := SaMake.scroll(margin, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var rows := SaMake.column(scroll, PAGE_NAME, SaTheme.GAP)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(rows)
    _show_active()


func _ready() -> void:
    _setup_docker_ready()
    if not SaInHand.Settings.profile_changed().is_connected(apply_layout_settings):
        SaInHand.Settings.profile_changed().connect(apply_layout_settings)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout(DOCKER_ID)


func _process(_delta: float) -> void:
    if not is_inside_tree():
        return
    var front := _front_layer()
    if visible:
        follow(front)
        _show_active()
    else:
        introduce(front)


## Brings the docker forward the first time a Colourise layer with nothing on
## it becomes the active one, so a painter who has just made one sees where its
## options are. Once per layer, so closing the docker is not undone.
func introduce(layer: SaLayer) -> void:
    if not SaColorize.is_colorize(layer) or layer.has_meta(INTRODUCED) or not layer.chunks.is_empty():
        return
    layer.set_meta(INTRODUCED, true)
    var found := get_tree().root.find_child(MANAGER_NAME, true, false)
    if found != null and found.has_method("toggle_docker_by_id"):
        found.call("toggle_docker_by_id", DOCKER_ID)


## Reads the rows from *layer*, when it is not the one they were read from or
## the layers it can read have changed.
func follow(layer: SaLayer) -> void:
    var names := _readable_names(layer)
    if layer == _layer and names == _names:
        return
    _layer = layer
    var rebuilt := names != _names
    _names = names
    active = colorize != null and SaColorize.is_colorize(layer)
    _reading = true
    if active:
        line_art = str(colorize.options(layer).get("line_art", BELOW))
        gap = colorize.gap_of(layer)
        transparent_key = colorize.transparent_of(layer)
        alone = colorize.alone_of(layer)
        auto = colorize.auto_of(layer)
    _reading = false
    if rebuilt:
        page.rebuild()
    page.refresh()
    _show_active()


## Works the active layer's flats out again, one history step.
func update_flats() -> void:
    if active and _layer != null:
        colorize.update(_layer)


## Turns the active layer into a paint layer of what it shows, the Layer menu's
## Rasterize Layer, one history step.
func convert_to_paint() -> void:
    if active and _layer != null:
        colorize.rasterize()


func _declare(declared: SaPage) -> void:
    var top := declared.section("")
    _note = (
        top
        . note(
            (
                "Colourise fills the shapes of a line art layer with the colours you scribble in them."
                + " Add one from Layer > Other Layers > Colourise Line Art, then pick it to set it up here."
            )
        )
        . named(&"note")
    )
    _howto = (
        top
        . note(
            (
                "Pick the line art layer below, scribble a colour inside each shape,"
                + " then press Update, or leave Auto update on to fill as you paint."
            )
        )
        . named(&"howto")
    )
    _needs_lines = (
        top
        . note(
            (
                "The line art layer has no lines yet, so only your scribbles show."
                + " Draw the lines on a paint layer and pick it as the line art."
            )
        )
        . named(&"needs_lines")
    )
    var choices: Array = [{"id": BELOW, "label": "The nearest layer"}]
    for layer_name in _names:
        choices.append({"id": layer_name, "label": layer_name})
    var rows := declared.section("Fill")
    rows.choice("Line art", choices, self, ^"line_art").named(&"line_art").node("ColorizeLineArt").explain(
        "The layer whose lines bound the regions."
    )
    (
        rows
        . slider("Gap closing", 0.0, SaColorize.GAP_MOST, self, ^"gap")
        . named(&"gap")
        . node("ColorizeGap")
        . step(1.0)
        . with_suffix(" px")
        . explain("Breaks in the lines up to this many pixels across hold the colour in.")
    )
    rows.colour("Transparent key", self, ^"transparent_key").named(&"transparent").node("ColorizeTransparent").explain(
        "Scribbles in this colour mark regions to leave empty."
    )
    rows.toggle("Show scribbles alone", self, ^"alone").named(&"alone").node("ColorizeAlone")
    rows.toggle("Auto update", self, ^"auto").named(&"auto").node("ColorizeAuto").explain(
        "Fills again each time a stroke on the layer ends."
    )
    rows.action("Update", update_flats).named(&"update").node("ColorizeUpdate")
    rows.action("Convert to Paint Layer", convert_to_paint).named(&"convert").node("ColorizeConvert")


## The rows live and the note gone while the active layer is a Colourise
## layer, and the other way round otherwise. Set here rather than by a rule,
## because no row of the page holds whether the layer is one.
func _show_active() -> void:
    for entry in page.rows():
        if entry == _note or entry == _howto or entry == _needs_lines:
            if entry.line != null and is_instance_valid(entry.line):
                if entry == _note:
                    entry.line.visible = not active
                elif entry == _howto:
                    entry.line.visible = active
                else:
                    entry.line.visible = active and colorize != null and not colorize.has_line_art(_layer)
        else:
            SaPage.set_live(entry, active)


func _write(key: String, value: Variant) -> void:
    if _reading or not active or _layer == null or colorize == null:
        return
    colorize.choose(_layer, key, value)


## The names of the layers *layer* can read as line art, nearest under it first.
func _readable_names(layer: SaLayer) -> PackedStringArray:
    var names := PackedStringArray()
    if layer == null or not is_instance_valid(layer) or not SaColorize.is_colorize(layer):
        return names
    var document := layer.get_parent()
    if document == null:
        return names
    for child in document.get_children():
        if SaColorize.readable(child, layer):
            names.insert(0, String(child.name))
    return names


func _front_layer() -> SaLayer:
    var surface := SaInHand.Canvas.front()
    if surface == null or surface.get_document() == null:
        return null
    return surface.get_document().active_layer
