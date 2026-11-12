## A page declared rather than built: sections of rows, each row a kind, a label
## and a binding.
##
## The lifecycle is three steps and there is no fourth. **Declare**, which is
## `build(ui)` running once and appending row descriptions, instantiating
## nothing. **Realize**, which walks the list, making one control per row,
## wiring each control's change to write its binding, and applying every
## dimming rule once against the values it just read. Realizing is the second
## of the page's own three steps. **Update**, which is a control's change
## writing the property and then re-evaluating only the rules that name the
## row that changed. Nothing is rebuilt, nothing loses focus, and a drag in
## progress stays a drag in progress.
##
## The exception the rerun would have made the rule is a page whose *rows*
## change rather than their values, the Keyboard Shortcuts page's rows half when
## a profile change brings other chords. It calls [method rebuild], the
## declaration from the top, and the values a row still exists for survive it.
## Its filter only hides lines, and no other shipped page calls it.
##
## The page draws with the controls `SaSettingsRows` draws today, so a
## Preferences page converted onto this layer later looks the same and
## `ui/settings/tests/test_settings_pages.gd` stays green over it unchanged. No page is
## converted here.
##
## The building is private functions here rather than a class of its own,
## because it reads `sections`, `host` and `_updating` on every call, and a
## file that reaches into one other object that often is a piece of that
## object's class. `translated` stays public, because files outside
## this one call it with no page of their own to hand. The path row is the
## exception, in `path_row/sa_path_row.gd`, because it reads nothing of the page
## and holds a picker and a label of its own. Its helpers take an
## explicit row rather than reading `SaPage.row(key)`, so the parameter is named
## `entry` throughout them: a local called `row` would shadow that method.
class_name SaPage
extends RefCounted

## Set on the container a page realized into, holding the page, so the state
## dump finds a declared page without every page having to register itself.
const PAGE_META := &"sa_page"

## How much of itself a dimmed row keeps.
##
## This settles 0.4 against `SaDisplayPage`'s 0.45, by taking `SaOptionSpec.DIMMED_ALPHA` rather than declaring a second
## number: it is the one the two option surfaces already enforce on every tool
## row a painter meets, and one number in one place is the point of settling it
## at all. The Display page dims by it too now.
const DIMMED_ALPHA: float = SaOptionSpec.DIMMED_ALPHA

## The readout beside a slider, the width `SaSettingsRows.slider_row` draws, so a
## page converted onto the layer keeps its slider where it was. It was 64, twenty
## units of slider on every row.
const READOUT_WIDTH := 44

## What that readout is called, so a refresh can find it from the slider.
const READOUT_NAME := "SliderReadout"

## The meta a slider row bound to a setting carries `settings/<property>` under,
## the name `FactorSlider.value_name` would be if this were one.
const VALUE_NAME_META := &"sa_value_name"

## The metas a control's own mouse filter and focus mode are kept under while a
## rule pass has them overwritten.
const OWN_FILTER_META := &"sa_own_mouse_filter"
const OWN_FOCUS_META := &"sa_own_focus_mode"

## Emitted after any row wrote its value, once per change.
signal row_changed(key: StringName, value: Variant)

var sections: Array[SaPageSection] = []

## What re-runs the declaration. A page built by hand rather than from a
## `build(ui)` function leaves this empty, and [method rebuild] then re-realizes
## the rows it already holds.
var declare: Callable = Callable()

## The container the rows were realized into, and the name a dump knows the page
## by, which is the container's.
var host: Container = null

## Every row by key, filled in as rows are adopted so a `.dims` written before
## its target still resolves.
var _by_key: Dictionary = {}

## True while a refresh is pushing stored values into controls, so a control
## that answers its own setter does not write the value back and, through a
## target's `changed` signal, ask for another refresh.
var _updating: bool = false

## Section -> the column [method realize] drew it as, its heading, its rule and
## its rows, so [method apply_rules] can put a heading away with the rows under
## it.
var _blocks: Dictionary = {}


func _init(declaration: Callable = Callable()) -> void:
    declare = declaration


## Opens a group and answers the section its rows go on.
func section(title: String) -> SaPageSection:
    var block := SaPageSection.new(title)
    sections.append(block)
    return block


