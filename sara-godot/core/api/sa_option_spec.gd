## One declarative row in a tool's options bar.
##
## Declared rows rather than probes into a tool's settings, so any tool, a
## module's included, fills the bar: a tool lists these on its
## SaToolDescriptor, the bar builds itself from them, and the canvas
## right-click menu offers the same list.
##
## `key` is the option's identity: the stored layout names the control by it,
## so it must not change casually. `property` is where the value lives, on the
## tool's `settings` resource by default or on the tool state itself with
## `on_tool`, and it may reach into a nested resource with a colon the way a
## NodePath does: the brush's hardness is a GammaFloat, so its key is
## `hardness` and its property `hardness:value`.
##
## Two tools that declare the same key share one control on the bar, which is
## what a painter expects of Size across the brush and the eraser, and which
## keeps the layout list one row per option rather than one per tool. The
## first tool to declare a key decides its kind, and a later tool has to
## agree on it.
class_name SaOptionSpec
extends RefCounted

enum Kind {
    FLOAT,  ## Slider. Uses min_value/max_value/step.
    INT,  ## Slider stepping by one.
    BOOL,  ## Toggle button, with `icon` when one is named.
    COLOR,  ## Not built yet: the picker docker holds the colour.
    ENUM,  ## Fixed choices in `choices`.
    BLEND_MODE,  ## Choices come from the blend registry, so module modes appear.
    CURVE,  ## A bare `Curve` on a square graph, with no sensors under it.
    ACTION,  ## A button that calls the method `property` names on the tool.
    CURVE_OPTION,  ## A modulated parameter, edited on a page of its own. See `build_control`.
    CUSTOM,  ## A widget the declaring module builds. See `build_control`.
    TIP_IMAGE,  ## A brush tip's picture, from a grid of the tip folders. See `make_tip_image`.
}

var key: StringName
var label: String = ""
var kind: Kind = Kind.FLOAT

## Where the value lives. Empty means the key itself.
var property: NodePath = ^""

## The property is on the tool state rather than on its settings resource,
## which is where per-instance state such as the eyedropper's sample size or
## the brush's erase toggle lives.
var on_tool: bool = false

var min_value: float = 0.0
var max_value: float = 1.0
## The ceiling the slider's drag and its fill reach when it is lower than
## `max_value`, Krita's soft limit. A typed value goes on to `max_value`, the
## hard one. Zero means the two are one.
var soft_max: float = 0.0
var step: float = 0.01

## Multiplies the stored value for display only.
var display_scale: float = 1.0
## The display is further multiplied by the document's smaller dimension, for
## a value stored as a fraction of the canvas and shown as pixels.
var scale_by_canvas: bool = false

## The slider's drag is geometric rather than linear, chosen by the row the
## way the soft maximum is. The Size row spans a tenth of a pixel to the whole
## document, and a linear drag spends nine tenths of its travel on sizes a
## painter never uses: on the default document the first tenth of the box is
## every size under 108 pixels, and the sizes a painter works at share the last
## few pixels of it. A geometric drag gives every octave of size the same room
## and a constant relative step, which is also what the bracket keys use.
##
## Off by default, so a slider whose values are a plain range keeps a linear
## mapping. A row wanting it must declare a minimum above zero, since the curve
## is a ratio and zero has none.
var logarithmic: bool = false
## Shown as a percentage of the range rather than as the stored number.
var percent: bool = false
var decimals: int = 1
## Whether the row's label drops trailing noughts after the point, so a size
## reads "25" and not "25.00". Off by default: a row's declared precision is
## what it shows unless it asks otherwise.
var trim_trailing_zeros: bool = false
## Whether Left and Right step the row by a whole displayed unit rather than
## its last decimal, so a Radius that shows two decimals still steps a pixel.
var steps_by_whole_units: bool = false
var suffix: String = ""

## For Kind.ENUM: [{ "id": Variant, "label": String }]. The id is what the
## property is set to, so an int-valued property lists ints. An optional
## `"tooltip"` is the sentence that choice's own row shows on hover, in the
## docker's list and in a menu that offers the choices as rows, the way the
## stabilizer's modes are offered in Tools. `make_enum` builds none, so a spec
## whose choices explain themselves writes the list out.
var choices: Array = []

