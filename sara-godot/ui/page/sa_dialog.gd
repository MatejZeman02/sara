## What a filter's `build(ui)` is handed: the declarative page plus the three
## things a dialog has and a Preferences page does not.
##
## `SaDialog` is `SaPage` plus a window, so a filter's dialog and a
## Preferences page are one way of declaring, and this adds `title()`, `thumbnail()`, `canvas_preview()`, `preview()` and
## `apply_cancel()` and inherits everything else: the row shape, the binding, the dimming, the
## three-step lifecycle and the description a dump prints. The window is
## [SaFilterDialogWindow], which realizes this into its content and owns the
## rerun.
##
## The six student-facing names of the scripting API, `slider`, `radio`,
## `checkbox`, `dropdown`, `color` and `button`, sit here rather than on a
## section, because a filter's `build` writes `ui.slider(...)` with no section
## at all. They go on one unnamed group, and so does `stops`, the choice
## `radio` offers drawn as one sliding control.
##
## **A row binds to the filter's parameter**. A dialog made by
## [method for_filter] binds every value row to the filter's
## [member SaFilter.store] under the row's key, the label snake-cased unless the
## row was `.named()`, so the filter reads `parameter(&"radius")` and keeps no
## copy. The row's range is the store's clamp. A dialog made with `new()`, or
## for a filter that writes its own `parameters()`, leaves every row holding
## its own value, read back as `radius.value`, as a filter that keeps no store
## reads it.
##
## **What every filter writes, the dialog assumes.** [method for_filter] names
## the window after the filter's `title()`, puts the Preview switch and the
## thumbnail under it after the rows and Apply with Cancel last, unless the `build` declared them
## itself: a `build` that calls any of `thumbnail`, `canvas_preview` or
## `preview` has placed its own pictures, and one that calls `apply_cancel` its
## own buttons. So the box blur's `build` is its one slider.
##
## **The rerun is not the rerun the declarative page forbids.** That rule is
## about widgets: a control is built once and never rebuilt, and a drag in
## progress stays a drag. What runs again here is the student's kernel, which
## is the whole point of a preview, and no control is touched by it.
class_name SaDialog
extends SaPage

## The window's title, what `ui.title("Box blur")` sets.
var dialog_title: String = ""

## How many times the rerun has actually fired. The number a scenario reads to
## say that two changes in one frame cost one run.
var runs: int = 0

## Whether a change is waiting for the frame to end.
var rerun_pending: bool = false

## The picture `thumbnail()` or `preview()` declared, or null for a filter that
## declared neither.
var preview_control: SaFilterPreview = null

## The Preview switch `canvas_preview()` or `preview()` declared, or null for a
## filter that declared neither. The window reads it and never makes one.
var canvas_box: CheckButton = null

var apply_button: Button = null
var cancel_button: Button = null

## The student pressed Apply, or Cancel. The window answers both.
signal applied
signal cancelled

## A change has settled and the filter's `run` should be called again.
signal rerun

## The widgets that want the whole control column rather than their own
## minimum width: the picture under either of its names, the buttons and every
## slider. The Preview switch is not one. Stretched over the column its box was
## a bordered bar the width of the dialog, which read as a field to type in.
##
## The presets row is one of them, because it holds a dropdown, a name field and
## two buttons, and shrunk to its minimum the name field is a sliver.
##
## `SaSettingsRows.row` fills the column for a bare `Slider` or `LineEdit` and
## shrinks anything else, which is right for a page of switches and dropdowns
## and wrong for these. A preview shrunk to its minimum width is nothing at all
## on screen: it was 200 logical pixels tall and zero wide, and the shot showed
## an empty band where the picture should have been.
const FILLING := ["preview", "thumbnail", "apply_cancel", "slider", "presets"]

## The one unnamed group every widget goes on, made on the first widget.
var _widgets: SaPageSection = null

## Row -> the student-facing name that made it, so a dump says `slider` where
## the row's kind says `custom`. By the row itself rather than its key, because
## a widget names itself before [method SaPage.declare_rows] or [method
## SaPage.realize] has given the row a key.
var _widget_names: Dictionary = {}

## Row -> the `build` a [method custom] row is waiting on, called once when
## the dialog is realized and dropped the moment it has answered. By the row
## itself for the same reason `_widget_names` is.
var _custom_builders: Dictionary = {}

