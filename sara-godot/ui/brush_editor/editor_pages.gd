## The brush editor's pages: which ones there are, what order they come in, and
## which one is open.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **An instance the window owns, rather than a page of statics handed the window
## back.** Statics that take the window as their first argument and write its
## fields are one class smeared over two files, so this class owns what it
## writes. The window holds one of these and asks it, and the fields the pages
## write are the pages' own.
##
## **Handed what it works on, and it says what happened**, rather than reaching
## back into the window for the tool, the box, the settings and the page list's
## selection. It is built with the box it fills, `bind_specs` hands it the tool
## and the settings, it keeps which page is open itself, and a write on a page
## is `option_written` or `curve_toggled`, which the window connects.
##
## `PageLayout` below owns one page's rows once they are built, as an inner
## class, because this is the one file that uses it. This file owns which pages
## there are and which one is showing.
class_name SaBrushEditorPages
extends RefCounted

## A row or a module's widget on the open page wrote *key*. The window redraws
## what a setting moves and asks the page again, because a written row can be
## the one another row's condition reads.
signal option_written(key: StringName, value: Variant)

## The curve option or the row called *key*, which a page's switch turns on and
## off, was switched, by the switch at the top of its page or by one above a
## graph.
signal curve_toggled(key: StringName, on: bool)

## The page a spec that names none lands on.
const DEFAULT_PAGE: String = "General"

## **The pages come in the order the tool declared them**: a page appears where
## its first row is declared, rather than by a list of titles held here, which
## would be one module's page order kept in the skeleton. A module that wants
## its pages sorted declares them sorted, and a second engine's pages come in
## the order it asked for without a line here.

## The column the open page is built into.
var _box: VBoxContainer

## What the pages edit, handed over by [method bind_specs].
var _tool_state: ToolState = null
var _settings: Resource = null

## The document's smaller dimension, for the rows that draw a canvas fraction as
## pixels.
var _canvas_min: float = 0.0

## What the blend row's list is filled from and which document its plain
## Normal's bracket names, handed over by [method follow_blend_modes].
##
## Held here rather than read per page, because a page is built fresh on every
## switch and the instance it builds would otherwise be handed neither.
var _blend_registry: SaBlendModeRegistry = null
var _document: SaDocument = null

## Which page is on the right, or -1 for none.
var _open: int = -1

## page title -> {"specs": Array[SaOptionSpec], "curve": SaOptionSpec or null}.
var _pages: Array[Dictionary] = []

## The open page's controls, built and torn down here.
var page_controls: ToolOptionControls = null

## The open page's curve control, for a page that is a curve option (f13).
##
## A `Control` and not the class that draws one: the widget is the declaring
## module's, built through the spec's `build_control` the way the base module's
## ramp is, so the skeleton parses without the stamp brush.
##
## The first of `curve_controls` for a page carrying several, so every reader
## written when a page had one still reads the page's own option.
var curve_control: Control = null

## Every curve control on the open page, in the order the tool declared them.
## Empty for a plain page and one long for every curve page but the one the five
## colour options share.
var curve_controls: Array[Control] = []

## The open page's switch, at the top of the page beside its title, for a page
## with something to switch. Null for a plain page and for the page several
## curve options share, whose switches are above their own graphs.
var page_switch: Button = null

## Everything on the open page below its title, which the page's switch dims
## while it reads Off. Null before a page is shown.
var page_body: VBoxContainer = null

## The lists the open page's `ENUM` rows offered when it was built, so a
## module's widget that rebuilds one is noticed.
var _lists: Dictionary = {}

## Where the open page's rows went, and what a condition does to them.
var _layout: PageLayout = null


func _init(box: VBoxContainer) -> void:
    _box = box


## Takes the pages *specs* declare, in the order they declare them, over *state*
## and its *settings*, and answers the rows the page list on the left is built
## from: which heading each sits under, whether it has a switch and whether that
## is on.
func bind_specs(specs: Array, state: ToolState, settings: Resource, canvas_min: float) -> Array:
    _tool_state = state
    _settings = settings
    _canvas_min = canvas_min
    _open = -1
    _pages = pages_from(specs)
    var rows: Array = []
    for page: Dictionary in _pages:
        var on: Variant = tick_of(page)
        (
            rows
            . append(
                {
                    "title": String(page["title"]),
                    "dynamic": is_dynamic(page),
                    "switch": on != null,
                    "on": on != null and bool(on),
                }
            )
        )
    return rows