## Gives a freshly declared row a key and files it, so `.dims` and a dump can
## name it. Called over every row once [method declare_rows] or
## [method realize] has the whole declaration in hand, never while a section is
## still being built, so a `.named()` chained onto the row that made it always
## wins over the label's own guess. Safe to call twice on the same row, which
## is what happens when both callers reach an already-declared page.
##
## The key is the label snake-cased, `SaOptionSpec.key` being the precedent, and
## a collision earns a numbered suffix and a warning rather than a silently
## shadowed row: two rows called Radius on one page is a declaration that wanted
## `.named()` and did not write it.
func adopt_row(fresh: SaPageRow) -> void:
    if _by_key.get(fresh.key) == fresh:
        return
    if String(fresh.key).is_empty():
        fresh.key = StringName(_free_key(fresh.label))
    elif _by_key.has(fresh.key):
        push_warning("SaPage: two rows called '%s', the second renamed" % String(fresh.key))
        fresh.key = StringName(_free_key(String(fresh.key)))
    _by_key[fresh.key] = fresh
    # Bound by key and not by row. `bind` keeps its arguments as `Variant`s, so
    # binding the row to a signal the row itself owns is a reference the row
    # holds to itself, which GDScript never collects, and every page would leak
    # its rows at exit.
    fresh.changed.connect(_on_row_changed.bind(fresh.key))


## Every row of every section, in declaration order.
func rows() -> Array[SaPageRow]:
    var out: Array[SaPageRow] = []
    for block in sections:
        out.append_array(block.rows)
    return out


## The row of that key, null for none.
##
## Asked of the rows and not of `_by_key`, which files a row under the key its
## label gave it before `.named()` has run, so a named row would answer null.
func row(key: StringName) -> SaPageRow:
    for declared in rows():
        if declared.key == key:
            return declared
    return null


## Runs the declaration, when there is one, then gives every row its key.
## Declaring twice on one page is what [method rebuild] does and nothing else
## should.
func declare_rows() -> void:
    if declare.is_valid():
        declare.call(self)
    for entry in rows():
        adopt_row(entry)


## Draws the page into *into*, replacing whatever was there.
##
## Adopts every row first, whether it went through [method declare_rows] or was
## appended to a section by hand with no declaration at all: a section holds no
## page of its own to call back into, so this is where such a row gets its key.
func realize(into: Container) -> void:
    host = into
    for entry in rows():
        adopt_row(entry)
    # A node the tree may still touch this frame is queued, one outside it is
    # freed at once. `queue_free` on a container that is not in a tree is never
    # collected at all, which a suite building pages offscreen pays for in
    # leaked objects and the runner fails the run over.
    var live := into.is_inside_tree()
    for child in into.get_children():
        into.remove_child(child)
        if live:
            child.queue_free()
        else:
            child.free()
    into.set_meta(PAGE_META, self)
    if into is VBoxContainer:
        SaSettingsRows.setup_page(into as VBoxContainer)

    var targets: Array[Object] = []
    _blocks.clear()
    for block in sections:
        var section_rows := SaSettingsRows.section(into, translated(block.title))
        _blocks[block] = section_rows.get_parent()
        for entry in block.rows:
            _draw(self, entry, section_rows, into)
            if entry.target != null and not targets.has(entry.target):
                targets.append(entry.target)

    # A target that can say when it changed is listened to, and a page that
    # opens re-reads everything anyway, because the second covers a target with
    # no signal at all. Through a node, for the reason `SaPageWatch` carries. A
    # page that binds nothing has nothing to hear from, and its host keeps only
    # what the declaration put there: the shortcut rows' host is walked child by
    # child as sections.
    if not targets.is_empty():
        var watch := SaPageWatch.new(self)
        into.add_child(watch)
        for target in targets:
            watch.watch(target)
    refresh()


## Re-reads every binding into its control, for a change made behind the page's
## back.
##
## Both halves are here: a target carrying a `changed`
## signal is subscribed to at realize time, and a page that opens re-reads
## everything, because the second covers a target that has no signal. The
## Display page's roll-off switch read its setting at construction while the
## View transform dropdown wrote the same setting, and the switch went on saying
## what it had read.
func refresh() -> void:
    if _updating:
        return
    _updating = true
    for entry in rows():
        push_value(entry)
    _updating = false
    apply_rules()