## For Kind.BOOL: an icon name resolved through SaUI.get_icon(). The button
## then shows the icon and keeps the label as its tooltip.
var icon: String = ""

var tooltip: String = ""

## The control's minimum width in logical pixels, 0 for the kind's default.
var width: int = 0

## Hides an option behind the advanced toggle rather than removing it.
var advanced: bool = false

## The title of the brush editor page this row belongs to, empty for none.
##
## A page rather than a category, because the editor's left list is one row per
## page and a page that names a `CURVE_OPTION` binds its switch to that
## option's own `enabled`. Two specs naming one page share it, in the order the
## tool declares them.
var page: String = ""

## This row is the switch of the page it names, so the editor draws it at the
## top of the page, with a dot in the page list while it is on, and nothing
## draws it as a row.
##
## The rule was "a page that names a curve option carries a checkbox", and the
## reason `page_list.gd` gives for it is narrower than the rule: a checkbox on a
## page with nothing to switch would read as an option the painter is not
## allowed to switch off. A curve option is not the only thing a page can have
## to switch. The Masking Brush page is a second tip that is off by default, and
## its `enabled` is exactly the claim a tick makes, so this flag says which row
## the tick is rather than making the mask pretend to be a modulated parameter.
##
## The row keeps its `property`, its kind and its place in the Tool Options
## docker, which is the surface with no page list to put a tick on. It is the
## editor that draws it as the page's switch instead of as a row, so set
## `in_editor = false` beside this or the page shows the same switch twice.
var page_switch: bool = false

## The option this row only means anything under, empty for a row that always
## does.
##
## A row that means nothing under its controlling option is dimmed and
## disabled, rather than saying so in its tooltip as "Nothing while the wobble
## is off" does, because a sentence is not a state a painter can see.
##
## Declared as a key and a list of values rather than as a `Callable`, for two
## reasons. A dump can print it, so a scenario can say which row was disabled and
## why rather than only that it was. And a spec is data a module hands over, so a
## closure here would be a module's code running inside the skeleton's row
## builder, which is no door a module is given.
var enabled_when: StringName = &""

## The values of `enabled_when` this row is enabled for. Empty means every value,
## which is the same as declaring no rule at all and is what an incomplete
## declaration falls back to rather than a permanently dead row.
var enabled_when_values: Array = []

## For Kind.CUSTOM and Kind.CURVE_OPTION: what builds the widget,
## `func(spec: SaOptionSpec, write: Callable) -> Control`.
##
## The door for a widget the skeleton's row kinds do not cover, such as the
## gradient's colour ramp editor: the module hands over the thing that builds
## its widget, rather than the skeleton's UI holding it, the skeleton builds
## every other row, and a second module wanting a curve, a matrix or a swatch
## grid adds no line
## anywhere in `ui/`.
##
## A `Callable` here where `enabled_when` above refused one, and the reason the
## two differ is what each is for. That one is a *rule* about a row, which a dump
## has to be able to print and which the skeleton has to be able to evaluate, so
## it is data. This is a *widget*, which nothing can print and only the module can
## build, so a factory is the only shape it has. A built-in registers the way a
## module does, so the base module's ramp comes through this door too.
##
## *write* is handed in rather than taken: the module's control reports a move by
## calling it, and the skeleton does the writing, the muting and the mirroring
## onto the other surface. A control whose value is an object it was pointed at,
## the ramp being the one in the tree, never calls it at all.
var build_control: Callable = Callable()

## For Kind.CUSTOM: what shows a value on the built widget,
## `func(control: Control, value: Variant) -> void`.
##
## Empty is allowed and means the widget shows nothing that comes from outside,
## which no kind here is: the ramp is pointed at the tool's own `SaColorRamp` by
## this call and edits it in place.
var bind_value: Callable = Callable()

## For Kind.CURVE_OPTION: what a row's button says the value is set to,
## `func(value: Variant) -> String`.
##
## A curve option is three widgets on three surfaces. The brush editor draws it
## as a page, the bare host draws the same page in a window of its own, and the
## Tool Options docker draws a button that opens one of those two and says what
## the option is set to. The first two come through `build_control` and
## `bind_value`, the same door as CUSTOM, because the page's widget types its
## option as a class the declaring module owns and a skeleton file naming that
## class would not parse in a clone without the module. The
## button is the skeleton's, and this is the one thing it cannot write itself:
## the words are about sensors, and only the module knows what a sensor is
## called. Empty means the button says nothing.
var describe_value: Callable = Callable()