## The widgets a row of a filter's dialog binds to its store. A button carries
## no value and a custom row's control holds its own.
const BOUND := ["slider", "checkbox", "dropdown", "radio", "stops", "color"]

## The store the rows are bound to, or null for a dialog whose rows hold their
## own values.
var _store: SaFilter.Store = null

## The filter [method for_filter] made this dialog for, whose values the presets
## row saves and puts back, or null for a dialog made with `new()`.
var _filter: SaFilter = null

## The parameter [method click] keeps the clicked pixel under, empty for a
## dialog that asked for no click.
var _click_key: StringName = &""

## The roll-off pictures [method rolloff] declared, or null for a dialog that
## asked for none.
var _rolloff: Rolloff = null


## The dialog of *filter*: its `build`, the frame it left out, and every value
## row bound to its store when the filter keeps its values there. What every
## window that shows a filter's rows makes, in place of `new()` and `build`.
## Given *filter_key*, the registry's, each slider names the option it moves.
static func for_filter(filter: SaFilter, filter_key: StringName = &"") -> SaDialog:
    var keeps := filter.keeps_values()
    if keeps:
        filter.store.settle()
    var made := SaDialog.new(Callable(), filter.store if keeps else null, filter)
    filter.page = weakref(made)
    filter.build(made)
    made._add_frame(filter.title())
    made._bind_rows(filter_key)
    if not made._click_key.is_empty() and made.preview_control != null:
        made.preview_control.take_clicks()
        made.preview_control.clicked.connect(made._clicked)
    return made


## Runs *filter*'s `build` over a dialog nobody shows, so its store learns every
## parameter, default and range before a record or a `run` reads one. The
## controls the rows made are freed with it, since no window will hold them.
static func declare_filter(filter: SaFilter) -> void:
    filter.store.settle()
    var made := SaDialog.new(Callable(), filter.store)
    filter.build(made)
    made._bind_rows()
    made.free_unrealized()


## `ui.parameter(&"angle", 0.0, -180.0, 180.0)`, a number the filter keeps with
## no row of its own, for the value of a custom control. Nothing on a dialog
## whose rows hold their own values.
func parameter(key: StringName, default: float, low: float, high: float) -> void:
    if _store != null:
        _store.declare_number(key, default, low, high)


## `ui.parameter_value(&"curves", {})`, a value of any kind the filter keeps
## with no row, which a custom control reads and writes whole. *unnamed*, when
## given, is what a record saved before the key existed reads as.
func parameter_value(key: StringName, default: Variant, unnamed: Variant = null) -> void:
    if _store != null:
        _store.declare_value(key, default, unnamed)


## `ui.click(&"seed")`, the area aware fill's click: a press on the preview's
## picture is the document pixel under it, kept under *key* as `[x, y]` in the
## record like any other value, and the filter runs again from it, so `run`
## reads `parameter(&"seed")`. *default* is what it holds before a click. The
## picture is the dialog's, declared or added after the `build`, and a dialog
## that asks for no click answers no press on it.
func click(key: StringName = &"pixel", default: Vector2i = Vector2i(-1, -1)) -> void:
    _click_key = key
    parameter_value(key, [default.x, default.y])


func _clicked(pixel: Vector2i) -> void:
    if _store != null:
        _store.write(_click_key, [pixel.x, pixel.y])
    request_rerun()


## Frees every control a row made that never went into a window, which is a
## dialog declared and not realized. A node outside the tree is never freed by
## anything else, and a suite counts it as leaked.
##
## Each control is freed once, by the row that holds it. The picture and the
## Preview switch are the controls of rows of their own, so the walk reaches them
## there. A second walk over [member preview_control] and [member canvas_box]
## finds both freed already, and building a `Control` array from them prints
## two engine errors for every filter that declares either.
## Both walks are untyped for the same reason: a node freed with an earlier one
## is asked `is_instance_valid` before anything typed is handed it. The second
## walk stays, so a picture or a box no row came to hold is still freed, which
## fixes the same errors from its side.
func free_unrealized() -> void:
    for entry: SaPageRow in rows():
        # `custom_control` and not `control`: the node a declaration hands over
        # sits in the first, and `realize` is what copies it into the second.
        for node: Variant in [entry.custom_control, entry.control]:
            if is_instance_valid(node) and (node as Node).get_parent() == null:
                (node as Node).free()
    for node: Variant in [preview_control, canvas_box]:
        if is_instance_valid(node) and (node as Node).get_parent() == null:
            (node as Node).free()