## Re-evaluates every rule of the page and dims or hides what they name.
##
## Every rule of every row, rather than only the ones the last change touched,
## because a page has tens of rows and the arithmetic is a dictionary lookup
## each. What a refresh forbids is rebuilding a control, not
## reading a value.
##
## **Only a row some rule names is touched**, rather than `disabled`, `visible`
## and the focus of every row on the page, which would put back a Delete button
## a page disabled itself or a restart note it hid itself at the next change to
## any other row.
##
## **A section whose rows a rule has all hidden goes with them**, heading and
## rule included, so a dialog never lists headings with nothing under them.
## Only a section holding a row some hide rule names is touched, so
## a page that hides a heading of its own keeps it hidden.
func apply_rules() -> void:
    var live := {}
    var shown := {}
    for entry in rows():
        var value: Variant = entry.read()
        for rule in entry.dim_rules:
            var key := SaPageRow.resolved_key(rule["key"])
            live[key] = bool(live.get(key, true)) and _holds(rule["values"] as Array, value)
        for rule in entry.hide_rules:
            var key := SaPageRow.resolved_key(rule["key"])
            shown[key] = bool(shown.get(key, true)) and _holds(rule["values"] as Array, value)
    for entry in rows():
        if live.has(entry.key):
            set_live(entry, bool(live[entry.key]))
        if shown.has(entry.key) and entry.line != null and is_instance_valid(entry.line):
            entry.line.visible = bool(shown[entry.key])
    for block in sections:
        _show_block(block, shown)


## Shows the column *block* was drawn as while the rules leave any of its rows
## on screen, when a rule in *shown* names one of them, and leaves it alone
## otherwise. Read from the rules and not from each line's `visible`, because
## the Preferences search hides lines too, and a section put away under a search
## would stay away once the search was cleared. A column freed with its host is
## dropped before any cast, because `as` on a freed object is a script error.
func _show_block(block: SaPageSection, shown: Dictionary) -> void:
    var held: Variant = _blocks.get(block)
    if not is_instance_valid(held):
        _blocks.erase(block)
        return
    var column := held as Control
    var ruled := false
    var any_shown := false
    for entry in block.rows:
        ruled = ruled or shown.has(entry.key)
        if entry.line != null and bool(shown.get(entry.key, true)):
            any_shown = true
    if ruled:
        column.visible = any_shown


## The declaration from the top, for a page whose rows change rather than their
## values. Values survive it by key, which is what an unbound row needs and a
## bound one gets from its target anyway.
func rebuild() -> void:
    var kept := {}
    for entry in rows():
        kept[entry.key] = entry.read()
    if declare.is_valid():
        sections.clear()
        _by_key.clear()
        declare_rows()
    for entry in rows():
        if kept.has(entry.key) and entry.target == null:
            entry.value = kept[entry.key]
    if host != null and is_instance_valid(host):
        realize(host)


## What the page is: its sections and whether each is on screen, its rows, each
## row's label, kind, value, bound target and whether it reads as live and on
## screen.
##
## The point of declaring rather than building. This is what the dump prints and
## what a search index would read, and a page that cannot say what it is is the
## thing the layer exists to stop.
func describe() -> Dictionary:
    var blocks: Array = []
    for block in sections:
        var held: Variant = _blocks.get(block)
        var on_screen := not is_instance_valid(held) or (held as Control).visible
        var described := block.rows.map(func(r: SaPageRow) -> Dictionary: return r.describe())
        blocks.append({"title": block.title, "shown": on_screen, "rows": described})
    return {"sections": blocks, "rows": rows().size()}


## Every declared page on screen, keyed by the container it was realized into.
##
## Untyped walk on purpose. A cast to this file's own `class_name` inside a
## static function leaks the script, which costs hundreds of live
## objects, so the page comes back out of the meta as an `Object` and answers
## through `describe`.
static func capture_state(root: Window) -> Dictionary:
    var out: Dictionary = {}
    if root == null:
        return out
    for window in ([root] as Array[Node]) + root.find_children("*", "Window", true, false):
        for node in (window as Window).find_children("*", "Container", true, false):
            var box := node as Container
            if box == null or not box.has_meta(PAGE_META):
                continue
            var page: Object = box.get_meta(PAGE_META)
            if page != null and page.has_method("describe"):
                out[String(box.name)] = page.call("describe")
    return out


