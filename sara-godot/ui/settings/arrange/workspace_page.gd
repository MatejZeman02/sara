## Preferences > Interface, its first part: the interface scale, its text and
## its font, the first rows Preferences opens on (`SaGeneralPage` says why each
## row of that page is where it is). What a save leaves behind moved to the Files
## page, and the named layouts, what every docker shares and whether the dockers
## live inside the main window to Layouts and dockers (`SaDockersPage`), where
## each docker's line is.
##
## **Declared rather than built**. A row that is a control, a read and a setter
## lambda is one line bound to the preference by name, which is the line the
## declarative page API lets this page stop writing:
## `func(val): SaSettings.recorder_settle_seconds = val` in one spelling or
## another. The two Interface sliders stay custom: they hold the setting back
## while the grabber is held, so the window does not move under the hand
## dragging it. That machinery is this page's subject, `_wire_slider` below is
## untouched, and each draws its value beside the track as a declared slider
## row does, "100%", under a title that says only what the row is.
class_name SaWorkspacePage
extends SaSettingsPage

## The page has to be built again: the interface font changed and the bold
## titles hold the old face. The window owns the rebuilding.
signal rebuild_requested

## The two Interface sliders, kept so each can be held still while its own value
## re-draws the window around it, and so a capture can drive them by name.
var _scale_slider: HSlider = null
var _font_slider: HSlider = null

## The number beside each slider, which follows the grabber while the setting
## behind it waits for the hand to let go.
var _scale_readout: Label = null
var _font_readout: Label = null

## Which slider has its grabber held, or null. Nothing re-draws the interface
## while one is held: a slider that moves under the hand dragging it feeds its
## own new position back in as a new value.
var held: HSlider = null

## What the last correction could not pay back, in physical screen pixels. Zero
## means the point the value sits at did not move at all. It is reported rather
## than asserted because the correction is best effort, and a reader of a capture
## should be able to see when it was and when it was not enough.
var residual := Vector2.ZERO

## The rows whose change needs the whole page drawn again, held as rows and
## matched by key only when a change arrives.
##
## A key read off the row in [method build] is the empty one: `SaPage` gives a
## row its key in `adopt_row`, once the whole declaration is in hand and after
## `build` returns, so the font row's key was `&""` here and a font pick never
## rebuilt the page. By the time a row announces a change it
## has its key, and the row it is filed under is the one held here.
var _rebuild_on: Array[SaPageRow] = []


func build(ui: SaPage) -> void:
    _rebuild_on.clear()
    _declare_interface(ui)
    ui.row_changed.connect(_on_row_changed)