## *store* is the filter's the rows bind to, and *filter* the one the presets
## row keeps, both given by [method for_filter].
func _init(declaration: Callable = Callable(), store: SaFilter.Store = null, filter: SaFilter = null) -> void:
    super(declaration)
    _store = store
    _filter = filter
    row_changed.connect(_widget_moved)


## `ui.title("Box blur")`, the window's name.
func title(text: String) -> void:
    dialog_title = text


## `ui.thumbnail()`, the small picture of the active layer with the filter run
## over it, for every kind of filter. A filter that shows a
## texture has that texture in it, and a point filter the pass it recorded run
## over a reduced copy of the layer, so the thumbnail is there whatever the
## canvas shows.
##
## A row like any other, with an empty label so the picture fills the control
## column. The declarative page has no layout language on purpose, and a
## picture that placed itself would be the first thing to invent one.
func thumbnail() -> SaPageRow:
    return _named(_picture_row(), "thumbnail")


## `ui.canvas_preview()`, the Preview switch, a row of its own.
## On, the filter is drawn on the canvas while the dialog is open, which is
## not a history step. It starts on.
##
## A switch with its words in the row's label column, the shape of Export's on
## or off rows, where a check box stretched over the dialog read as a field.
## Not "Preview" alone, which the picture's caption already says.
##
## The switch is all this makes. What it drives is the window's, because the
## canvas is: a filter that records a pass has that pass run by the compositor
## over the active layer, and one that shows a texture has no canvas preview, so
## the window greys the switch out for it rather than offering one that does
## nothing. A filter that leaves this out is drawn in its dialog alone.
##
## The switch stands above the picture, whatever order the `build` declared
## them in. The window hides the picture while the switch is on, so a switch
## under it would be pushed down, out from under the pointer, the moment it is
## turned off. Placed here rather than in each `build`, so a stranger's
## module that declares the picture first gets it with no edit.
func canvas_preview() -> SaPageRow:
    canvas_box = SaMake.switch(null, "CanvasPreview", "", true)
    canvas_box.tooltip_text = SaPage.translated("Show the filter on the canvas while you drag. Not a history step.")
    # Translated here so the template holds it, and named so its key stays
    # the same in every language.
    var preview_row := _widgets_section().custom(SaPage.translated("Preview on canvas"), canvas_box).named(&"preview_on_canvas")
    var made := _named(preview_row, "canvas_preview")
    _above_the_picture(made)
    return made


## `ui.preview()`, both of the two calls at once: the picture [method
## thumbnail] makes and the switch of [method canvas_preview], which stands
## above it, so a module written against the one call keeps both behaviours
## without an edit. The picture is named `preview` in the dump, so a caller
## that looks a row up by that name finds it.
func preview() -> SaPageRow:
    var picture := _named(_picture_row(), "preview")
    canvas_preview()
    return picture


## `ui.apply_cancel()`, the two buttons every filter has.
##
## Cancel first and Apply last, which is the order every dialog in the tree
## draws them in, and Apply is the window's default button so Enter presses it.
func apply_cancel() -> SaPageRow:
    var buttons := HBoxContainer.new()
    buttons.name = "ApplyCancel"
    buttons.alignment = BoxContainer.ALIGNMENT_END
    buttons.add_theme_constant_override("separation", SaUI.px(8))

    cancel_button = Button.new()
    cancel_button.name = "CancelButton"
    cancel_button.text = SaPage.translated("Cancel")
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(cancelled.emit)
    buttons.add_child(cancel_button)

    apply_button = Button.new()
    apply_button.name = "ApplyButton"
    apply_button.text = SaPage.translated("Apply")
    apply_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    apply_button.pressed.connect(applied.emit)
    buttons.add_child(apply_button)

    return _named(_widgets_section().custom("", buttons), "apply_cancel")


## `ui.slider(label, soft_min, soft_max, default, options)`.
##
## The three numbers are untyped and passed on as written, because [method
## SaSlider.make] reads whether they were integers to decide the step and the
## decimals: `1, 20, 3` is a count and `0.0, 1.0, 1.0` is a fraction.
func slider(label: String, soft_min: Variant, soft_max: Variant, default: Variant, options: Dictionary = {}) -> SaSlider:
    var made := SaSlider.make(label, soft_min, soft_max, default, options)
    _widgets_section().rows.append(made)
    return _named(made, "slider") as SaSlider