## Pushes a row's stored value into its control, for a change made behind the
## page's back. The page's own guard is what keeps this from writing back.
static func push_value(entry: SaPageRow) -> void:
    var control := entry.control
    if control == null or not is_instance_valid(control):
        return
    var value: Variant = entry.read()
    match entry.kind:
        SaPageRow.Kind.TOGGLE:
            (control as CheckButton).button_pressed = value != null and bool(value)
        SaPageRow.Kind.SLIDER, SaPageRow.Kind.NUMBER:
            # `set_value_no_signal` rather than `value`, because a `Range` does
            # not emit `value_changed` in the frame a script assigns to it: the
            # write-back would land a frame later, after the page's guard had
            # gone down. The silent setter is the same fact from the other side
            # and needs no guard at all.
            var moved := control as Range
            moved.set_value_no_signal(entry.shown_value(float(value if value != null else 0.0)))
            _show_readout(entry, moved)
        SaPageRow.Kind.CHOICE:
            _select_choice(entry, control as SaChoiceButton, value)
        SaPageRow.Kind.TEXT:
            # A field that has the keyboard is somebody typing, and a refresh
            # that lands on it would put the stored words back under the caret.
            var edit := control as LineEdit
            if not (edit.is_inside_tree() and edit.has_focus()):
                edit.text = entry.shown_text(value)
        SaPageRow.Kind.COLOUR:
            (control as ColorPickerButton).color = value if value is Color else Color.WHITE
        SaPageRow.Kind.PATH:
            SaPathRow.show(control, entry.shown_text(value))
        SaPageRow.Kind.CUSTOM:
            # A `SaSlider` holds the number its control draws, so the page moves
            # it the way it moves every kind above, silently and for the same
            # reason. So is a module's control that holds a number, which is
            # shown what its binding holds. Any other row a module declared with
            # `ui.custom` holds no value of its own: its callable builds the
            # control from the declaration's numbers, and a record's are handed
            # to it before the control exists, so it is left alone.
            if entry is SaSlider and control is FactorSlider and entry.value != null:
                (control as FactorSlider).set_value_no_signal(float(entry.value))
            elif control is SaValueControl and value != null:
                (control as SaValueControl).show_value(float(value))
            elif control is SaStopSlider:
                (control as SaStopSlider).value = value


## Greys a row and refuses the hand, or puts both back.
##
## **Dimmed also means disabled**: a control that is greyed and still moves is
## never what a painter asking for dimming means. The
## whole line dims, so the label greys with the control, and every control in it
## is disabled, because a slider row is a slider and a readout and a path row is
## a label and two buttons.
##
## **Back means back to what the control asked for**, not to STOP and FOCUS_ALL
## for everything. STOP on every descendant of a live row would make the
## `Label` a `FactorSlider` builds click-through on purpose into a full-rect
## control that eats every press before the slider's `_gui_input` sees one, and
## no filter slider could be dragged. A control's own filter and focus
## mode are noted the first time a pass touches it and put back on every live
## pass, so a custom control keeps the routing it chose and a plain one keeps
## Godot's default.
static func set_live(entry: SaPageRow, on: bool) -> void:
    var line := entry.line
    if line == null or not is_instance_valid(line):
        return
    line.modulate = Color(1.0, 1.0, 1.0, 1.0 if on else DIMMED_ALPHA)
    for node in ([line] as Array[Node]) + line.find_children("*", "Control", true, false):
        var control := node as Control
        if control == null:
            continue
        if "disabled" in control:
            control.set("disabled", not on)
        elif "editable" in control:
            control.set("editable", on)
        if not control.has_meta(OWN_FILTER_META):
            control.set_meta(OWN_FILTER_META, control.mouse_filter)
            control.set_meta(OWN_FOCUS_META, control.focus_mode)
        if on:
            control.mouse_filter = control.get_meta(OWN_FILTER_META) as Control.MouseFilter
            control.focus_mode = control.get_meta(OWN_FOCUS_META) as Control.FocusMode
        else:
            control.mouse_filter = Control.MOUSE_FILTER_IGNORE
            control.focus_mode = Control.FOCUS_NONE


static func _holds(values: Array, value: Variant) -> bool:
    if values.is_empty():
        return true
    for wanted: Variant in values:
        if wanted == value or (_numeric(wanted) and _numeric(value) and is_equal_approx(float(wanted), float(value))):
            return true
    return false