func _declare_interface(ui: SaPage) -> void:
    # "I'm coming from" heads the page, the same row Quick settings opens with,
    # so it is found again after the first run.
    var programs := ui.section("Start from")
    var coming_from := SaComingFromRow.new()
    programs.custom("I'm coming from", coming_from).named(&"coming_from").explain(SaComingFromRow.HINT)

    # Not headed Interface, which is the page's own title above it.
    var rows := ui.section("Size and font")

    # "UI scale" is a multiplier on top of the system scale, not an absolute
    # size, so the hint shows what the system reports and what the two multiply
    # out to. Without that, 100% on a 2x display looks like a bug rather than
    # the default.
    _scale_slider = HSlider.new()
    _scale_slider.name = "UiScaleSlider"
    # The wheel belongs to the page that scrolls, which has no undo for a
    # value moved by a notch passing over the track.
    _scale_slider.scrollable = false
    _scale_slider.min_value = 0.5
    _scale_slider.max_value = 2.0
    # 0.05 rather than 0.1. A tenth is a large jump for a control that rescales
    # every window at once, and the arrow keys move it by one step.
    _scale_slider.step = 0.05
    _scale_slider.value = SaSettings.ui_scale
    _scale_readout = readout_beside(_scale_slider)
    # Both rows are named by the keys `slider_named` answers to, so a change to
    # either title cannot move them.
    var scale_row := rows.custom("UI scale", _scale_slider.get_parent() as Control)
    scale_row.named(&"ui_scale").explain(_scale_hint(SaSettings.ui_scale))
    _scale_slider.tooltip_text = tr("Resize every window, row and control at once.")
    _wire_slider(
        _scale_slider,
        func(val: float) -> void: _relabel(scale_row, _scale_readout, val, _scale_hint(val)),
        func(val: float) -> void: SaSettings.ui_scale = val
    )

    # Text alone, below the scale it is a fraction of. It writes
    # SaSettings.ui_text_size, which reaches SaUI.get_font_size() and the shared
    # theme, and never Window.content_scale_factor: hard rule 7 keeps one writer
    # for that and this is not it. The slider holds the painter's reading, 1.0
    # at the size Sara ships with, in steps of 1% from a whole percent, so 100%
    # is a stop on the track. A profile's 0.85 shows at 113%, and the stored
    # multiplier is written only when the slider moves.
    _font_slider = HSlider.new()
    _font_slider.name = "FontSizeSlider"
    _font_slider.scrollable = false
    _font_slider.min_value = ceilf(SaSettingsValues.MIN_TEXT_SIZE * 100.0) / 100.0
    _font_slider.max_value = floorf(SaSettingsValues.MAX_TEXT_SIZE * 100.0) / 100.0
    _font_slider.step = 0.01
    _font_slider.value = SaSettings.ui_text_size
    _font_readout = readout_beside(_font_slider)
    var font_row := rows.custom("Font size", _font_slider.get_parent() as Control)
    font_row.named(&"font_size").explain(_font_hint(SaSettings.ui_text_size))
    _font_slider.tooltip_text = tr("Set the size of the interface's text.")
    _wire_slider(
        _font_slider,
        func(val: float) -> void: _relabel(font_row, _font_readout, val, _font_hint(val)),
        func(val: float) -> void: SaSettings.ui_text_size = val
    )

    # The interface font: the four shipped families and the engine's own,
    # applied at once. Each row carries the id the setting stores, so nothing
    # keeps a second array to turn a position back into a font.
    var fonts: Array = []
    for entry: Dictionary in SaFonts.available():
        fonts.append({"id": String(entry["id"]), "label": String(entry["name"])})
    var font_choice := rows.choice("Interface font", fonts, SaSettings, ^"ui_font")
    font_choice.explain(tr("The face every label, menu and slider is drawn in. Applies at once.")).node("InterfaceFontOpt")
    # Still needed: every title and heading on the page carries
    # `SaFonts.bold()` as an override, taken when it was built, so without a
    # rebuild they stay in the old face's bold while the hints take the new one.
    _rebuild_on.append(font_choice)
    # Sara's own pointer, the cursor lead and the tablet driver are the Tablet
    # page's, beside the pen they are about, and not this section's.


## The interface font changes the face of every window at once, so the page it
## was changed on is drawn again.
func _on_row_changed(key: StringName, _value: Variant) -> void:
    for row: SaPageRow in _rebuild_on:
        if row.key == key:
            rebuild_requested.emit()
            return


## *slider* in a box with its value read out beside it, the shape `SaPage`
## draws a declared slider row in, so the number sits by the track and the
## title says only what the row is. The readout is returned, and the box is the
## slider's parent. Public, because the welcome window's Quick settings draws
## the same scale row.
static func readout_beside(slider: HSlider) -> Label:
    var box := SaMake.row(null, "SliderBox", SaTheme.GAP)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    box.add_child(slider)
    var readout := SaMake.label(box, SaPage.READOUT_NAME, percent(slider.value))
    readout.custom_minimum_size = Vector2(SaUI.px(SaPage.READOUT_WIDTH), 0)
    readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    return readout


## A slider row's readout and hint at *value*. The row writes the hint, its
## field and its line alike, so a dump and the search read the scale on screen
## rather than the one the page was built at.
func _relabel(row: SaPageRow, readout: Label, value: float, hint: String) -> void:
    readout.text = percent(value)
    if row != null:
        row.retitle(row.label, hint)