## Whether *page* is one of the brush's dynamics rather than one of the pages
## that make it: a page with a curve option on it, or a row flagged
## `page_switch`. The page several colour options share is one, though it has
## no switch of its own, and the tip and the general rows are not.
##
## Read off the specs a tool declares rather than off a list of titles, because
## the titles are a module's and this file names none: a second engine's pages
## fall under one heading or the other by what they carry.
static func is_dynamic(page: Dictionary) -> bool:
    return not (page.get("curves", []) as Array).is_empty() or switch_of(page) != null


## Points every instance this class builds at the blend registry and the
## document the bar's own controls follow, so a page's blend row lists what the
## bar's does.
##
## Handed once per window rather than per page, and applied to the open page at
## once, because the row is on whichever page a painter walked to.
func follow_blend_modes(blend_registry: SaBlendModeRegistry, document: SaDocument = null) -> void:
    _blend_registry = blend_registry
    _document = document
    if page_controls == null:
        return
    page_controls.binding.follow_blend_modes(blend_registry, _live_document())


## The document handed over, or null once a close has freed it. A tab closed
## with the editor open freed the document this still named, and the next page
## built handed the freed one on and stopped the script. Null is the
## answer the controls already take for a window with no document of its own.
func _live_document() -> SaDocument:
    if is_instance_valid(_document):
        return _document
    _document = null
    return null


## How many pages this tool declares.
func count() -> int:
    return _pages.size()


## The title of the page at *index*, or "" for an index this tool has none for.
func title_at(index: int) -> String:
    if index < 0 or index >= _pages.size():
        return ""
    return String(_pages[index]["title"])


## Where the page called *title* is, or -1 for a title this tool has none for.
func index_of(page_title: String) -> int:
    for i in _pages.size():
        if String(_pages[i]["title"]) == page_title:
            return i
    return -1


## The `SaCurveOption` a page's switch is bound to, or null for a plain page.
func curve_option_of(page: Dictionary) -> Resource:
    return _option_of(page.get("curve") as SaOptionSpec)


## The row a page's switch is when the page is not a curve option, or null.
##
## A page has one at most: the first `page_switch` row wins, so a module that
## flags two gets the one it declared first rather than a switch that answers to
## whichever was read last.
static func switch_of(page: Dictionary) -> SaOptionSpec:
    for spec: SaOptionSpec in page.get("specs", []) as Array:
        if spec != null and spec.page_switch:
            return spec
    return null


## Whether the page's switch is on, or null for a page with nothing to switch.
## The page list draws a dot for it and the page draws the switch.
##
## A `Variant` rather than a `bool`, because "no switch" and "a switch that is
## off" are two different pages: the first has nothing at the top of its page
## and no dot to show, the second has both. Reading them back as one `false` is
## what would put a switch on every plain page.
func tick_of(page: Dictionary) -> Variant:
    # A page several curve options share has no switch of its own: one switch
    # cannot say which of five is on, so each option draws its own above its
    # graph and the row on the left draws no dot.
    if (page.get("curves", []) as Array).size() > 1:
        return null
    var option := curve_option_of(page)
    if option != null:
        return bool(option.enabled)
    var spec := switch_of(page)
    if spec == null:
        return null
    var value: Variant = ToolOptionControls.read_spec(spec, _tool_state)
    if value == null:
        return null
    return bool(value)


## The switch of the page at *index*, or null. What the window's ticker asks.
func tick_at(index: int) -> Variant:
    if index < 0 or index >= _pages.size():
        return null
    return tick_of(_pages[index])


## The widget a curve option page is, built by the module that declared the
## option and pointed at *option*.
##
## The module's factory is handed [signal option_written] as its write door, so a
## moved curve marks the session dirty and asks for a preview exactly as a
## written row does. A method rather than a lambda, for the reason the plain page
## gives. The door takes a key and a value, and the widget calls with the value
## alone, so the key is bound and the value dropped: the window ignores both and
## reads the settings.
func _build_curve_control(spec: SaOptionSpec, option: Resource) -> Control:
    if spec == null or not spec.build_control.is_valid():
        push_warning("SaBrushEditorPages: curve option '%s' brought no widget" % (spec.key if spec != null else &""))
        return null
    var write := _on_option_written.bind(spec.key, null).unbind(1)
    var control := spec.build_control.call(spec, write) as Control
    if control == null:
        return null
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if spec.bind_value.is_valid():
        spec.bind_value.call(control, option)
    return control


