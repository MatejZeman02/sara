## The steps that ask a registered filter by its id: applying one to the
## layer, driving the live preview its dialog shows before Apply, and the
## custom rows of Levels, Curves and the colour lookup.
##
## All start where the dialog hands off, because the dialog lives in an
## embedded subwindow and an injected click does not route into one. What is
## proved is what the app does with the answer, never the dialog's own chrome.
##
## The steps were the six adjustments' own, and they keep their spelling. The
## six are a module's filters, so each step
## asks the filter registry for the filter whose id is the kind and speaks to
## it by method name, the way `kpp` asks a role. The harness names no module
## class, and a module that replaces one of the six answers the same steps.
## It is not called an adjust driver because the skeleton has no adjustment
## engine of its own left to drive.
##
## Reached by path from the step table rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaFilterDriver
extends RefCounted

## The canvas driver, for the one lookup this shares with it.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for its tree.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Applies an adjustment: to the main document's active layer, in the units the
## pass takes and as the one step the dialog's Apply makes, `{"adjust": {"kind":
## "brightness_contrast", "brightness": 0.2, "contrast": 1.5}}` or `{"adjust":
## {"kind": "hue_saturation_lightness", "hue": 90, "saturation": 1.0,
## "lightness": 0.0}}`, where `"colorize": true` makes the hue an absolute
## Oklab hue from 0 to 360 and the saturation a fraction of a strong chroma, so
## every pixel takes that one hue at its own lightness. No dialog opens: the
## filter's own `capture_apply` is the door.
func adjust(spec: Dictionary) -> void:
    var canvas := CanvasDriver.main_canvas()
    var document: SaDocument = canvas.document if canvas != null else null
    if document == null:
        push_warning("SaCapture: no document to adjust")
        return
    var kind := String(spec.get("kind", "brightness_contrast"))
    var filter := _filter_of(kind)
    if filter == null or not filter.has_method("capture_apply"):
        push_warning("SaCapture: no registered filter answers the adjust step for '%s'" % kind)
        return
    var applied := bool(filter.call("capture_apply", document, spec))
    print("SaCapture: adjust %s -> %s" % [kind, "applied" if applied else "nothing to do"])


## Previews an adjustment: it opens an adjustment's dialog as Filter would and
## sets its sliders in their own units, degrees and percentages, so the preview
## shows on the canvas with no history step, `{"preview": {"kind":
## "hue_saturation_lightness", "hue": 120}}`, and `"colorize": true` with
## `colorize_hue` and `colorize_saturation` ticks Colorize and moves its rows.
## `{"preview": {"apply": true}}`
## presses Apply, `{"preview": {"cancel": true}}` closes it, and `"enabled":
## false` unticks the Preview box first. `{"preview": {"read": true}}` prints the
## dialog's current values and touches nothing else: every other branch here opens
## the filter again, which rebuilds its rows from their declared defaults and
## would answer a slider a gesture had just moved with the row it was built from
## instead.
func preview(spec: Dictionary) -> void:
    var window := SaFilterDialogWindow.find_in(_run.tree())
    if window == null:
        push_warning("SaCapture: no filter dialog installed")
        return
    var open := window.visible and window.filter != null and window.filter.has_method("capture_set")
    if spec.get("apply", false) or spec.get("cancel", false):
        if not open:
            push_warning("SaCapture: no adjustment dialog is open")
            return
        if spec.get("apply", false):
            window.apply_filter()
        else:
            window.cancel_filter()
        print("SaCapture: preview %s" % ("applied" if spec.get("apply", false) else "cancelled"))
        return
    if spec.get("read", false):
        if not open:
            push_warning("SaCapture: no adjustment dialog is open")
            return
        print("SaCapture: preview read %s" % JSON.stringify(window.filter.call("values")))
        return
    var kind := String(spec.get("kind", "hue_saturation_lightness"))
    var key := _key_of(kind)
    if key.is_empty():
        push_warning("SaCapture: no registered filter answers the preview step for '%s'" % kind)
        return
    window.open_filter(StringName(key))
    if window.filter == null or not window.filter.has_method("capture_set"):
        push_warning("SaCapture: opening the adjustment dialog made none")
        return
    if spec.has("enabled"):
        var box := window.find_child("CanvasPreview", true, false) as CheckButton
        if box != null:
            box.button_pressed = bool(spec["enabled"])
    # The filter reads the step against its own rows, so a kind that adds rows
    # is drivable the day it lands. Colour balance is nine sliders and a toggle,
    # and a list kept here would have reached none of them.
    var sliders: Dictionary = window.filter.call("capture_set", spec)
    window.dialog.flush_rerun()
    print("SaCapture: preview %s %s" % [kind, JSON.stringify(sliders)])