## `ui.checkbox(label, default)`.
func checkbox(label: String, default: bool = false) -> SaPageRow:
    var made := _widgets_section().toggle(label)
    made.value = default
    return _named(made, "checkbox")


## `ui.dropdown(label, choices, default)`, where *default* is the id of the
## entry that starts selected and an entry's id is its index unless the choice
## list said otherwise.
func dropdown(label: String, choices: Array, default: Variant = 0) -> SaPageRow:
    var made := _widgets_section().choice(label, choices)
    made.value = default
    return _named(made, "dropdown")


## `ui.radio(label, choices, default)`, one button per choice, one of them down.
##
## A `CUSTOM` row rather than the `choice` kind, because mapping radio onto the
## dropdown would make two of the six names draw the same control, and a
## student who wrote `radio` and got a dropdown would be right to call it a bug.
func radio(label: String, choices: Array, default: Variant = 0) -> SaPageRow:
    var entries := SaPageSection.normalize_choices(choices)
    var box := HBoxContainer.new()
    box.add_theme_constant_override("separation", SaUI.px(10))
    var group := ButtonGroup.new()
    var made := _widgets_section().custom(label, box)
    made.choices = entries
    made.value = default
    for index in entries.size():
        var entry: Dictionary = entries[index]
        var pick := CheckBox.new()
        pick.text = SaPage.translated(String(entry.get("label", "")))
        pick.button_group = group
        pick.button_pressed = entry.get("id", index) == default
        pick.pressed.connect(_radio_picked.bind(weakref(made), entry.get("id", index)))
        box.add_child(pick)
    return _named(made, "radio")


## `ui.stops(label, choices, default)`, one thumb sliding between a stop per
## choice with the choice's label over it, [SaStopSlider]. A choice may carry a
## `tooltip` beside its id and label, and the control translates both itself.
func stops(label: String, choices: Array, default: Variant = 0) -> SaPageRow:
    var track := SaMake.stops(null, "Stops", choices)
    track.value = default
    var made := _widgets_section().custom(label, track)
    made.choices = track.options
    made.value = default
    track.picked.connect(made.write)
    return _named(made, "stops")


## `ui.color(label, default)`. American here and `colour` on the section it
## goes through, because this is the name the scripting API gives a
## student and that is the name the section's table gives a page.
func color(label: String, default: Color = Color.WHITE) -> SaPageRow:
    var made := _widgets_section().colour(label)
    made.value = default
    return _named(made, "color")


## `ui.button(label, pressed)`, a row that carries no value at all.
func button(label: String, pressed: Callable = Callable()) -> SaPageRow:
    return _named(_widgets_section().action(label, pressed), "button")


## `ui.custom(label, build)`, a widget of the filter's own.
##
## *build* is called once, when the dialog is realized, and answers the `Control`
## the row draws. It is handed [method request_rerun], which is the whole of what
## a widget this page knows nothing about needs from it: a control that changes
## something `run` reads asks for the run itself rather than waiting for a slider
## beside it to be moved.
##
## A row and not a second declaration language. It keeps the label column, the
## explanation and the dimming, and loses the binding, because there is nothing
## here for the page to read: a custom control holds its own value and the
## filter reads it off the member `build` kept. That is why the six names above
## are the closed set and this is the escape hatch beside them.
##
## The one exception is a control that holds a number. A [SaValueControl] on a
## row `.named()` after a key the filter declared with [method parameter] is
## bound to it like a slider, so the dial of the kaleidoscope is written
## `ui.custom("Wedges", make_dial).named(&"angle")` and keeps no copy.
##
## The control is built at realize and never again, as every control of a
## declarative page is: a drag in progress stays a drag,
## and a rebuild would throw away the widget the painter's pointer is on.
func custom(label: String, build: Callable = Callable()) -> SaPageRow:
    var made := _widgets_section().custom(label, null)
    _custom_builders[made] = build
    return _named(made, "custom")