## Whether a row is enabled, given what its controlling option currently reads.
##
## Static and handed the value, because the two surfaces that build rows each
## read it their own way and neither should have to know how the other does.
static func row_is_enabled(spec: SaOptionSpec, controlling_value: Variant) -> bool:
    if spec == null or String(spec.enabled_when).is_empty() or spec.enabled_when_values.is_empty():
        return true
    return spec.enabled_when_values.has(controlling_value)


## Greys *control* and refuses the hand when its row is dead, and puts both back
## when it is not.
##
## Here rather than on either surface, because both the bar and the docker build
## rows from these specs and a rule kept in two places is a rule that comes to
## disagree with itself. *row* is the labelled container the docker wraps a
## control in, so the label greys with it, and may be null on the bar, which puts
## controls straight on the row.
##
## **Dimmed also means disabled**: a control that is greyed and still moves is
## never what dimming promises. `Button` and `BaseButton` carry `disabled`, `Range`
## subclasses carry `editable`, and a control with neither is greyed and left
## alone rather than skipped, because a grey row that still answers is closer to
## that promise than a row that looks live.
static func apply_enabled(control: Control, row: Control, spec: SaOptionSpec, controlling_value: Variant) -> void:
    if control == null or spec == null:
        return
    var on := row_is_enabled(spec, controlling_value)
    var tint := Color(1.0, 1.0, 1.0, 1.0) if on else Color(1.0, 1.0, 1.0, DIMMED_ALPHA)
    if row != null:
        row.modulate = tint
    else:
        control.modulate = tint
    if "disabled" in control:
        control.set("disabled", not on)
    elif "editable" in control:
        control.set("editable", on)
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE if not on else Control.MOUSE_FILTER_STOP
    # Back to what the control asked for, never to `FOCUS_ALL`. Every sync of
    # the bar came through here, so a button built without focus was handed it
    # on the first sync, and the next Space reopened its list.
    if not control.has_meta(OWN_FOCUS_META):
        control.set_meta(OWN_FOCUS_META, control.focus_mode)
    var own_focus: Control.FocusMode = control.get_meta(OWN_FOCUS_META)
    control.focus_mode = Control.FOCUS_NONE if not on else own_focus


## Whether a built row reads as live, for a dump.
##
## Both halves, because dimmed also means disabled and a
## row that reads one and not the other is the defect rather than the fix: the
## alpha says a painter can see it is dead, the flag says the hand cannot move it.
## Walks the row for the first control carrying either flag, so it answers for a
## labelled container the docker built as readily as for a bare control.
##
## Static and here rather than in the dump, so the file that decides what dimmed
## means is the file that reports it.
static func row_reads_enabled(row: Control) -> bool:
    if row == null:
        return true
    if row.modulate.a < 1.0 - 0.001:
        return false
    for node in ([row] as Array[Node]) + row.find_children("*", "Control", true, false):
        var control := node as Control
        if control == null:
            continue
        if "disabled" in control and SaTyped.flag(control.get("disabled")):
            return false
        if "editable" in control and not SaTyped.flag(control.get("editable")):
            return false
    return true


## How much of itself a dimmed row keeps. Krita's disabled rows sit around here
## and the theme has no token for it, so it is a number rather than a palette
## entry until one exists.
const DIMMED_ALPHA: float = 0.4

## Where `apply_enabled` keeps the focus mode a control was built with, so a row
## that comes back live comes back to that and not to the engine's default.
const OWN_FOCUS_META := &"sa_option_own_focus_mode"

## Whether the top bar shows this option as well as the Tool Options docker.
##
## The docker shows every option a tool declares, the bar shows the few the
## painter wants at hand. True by default, so a module tool that declares a
## spec and knows
## nothing about this flag appears on both surfaces rather than on neither.
var bar: bool = true