static func _numeric(value: Variant) -> bool:
    var kind := typeof(value)
    return kind == TYPE_INT or kind == TYPE_FLOAT or kind == TYPE_BOOL


static func _draw(page: SaPage, entry: SaPageRow, rows_box: Container, host_box: Container) -> void:
    entry.control = null
    entry.line = null
    if entry.kind == SaPageRow.Kind.NOTE:
        entry.line = SaSettingsRows.note(rows_box, translated(entry.explanation))
        _name_node(entry, entry.line)
        return
    # The outer control is what the row shows, `entry.control` what it reads: a
    # slider row is a box holding a slider and its readout, and the value lives
    # on the slider.
    var outer := _control_for(page, entry, host_box)
    if entry.control == null:
        entry.control = outer
    _name_node(entry, entry.control)
    # An action row's button carries the label, so the label column stays empty:
    # a button says what it does and a title repeating it beside it is the
    # doubling the row shape exists to stop. One that declared `button()` has a
    # title that is not the button's words, and keeps it. A `FactorSlider`
    # carries its caption inside the box as its prefix, for the same reason.
    var untitled := (entry.kind == SaPageRow.Kind.ACTION and entry.button_text.is_empty()) or outer is FactorSlider
    var title := "" if untitled else translated(entry.label)
    # `SaSettingsRows.row` writes both size flags of whatever it is handed, and a
    # custom control was sized by the page that made it.
    var own_width := outer.size_flags_horizontal if outer != null else Control.SIZE_FILL
    var own_height := outer.size_flags_vertical if outer != null else Control.SIZE_FILL
    if _spans_bare(page, entry, outer):
        _place_bare(entry, outer, rows_box)
        return
    entry.line = SaSettingsRows.row(rows_box, title, translated(entry.explanation), outer)
    if not entry.search_words.is_empty():
        entry.line.set_meta(SaSettingsRows.WORDS_META, translated(entry.search_words))
    if entry.kind == SaPageRow.Kind.SLIDER:
        entry.control.tooltip_text = title
    if entry.kind == SaPageRow.Kind.TOGGLE and not entry.explanation.is_empty():
        entry.control.tooltip_text = translated(entry.explanation)
    if entry.kind == SaPageRow.Kind.CUSTOM and outer != null:
        _place_custom(entry, outer, own_width, own_height)
    # `SaSettingsRows.row` fills the control column for a bare slider, line edit
    # or dropdown and shrinks anything else, and a slider or a path row is a
    # box. The same line `slider_row` writes after its own call, for the same
    # reason.
    if entry.kind == SaPageRow.Kind.SLIDER or entry.kind == SaPageRow.Kind.PATH:
        outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Whether a custom row goes into the rows container bare, with no line around
## it. One with no label on a page that draws spanning rows bare does. A
## `FactorSlider` carries its caption inside the bar and is a row like any other.
static func _spans_bare(page: SaPage, entry: SaPageRow, outer: Control) -> bool:
    if entry.kind != SaPageRow.Kind.CUSTOM or outer == null or outer is FactorSlider:
        return false
    return entry.label.is_empty() and not page.spanning_row_keeps_line()


## A spanning row the way a note is drawn: the control itself in the rows
## container, `entry.line` the control, no `ROW_META` because it is no label
## column beside a control, and both size flags as the page handed them over.
##
## **The default width flag stays too.** In the rows container, which is a
## `VBoxContainer`, `SIZE_FILL` already takes the page's width, so a control
## that asked for nothing spans and one that asked for a narrower flag gets it.
## The vertical flag is what lets a browser take the page's spare height, and
## nothing between the control and the section now stands in its way.
static func _place_bare(entry: SaPageRow, outer: Control, rows_box: Container) -> void:
    rows_box.add_child(outer)
    entry.line = outer
    if outer.tooltip_text.is_empty() and not entry.explanation.is_empty():
        outer.tooltip_text = translated(entry.explanation)
    if not entry.search_words.is_empty():
        outer.set_meta(SaSettingsRows.WORDS_META, translated(entry.search_words))


