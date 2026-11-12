## The active layer's blend mode and opacity: the word "Blend" and the blend
## dropdown on one row, the opacity slider on the row under it, which the Layers
## docker shows above its list. Each row takes the docker's full width, so
## neither control is squeezed by the other.
##
## The row follows the layer itself. Handed a canvas, it hears that canvas's
## document for the active layer and for every change an undo, a command or a
## module makes, and handed the blend registry, it hears the registry and the
## document's colour space. A press on it is a step on that document. So a
## second row built anywhere and handed the same canvas shows and moves the
## same layer as the docker's, and nothing has to drive either of them.
##
## **A view is a row of one part.** Blend Mode and Opacity are each an element
## another docker can hold, and a view always acts on the active layer and
## stays in sync with its home copy. So [method view_of] builds a row with the one part asked for, and it
## follows the home row it was built from, the canvas and the registry the
## Layers docker hands that row, now and every time they change. Nothing pins a
## view to a layer or a document of its own.
class_name SaLayerBlendOpacityRow
extends VBoxContainer

## The row was pointed at another canvas or another blend registry, so every
## view built from it points at the same.
signal rebound

## What a row holds: both parts, as the Layers docker shows them, or the one a
## view of Blend Mode or of Opacity stands for.
enum Part { BOTH, BLEND, OPACITY }

## "Blend" in front of the dropdown, at the size Tool Options and Info draw a
## row's label, a fraction of the theme's through the meta its pass reads.
const LABEL_FONT_SCALE := 0.8

## The gap between the dropdown's row and the slider's, and between the word
## and the dropdown, in logical pixels.
const GAP := 6

## The row's node name by what it holds. The Layers docker's keeps the name its
## readers find it by, and a view says which element it is in a dump.
const NAMES: Dictionary[Part, StringName] = {
    Part.BOTH: &"BlendOpacityRow",
    Part.BLEND: &"BlendModeView",
    Part.OPACITY: &"OpacityView",
}

## The Layers docker's elements a view stands for, by the names its layout and
## its Elements… page give them, each with the part of the row it shows.
const VIEWS: Dictionary[String, Part] = {
    "Blend Mode": Part.BLEND,
    "Opacity": Part.OPACITY,
}

## The word and the dropdown, the element Preferences calls Blend Mode. Null on
## a view of Opacity alone, with its dropdown.
var blend_box: HBoxContainer
## The slider, the element Preferences calls Opacity. Null on a view of Blend
## Mode alone, with its slider.
var opacity_box: HBoxContainer
var blend_mode_opt: BlendModeButton
var opacity_slider: FactorSlider

## The canvas whose active layer the row shows and moves. Null shows nothing
## and moves nothing.
var target_canvas: SaCanvas = null:
    set(val):
        _listen_to(null)
        target_canvas = val
        _listen_to(val.document if val != null else null)
        _refresh_blend_modes()
        rebound.emit()

## The document the row is connected to, kept apart from the canvas so the
## connections are taken off the one they were made on.
var _heard: SaDocument = null
## The blend modes the dropdown offers, written before [method refresh].
var blend_registry: SaBlendModeRegistry = null
var _heard_registry: SaBlendModeRegistry = null


func _init(part := Part.BOTH) -> void:
    name = NAMES[part]
    set_meta(SaMake.KIND_META, SaMake.Kind.COLUMN)
    add_theme_constant_override("separation", SaUI.px(GAP))
    if part != Part.OPACITY:
        _build_blend_box()
    if part != Part.BLEND:
        _build_opacity_box()