## Whether a fresh profile hides this option's control on the bar.
##
## The way to keep a reduced option off a fresh bar and one tick away in
## Preferences > Top Menu Bar. `bar = false` is not that: it builds no control,
## so the Preferences row has nothing behind it. Declared here rather than in a
## list the skeleton keeps, so a third-party tool makes the judgement for its
## own rows. A profile that stored a
## visibility for the row keeps it, whatever this says.
var bar_hidden: bool = false

## Whether the bar shows this option only while the tool that declared it is
## the one in hand.
##
## A tool that does not paint already has its rows come and go with it, while a
## painting tool's rows stay whatever is chosen, so the brush group does not
## vanish under the eyedropper. That is right for the rows a painter reaches for
## with any tool, the blend mode and the radius, and wrong for a row that is one
## painting tool's own: the fill's Grow stood on the brush's bar doing nothing
## for it. Such a row says so here and then comes and goes with its tool, the
## way a row of a tool that does not paint does. False by default, so a module
## that knows nothing about this flag keeps the group it had.
var bar_own_tool: bool = false

## Whether the Tool Options panel shows this option's row while the bar shows
## it too, where it otherwise leaves the row to the bar and names it in a line
## at the foot. For a tool whose only options are on the bar, so the panel is not
## left empty. Both controls read and write the same value.
var panel_also: bool = false

## The top bar element this option's control follows on a fresh bar, empty for
## the end of the bar.
##
## An element name as the bar's order stores it: a skeleton element such as
## "Brush Presets" or "Reset Rotation", or another option's key. A control
## registered at run time otherwise lands after every element of the default
## order, which would put a tool's row past the symmetry toggles. An anchor the
## order does not hold places the control at the end.
var bar_after: String = ""

## The skeleton's three words for `bar_group`, which the bar's own controls
## take as well: what the dab is, how a line is laid down, and how the canvas
## is seen.
const BAR_GROUP_BRUSH := &"brush"
const BAR_GROUP_STROKE := &"stroke"
const BAR_GROUP_VIEW := &"view"

## The group of the top bar this option's control sits in, empty for none.
##
## The bar draws a gap and a thin rule between two shown neighbours on one row
## whose groups differ, and nothing beside a control with no group, so an
## option that names none sits where `bar_after` puts it with no break drawn
## either side of it. A module with an errand of its own names any other word,
## and the bar breaks around that the same way.
##
## Declared on the option rather than kept as a list in the bar, because the
## tool that declares a row is what knows which errand it belongs to, the
## reason `bar_after` gives for a place on a fresh bar. The first tool to name a
## group for a key decides it, since every tool declaring the key shares one
## control.
var bar_group: StringName = &""

## Whether the brush editor's page draws a row for this option.
##
## `bar`'s twin, and false is not the same as deleting the spec: a hidden option
## keeps its number, a preset carries it and a Krita import writes it, only the
## page omits the row. Five of the Brush Tip page's rows are hidden that way,
## Spikes, Density, Antialias Edges and the two Sharpness ones, so the page
## stays near the four rows of Krita's own tip dialog.
##
## True by default, for the reason `bar` is: a module tool that knows nothing
## about this flag appears rather than vanishing.
var in_editor: bool = true

## Whether the Tool Options docker draws a row for this option.
##
## The third of `bar` and `in_editor`, for a row that only means something on
## a page of the brush editor: the stamp brush's dab preview is a `Kind.CUSTOM`
## row at the top of two pages, and the docker, which draws every option a tool
## declares, would have drawn a dab in its column of controls. True by default,
## for the reason the other two are.
var in_docker: bool = true

## When this row is drawn at all, as `{"key": &"other", "value": v}` and an
## optional `"equals": false` to invert it.
##
## `enabled_when` above is the sibling rule and answers a different question:
## that one dims a row a painter can still see is there, this one takes it off
## the page. The Brush Tip page's two sections are the second kind, because a
## Mask row beside a generated tip is not a row that does nothing, it is a row
## about something that is not on screen.
##
## Empty means always. The Brush Tip page's two sections are this and nothing
## else: Procedural is every row whose condition is Tip not being Image, Mask is
## every row whose condition is Tip being Image, and the rows that apply to both
## carry no condition at all. A rule rather than a list in the page builder,
## because the tool that declares a row is the thing that knows when it
## applies.
var shown_when: Dictionary[String, Variant] = {}