## Whether a custom row with no label keeps the line a titled row has, with its
## label column hidden, rather than going into the rows container bare. A plain
## page answers no. `SaDialog` answers yes, and says why.
func spanning_row_keeps_line() -> bool:
    return false


## Gives a custom control back the width it was handed over with, and lets one
## with no label span a page whose spanning rows keep their line.
##
## The default `SIZE_FILL` is not put back, because in a row it draws exactly as
## the `SIZE_SHRINK_BEGIN` the row shape chose and `ui/settings/tests/test_settings_pages.gd`
## reads a dropdown on a row for `SIZE_EXPAND_FILL`.
##
## A spanning row on such a page hides the label column and drops `ROW_META`,
## because a row is a label column beside a control and this is neither to the
## search nor to the suite that measures the column.
static func _place_custom(entry: SaPageRow, outer: Control, own_width: int, own_height: int) -> void:
    if own_width != Control.SIZE_FILL:
        outer.size_flags_horizontal = own_width as Control.SizeFlags
    if not entry.label.is_empty() or outer is FactorSlider:
        return
    entry.line.remove_meta(SaSettingsRows.ROW_META)
    entry.line.get_child(0).visible = false
    if own_width == Control.SIZE_FILL:
        outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # A control that asked for the page's spare height gets it through the line.
    outer.size_flags_vertical = own_height as Control.SizeFlags
    entry.line.size_flags_vertical = own_height as Control.SizeFlags


static func _name_node(entry: SaPageRow, made: Control) -> void:
    if made != null and not entry.node_name.is_empty():
        made.name = entry.node_name


static func _control_for(page: SaPage, entry: SaPageRow, host_box: Container) -> Control:
    match entry.kind:
        SaPageRow.Kind.TOGGLE:
            var check := CheckButton.new()
            check.toggled.connect(func(on: bool) -> void: _wrote(page, entry, on))
            return check
        SaPageRow.Kind.SLIDER:
            return _slider(page, entry)
        SaPageRow.Kind.NUMBER:
            var spin := NumberField.new()
            spin.min_value = entry.min_value
            spin.max_value = entry.max_value
            spin.step = entry.step_value
            # The engine puts a space of its own before a spin box's suffix, so
            # the one a unit carries for a readout would be a second.
            spin.suffix = entry.suffix.strip_edges(true, false)
            spin.value_changed.connect(func(val: float) -> void: _wrote(page, entry, entry.stored_value(val)))
            _fit_number(spin)
            return spin
        SaPageRow.Kind.CHOICE:
            # `SaChoiceButton` rather than the engine's `OptionButton`: the list
            # is `SaChoicePopup`, so every row is a Control the note mode can
            # point at, an icon is drawn at the row's height, and the chosen row
            # is a mark that stays put while the pointer moves over the list. The
            # rows carry the row's own ids, so the signal is the value the
            # setting stores and nothing counts indices any more.
            var option := SaMake.choice(null, "Choice", entry.choices)
            option.choice_picked.connect(func(value: Variant) -> void: _wrote(page, entry, value))
            return option
        SaPageRow.Kind.TEXT:
            var edit := SaMake.line_edit(null, "Text")
            # Both commit paths, because the one bound text row in the tree
            # wires both by hand and the pattern is written down nowhere.
            edit.text_submitted.connect(func(text: String) -> void: _typed(page, entry, text))
            edit.focus_exited.connect(func() -> void: _typed(page, entry, edit.text))
            return edit
        SaPageRow.Kind.COLOUR:
            var picker := ColorPickerButton.new()
            picker.edit_alpha = true
            picker.custom_minimum_size = Vector2(SaUI.px(64), SaUI.px(SaUI.BASE_BTN_H))
            picker.color_changed.connect(func(color: Color) -> void: _wrote(page, entry, color))
            return picker
        SaPageRow.Kind.PATH:
            return SaPathRow.make(func(picked: String) -> void: _wrote(page, entry, picked), host_box)
        SaPageRow.Kind.ACTION:
            # The button carries the label and the label column stays empty: a
            # button says what it does, and a title repeating it beside it is
            # the doubling the row shape exists to stop.
            var button := SaMake.button(
                null, "Action", translated(entry.label if entry.button_text.is_empty() else entry.button_text)
            )
            button.pressed.connect(func() -> void: _pressed(entry))
            return button
    # A control that holds a number writes the row the way a slider does, so a
    # module's own widget is bound like the kinds above.
    var holds := entry.custom_control as SaValueControl
    if holds != null:
        holds.value_changed.connect(func(moved: float) -> void: _wrote(page, entry, moved))
    return entry.custom_control