## The curve option of the page at *index*, or null.
func curve_option_at(index: int) -> Resource:
    if index < 0 or index >= _pages.size():
        return null
    return curve_option_of(_pages[index])


## Builds the page at *index* on the right. The window marks its row in the
## list, which is the window's.
func show_page(index: int) -> void:
    if index < 0 or index >= _pages.size():
        return
    _open = index
    # The profile remembers it, so the bar's Edit Brush button reopens where the
    # painter left off. Written on every switch rather than on close, because an
    # editor closed by the window manager never reaches a close path.
    SaSettings.brush_editor_page = String(_pages[index]["title"])
    var box := _box
    # The body's rows are queued as well as the body, because a row that is
    # going still hears the tool until the frame ends and asks whether it is
    # queued itself, or the tip preview of a page left behind answers the Load
    # Tip of a tool it does not show.
    if page_body != null and is_instance_valid(page_body):
        for row in page_body.get_children():
            row.queue_free()
    for child in box.get_children():
        child.queue_free()
    page_body = null
    page_controls = null
    curve_control = null
    curve_controls = []
    var page := _pages[index]
    _build_title(page, index)
    # The rows and the graphs go in a body of their own under the title, so
    # the page switch dims the whole page and not itself. A row's own dimming,
    # a condition's, is the row's `modulate` and multiplies with this one.
    page_body = SaMake.column(box, "PageBody")
    page_body.add_theme_constant_override(&"separation", box.get_theme_constant(&"separation"))
    page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _layout = PageLayout.new(page_body)

    # The plain rows first, then the curve. A plain page is only rows, and a
    # curve page can carry rows as well as its widget: the Texture page's
    # chooser, scale, offset and invert are declared
    # under the page's title and sit above the strength and the graph, because
    # what paper comes before how much of it.
    var option := curve_option_of(page)
    var rows: Array[SaOptionSpec] = []
    for spec: SaOptionSpec in page["specs"] as Array:
        # `in_editor` is false for a row the editor does not show. The spec
        # stays on the tool, so a preset carries the number and
        # a Krita import writes it, and only the page omits the row.
        if spec != null and spec.in_editor and spec.kind != SaOptionSpec.Kind.CURVE_OPTION:
            rows.append(spec)
    if option == null or not rows.is_empty():
        _build_rows(rows)
    _build_curves(page)
    _lists = _choice_lists()
    _dim_body()


## The page's title across its top, and the page's On/Off switch beside it for
## a page with something to switch.
##
## The switch stands on the page it switches rather than as a checkbox in the
## page list, so a painter sees what they turned on. It
## reads the page's own title, which is the option's own name, "Size" or
## "Masking Brush", rather than "Size follows the pen": a curve option's
## "Enable pen settings" box is `use_curve`, the pen half of the option, and
## `enabled` is the whole option, so "follows the pen" would have named the
## other switch.
func _build_title(page: Dictionary, index: int) -> void:
    page_switch = null
    var row := SaMake.row(_box, "PageTitleRow", SaTheme.GAP)
    var heading := SaMake.label(row, "PageTitle", String(page["title"]))
    SaUI.size_text(heading, SaUI.fraction_of(16))
    heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var on: Variant = tick_of(page)
    if on == null:
        return
    # Beside the title rather than at the far end of the row, where the eye
    # never goes, and the On/Off button the rows draw rather than a small
    # switch a painter misses.
    page_switch = SaOnOffSwitch.make(row, "PageSwitch", bool(on))
    page_switch.tooltip_text = _switch_tooltip(page)
    # A method with the index bound, for the reason `_build_rows` gives.
    page_switch.toggled.connect(_on_page_switch_toggled.bind(index))