## A rule of the same shape as `shown_when` under which a slider says "off" in
## words rather than its number, empty for never.
##
## Paint and Smudge reads `ticked_strength`, which is nought while the Colour
## Rate is switched off, and "0 %" would read as a rate the painter set. The
## rule names the switch, so the row says what the brush holds.
var off_when: Dictionary[String, Variant] = {}


## "off", translated, while `off_when` holds on *target*, the object the row's
## property is read off, and nothing otherwise or with no rule.
func words_on(target: Object) -> String:
    if target == null or off_when.is_empty():
        return ""
    var read := func(asked: StringName) -> Variant: return target.get_indexed(NodePath(String(asked)))
    return tr("off") if _rule_holds(off_when, read) else ""


## The heading this row sits under on its editor page, empty for none.
##
## The Brush Tip page has two, Procedural and Mask, and only one of them is ever
## on screen because every row under a heading also carries the `shown_when` that
## picks it. The heading is drawn when at least one of its rows is.
var section: String = ""

## The option this one shares a row with, empty for none.
##
## One label and two small toggles side by side, as Mirror Tip H and V are,
## rather than the label written twice. The partner keeps its own spec and its
## own tooltip, and `pair_label` is what the
## row is called once the two are in it.
var pair_with: StringName = &""
var pair_label: String = ""


## A number row, for Kind.FLOAT, and for Kind.INT through *fields*.
##
## *fields* names any other field of the spec with its value, so a caller writes
## a row in one expression rather than setting `property`, `percent`, `tooltip`
## and the rest on the lines after the maker returns it. A name no field answers
## is an error at the call.
static func make_float(
    option_key: StringName,
    label_text: String,
    minimum: float,
    maximum: float,
    increment: float = 0.01,
    fields: Dictionary[String, Variant] = {}
) -> SaOptionSpec:
    var spec := make(option_key, label_text, Kind.FLOAT)
    spec.min_value = minimum
    spec.max_value = maximum
    spec.step = increment
    return spec._filled(fields)


## A row of *option_kind*, with *fields* as [method make_float] takes them.
static func make(
    option_key: StringName, label_text: String, option_kind: Kind, fields: Dictionary[String, Variant] = {}
) -> SaOptionSpec:
    var spec := SaOptionSpec.new()
    spec.key = option_key
    spec.label = label_text
    spec.kind = option_kind
    return spec._filled(fields)


## A choice list from parallel ids and labels, for Kind.ENUM.
static func make_enum(
    option_key: StringName, label_text: String, ids: Array, labels: Array, fields: Dictionary[String, Variant] = {}
) -> SaOptionSpec:
    var spec := make(option_key, label_text, Kind.ENUM)
    for index in mini(ids.size(), labels.size()):
        spec.choices.append({"id": ids[index], "label": str(labels[index])})
    return spec._filled(fields)


## A row a module builds itself, for Kind.CUSTOM.
##
## *factory* and *binder* are the two `Callable` fields above, and naming them
## here in one call is what keeps a module's declaration one line per option the
## way every other kind's is.
static func make_custom(
    option_key: StringName,
    label_text: String,
    factory: Callable,
    binder: Callable = Callable(),
    fields: Dictionary[String, Variant] = {}
) -> SaOptionSpec:
    var spec := make(option_key, label_text, Kind.CUSTOM)
    spec.build_control = factory
    spec.bind_value = binder
    return spec._filled(fields)


## The Tip Image row of a brush engine, for Kind.TIP_IMAGE: the path of the
## picture the settings' tip holds, `tip:image_path`.
##
## Tips are chosen the way the brush presets are, from their pictures rather
## than from a list of names, so the surfaces draw this kind as a grid with one
## cell a tip, each the mask it is,
## under a filter whose rows are the folders the tips sit in, All first, which
## makes a folder a tip's tag with no tag store. What the grid offers is
## [SaTipChoices]'s, so two engines declaring this list the same tips.
##
## **A press writes the path**, the way a choice writes its id, which is what a
## scenario's `tool` step and a preset write as well, and what the Masking
## Brush's own Tip Image row, the stamp's row pointed at the mask, needs: a
## press going through the tool's `load_tip` would load the dab's tip under the
## mask's row. A picture that cannot be read is refused at the press with its
## reason. The grid follows a tool that announces `tip_loaded`, so a picture the
## Load Tip action reads from anywhere joins it under its own folder.
static func make_tip_image(option_key: StringName, label_text: String, fields: Dictionary[String, Variant] = {}) -> SaOptionSpec:
    var spec := make(option_key, label_text, Kind.TIP_IMAGE)
    spec.property = ^"tip:image_path"
    return spec._filled(fields)


