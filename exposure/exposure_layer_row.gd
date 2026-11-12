## The Exposure docker's Layer row: the Exposure filter on the active layer or
## group, with Affect all and the Bake, Attach and Layer toggle, previewed
## while a hand drags and committed by Apply as one undo step.
##
## **The filter is the registry's, found by its id.** The base module registers
## Exposure under its own key, and `ui` names no module, so the row asks the
## filter registry for the filter whose `id()` is `exposure`, the half of the
## key a filter gives itself. With none registered, the skeleton without its
## modules, the row says so in place of its controls.
##
## **A drag previews as the filter dialog's does.** Each move writes the stops
## into the registry's one instance, runs it on a previewing context and hands
## the point pass it recorded to the compositor's point preview, which draws the
## active layer through it and writes no chunk. Nought stops is no preview. A
## preview left standing is taken off when the docker hides, when the painter
## goes to another document or another layer, and on Apply. The registry holds
## one instance per key, so the stops are written again before every run and
## Apply, whatever a dialog or an evaluated record left in it, and one point
## preview stands per document, so a drag here replaces a filter dialog's.
##
## **Apply is the dialog's Apply.** Bake through `SaFilterOps.one_shot`,
## Attach through `SaFilterOps.attach` and Layer through
## `SaFilterConversion.add_holding`, each one history step, and the slider goes
## back to nought after, since what it held is in the picture now.
##
## **Affect all is the dialog's preference**, `SaSettings.filter_affect_all`,
## written by a hand's tick here as by one there, and followed when the dialog
## writes it. The way is the way toggle's, `exposure_way_toggle.gd` beside this.
extends VBoxContainer

const WayToggle := preload("exposure_way_toggle.gd")

## The filter's own id, `slug("Exposure")`.
const FILTER_ID := &"exposure"
## The filter's one row.
const PARAMETER := &"stops"

## The stops, the slider the docker draws its three rows with.
var slider: FactorSlider = null
var affect_all: CheckBox = null
var way_toggle: WayToggle = null
var apply_button: Button = null
## Says why the row has no controls, shown in their place.
var note: Label = null

## The controls, hidden while no Exposure filter is registered.
var _controls: VBoxContainer = null
var _surface: SaSurface = null
var _registry: SaFilterRegistry = null
var _layer_types: SaLayerTypeRegistry = null
## The key the Exposure filter is registered under, or empty.
var _key: StringName = &""
## The document a drag previews on, and the layer it previews, or null.
var _previewed: SaDocument = null
var _previewed_layer: SaLayer = null


## A row around *stops*, a slider the docker made as it makes the other two.
func _init(stops: FactorSlider) -> void:
    name = "ExposureLayer"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    note = SaMake.label(self, "Note", tr("No module registers the Exposure filter."))
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(note, "text_muted")
    _controls = SaMake.column(self, "Controls")
    slider = stops
    _controls.add_child(slider)
    slider.tooltip_text = tr("Moves the active layer's values by stops of light, previewed on the canvas until Apply.")
    slider.value_changed.connect(preview)
    affect_all = SaMake.check_box(_controls, "ExposureAffectAll", tr("Affect all"), _affects_all())
    affect_all.tooltip_text = tr(
        "Applies to the whole picture: Bake writes every paint layer, Attach the document, Layer a layer set to it."
    )
    affect_all.toggled.connect(_on_affect_all_toggled)
    way_toggle = WayToggle.new()
    _controls.add_child(way_toggle)
    way_toggle.picked.connect(func(_id: Variant) -> void: _sync_apply())
    var applies := tr("Applies the exposure the slider holds, as one undo step.")
    apply_button = SaMake.button(_controls, "ExposureApply", tr("Apply"), applies)
    apply_button.size_flags_horizontal = Control.SIZE_SHRINK_END
    apply_button.pressed.connect(apply)
    _show_controls()


## Points the row at *surface*, the filters and the layer types as they stand,
## and settles it on them: the filter looked up again when the registry changed
## or lost it, a preview taken off a document or a layer the painter has left,
## and the ways dimmed for the layer now active.
func follow(surface: SaSurface, registry: SaFilterRegistry, types: SaLayerTypeRegistry) -> void:
    _surface = surface
    _layer_types = types
    if registry != _registry or (registry != null and not registry.has(_key)):
        _registry = registry
        _key = _find_key()
        _fit_range()
        _show_controls()
    var document := _document()
    if _previewed != null and (_previewed != document or _previewed_layer != _active_layer()):
        cancel()
    _settle()


## Affect all or the way moved elsewhere, the dialog's toggle or a profile, and
## this row follows without writing them back.
func follow_settings() -> void:
    if affect_all.button_pressed != _affects_all():
        affect_all.set_pressed_no_signal(_affects_all())
    _settle()


## Runs the filter at *stops* on the active layer and shows what it recorded on
## the canvas, writing no chunk. Nought stops takes the preview off.
func preview(stops: float) -> void:
    var document := _document()
    if _active_layer() == null or _filter() == null:
        return
    if is_zero_approx(stops):
        _clear_preview()
        _sync_apply()
        return
    var context := _run(document, stops)
    if context.point == null:
        _clear_preview()
    else:
        SaInHand.Canvas.preview_point(_surface, document, context.point)
        _previewed = document
        _previewed_layer = document.active_layer
        _redraw(document, _previewed_layer)
    _sync_apply()