## What the page's switch says on hover: the tooltip its own row declares when
## the switch is a row, and a sentence about the option when it is a curve
## option, whose spec's tooltip describes the option rather than the switch.
func _switch_tooltip(page: Dictionary) -> String:
    var spec := switch_of(page)
    if spec != null and not spec.tooltip.is_empty():
        return tr(spec.tooltip)
    if SaWholeSentences.PAGE_SWITCH.has(String(page["title"])):
        return tr(SaWholeSentences.PAGE_SWITCH[String(page["title"])])
    return tr("Turns %s on for this brush. Off, the brush paints as if the page were not there.") % tr(String(page["title"]))


func _on_page_switch_toggled(on: bool, index: int) -> void:
    set_page_enabled(index, on)
    _dim_body()


## Dims the page below its title while the page's switch reads Off, as a
## painter reads a dimmed control as switched off, and lifts it while it reads
## On. Dimmed and not disabled: a setting changed on a switched-off page
## switches the page on, so every row stays live under the tint.
func _dim_body() -> void:
    if page_body == null or not is_instance_valid(page_body):
        return
    var off := page_switch != null and is_instance_valid(page_switch) and not page_switch.button_pressed
    page_body.modulate = Color(1.0, 1.0, 1.0, SaOptionSpec.DIMMED_ALPHA if off else 1.0)


## Puts the open page's switch back onto what it switches without a signal, for
## a switch moved from somewhere else: a preset loaded, a row on the bar, the
## capture step.
func sync_switch() -> void:
    if page_switch == null:
        return
    var on: Variant = tick_at(_open)
    if on != null:
        page_switch.set_pressed_no_signal(bool(on))
        SaOnOffSwitch.refresh(page_switch)
    _dim_body()


## The open page's curve options, each under its own switch when the page
## carries more than one.
##
## A page with one draws the widget alone, its switch being the page's own at
## the top. A page with several cannot use that one, so each option gets a
## switch of its own here, labelled with the option's name, and the page has
## none at the top and no dot in the list. The switch is the editor's rather
## than the widget's because the widget is the declaring module's and `enabled`
## is the one field of a curve option the skeleton already writes, in
## `set_page_enabled` beside this.
func _build_curves(page: Dictionary) -> void:
    var curves: Array = page.get("curves", []) as Array
    var many := curves.size() > 1
    for spec: SaOptionSpec in curves:
        var option := _option_of(spec)
        if option == null:
            continue
        if many:
            page_body.add_child(_curve_switch(spec, option))
        var control := _build_curve_control(spec, option)
        if control == null:
            continue
        page_body.add_child(control)
        curve_controls.append(control)
        if curve_control == null:
            curve_control = control


## The switch row above one option's graph on a page that carries several: the
## option's name and its On/Off switch beside it, the shape the page's own
## title row has.
##
## The switch is named after the option's key so a scenario and a dump can find
## it, and the label is the name the page list would have shown had the page
## been the option.
func _curve_switch(spec: SaOptionSpec, option: Resource) -> HBoxContainer:
    var row := SaMake.row(null, "%sRow" % String(spec.key).to_pascal_case(), SaTheme.GAP)
    var label := SaMake.label(row, "Label", tr(spec.label))
    SaUI.size_text(label, SaUI.fraction_of(14))
    var box := SaOnOffSwitch.make(row, "%sEnabled" % String(spec.key).to_pascal_case(), bool(option.get("enabled")))
    if not spec.tooltip.is_empty():
        box.tooltip_text = tr(spec.tooltip)
    # A method with the key bound, for the reason `_build_rows` gives: what the
    # box holds names this object by its id and binds a `StringName`, and
    # neither is a reference that can close a ring.
    box.toggled.connect(_on_curve_box_toggled.bind(spec.key))
    return row


func _on_curve_box_toggled(on: bool, key: StringName) -> void:
    set_option_enabled(key, on)


## The `SaCurveOption` *spec* names on the shown settings, or null.
func _option_of(spec: SaOptionSpec) -> Resource:
    if spec == null or _settings == null:
        return null
    return _settings.get_indexed(spec.property_path()) as Resource