## The highlight roll-off drawn on *into*, the two pictures Preferences >
## Display shows over its own Knee and Desaturation: the curve, and every colour
## with the operator run and without. Both follow the *knee* and *desaturation*
## rows as a drag moves them. Answers the two rows, the curve's first, so a
## filter can hang a rule on them.
##
## A door of its own because a module names only the door, and the curve plot
## and the gamut preview live in `ui/color_space`. The Tonemap's Paper method is
## the view's roll-off applied to a layer, and its dialog shows the same two
## pictures the Display page does.
func rolloff(into: SaPageSection, knee: SaPageRow, desaturation: SaPageRow) -> Array[SaPageRow]:
    _rolloff = Rolloff.new(knee, desaturation)
    var curve_row := into.custom("The curve", _rolloff.curve)
    curve_row.explain(
        tr(
            (
                "How much of a colour's chroma survives, over stored value along the bottom: flat up to the knee, then"
                + " falling the faster the further Desaturation is pushed. The dim line is the magnitude, which stays"
                + " white at white. The dashed mark is the knee."
            )
        )
    )
    var pair_row := into.custom("Every colour", _rolloff.pair)
    pair_row.explain(
        tr("Every hue a screen can show with the roll-off run on the left, and the same picture untouched on the right.")
    )
    var made: Array[SaPageRow] = [curve_row, pair_row]
    return made


## The rules, and then the roll-off pictures read from the rows they follow.
## Here because every change to a row and every refresh of the page ends in this
## pass, so a preset written over the store moves the pictures as a drag does.
func apply_rules() -> void:
    super()
    if _rolloff != null:
        _rolloff.follow()


## `ui.presets()`, the filter's values kept under a name a painter gives them:
## a dropdown of the saved ones, a name field, Save and Delete.
##
## Every filter gets them for this one line, because the row reads what
## `parameters()` answers and puts a preset back through `set_parameters()`,
## which every filter has. They go through [SaPresetStore] as
## [SaFilterPreset] files, in a directory named after the filter's id. On a
## dialog made with `new()` there is no filter to keep, and the row is drawn
## with its buttons off.
func presets() -> SaPageRow:
    return _named(custom("Preset", _make_presets), "presets")


## Asks for a rerun at the end of this frame, whatever else asks between now
## and then.
##
## Deferred rather than counted down in `_process`, because the dialog is
## `RefCounted` and has no frame of its own, and because a deferred call is
## exactly "once, when this frame's work is done". Two widgets moved in one
## frame therefore cost one run, the way the gradient preview coalesces for the
## same reason.
func request_rerun() -> void:
    if rerun_pending:
        return
    rerun_pending = true
    flush_rerun.call_deferred()


## Fires the pending rerun now. The frame boundary in the running app, and what
## a suite calls in place of one.
func flush_rerun() -> void:
    if not rerun_pending:
        return
    rerun_pending = false
    runs += 1
    rerun.emit()


## Puts *texture* in the preview, which is where `ctx.show` ends up.
func show_texture(texture: SaTexture, covering: Rect2i) -> void:
    if preview_control != null and is_instance_valid(preview_control):
        preview_control.show_texture(texture, covering)


## Yes, because a dialog lays its untitled rows out itself in [method realize]
## below, and the filter panel and `test_filter_dialog_columns` read the
## label column of every line, a spanning one included.
func spanning_row_keeps_line() -> bool:
    return true


## Builds the controls, then gives three of the widget kinds the whole control
## column. See [constant FILLING] for which and why.
##
## The custom rows build first, because the control a
## [method custom] builder answers is what the builder draws that row from.
##
## A filling row with no title gives up its label column as well, so it spans
## the dialog. The preview and the buttons are declared with an empty label, and
## a student's slider carries its caption inside the bar, so all three would
## sit beside an empty column, and on a dialog that declares nothing else that
## is the left third of the window with nothing in it. A row with a title keeps its column, and a
## titled row's control still lines up with the others.
func realize(into: Container) -> void:
    _build_customs()
    super(into)
    for wide in rows():
        if not FILLING.has(widget_name(wide.key)) or wide.control == null:
            continue
        wide.control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if wide.line != null and String(wide.line.get_meta(SaSettingsRows.TITLE_META, "")).is_empty():
            wide.line.get_child(0).visible = false


## The page's description, plus the six things only a dialog has: its title,
## how many runs it has asked for, whether one is pending, what the preview is
## showing, where the Preview switch stands and what the roll-off pictures draw.
## Every row gains the student-facing name that declared it.
func describe() -> Dictionary:
    var out := super()
    out["title"] = dialog_title
    out["runs"] = runs
    out["rerun_pending"] = rerun_pending
    out["preview"] = preview_control.describe() if preview_control != null else {}
    out["canvas_preview"] = _describe_canvas_box()
    out["rolloff"] = _rolloff.describe() if _rolloff != null else {}
    for block: Dictionary in out["sections"] as Array:
        for described: Dictionary in block["rows"] as Array:
            described["widget"] = widget_name(StringName(String(described["key"])))
    return out