## The Layers docker's own row, with Blend Mode and Opacity made elements another
## docker can hold: a view of each part, built by [method view_of] from this
## row, is registered under *category* through
## `SaSettings.register_layout_element`, the call a module makes (hard rule 6,
## built-ins go through the public door). The views follow this row and not a
## line in `main.gd`, so one built before main hands the docker its canvas takes it when main does. The row is
## held weakly, so the door keeps no docker a suite has freed alive, and a
## docker built again registers again, its views replacing the last one's.
## Here rather than in the docker, whose folder stands at its line budget.
static func with_views(category: String) -> SaLayerBlendOpacityRow:
    var home := SaLayerBlendOpacityRow.new()
    var held: WeakRef = weakref(home)
    for element: String in VIEWS:
        var part: Part = VIEWS[element]
        var builder := func() -> Control: return SaLayerBlendOpacityRow.view_of(held.get_ref() as SaLayerBlendOpacityRow, part)
        SaSettings.register_layout_element(category, element, element, false, "", builder)
    return home


## A view of *part*, Blend Mode or Opacity, that follows *home*: it shows and
## moves the active layer of the canvas *home* is handed, with the blend modes
## *home* offers, and takes the next canvas or registry *home* is handed as
## well. With no home it shows nothing and moves nothing, as a row handed no
## canvas does.
static func view_of(home: SaLayerBlendOpacityRow, part: Part) -> SaLayerBlendOpacityRow:
    var view := SaLayerBlendOpacityRow.new(part)
    if home != null:
        view._follow(home)
        home.rebound.connect(view._follow.bind(home))
    return view


## The upper part, the word and the dropdown on a row of their own at the
## column's full width, an element of its own to Preferences. They stood left
## of the slider once, as Krita lays them out, where the dropdown took three
## quarters of the row and still cut a long mode's name.
func _build_blend_box() -> void:
    blend_box = SaMake.row(self, "BlendBox", GAP)
    blend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # "Blend" in front of the dropdown rather than "Layer", which would tell
    # the layer's list from the bar's and Tool Options' but reads wrong on a
    # row that says what it sets. The tooltip says whose mode it is. One short word at a row label's size, so
    # the mode name keeps its width.
    var label := SaMake.label(blend_box, "BlendLabel", tr("Blend"))
    label.tooltip_text = tr("The active layer's blend mode. The brush's blend mode is on the top bar.")
    label.mouse_filter = Control.MOUSE_FILTER_PASS
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.set_meta(SaUI.FONT_SCALE_META, LABEL_FONT_SCALE)
    var dropdown := BlendModeButton.new()
    dropdown.name = "BlendModeOpt"
    dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dropdown.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    # The docker is too narrow to grow, so a mode's name longer than the room
    # left of "Blend" goes onto a second line rather than ending cut.
    dropdown.wrap_its_words()
    blend_box.add_child(dropdown)
    dropdown.mode_selected.connect(_on_blend_mode_chosen)
    blend_mode_opt = dropdown


## The lower part, the options bar's slider on a row of its own, reading as a
## percentage. The value goes with the range, where a slider's setters take it,
## and no display setting below clamps or reads it. The word is in the tooltip,
## as it was when the slider shared a row with the dropdown and "Opacity: 100 %"
## was cut.
func _build_opacity_box() -> void:
    opacity_box = SaMake.row(self, "OpacityBox")
    opacity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var slider := SaMake.slider(opacity_box, "OpacitySlider", 0.0, 1.0, 0.01, 1.0)
    slider.suffix = "%"
    slider.normalized_display = true
    slider.decimal_places = 0
    slider.tooltip_text = tr("Opacity: how much of this layer shows over the layers below it.")
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.preferred_width = 0
    slider.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    slider.value_changed.connect(_on_opacity_moved)
    slider.value_name = &"layer/opacity"
    opacity_slider = slider


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _listen_to(null)