## The rows of the open page, the same controls the Tool Options docker builds,
## from the same specs through the same class, so a row behaves identically in
## both places and neither knows the other exists.
func _build_rows(shown: Array[SaOptionSpec]) -> void:
    page_controls = ToolOptionControls.new(_box)
    page_controls.place = _layout.place_row
    # Through a method and never a lambda. This class holds the controls, and a
    # lambda holds the object it was written in, so a lambda the controls hold
    # is a cycle between two `RefCounted`s and neither is ever released: the
    # run leaked 556 objects and the whole brush module's scripts with it. A
    # method `Callable` holds the object's id and no reference, so the wire can
    # end here and say what it heard.
    page_controls.option_written.connect(_on_option_written)
    var descriptor := SaToolDescriptor.new()
    descriptor.id = &"brush_editor_page"
    descriptor.options.assign(shown)
    page_controls.build_for(descriptor)
    # The binding the bar hands its own instance, and after the rows are built
    # because it is the blend button's own: an instance handed neither shows the
    # NO_MODES label and lists nothing.
    # The registry fills the list and the document names the space in plain
    # Normal's label.
    page_controls.binding.follow_blend_modes(_blend_registry, _live_document())
    # The window's number rather than 1.0. A spec flagged `scale_by_canvas`
    # holds a fraction of the document's smaller dimension, so 1.0 drew every
    # size in this editor as "Size: 0 px" while the bar's own row read the
    # pixels correctly.
    page_controls.sync(_tool_state, descriptor.id, _canvas_min)
    apply_conditions()


## Hides and dims the open page's rows, through the layout that placed them.
func apply_conditions() -> void:
    if _layout == null:
        return
    _layout.apply_conditions(page_controls, _tool_state, open_specs())


func _on_option_written(key: StringName, value: Variant) -> void:
    _switch_on_for(key)
    option_written.emit(key, value)


## Switches on the option a painter's edit of *key* on the open page belongs
## to, when it is off.
##
## A painter who ticks Fuzzy per dab on a Rotation page whose Rotation is off
## sees nothing turn and has to find out why. An edit on a page that is
## switched off is a painter asking for the page, so
## the edit switches it on, through the same `set_page_enabled` and
## `set_option_enabled` the switches use, so the switch and the list's dot
## follow by the signal they already hear.
##
## Here and nowhere else, because this is where a row's write and a curve
## widget's write both arrive and the one place that knows which page they are
## on. A preset loaded, a migration and the switch itself never come through
## it: a load writes the settings and syncs, and the switch writes through
## `set_page_enabled` directly. The page's own switch row is left out by key,
## so a painter turning the page off by its row is not turned back on.
##
## On a page several curve options share there is no page switch, so only a
## curve widget's write switches its own option, and a plain row there belongs
## to no one option and switches none.
func _switch_on_for(key: StringName) -> void:
    if _open < 0 or _open >= _pages.size():
        return
    var page := _pages[_open]
    var curves: Array = page.get("curves", []) as Array
    if curves.size() > 1:
        for spec: SaOptionSpec in curves:
            var option := _option_of(spec) if spec.key == key else null
            if option != null and not bool(option.get("enabled")):
                set_option_enabled(key, true)
        return
    var on: Variant = tick_of(page)
    if on == null or bool(on):
        return
    var own := switch_of(page)
    if own != null and own.key == key:
        return
    set_page_enabled(_open, true)


## Writes *on* onto whatever the page at *index* switches, its curve option's
## `enabled` or the row it flagged `page_switch`. The page switch's own handler,
## and the door a scenario moves it through.
func set_page_enabled(index: int, on: bool) -> void:
    if index < 0 or index >= _pages.size():
        return
    var page := _pages[index]
    var option := curve_option_of(page)
    if option != null:
        option.set("enabled", on)
        curve_toggled.emit((page["curve"] as SaOptionSpec).key, on)
        return
    var spec := switch_of(page)
    if spec == null or not ToolOptionControls.write_spec(spec, on, _tool_state):
        return
    curve_toggled.emit(spec.key, on)


## Writes *on* onto the curve option called *key* on the open page, which is
## what a switch above one graph of several does.
##
## By key rather than by index, because the index is the page's and the page has
## more than one option: the switch knows which spec it was built for and
## nothing else on the page does.
func set_option_enabled(key: StringName, on: bool) -> void:
    for spec: SaOptionSpec in open_specs():
        if spec == null or spec.kind != SaOptionSpec.Kind.CURVE_OPTION or spec.key != key:
            continue
        var option := _option_of(spec)
        if option == null:
            return
        option.set("enabled", on)
        curve_toggled.emit(key, on)
        return