## Writes the stops the slider holds by the way the toggle stands on, as one
## history step, and puts the slider back at nought. False when nothing could
## be written: no filter, no layer, nought stops or no open way.
func apply() -> bool:
    var stops := slider.value
    var document := _document()
    var layer := _active_layer()
    var filter := _filter()
    if layer == null or filter == null or is_zero_approx(stops) or not way_toggle.is_open():
        return false
    var every := affect_all.button_pressed
    var context := _run(document, stops)
    _clear_preview()
    var done := false
    match StringName(way_toggle.value):
        &"attach":
            var filed := filter.filed_as(_key)
            done = SaFilterOps.new(document).attach(null if every else layer, filed.key, filed.parameters) != null
        &"layer":
            var held := filter.filed_as(_key)
            var conversion := SaFilterConversion.new(document)
            done = conversion.add_holding(held.key, held.parameters, _layer_types, filter.translated_title(), every) != null
        _:
            done = SaFilterOps.one_shot(context, filter, every)
    slider.set_value_no_signal(0.0)
    _settle()
    return done


## Takes a preview off the canvas and the slider back to nought, writing
## nothing: the dialog's Cancel.
func cancel() -> void:
    _clear_preview()
    slider.set_value_no_signal(0.0)
    _sync_apply()


## What the row shows, for the docker's half of the state dump.
func describe() -> Dictionary:
    return {
        "filter": String(_key),
        "stops": slider.value,
        "way": String(way_toggle.value),
        "dimmed": way_toggle.dimmed.duplicate(),
        "affect_all": affect_all.button_pressed,
        "apply_live": not apply_button.disabled,
        "previewing": _previewed != null,
        "note": note.text if note.visible else "",
    }


## A previewing context over the active layer with the filter at *stops*, run
## once, so it holds the point pass the preview shows and Apply writes.
func _run(document: SaDocument, stops: float) -> SaFilterContext:
    var filter := _filter()
    filter.set_parameters({String(PARAMETER): stops})
    var context := SaFilterContext.new(document, document.active_layer, _registry.owner_of(_key), filter.title(), true)
    SaFilterApply.call_run(filter, context)
    return context


## The ways dimmed for the active layer and Affect all as they stand, and Apply
## live or not after them.
func _settle() -> void:
    var filter := _filter()
    var problem := filter.problem().split("\n")[0].strip_edges() if filter != null else ""
    way_toggle.settle(_active_layer(), affect_all.button_pressed, problem, _layer_types != null)
    _sync_apply()


## Apply is live with a filter, an active layer, stops off nought and the
## thumb on an open way.
func _sync_apply() -> void:
    var live := _filter() != null and _active_layer() != null
    live = live and not is_zero_approx(slider.value) and way_toggle.is_open()
    if apply_button.disabled == live:
        apply_button.disabled = not live


## A hand's tick on Affect all becomes where every filter's Apply reaches, and
## Bake is dimmed again for it.
func _on_affect_all_toggled(on: bool) -> void:
    SaInHand.Settings.write(&"filter_affect_all", on)
    _settle()


## The key of the filter whose own id is Exposure's, or empty.
func _find_key() -> StringName:
    if _registry == null:
        return &""
    for key: StringName in _registry.list_keys():
        var found := _registry.get_filter(key)
        if found != null and found.id() == FILTER_ID:
            return key
    return &""


func _filter() -> SaFilter:
    if _registry == null or _key == &"":
        return null
    return _registry.get_filter(_key)


## The slider over the filter's own range, which `parameter` declares.
func _fit_range() -> void:
    var filter := _filter()
    if filter == null:
        return
    filter.parameter(PARAMETER)
    var span: Variant = filter.store._ranges.get(PARAMETER)
    if span is Vector2:
        slider.min_value = (span as Vector2).x
        slider.max_value = (span as Vector2).y


## The controls with a filter to run, the note in their place without one.
func _show_controls() -> void:
    var found := _key != &""
    _controls.visible = found
    note.visible = not found


func _document() -> SaDocument:
    return _surface.get_document() if _surface != null else null


## Whether a filter's Apply reaches the whole picture, the preference the
## dialog's Affect all and this row's both move.
static func _affects_all() -> bool:
    return bool(SaInHand.Settings.read(&"filter_affect_all"))


func _active_layer() -> SaLayer:
    var document := _document()
    return document.active_layer if document != null else null


func _clear_preview() -> void:
    if _previewed == null:
        return
    if _surface != null and _surface.easel != null:
        SaInHand.Canvas.clear_point_preview(_surface, _previewed)
        _redraw(_previewed, _previewed_layer)
    _previewed = null
    _previewed_layer = null


## The preview changes what *layer*'s chunks show and nothing in them, so they
## are marked dirty by hand and composited on the next frame.
func _redraw(document: SaDocument, layer: SaLayer) -> void:
    if layer != null:
        document.invalidate_chunks(layer.chunks.keys())
    SaInHand.Canvas.request_composite(_surface)