## The name a student's widget knows the row by, empty for a row declared
## through the page's own kinds.
##
## Looked up by row rather than by key, and the key is asked of the page rather
## than trusted from the caller, because a widget names itself before the row
## has one: `_widget_names` is keyed by the row itself for the same reason.
func widget_name(key: StringName) -> String:
    var found := row(key)
    return String(_widget_names.get(found, "")) if found != null else ""


## Names the window after *default_title* when the `build` did not, and adds
## the pictures and the buttons it did not declare, the pictures after the
## declared rows and the buttons last.
##
## After and not before, which is the order the adjust filters, Levels and
## Curves already declare for themselves: the controls a painter came to move
## first, then what moving them does. Put first, the picture and its switch
## would be the top half of a one-slider window, with the slider under them.
func _add_frame(default_title: String) -> void:
    if dialog_title.is_empty():
        dialog_title = default_title
    var said := _widget_names.values()
    if not (said.has("thumbnail") or said.has("canvas_preview") or said.has("preview")):
        thumbnail()
        canvas_preview()
    if not said.has("apply_cancel"):
        apply_cancel()


## Binds every value row to the store, and gives the store the row's default
## and range. A key the store already holds keeps its value, which is the one a
## record or the last dialog left, and the row opens on it. A slider is named
## for *filter_key* and its row, when the window that shows it gave the key.
func _bind_rows(filter_key: StringName = &"") -> void:
    if _store == null:
        return
    for entry in rows():
        adopt_row(entry)
    for entry in rows():
        var widget := String(_widget_names.get(entry, ""))
        if not BOUND.has(widget) or entry.target != null:
            continue
        match widget:
            "slider":
                _store.declare_number(entry.key, float(entry.value), entry.min_value, entry.max_value)
                # Named for the store's key, which the next dialog of this filter binds again.
                if not filter_key.is_empty() and entry.custom_control is FactorSlider:
                    (entry.custom_control as FactorSlider).value_name = StringName("filter/%s/%s" % [filter_key, entry.key])
            "dropdown", "radio", "stops":
                var ids: Array = []
                for choice: Dictionary in entry.choices:
                    ids.append(choice.get("id"))
                _store.declare_choice(entry.key, entry.value, ids)
            _:
                _store.declare_value(entry.key, entry.value)
        entry.target = _store
        entry.property = NodePath(String(entry.key))
        entry.value = _store.read(entry.key)
        if widget == "radio" and entry.custom_control != null:
            for index in entry.custom_control.get_child_count():
                var pick := entry.custom_control.get_child(index) as CheckBox
                pick.set_pressed_no_signal(entry.choices[index].get("id") == entry.value)
        if entry.custom_control is SaStopSlider:
            (entry.custom_control as SaStopSlider).value = entry.value


## The Preview switch as the dump prints it, empty when none was declared.
func _describe_canvas_box() -> Dictionary:
    if canvas_box == null or not is_instance_valid(canvas_box):
        return {}
    return {"on": canvas_box.button_pressed, "enabled": not canvas_box.disabled}


func _widgets_section() -> SaPageSection:
    if _widgets == null:
        _widgets = section("")
    return _widgets


## Calls every custom row's builder, before `realize` walks the declaration: it
## draws a `CUSTOM` row from the control the row already holds, so the control
## has to exist by the time it looks. By the row itself rather than by its key,
## since [method custom] runs before the row has one.
##
## Called on every [method realize] rather than once for the life of the dialog.
## The control the last one made is a child of the host and goes with it when
## the host is cleared, so skipping the second call would hand the row a freed
## control rather than a second widget. A dialog is realized once and never
## rebuilt, which is what makes that once in the running app.
##
## A control that holds a number, on a row named after a parameter the filter
## declared, is bound to that parameter here, where the control first exists.
## Only then, because a module's panel for curves or a palette sits on a row
## named after its parameter too and keeps writing it itself.
func _build_customs() -> void:
    for waiting: SaPageRow in _custom_builders:
        var build: Callable = _custom_builders[waiting]
        if build.is_valid():
            waiting.custom_control = build.call(request_rerun) as Control
        if waiting.custom_control is SaValueControl and _store != null and _store.has(waiting.key):
            waiting.target = _store
            waiting.property = NodePath(String(waiting.key))