## The slider and its readout, the shape `SaSettingsRows.slider_row` draws with
## one difference: the number is formatted by the row's own decimals, scale and
## suffix rather than by a hard-coded `"%.2f"`. The Timelapse cap reading
## `1024.00` megabytes on the page and `1024` in the docker is what one format
## for every slider in the tree costs.
static func _slider(page: SaPage, entry: SaPageRow) -> Control:
    var box := SaMake.row(null, "SliderBox", SaTheme.GAP)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var slider := HSlider.new()
    # The wheel belongs to the page that scrolls, which has no undo for a
    # value moved by a notch passing over the track.
    slider.scrollable = false
    slider.min_value = entry.shown_value(entry.min_value)
    slider.max_value = entry.shown_value(entry.max_value)
    slider.step = entry.step_value
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    if entry.target == SaSettings:
        slider.set_meta(VALUE_NAME_META, StringName("settings/%s" % entry.property))
    box.add_child(slider)

    var readout := SaMake.label(box, READOUT_NAME)
    readout.custom_minimum_size = Vector2(SaUI.px(READOUT_WIDTH), 0)
    readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

    slider.value_changed.connect(
        func(val: float) -> void:
            readout.text = _readout(entry, val)
            _wrote(page, entry, entry.stored_value(val))
    )
    entry.control = slider
    return box