## Whether the page at *index* has a switch of its own at its top, and a dot in
## the list on the left when that is on.
##
## `tick_at` read as a yes or a no, which is the same question asked twice: a
## page with nothing to switch and a page several curve options share both answer
## null, and everything else answers a state. Named because a reader asking "does
## this page have a switch" should not have to know that null is the answer.
func has_switch(index: int) -> bool:
    return tick_at(index) != null


## Every graph on the open page that is showing, in the order the page draws
## them: a `Kind.CURVE` row, the Brush Tip page's falloff among them, and then
## each curve option's widget. What the window measures against the page
## scroll, to say whether a page opens with its graph in sight.
func graphs() -> Array[Control]:
    var out: Array[Control] = []
    if page_controls != null:
        for spec: SaOptionSpec in open_specs():
            if spec == null or spec.kind != SaOptionSpec.Kind.CURVE:
                continue
            var control := page_controls.control(spec.key)
            if control != null and control.is_visible_in_tree():
                out.append(control)
    for control: Control in curve_controls:
        if control.is_visible_in_tree():
            out.append(control)
    return out


## The specs of the page that is open, or an empty list when none is.
func open_specs() -> Array:
    var index := _open
    if index < 0 or index >= _pages.size():
        return []
    return _pages[index]["specs"]


## Every row the open page put on the right, for a dump: the option each one is
## for, its label and what it reads.
##
## The page list's `row_report` says which pages exist and this says what is on
## the open one, which is the half no dump had: which rows a page carries, and
## which of them are moved, hidden or dimmed.
##
## Read off the page's own specs rather than off the built controls, because
## `ToolOptionControls` is not this file's concern and a spec that built no control
## is exactly the case a reader wants to see. `drawn` is what says whether one
## did.
##
## `value` is read through the same `ToolOptionControls.read` the bar reads
## through, so a row that shows one number while the bar shows another is
## visible in a dump. Decision 4 asks for the General page's Blend Mode to be
## connected to the one the bar edits, and this is what answers it either way.
func row_report() -> Array:
    var out: Array = []
    for spec: SaOptionSpec in open_specs():
        var control := page_controls.control(spec.key) if page_controls != null else null
        (
            out
            . append(
                {
                    "key": String(spec.key),
                    "label": spec.label,
                    "advanced": spec.advanced,
                    "drawn": control != null and control.is_visible_in_tree(),
                    # The three row fields. `in_editor` false is a row the page
                    # omits on purpose, `section` is which of the two headings
                    # it sits under, and `live` is the half a shot cannot show:
                    # a dimmed row and a live one look alike at a glance and are
                    # not.
                    "in_editor": spec.in_editor,
                    "section": spec.section,
                    "live": control == null or SaOptionSpec.row_reads_enabled(control),
                    "value": page_controls.read(spec.key, _tool_state, &"brush_editor_page") if page_controls != null else null,
                }
            )
        )
    return out


## Whether a module's widget on the open page, writing *key*, changed what the
## page offers, so the page has to be built again.
##
## A `Kind.CUSTOM` row is a widget this editor did not build, and its write is
## the one way it can say it moved something the page shows: the stamp brush's
## tip preview writes when a tip landed. A list one of the page's rows offers
## that changed since the build answers true. Any
## other write of a widget has the rows shown their values again, because a
## selection that moved with no list behind it needs no more than that.
func widget_wrote(key: StringName) -> bool:
    var written: SaOptionSpec = null
    for spec: SaOptionSpec in open_specs():
        if spec != null and spec.key == key:
            written = spec
    if written == null or written.kind != SaOptionSpec.Kind.CUSTOM:
        return false
    if _choice_lists() != _lists:
        return true
    if page_controls != null:
        page_controls.sync(_tool_state, &"brush_editor_page", _canvas_min)
        apply_conditions()
    return false


## Tells every module widget on the open page that the settings moved, so one
## that draws from them draws again. A widget answers through
## `option_settings_moved`, named for the door rather than the verb for the
## reason `capture_option_edit` gives.
func settings_moved() -> void:
    if page_controls == null:
        return
    for spec: SaOptionSpec in open_specs():
        if spec == null or spec.kind != SaOptionSpec.Kind.CUSTOM:
            continue
        var control := page_controls.control(spec.key)
        if control != null and control.has_method("option_settings_moved"):
            control.call("option_settings_moved")