## Whether the dockers open in the main window would leave the painting less of
## its width at *user_scale* than the default layout keeps it,
## `DockerLayoutStore.PAINTING_SHARE`. A docker keeps its width in logical units
## while the scale changes the window's, so the width the dockers stand on is
## the same at every scale and the window's is what moves. A docker let out of
## the window is a window of its own and covers none of it.
##
## False while the page is being built, before it is in the tree, when the
## scale is the one on screen and the fit has already made the room. The store
## is found the way the Layouts and dockers page finds it, under the name
## `MainDockers._init` gives it.
func _dockers_crowd_the_painting_at(user_scale: float) -> bool:
    if not is_inside_tree():
        return false
    var store := get_tree().root.find_child("DockerLayoutStore", true, false) as DockerLayoutStore
    if store == null or not store.dockers_provider.is_valid():
        return false
    var spans: Array[Vector2i] = []
    var host := 0
    for config: Dictionary in store.dockers_provider.call():
        var win := config.get("node") as Window
        if win == null or not win.visible or not win.is_embedded():
            continue
        host = DockerDragHandle.host_size_of(win).x
        spans.append(Vector2i(win.position.x, win.position.x + win.size.x))
    var at_scale := float(host) * SaUI.user_scale / maxf(0.01, user_scale)
    return host > 0 and at_scale - covered_width(spans) < at_scale * DockerLayoutStore.PAINTING_SHARE


## How much of a row the *spans*, each `Vector2i(start, end)`, cover between
## them, a stretch two of them share counted once.
static func covered_width(spans: Array[Vector2i]) -> int:
    var sorted := spans.duplicate()
    sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
    var covered := 0
    var reach: int = sorted[0].x if not sorted.is_empty() else 0
    for span: Vector2i in sorted:
        var start := maxi(span.x, reach)
        if span.y > start:
            covered += span.y - start
        reach = maxi(reach, span.y)
    return covered


## *fraction* as the readout beside either slider shows it, "100%".
static func percent(fraction: float) -> String:
    return str(int(round(fraction * 100.0))) + TranslationServer.translate("%")


func _scale_hint(user_scale: float) -> String:
    var system_pct := int(round(SaUI.scale() / maxf(0.01, SaUI.user_scale) * 100.0))
    var effective_pct := int(round(user_scale * system_pct))
    var hint := (
        tr("On top of the system's %s, so the interface is drawn at %s.")
        % [percent(float(system_pct) / 100.0), percent(float(effective_pct) / 100.0)]
    )
    if _dockers_crowd_the_painting_at(user_scale):
        var share := percent(DockerLayoutStore.PAINTING_SHARE)
        hint += " " + tr("At this scale the dockers open now would leave less than %s of the window to paint in.") % share
    return hint


## The hint under the Font size row at *text_size*, the painter's reading, which
## names the points the stored multiplier draws.
func _font_hint(text_size: float) -> String:
    var font_scale := text_size * SaSettingsValues.DEFAULT_FONT_SCALE
    var points := maxi(1, int(round(float(SaUI.BASE_FONT_SIZE) * font_scale)))
    return (
        tr_n(
            "Text at %d point, and the dockers grow with it. Buttons, margins and icons keep the size the UI scale gives them.",
            "Text at %d points, and the dockers grow with it. Buttons, margins and icons keep the size the UI scale gives them.",
            points
        )
        % points
    )


## One slider: its labels follow every value, and the setting behind it is
## written when the hand is not holding the grabber.
##
## Both sliders re-draw the window around themselves the moment they are
## written. The scale one stretches every logical pixel, so the track moves and
## grows under the pointer, and Godot maps the next motion to a value through
## the track's *new* rectangle: the drag then chases its own handle. The font
## one reflows the page, because a taller label pushes the row under it down. So
## while the grabber is held the interface is left exactly as it is and only the
## two labels move, and the value is applied once, when the hand lets go.
##
## A change that is not a drag, an arrow key or a click on the track, applies at
## once, because there is no gesture in progress for it to disturb.
func _wire_slider(slider: HSlider, relabel: Callable, apply: Callable) -> void:
    slider.drag_started.connect(func() -> void: held = slider)
    slider.drag_ended.connect(
        func(changed: bool) -> void:
            held = null
            if changed:
                _apply_and_hold(slider, apply)
    )
    slider.value_changed.connect(
        func(val: float) -> void:
            relabel.call(val)
            if held != slider:
                _apply_and_hold(slider, apply)
    )