## A new spec with every field of this one and *fields* over them, for a page
## that offers another's rows under addresses of its own, as the Masking Brush
## page offers the Brush Tip's. This spec is left as it was, and a container
## field is copied rather than shared.
func remade(fields: Dictionary[String, Variant]) -> SaOptionSpec:
    var spec := SaOptionSpec.new()
    for entry: Dictionary in get_property_list():
        var usage: int = entry["usage"]
        if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
            continue
        var field: String = entry["name"]
        var held: Variant = get(field)
        if held is Dictionary:
            var into: Dictionary = spec.get(field)
            var copied: Dictionary = held
            into.assign(copied.duplicate(true))
        elif held is Array:
            var into: Array = spec.get(field)
            var copied: Array = held
            into.assign(copied.duplicate(true))
        else:
            spec.set(field, held)
    return spec._filled(fields)


## This spec with each of *fields* set, the maker's last step.
##
## A typed field, `shown_when` and the rest, takes its value through `assign`,
## because `set` leaves a typed dictionary as it was when handed a literal one,
## and says nothing. A name that is no field is pushed as an error rather than
## dropped, so a misspelt `toolip` is seen at the first run.
func _filled(fields: Dictionary[String, Variant]) -> SaOptionSpec:
    for field: String in fields:
        if not field in self:
            push_error("SaOptionSpec %s has no field %s" % [key, field])
            continue
        var held: Variant = get(field)
        if held is Dictionary:
            var into: Dictionary = held
            var given: Dictionary = fields[field]
            into.assign(given)
        elif held is Array:
            var into: Array = held
            var given: Array = fields[field]
            into.assign(given)
        else:
            set(field, fields[field])
    return self


## The path the bar reads and writes.
func property_path() -> NodePath:
    return property if not property.is_empty() else NodePath(String(key))


## The name the stored layout knows this control by.
func element_name() -> String:
    return String(key)


## Whether a control built for *other* can serve this spec too.
func compatible_with(other: SaOptionSpec) -> bool:
    return other != null and other.key == key and other.kind == kind


## Whether *state* satisfies this spec's `shown_when`, reading the other option
## through *read*, a `Callable` taking a key and answering its value.
##
## A callable rather than a settings resource, because the two surfaces that ask
## read a value differently: the editor's page goes through
## `ToolOptionControls.read` and the docker's rows through their own.
func shown_under(read: Callable) -> bool:
    return _rule_holds(shown_when, read)


## *read*, which answers a key a row declares, widened to a key no row does:
## a property path read off *settings*. So a rule can name a field of a curve
## option, as Paint and Smudge's names `smudge_pickup_option:enabled`, where a
## surface's own read answers null because no row is that field alone.
static func reading_settings(read: Callable, settings: Variant) -> Callable:
    var source: Object = null
    if settings is Object:
        source = settings
    return func(asked: StringName) -> Variant:
        var held: Variant = read.call(asked)
        if held == null and source != null:
            return source.get_indexed(NodePath(String(asked)))
        return held


static func _rule_holds(rule: Dictionary[String, Variant], read: Callable) -> bool:
    if rule.is_empty():
        return true
    var held: Variant = read.call(SaTyped.name_at(rule, "key", &""))
    var same: bool = typeof(held) == typeof(rule.get("value")) and held == rule.get("value")
    if not same and held != null and rule.get("value") != null:
        # A choice id arrives as an int from one surface and a float from
        # another, because a `FactorSlider` reads a float whatever the kind says.
        same = (
            is_same(SaTyped.real(held), SaTyped.real(rule.get("value")))
            if _numeric(held) and _numeric(rule.get("value"))
            else false
        )
    return same if SaTyped.bool_at(rule, "equals", true) else not same


static func _numeric(value: Variant) -> bool:
    return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_BOOL