## What each `ENUM` row of the open page offers, by key.
func _choice_lists() -> Dictionary:
    var out: Dictionary = {}
    for spec: SaOptionSpec in open_specs():
        if spec != null and spec.kind == SaOptionSpec.Kind.ENUM:
            out[spec.key] = spec.choices.duplicate(true)
    return out


## What the module widgets on the open page say about themselves, for a dump,
## keyed by option. A widget answers through `capture_option_report`, the dump's
## twin of the capture door `capture_option_edit`, and one that has nothing to
## say is left out. The Tip Image grid answers the same door.
func widget_report() -> Dictionary:
    var out: Dictionary = {}
    if page_controls == null:
        return out
    for spec: SaOptionSpec in open_specs():
        if spec == null or spec.kind not in [SaOptionSpec.Kind.CUSTOM, SaOptionSpec.Kind.TIP_IMAGE]:
            continue
        var control := page_controls.control(spec.key)
        if control != null and control.has_method("capture_option_report"):
            out[String(spec.key)] = control.call("capture_option_report")
    return out


## The pages *specs* declare, each where its first row is declared.
##
## A `CURVE_OPTION` is its own page when it names none, because its page is the
## option. A plain spec naming that page joins it as a row under the switch,
## which is how the Texture page carries its chooser, scale, offset and invert
## beside its strength. One pass, because the order a page takes is the order
## its first row came in, whichever kind that row is.
##
## **Several curve options may share a page**, because the switch of each is
## drawn on the page rather than as one checkbox in the page list, which two
## options would have claimed at once. A page carrying more than one curve
## option has no switch of its own and `show_page` draws a switch above each
## option's graph instead, which is what lets the five colour options be one page a painter
## reads as one idea rather than five entries in a column. The first of them is
## the page's `curve`, so every reader that asks a page for its option gets an
## answer, and `curves` beside it is the whole list.
##
## Static, and the only thing here that is: it answers a question about a list of
## specs and touches no window, which is what `ui/brush_editor/tests/test_brush_editor_window.gd`
## asks it on its own.
static func pages_from(specs: Array) -> Array[Dictionary]:
    var pages: Array[Dictionary] = []
    var by_title: Dictionary = {}
    for spec: SaOptionSpec in specs:
        if spec == null:
            continue
        var curve := spec.kind == SaOptionSpec.Kind.CURVE_OPTION
        var title := spec.page if not spec.page.is_empty() else (spec.label if curve else DEFAULT_PAGE)
        if not by_title.has(title):
            var fresh: Dictionary = {"title": title, "specs": [], "curve": null, "curves": []}
            by_title[title] = fresh
            pages.append(fresh)
        var page: Dictionary = by_title[title]
        (page["specs"] as Array).append(spec)
        if curve:
            (page["curves"] as Array).append(spec)
            if page["curve"] == null:
                page["curve"] = spec
    return pages