## A number field as wide as the widest value it can hold, with its prefix and
## suffix. The engine sizes the field by its theme's `minimum_character_width`,
## four characters, which showed a wait of 1000 ms as "000 m" on all thirteen
## docker pages. Measured again by `NumberField` whenever the theme changes,
## because the font size follows the interface scale, and asked of the box
## under the field's type: a theme change reaches the box first, and the
## field's own cache still answered the engine's sixteen it was built at off
## the tree, which cut "1000 ms" to "1000 m" in a window drawing twenty.
static func _fit_number(spin: SpinBox) -> void:
    var line := spin.get_line_edit()
    var font := spin.get_theme_font(&"font", &"LineEdit")
    var font_size := spin.get_theme_font_size(&"font_size", &"LineEdit")
    var widest := 0.0
    for value: float in [spin.min_value, spin.max_value]:
        var shown := _spin_text(spin, String.num(value, SaPageRow.step_places(spin.step)))
        widest = maxf(widest, font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    # One character more for the caret and the rounding of a scaled font.
    widest += font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var style := line.get_theme_stylebox(&"normal")
    if style != null:
        widest += style.get_minimum_size().x
    line.custom_minimum_size.x = ceilf(widest)


## *number* as a spin box draws it, with the space the engine puts between it
## and a prefix or a suffix.
static func _spin_text(spin: SpinBox, number: String) -> String:
    var text := number
    if not spin.prefix.is_empty():
        text = spin.prefix + " " + text
    if not spin.suffix.is_empty():
        text += " " + spin.suffix
    return text


## Every user-facing string the builder draws passes through here, which matters because
## the pages hold a hundred and sixty `tr()` calls, and a missed one is
## invisible until the language is switched. Through
## the server rather than through `Object.tr`, because a static builder has no
## instance to ask. Public, because `sa_page_demo.gd`, `sa_dialog.gd`,
## `sa_slider.gd`, `sa_path_row.gd` and others call it with no page of their own to hand.
static func translated(text: String) -> String:
    return "" if text.is_empty() else String(TranslationServer.translate(text))


## The number beside a slider, in the row's decimals with the zeros a whole
## value leaves trimmed, and the unit after it: "315°", "4" and "4.25" on a
## row that steps by a quarter.
static func _readout(entry: SaPageRow, shown: float) -> String:
    var number := "%.*f" % [entry.shown_places(), shown]
    if number.contains("."):
        number = number.rstrip("0").trim_suffix(".")
    return number + entry.suffix


## Writes the number beside a slider, for a value the page pushed rather than a
## hand moved. Found from the slider, because the row holds the slider and the
## readout is its sibling.
static func _show_readout(entry: SaPageRow, moved: Range) -> void:
    var box := moved.get_parent()
    if box == null:
        return
    var readout := box.get_node_or_null(NodePath(READOUT_NAME)) as Label
    if readout != null:
        readout.text = _readout(entry, moved.value)


## The stored value shown as the chosen row, by the row's own id rather than by
## its position, and through the near-equal branch a stored float needs when the
## id it stands for is written as an int.
##
## A value no row stands for keeps the words the button shows and lets go of the
## value behind them. Holding the old value made a press on the row the button
## names read as no move, so `choice_picked` never fired and the profile could
## not be put back on that row from the page.
static func _select_choice(entry: SaPageRow, option: SaChoiceButton, value: Variant) -> void:
    if option == null:
        return
    for index in entry.choices.size():
        var id: Variant = (entry.choices[index] as Dictionary).get("id", index)
        if id == value or (_numeric(id) and _numeric(value) and is_equal_approx(float(id), float(value))):
            option.select_value(id)
            return
    option.clear_choice(option.text)


## A control answered its own setter, which a refresh does on every row. The
## page's guard is read rather than asked for, because a private member is
## written by its own class and read by anyone.
static func _wrote(page: SaPage, entry: SaPageRow, value: Variant) -> void:
    if page._updating:
        return
    entry.write(value)
    # A path or a text row shows what the binding now holds and not what was
    # handed to it: the settings folder answers "" with the default folder, and
    # a globalized row stores `user://` and shows the real one.
    if entry.kind == SaPageRow.Kind.PATH or entry.kind == SaPageRow.Kind.TEXT:
        push_value(entry)


## A text row's commit. Leaving a globalized field untouched is not a write:
## the field holds the real path, and writing that back would replace the
## `user://` the setting stores with what it was only shown as.
static func _typed(page: SaPage, entry: SaPageRow, text: String) -> void:
    if entry.shows_global_path and text == entry.shown_text(entry.read()):
        return
    _wrote(page, entry, text)


static func _pressed(entry: SaPageRow) -> void:
    if entry.action.is_valid():
        entry.action.call()
    entry.changed.emit(null)


func _on_row_changed(value: Variant, changed_key: StringName) -> void:
    row_changed.emit(changed_key, value)
    if not _updating:
        apply_rules()


func _free_key(from: String) -> String:
    var base := from.to_snake_case()
    if base.is_empty():
        base = "row"
    var candidate := base
    var index := 2
    while _by_key.has(StringName(candidate)):
        candidate = "%s_%d" % [base, index]
        index += 1
    return candidate


## The one node a realized page adds: what listens to a binding's target for a
## change made behind the page's back.
##
## A node, and not a `Callable` from the target straight to the page, because
## that is a reference cycle GDScript never collects. `SaPage` is `RefCounted`,
## it holds its rows, a row holds its target, and a target holding a connection
## back to the page closes the ring: the page keeps the target alive and the
## target keeps the page alive, and a suite that builds a page per test leaks
## every object in it. A signal connection to a `Node` counts no reference, so
## the ring is open here, and freeing the container the page was realized into
## frees the watch and lets the page go.
##
## An inner class rather than a sibling file, because the reason above is the
## whole of its subject and a reader looking for why a page owns a node has one
## place to look.
class SaPageWatch:
    extends Node

    var _page: SaPage = null

    func _init(page: SaPage = null) -> void:
        name = "PageWatch"
        _page = page

    ## Listens to *target* when it can say it changed. A target that cannot is
    ## not an error: the page re-reads every binding when it opens, which is
    ## the half that covers exactly this.
    func watch(target: Object) -> void:
        if target == null or not target.has_signal("changed"):
            return
        if not target.is_connected("changed", _target_changed):
            target.connect("changed", _target_changed)

    ## A watch a second realize took off its host is only queued, and answers nothing.
    func _target_changed(_property: Variant = null) -> void:
        if _page != null and not is_queued_for_deletion():
            _page.refresh()


## The spin box a number row draws, fitted again on every theme change from
## `_notification`, which runs after the engine has refreshed the box's theme
## cache. `theme_changed` is sent before that refresh, and a fit from there
## measures the size the box was built at.
class NumberField:
    extends SpinBox

    func _notification(what: int) -> void:
        if what == NOTIFICATION_THEME_CHANGED:
            SaPage._fit_number(self)