## The picture row both [method thumbnail] and [method preview] declare. One
## picture a dialog, the last declared, since the window fills one.
func _picture_row() -> SaPageRow:
    preview_control = SaFilterPreview.new()
    return _widgets_section().custom("", preview_control)


## Moves *switch* to stand right above the picture row when the picture was
## declared first, and leaves it where it is otherwise. Both rows are on the one
## unnamed group, so the move is within its rows. Right above and not at the
## top, so a row declared between the two stays where its `build` put it.
func _above_the_picture(switch: SaPageRow) -> void:
    var group := _widgets_section().rows
    for index in group.size():
        if group[index] == switch:
            return
        if group[index].custom_control == preview_control and preview_control != null:
            group.erase(switch)
            group.insert(index, switch)
            return


func _make_presets(ask_rerun: Callable) -> Control:
    return PresetsRow.new(_filter, ask_rerun)


func _named(made: SaPageRow, widget: String) -> SaPageRow:
    _widget_names[made] = widget
    return made


## Bound by a `WeakRef` rather than by the row itself, for the reason
## `SaPage.adopt_row` gives: a `bind` argument is a `Variant` and a `Variant`
## holding a `RefCounted` is a strong reference, and the row owns the box that
## owns the button this closure is bound to, so binding the row itself is a
## ring. Not by key, because the key is not settled at the point a widget
## names itself.
func _radio_picked(ref: WeakRef, id: Variant) -> void:
    var picked := ref.get_ref() as SaPageRow
    if picked != null:
        picked.write(id)


func _widget_moved(_key: StringName, _value: Variant) -> void:
    request_rerun()


## The two pictures [method rolloff] places, and the rows they follow.
##
## Inner because it owns nothing but the two controls and the reading of two
## rows into them. The curve is handed over at `SIZE_FILL`, as the Display page
## hands its own, because `SaPage` gives a custom control back the width it was
## handed over with and the plot asks to expand.
class Rolloff:
    extends RefCounted

    var curve: SaCurvePlot = null
    var pair: HBoxContainer = null
    var _operated: SaGamutPreview = null
    var _plain: SaGamutPreview = null
    var _knee: SaPageRow = null
    var _desaturation: SaPageRow = null

    func _init(knee: SaPageRow, desaturation: SaPageRow) -> void:
        _knee = knee
        _desaturation = desaturation
        curve = SaCurvePlot.new()
        curve.size_flags_horizontal = Control.SIZE_FILL
        _operated = SaGamutPreview.new(true)
        _plain = SaGamutPreview.new(false)
        pair = SaGamutPreview.pair(_operated, _plain)
        follow()

    ## Both pictures drawn at the two rows' values as they stand.
    func follow() -> void:
        var knee := float(_knee.read())
        var desaturation := float(_desaturation.read())
        if is_instance_valid(curve):
            curve.configure(knee, desaturation)
        if is_instance_valid(_operated):
            _operated.configure(knee, desaturation)
        if is_instance_valid(_plain):
            _plain.configure(knee, desaturation)

    ## The knee and desaturation the curve is drawn at, for a dump and a suite.
    func describe() -> Dictionary:
        if not is_instance_valid(curve):
            return {}
        var mirrored := is_instance_valid(_plain) and _plain.flip_h
        var gap := pair.get_theme_constant("separation") if is_instance_valid(pair) else -1
        return {"knee": curve.knee, "desaturation": curve.desaturation, "plain_mirrored": mirrored, "gap": gap}