## One page laid out and torn down: the rows, the headings the sections open
## with, and what a condition hides or dims.
##
## It owns the three dictionaries, which is the whole reason it is a class,
## rather than leaving them on a window that never touches them. An inner
## class, because this is the one file that uses it. `ToolOptionControls`
## builds the controls, the same class
## the Tool Options docker builds them with, so a row behaves identically in
## both places, and this decides where each one lands and what it is drawn
## beside.
class PageLayout:
    extends RefCounted

    ## The column the rows are added to, handed over at construction because a layout
    ## with no box to lay out in is nothing.
    var _box: VBoxContainer

    ## What this page put on the right, so a condition can find a row again without
    ## walking the box: option key -> its row or its bare control.
    var _rows: Dictionary = {}

    ## key -> the shared box a pair's second half joins.
    var _pair_rows: Dictionary = {}

    ## section title -> its heading.
    var _sections: Dictionary = {}

    func _init(box: VBoxContainer) -> void:
        _box = box

    ## A labelled row, the way the Tool Options docker lays one out. A slider draws
    ## its own label, so it goes in bare.
    ##
    ## Three things it does beyond that. A row whose spec names a `section` gets that
    ## heading first, once. A row whose spec names a `pair_with` is put in the same
    ## box as its partner under one label, which is the Mirror tip pair. And every
    ## row is remembered by key, so `apply_conditions` can find it again without
    ## walking the box.
    func place_row(spec: SaOptionSpec, control: Control) -> void:
        control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        control.custom_minimum_size.x = 0
        _open_section(spec)

        var partner := _pair_rows.get(spec.key, null) as HBoxContainer
        if partner != null:
            control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
            partner.add_child(control)
            _rows[spec.key] = partner
            return

        # A row with no name goes in bare too, across the page, which is how a
        # module's widget that is a picture rather than a value asks to be
        # drawn: a label column beside it would push it off centre.
        if spec.kind == SaOptionSpec.Kind.FLOAT or spec.kind == SaOptionSpec.Kind.INT or spec.label.is_empty():
            _box.add_child(control)
            _rows[spec.key] = control
            return

        var row := SaMake.row(null, String(spec.key).capitalize().replace(" ", "") + "Row")
        # An action carries its own word and is a command rather than a value, so it
        # spans the row and takes no label beside it. Every other kind is a value
        # with a name on the left, and a toggle that also draws that name reads it
        # twice.
        if spec.kind != SaOptionSpec.Kind.ACTION:
            var label := SaMake.label(row, "Label", tr(spec.pair_label if not spec.pair_label.is_empty() else spec.label))
            label.custom_minimum_size.x = SaUI.px(120)
            var button := control as BaseButton
            if button != null and button.get("text") == spec.label and spec.pair_with.is_empty():
                # The tooltip already says what the row is, and the label on the left
                # now says it once.
                button.set("text", "")
        if not spec.pair_with.is_empty():
            control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
            _pair_rows[spec.pair_with] = row
        row.add_child(control)
        # A plain switch row says On or Off on the button the Tool Options
        # docker draws, through the same class, where it was a long coloured
        # bar with nothing on it. A pair's halves keep their names,
        # because two buttons under one label are told apart by them.
        if spec.kind == SaOptionSpec.Kind.BOOL and spec.pair_with.is_empty() and control is Button:
            SaOnOffSwitch.dress(control as Button)
        _box.add_child(row)
        _rows[spec.key] = row

    ## Hides and dims the rows of *specs* whose conditions say so, and the heading of
    ## a section with nothing left under it.
    ##
    ## Run after the page is built and again after any row is written, because the
    ## row a condition reads is a row on the same page: the stamp brush's tip page
    ## chooses between its two sections with its own Tip dropdown.
    func apply_conditions(controls: ToolOptionControls, state: ToolState, specs: Array) -> void:
        if controls == null:
            return
        # A condition may name a row on another page: the noise brush's field rows
        # on Texture name the Texture row on General, and a page knows only its
        # own rows, so every field's rows read null and stayed hidden. A key
        # this page has no row for is read off the settings themselves.
        var settings: Variant = state.get("settings") if state != null else null
        var read := func(key: StringName) -> Variant:
            if controls.spec_for(key, &"brush_editor_page") != null or not settings is Object:
                return controls.read(key, state, &"brush_editor_page")
            return (settings as Object).get(key)
        var live: Dictionary = {}
        for spec: SaOptionSpec in specs:
            var row := _rows.get(spec.key, null) as Control
            if row == null:
                continue
            var shown := spec.shown_under(read)
            # A shared row is drawn while either half wants it, or the pair would
            # vanish because the second of the two answered false.
            row.visible = shown if not _pair_rows.has(spec.key) else (row.visible or shown)
            # The dimming rule, honoured here as well as on the bar and in the
            # docker, so the file that decides what dimmed means is the only file
            # that says it.
            var control := controls.control(spec.key)
            if control != null:
                SaOptionSpec.apply_enabled(control, row if row != control else null, spec, read.call(spec.enabled_when))
            if shown and not spec.section.is_empty():
                live[spec.section] = true
        for section: String in _sections:
            (_sections[section] as Control).visible = live.has(section)

    ## The heading a section opens with, drawn once, before the first row under it.
    func _open_section(spec: SaOptionSpec) -> void:
        if spec.section.is_empty() or _sections.has(spec.section):
            return
        var heading := SaMake.label(_box, "Section" + spec.section.replace(" ", ""), tr(spec.section))
        SaUI.size_text(heading, SaUI.fraction_of(13))
        SaSettingsRows.embolden(heading)
        _sections[spec.section] = heading