## Takes `blend_registry` up and keeps the dropdown live, through its changes
## and the document's colour space, which plain Normal's label names. The one
## heard before, `_heard_registry`, stops being heard, so a view that follows
## its home through a second binding hears one list.
func refresh() -> void:
    if _heard_registry != null and _heard_registry != blend_registry:
        if _heard_registry.changed.is_connected(_refresh_blend_modes):
            _heard_registry.changed.disconnect(_refresh_blend_modes)
    _heard_registry = blend_registry
    if blend_registry != null and not blend_registry.changed.is_connected(_refresh_blend_modes):
        blend_registry.changed.connect(_refresh_blend_modes)
    if not EventBus.document_color_space_changed.is_connected(_on_document_space_changed):
        EventBus.document_color_space_changed.connect(_on_document_space_changed)
    _refresh_blend_modes()
    rebound.emit()


## Shows the active layer's mode and opacity, those of the two parts the row
## holds. Neither call emits, so showing a layer never writes it back as a step.
func sync_from_active_layer() -> void:
    var layer := _active_layer()
    if layer == null:
        return
    if blend_mode_opt != null:
        blend_mode_opt.select_mode(layer.blend_mode)
    if opacity_slider != null:
        opacity_slider.set_value_no_signal(layer.opacity)


## Takes *home*'s canvas and blend registry, which is how a view follows the
## Layers docker's row. The registry first, so the list is whole when the
## canvas shows the layer's mode in it.
func _follow(home: SaLayerBlendOpacityRow) -> void:
    if home.blend_registry != blend_registry:
        blend_registry = home.blend_registry
        refresh()
    if home.target_canvas != target_canvas:
        target_canvas = home.target_canvas


## Takes the row's connections off the document it heard and puts them on
## *doc*, or on nothing for null. A layer made active by a press, PageDown or an
## undo arrives on `active_layer_changed`. Undoing an opacity or a blend mode
## change moves nothing in the tree and changes no active layer, so without
## `document_changed` the slider kept showing the value just undone.
func _listen_to(doc: SaDocument) -> void:
    if _heard != null and is_instance_valid(_heard):
        if _heard.active_layer_changed.is_connected(_on_active_layer_changed):
            _heard.active_layer_changed.disconnect(_on_active_layer_changed)
        if _heard.document_changed.is_connected(sync_from_active_layer):
            _heard.document_changed.disconnect(sync_from_active_layer)
    _heard = doc
    if doc == null:
        return
    doc.active_layer_changed.connect(_on_active_layer_changed)
    doc.document_changed.connect(sync_from_active_layer)


## The layer the row shows, or null with no document.
func _active_layer() -> SaLayer:
    return _heard.active_layer if _heard != null else null


func _on_active_layer_changed(_layer: SaLayer) -> void:
    sync_from_active_layer()


## Only the document the row is showing rebuilds it, so a document behind
## another tab, or the scratchpad, leaves the row's label alone.
func _on_document_space_changed(changed: SaDocument) -> void:
    if _heard != null and changed != _heard:
        return
    _refresh_blend_modes()


## Plain Normal's label names the space it is currently mixing in, so this has to
## run again when the document's space changes and not only when the registry
## does. The space is read off the document rather than taken from the signal,
## because Sara runs more than one easel and the signal may be another one's.
## The layer's mode is shown again after, because a button rebuilt before it had
## a registry knew no mode to keep and fell back on the list's first.
func _refresh_blend_modes() -> void:
    if blend_mode_opt == null:
        sync_from_active_layer()
        return
    # Erase is a brush concept, so the layer's list is the one without it.
    blend_mode_opt.registry = blend_registry
    blend_mode_opt.include_hidden_in_layers = false
    blend_mode_opt.space = _heard.color_space if _heard != null else null
    blend_mode_opt.refresh()
    sync_from_active_layer()


func _on_blend_mode_chosen(mode_id: StringName) -> void:
    var layer := _active_layer()
    if layer != null:
        SaLayerOps.new(_heard).set_blend_mode(layer, mode_id, blend_mode_opt.run_merge())


func _on_opacity_moved(val: float) -> void:
    var layer := _active_layer()
    if layer != null:
        SaLayerOps.new(_heard).set_opacity(layer, val)