## `{"levels": {...}}`, `{"curve": {...}}` and `{"palette": {...}}`, the three
## steps that drive the custom row Levels, Curves and the colour lookup hand
## their page. They keep the spelling they had as
## dialogs and reach the control through the `filter` step's door,
## `capture_option_edit`, so what a handle, a curve or a chip understands is
## the module's business. Only the window's own half is here: `"apply": true`
## and `"cancel": true` press the two buttons, `"enabled"` sets the Preview
## box, and the rest goes to the row whose key is *row_key*.
##
## *opens* is the id of a filter to open first when it is not the one showing,
## as its Filter menu row would. The `palette` step names one, because it has
## always opened its dialog itself, and the other two leave it empty, because
## theirs never did and a scenario opens them with an `open` step.
func custom_row(row_key: String, spec: Dictionary, opens: String = "") -> void:
    var window := SaFilterDialogWindow.find_in(_run.tree())
    var pressing: bool = spec.get("apply", false) or spec.get("cancel", false)
    if window != null and not opens.is_empty() and not pressing and not _is_showing(window, opens):
        var key := _key_of(opens)
        if not key.is_empty():
            window.open_filter(StringName(key))
    if window == null or not window.visible or window.dialog == null:
        push_warning("SaCapture: no %s filter is open" % row_key)
        return
    if spec.get("apply", false):
        window.apply_filter()
        print("SaCapture: %s applied" % row_key)
        return
    if spec.get("cancel", false):
        window.cancel_filter()
        print("SaCapture: %s cancelled" % row_key)
        return
    if spec.has("enabled"):
        var box := window.find_child("CanvasPreview", true, false) as CheckButton
        if box != null:
            box.button_pressed = bool(spec["enabled"])
    var row := window.dialog.row(StringName(row_key))
    if row == null or row.control == null or not row.control.has_method("capture_option_edit"):
        push_warning("SaCapture: the open filter has no %s row" % row_key)
        return
    print(String(row.control.call("capture_option_edit", spec)))
    window.dialog.flush_rerun()


## Whether *window* is up and showing the filter whose id is *kind*.
static func _is_showing(window: SaFilterDialogWindow, kind: String) -> bool:
    return window.visible and window.filter != null and String(window.filter.id()) == kind


## Opens the filter whose id is *kind* the way its Filter menu row does, by
## asking the registry to invoke it. Static, because the menu driver's `open`
## step reaches it too. False when nothing registered answers *kind*.
static func invoke_filter(tree: SceneTree, kind: String) -> bool:
    var registry := _registry_in(tree)
    var key := _key_in(registry, kind)
    if key.is_empty():
        push_warning("SaCapture: no registered filter answers '%s'" % kind)
        return false
    registry.invoke(StringName(key))
    return true


## The registry key of the filter whose id is *kind*, or "" for none.
func _key_of(kind: String) -> String:
    return _key_in(_registry(), kind)


static func _key_in(registry: SaFilterRegistry, kind: String) -> String:
    if registry == null:
        return ""
    for key: StringName in registry.list_keys():
        var filter := registry.get_filter(key)
        if filter != null and String(filter.id()) == kind:
            return String(key)
    return ""


func _filter_of(kind: String) -> SaFilter:
    var key := _key_of(kind)
    return _registry().get_filter(StringName(key)) if not key.is_empty() else null


func _registry() -> SaFilterRegistry:
    return _registry_in(_run.tree())


static func _registry_in(tree: SceneTree) -> SaFilterRegistry:
    var main_node := tree.current_scene if tree != null else null
    var registries := main_node.get("registries") as SaRegistries if main_node != null else null
    return registries.filters if registries != null else null