## The row [method presets] draws. The first entry is the filter's defaults, which
## a painter cannot delete, and the rest are the saved presets by name.
class PresetsRow:
    extends HBoxContainer

    var picker: SaChoiceButton = null
    var name_field: LineEdit = null
    var save_button: Button = null
    var delete_button: Button = null
    var _filter: SaFilter = null
    var _presets: SaPresetStore = null
    var _rerun: Callable = Callable()

    func _init(filter: SaFilter, rerun: Callable) -> void:
        _filter = filter
        _rerun = rerun
        if filter != null:
            _presets = SaFilterPreset.store_for(filter.id())
        name = "Presets"
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add_theme_constant_override("separation", SaUI.px(6))
        picker = SaChoiceButton.new()
        # The button clips its text, so beside three other controls it would
        # shrink to its arrow without a width of its own.
        picker.custom_minimum_size.x = SaUI.px(140)
        picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        picker.choice_picked.connect(_picked)
        add_child(picker)
        name_field = LineEdit.new()
        name_field.name = "PresetName"
        name_field.placeholder_text = SaPage.translated("Name")
        name_field.custom_minimum_size.x = SaUI.px(100)
        name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_field.text_submitted.connect(_saved.unbind(1))
        add_child(name_field)
        save_button = Button.new()
        save_button.name = "SavePreset"
        save_button.text = SaPage.translated("Save")
        save_button.tooltip_text = SaPage.translated("Save these settings as a preset with this name.")
        save_button.pressed.connect(_saved)
        add_child(save_button)
        delete_button = Button.new()
        delete_button.name = "DeletePreset"
        delete_button.text = SaPage.translated("Delete")
        delete_button.tooltip_text = SaPage.translated("Delete the selected preset.")
        delete_button.pressed.connect(_deleted)
        add_child(delete_button)
        save_button.disabled = _presets == null
        name_field.editable = _presets != null
        _refill("")

    ## Every saved preset's name, sorted, the defaults not among them.
    func names() -> PackedStringArray:
        return _presets.list_names() if _presets != null else PackedStringArray()

    ## `{"preset": "Soft"}` picks one, `""` the defaults, `{"name": "Soft"}`
    ## types a name, `{"save": true}` presses Save and `{"delete": "Soft"}`
    ## removes one. Several at once run in that order.
    func capture_option_edit(spec: Dictionary) -> String:
        if spec.has("preset"):
            picker.select_value(String(spec["preset"]))
            _picked(String(spec["preset"]))
        if spec.has("name"):
            name_field.text = String(spec["name"])
        if bool(spec.get("save", false)):
            _saved()
        if spec.has("delete") and picker.select_value(String(spec["delete"])):
            _deleted()
        var listed := ", ".join(names()) if not names().is_empty() else "none"
        return "presets are %s, showing %s" % [listed, _shown()]

    func _shown() -> String:
        return _current() if not _current().is_empty() else "the defaults"

    ## The name the list shows, empty for the defaults.
    func _current() -> String:
        var shown: Variant = picker.selected_value()
        return String(shown) if shown is String else ""

    func _refill(current: String) -> void:
        var choices: Array = [{"id": "", "label": SaPage.translated("Defaults")}]
        for preset_name: String in names():
            choices.append({"id": preset_name, "label": preset_name})
        picker.set_choices(choices)
        picker.select_value(current)
        delete_button.disabled = current.is_empty()

    ## Puts the preset *value* on the filter, or its defaults for the first
    ## entry, and asks for a run.
    func _picked(value: Variant) -> void:
        if _filter == null:
            return
        var preset_name := String(value)
        if preset_name.is_empty():
            # `reset` and not an empty record, since a record that names no
            # value reads a key's `unnamed`, which is not its default.
            if _filter.keeps_values():
                _filter.store.reset()
            else:
                _filter.set_parameters({})
        else:
            var values := SaFilterPreset.values_in(_presets, preset_name)
            if values.is_empty():
                return
            _filter.set_parameters(values)
        name_field.text = preset_name
        delete_button.disabled = preset_name.is_empty()
        _rerun.call()

    ## Keeps what the controls show under the typed name, or the first free
    ## "Preset" and a number when none is typed.
    func _saved() -> void:
        if _presets == null:
            return
        var wanted := name_field.text.strip_edges()
        if wanted.is_empty():
            wanted = _free_name()
        var stored := _presets.save_preset(wanted, SaFilterPreset.of(_filter.parameters()))
        if stored.is_empty():
            return
        name_field.text = stored
        _refill(stored)

    func _deleted() -> void:
        var current := _current()
        if _presets == null or current.is_empty():
            return
        _presets.delete_preset(current)
        name_field.text = ""
        _refill("")

    func _free_name() -> String:
        var taken := names()
        var count := 1
        while taken.has(String(TranslationServer.translate_plural("Preset %d", "Preset %d", count)) % count):
            count += 1
        return String(TranslationServer.translate_plural("Preset %d", "Preset %d", count)) % count