## Writes the value through `apply`, then puts the window back so the point on
## the track the value sits at is where it was.
##
## Best effort, and it says so: the window is the only thing free to move, and
## `fit_to_host` keeps Preferences inside its host, so a scale large enough to
## leave the window filling the host has nowhere to give the correction back
## from. The drag path above is what makes that rare rather than constant.
func _apply_and_hold(slider: HSlider, apply: Callable) -> void:
    var anchor := grip_screen_point(slider)
    apply.call(slider.value)
    _hold_still(slider, anchor)
    # A second pass next frame, because the containers re-sort deferred and the
    # grip has not finished moving yet. It cannot compound: each pass measures
    # what drift is left rather than repeating the last correction.
    _hold_still.call_deferred(slider, anchor)


func _hold_still(slider: HSlider, anchor: Vector2) -> void:
    var window := get_window()
    if window == null or slider == null or not is_instance_valid(slider):
        return
    var drift := anchor - grip_screen_point(slider)
    if drift.length() < 0.5:
        residual = drift
        return
    var wanted := Vector2(window.position) + drift / _screen_units_per_window_unit(window)
    window.position = _within_host(window, Vector2i(wanted.round()))
    residual = anchor - grip_screen_point(slider)


## Where a slider's grip sits in physical screen pixels, which is the only space
## the pointer and the interface agree in.
##
## An embedded subwindow's position is measured in the host viewport's logical
## units and drawn through the root's transform, while a real OS window's is
## already physical and its own content scale applies inside it. Reading either
## one as the other is a mistake that misplaces injected input.
func grip_screen_point(slider: HSlider) -> Vector2:
    var window := get_window()
    if window == null or slider == null or not is_instance_valid(slider):
        return Vector2.ZERO
    var rect := slider.get_global_rect()
    var span: float = maxf(0.001, slider.max_value - slider.min_value)
    var along: float = clampf((slider.value - slider.min_value) / span, 0.0, 1.0)
    var local := rect.position + Vector2(rect.size.x * along, rect.size.y * 0.5)
    if not window.is_embedded():
        return Vector2(window.position) + local * window.content_scale_factor
    var tree := get_tree()
    if tree == null or tree.root == null:
        return local
    return tree.root.get_final_transform() * (Vector2(window.position) + local)


## How many physical screen pixels one unit of `window.position` is worth.
func _screen_units_per_window_unit(window: Window) -> float:
    if not window.is_embedded():
        return 1.0
    var tree := get_tree()
    if tree == null or tree.root == null:
        return 1.0
    return maxf(0.01, tree.root.get_final_transform().get_scale().x)


## Keeps an embedded Preferences inside the host it is drawn in, so paying for
## the scale change with the window's position cannot push its title bar out of
## reach. A real OS window is left alone: it is already wherever it was dragged.
func _within_host(window: Window, wanted: Vector2i) -> Vector2i:
    if not window.is_embedded():
        return wanted
    var tree := get_tree()
    if tree == null or tree.root == null:
        return wanted
    var host := Vector2i(tree.root.get_visible_rect().size)
    var last := Vector2i(maxi(0, host.x - window.size.x), maxi(0, host.y - window.size.y))
    return wanted.clamp(Vector2i.ZERO, last)


## The slider's own rectangle in physical screen pixels: where the pointer has
## to be for a value, and how wide a value is worth.
func track_screen_rect(slider: HSlider) -> Rect2:
    var window := get_window()
    if window == null or slider == null or not is_instance_valid(slider):
        return Rect2()
    var rect := slider.get_global_rect()
    if not window.is_embedded():
        var factor := window.content_scale_factor
        return Rect2(Vector2(window.position) + rect.position * factor, rect.size * factor)
    var tree := get_tree()
    if tree == null or tree.root == null:
        return rect
    var transform := tree.root.get_final_transform()
    return Rect2(transform * (Vector2(window.position) + rect.position), transform.get_scale() * rect.size)


## `"ui_scale"` or `"font_size"`, the two names a capture and this page's own
## corrections both address a slider by.
func slider_named(key: String) -> HSlider:
    return _font_slider if key == "font_size" else _scale_slider


## The `ScrollContainer` this page is drawn inside, which is what the wheel
## moves. Found by walking up rather than asked of the window, so the page
## reports the container it is actually in.
func page_scroll() -> ScrollContainer:
    var node: Node = get_parent()
    while node != null:
        var scroll := node as ScrollContainer
        if scroll != null:
            return scroll
        node = node.get_parent()
    return null
