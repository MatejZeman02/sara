## What a module writes to put one entry in the Filter menu: a dialog built
## once, and a run on every change.
##
## The whole of the class a student
## writes is `build(ui)`, which declares the widgets in order, and `run(ctx)`,
## which reads them and hands a texture to `ctx.show()`. `title()` names the
## entry. Nothing else is required.
##
## **The filter keeps its values, not its widgets**. A row the
## dialog declares is bound to [member store] under the parameter's name, the
## row's key, so `run` reads `parameter(&"radius")` whether a dialog is open or
## the compositor runs an attached copy with none. [method parameters] and
## [method set_parameters] read and write the store, and the row's range is the
## clamp. A filter that writes those two itself keeps its own values, and its
## rows hold theirs, see [method keeps_values].
##
## **The two parameters carry their types**, because `SaDialog` and
## `SaFilterContext` parse before this file and a base class cannot name a
## class that does not parse yet. So the base reads the way the box blur
## module writes its own two methods, and a filter that mistypes either is a
## parse error rather than a null at the first call.
##
## **`run` is abstract**, the one method a filter cannot do without. A filter
## that forgets it fails to parse, and the module loader refuses the module with
## a sentence naming the file and the method, rather than the empty body running
## and the first run reporting that nothing was shown.
@abstract class_name SaFilter
extends RefCounted

## The section a filter lands in when it names none, or names one nobody
## registered. It exists whether or not a module registered it, so a filter
## from a module loaded without the base module still has somewhere to be, and
## it is always listed last whatever place its registration asked for.
const OTHER_SECTION := &"other"

## The values of every parameter the dialog declared, by the row's key. Written
## through its own methods alone: a bound row writes it by the engine's
## `set_indexed`, a record by [method set_parameters].
var store: Store = Store.new()

## The page `SaDialog.for_filter` last built on this instance, held weakly so
## the filter does not keep a closed dialog alive. The registry holds one
## instance per filter, and the store and the widgets answer the controls of
## that page alone, so a reader holding a page of its own asks whether it is
## still this one before it trusts [method parameters].
var page: WeakRef = null


## The entry's text, in the Filter menu and in the command list.
##
## Defaults to the filter's own class name in sentence case, so `BoxBlur` reads
## `Box blur`, which is why the box blur module writes `Box Blur` for itself, the
## way every other row of the Filter menu reads. A method rather than what
## `ui.title()` sets, because the menu needs a word before any dialog has been
## built, and building one to ask would run a module's `build` at registration
## time for a string.
##
## A filter whose class name and menu entry differ overrides this, which is what
## a title with punctuation or a second word in it wants.
func title() -> String:
    var script: Script = get_script()
    if script == null:
        return "Filter"
    var named := String(script.get_global_name())
    if named.is_empty():
        named = script.resource_path.get_file().get_basename()
    var words := named.to_snake_case().replace("_", " ")
    return words.substr(0, 1).to_upper() + words.substr(1) if not words.is_empty() else "Filter"


## The title in the painter's language, the one place a filter's title meets a
## catalogue. A module's filter names itself, so the template holds the titles
## the tree spells out and no reading of the source holds a third party's.
func translated_title() -> String:
    return TranslationServer.translate(title())


## What the filter does, in one sentence, for the Filter menu's tooltip and the
## filter browser's detail column.
##
## Beside [method title] because the two are asked at the same moment, at
## registration, and for the same reason: the menu needs words before any dialog
## has been built. `SaContext.register_filter` writes it onto the filter's
## command, and every surface that explains a command reads it from there, so a
## module says it once. Empty means the module said nothing, and the menu falls
## back to saying who registered the row.
func sentence() -> String:
    return ""


## The stable half of the registry key. Derived from the title, so the box
## blur's forty-two lines declare no id at all, and overridden by a filter
## that wants its command to survive a change of wording.
func id() -> StringName:
    return slug(title())


## The ids of filters whose records this one reads, under the module that
## registers it, empty for none. A filter that took another's place names it
## here, and its own id where an older record of its own needs rewriting, so a
## document saved before the change loads as this filter. The registry maps
## each to this filter's key, and [SaAttachedFilter] asks it whenever a record
## is made, on a load as on an attach. An id with a full stop in it is a whole
## key under another module, as the base module's Box Blur names
## `box_blur.box_blur`, its key when it was a module of its own.
func reads_records_of() -> Array[StringName]:
    return []


## *values*, a record of the filter *former_id* named in [method
## reads_records_of], as a record of this one that paints the same pixels.
## Asked before [method set_parameters] ever sees the values, so a choice the
## dialog no longer lists can become the rows that now say it.
func record_from(_former_id: StringName, values: Dictionary) -> Dictionary:
    return values


## The command and the InputMap action this filter registers under, or empty for
## the spelling derived from its key.
##
## The derived spelling is `filter_` and the key with its full stops underscored,
## `filter_sara-base-modules_box_blur`, and empty is the answer for almost every
## filter, the box blur included. The six adjustments are why it is a method at all: they
## are reached by `filter_levels` and the rest, a painter has those chords
## rebound, and a filter that takes its own registry key as its command would
## arrive under a second name and leave every one of those bindings behind. So a
## filter whose command has already shipped answers with that name here, and
## `SaContext.register_filter` refuses the registration whole when the name is
## taken rather than leaving a filter nothing can reach.
func action_name() -> StringName:
    return &""


## The chords this filter opens on, empty for none.
##
## Written onto the command's `default_events` at registration, which is what
## puts them in the InputMap on a fresh install and in the Keyboard Shortcuts
## page beside every other chord. Empty by default, which leaves a filter to
## the Filter menu and the command palette.
##
## An entry is an `InputEventKey` with its `keycode` set to the printed key
## rather than to the physical one, which is the shape the skeleton writes its
## own chords in and the reason a painter on a Czech keyboard gets the key they
## are looking at.
func chord() -> Array[InputEvent]:
    return []


## The id of the section this filter is listed in, or empty for none.
##
## A section is what a module registers through
## `SaContext.register_filter_section`, and the base module registers the
## usual ones: `tone`, `color`, `3d`, `blur`, `sharpen`, `distort`, `noise`,
## `pixelate`, `stylize` and `other`. A filter from any module that names one
## sits in its list beside the base module's. Empty, or an id nobody
## registered, lands in [constant OTHER_SECTION].
func family() -> StringName:
    return &""


## Whether this filter is a finishing effect, which an attached chain runs
## after every other record of its node whatever the array order, as a dither
## quantises the picture the records before it made. False by default, which
## is every filter's place in its array.
func finishes() -> bool:
    return false


## Whether this filter forms the picture the screen shows, which a filter does
## when its output is a display transform and not a change to the paint: the
## Tonemap is the one built in, at either of its methods, and a filter's own
## default is no.
##
## Asked by the view rather than the filter named. A Tonemap that covers the
## whole document, as a record on the picture or a top-level filter layer with
## nothing visible above it, is already the picture, and the view's own rolloff
## over it would be a second one, so the view steps aside and
## `SaFilterChain.covers_the_picture` asks this of every record it finds. The
## canvas and the View menu read that answer and never name a filter, so a
## third-party filter that forms a picture is treated the same way.
func forms_the_picture() -> bool:
    return false


## Whether the Filter Brush can paint this filter, which it can when the
## filter's result at a pixel reads that pixel and at most a neighbourhood of
## it, as a blur does. A filter that reads the whole layer for every pixel, a
## kaleidoscope or a mirror, answers no, because under a brush its result
## would change everywhere the brush had not been.
##
## Yes by default, so a module filter that says nothing is offered, and the
## brush's own refusal at the press stays the guard for a filter that said yes
## and records a pass the brush cannot run. The Filter Brush lists only the
## filters that answer yes, and a saved brush naming one that answers no still
## opens and says why it paints nothing.
func can_be_a_brush() -> bool:
    return true


## Declares the dialog's widgets, in order, once. Each is kept as a member of
## the filter and read back in [method run].
func build(_ui: SaDialog) -> void:
    pass


## Reads the widgets, dispatches whatever the filter does, and hands the result
## to `ctx.show()`. Called when the dialog opens and after every change.
@abstract func run(ctx: SaFilterContext) -> void


## What the widgets hold just now, by a name of the filter's own choosing, as
## values JSON can carry: numbers, strings, booleans, arrays and dictionaries of
## those. It is what an attached filter's record keeps and what `.sad` writes,
## so a number comes back a float whatever went in.
##
## The store by default: every row the dialog declares, by its key, which is
## the whole of what a filter with plain rows needs. A filter whose values live
## somewhere a row cannot reach overrides this together with `set_parameters`.
func parameters() -> Dictionary:
    _declare()
    return store.all()


## Writes *values* back, the other half of `parameters`. A key the filter does
## not know is ignored and a key that is absent reads as its row's default,
## because the registry holds one instance per key and whoever evaluates a
## record calls this before every `run`, so the instance must remember nothing
## of the record before. A number is clamped to its row's range, a choice that
## is not one of the row's entries is the default, and a record written by an
## older version of the filter still loads.
func set_parameters(values: Dictionary) -> void:
    _declare()
    store.take(SaTyped.strings(values))


## The record an Attach or an adjustment layer of this filter is filed as, with
## *own_key*, the key it is registered under, handed in because a filter does
## not know the module that registered it.
##
## *own_key* and [method parameters] by default, which is every filter but an
## entry over another filter's kernel. Desaturate is Hue/Saturation at
## Saturation nought, and answers Hue/Saturation's key and its rows in their
## own units, so the record the dialog attaches and the layer the browser adds
## are Hue/Saturation's own, and a double click on either opens Hue/Saturation
## where a painter can take it part of the way. The filter answers rather than
## the registry because only the filter knows whose entry it is.
func filed_as(own_key: StringName) -> SaAttachedFilter:
    return SaAttachedFilter.new(own_key, parameters())


## The value of the parameter *key*, the row's key, whether a dialog is open or
## not. Null for a key no row declared.
func parameter(key: StringName) -> Variant:
    _declare()
    return store.read(key)


## Writes one parameter, clamped as a row's own write is. What a custom control
## calls when it moves, since it has no row to bind.
func write_parameter(key: StringName, value: Variant) -> void:
    _declare()
    store.write(key, value)


## Whether this filter's values are the store's, which is whether it leaves
## both [method parameters] and [method set_parameters] to this class.
##
## The rule a dialog binds its rows by. A filter that keeps its own values
## reads its rows back itself and writes them in `set_parameters`, and a row
## bound to a store it never writes would read the store's default over the
## value the filter had just put there. Asked of the script, whose method list
## names an overridden method once for each class that writes it, so the
## answer needs no line in any filter.
func keeps_values() -> bool:
    var script: Script = get_script()
    if script == null:
        return true
    var written := 0
    for raw: Variant in script.get_script_method_list():
        var method := SaTyped.strings(raw)
        if method["name"] == &"parameters" or method["name"] == &"set_parameters":
            written += 1
    return written <= 2


## Why this filter cannot run, or "" when it can.
##
## A filter whose kernel did not compile registers all the same, so the painter
## sees the entry they were promised rather than a menu that silently lost a
## row. The Filter menu asks this every time it is filled, dims the entry of a
## filter that answers and carries the first line of the answer as its tooltip.
##
## Asked rather than pushed, and asked on every fill, because that is what makes
## a fixed file clear itself: a filter that recompiles here is live again on the
## next open with nothing to restart.
func problem() -> String:
    return ""


## "Box blur" as `box_blur`: lower case, and every run of anything that is not
## a letter or a digit collapsed to one underscore.
##
## Here rather than on the registry because the registry names this class and
## a reference back the other way would be a cycle between two files that both
## have to parse before either can be used.
static func slug(text: String) -> StringName:
    var out := ""
    for i in text.length():
        var c := text.substr(i, 1).to_lower()
        if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
            out += c
        elif not out.ends_with("_"):
            out += "_"
    while out.begins_with("_"):
        out = out.substr(1)
    while out.ends_with("_"):
        out = out.substr(0, out.length() - 1)
    return StringName(out)


## Runs the declaration once, so the store knows every parameter, its default
## and its range before anything reads it. A dialog that bound its rows has
## already done so.
func _declare() -> void:
    if not store.settled:
        SaDialog.declare_filter(self)


## The values of one filter, by parameter name, with the default and the range
## each row declared.
##
## A row binds to it by the engine's own property path: `_get` and `_set` answer
## the parameter names, so [SaPageRow] reads and writes it the way it reads a
## setting, with no change to the row. An inner class because it is the one
## thing the filter keeps, and nothing but a filter's rows and records reach it.
class Store:
    extends RefCounted

    ## After a record or a custom control wrote a value, so an open page reads
    ## its rows again. A row's own write does not emit it, since the row already
    ## shows what it wrote.
    signal changed

    ## The key a filter's time is kept under, in seconds from nought.
    const TIME: StringName = &"t"

    ## Whether the declaration has run. Set at its start, so a `build` that
    ## reads a parameter while it declares does not declare a second time.
    var settled: bool = false

    var _held: Dictionary[StringName, Variant] = {}
    var _defaults: Dictionary[StringName, Variant] = {}
    ## Key -> Vector2 of the hard range, for a number.
    var _ranges: Dictionary[StringName, Vector2] = {}
    ## Key -> the ids a choice may take.
    var _choices: Dictionary[StringName, Array] = {}
    ## Key -> what a record that does not name it reads as, for a key added
    ## after records without it were saved.
    var _unnamed: Dictionary[StringName, Variant] = {}

    ## The declaration has begun.
    func settle() -> void:
        settled = true

    ## A number between *low* and *high*. A key declared again, by the next
    ## dialog over the same filter, keeps its value clamped to the range now
    ## declared.
    func declare_number(key: StringName, default: float, low: float, high: float) -> void:
        _ranges[key] = Vector2(low, high)
        _declared(key, clampf(default, low, high))

    ## One of *ids*, the entries of a dropdown or a radio row.
    func declare_choice(key: StringName, default: Variant, ids: Array) -> void:
        _choices[key] = ids.duplicate()
        _declared(key, default)

    ## A value with no range: a toggle's bool, a colour, or whatever a custom
    ## control keeps. *unnamed*, when given, is what a record without the key
    ## reads as instead of *default*.
    func declare_value(key: StringName, default: Variant, unnamed: Variant = null) -> void:
        if unnamed != null:
            _unnamed[key] = _copied(unnamed)
        _declared(key, default)

    func has(key: StringName) -> bool:
        return _defaults.has(key)

    func read(key: StringName) -> Variant:
        return _held.get(key)

    ## Every value, a colour as its hex so the record can be JSON.
    func all() -> Dictionary[String, Variant]:
        var out: Dictionary[String, Variant] = {}
        for key: StringName in _held:
            var held: Variant = _held[key]
            if held is Color:
                var color: Color = held
                out[String(key)] = "#" + color.to_html(true)
            else:
                out[String(key)] = _copied(held)
        return out

    func write(key: StringName, value: Variant) -> void:
        if not _defaults.has(key):
            return
        _held[key] = _fitted(key, value)
        changed.emit()

    ## A record: every declared key from *values*, or its default when absent.
    func take(values: Dictionary[String, Variant]) -> void:
        for key: StringName in _defaults:
            var name := String(key)
            _held[key] = _fitted(key, values[name]) if values.has(name) else _copied(_unnamed.get(key, _defaults[key]))
        changed.emit()

    ## Every declared key at its default, what a dialog opened afresh shows.
    func reset() -> void:
        for key: StringName in _defaults:
            _held[key] = _copied(_defaults[key])
        changed.emit()

    func _declared(key: StringName, default: Variant) -> void:
        _defaults[key] = _copied(default)
        _held[key] = _fitted(key, _held[key]) if _held.has(key) else _copied(default)

    ## *value* as the key's own kind, and inside its range.
    func _fitted(key: StringName, value: Variant) -> Variant:
        var default: Variant = _defaults.get(key)
        if _ranges.has(key):
            var span: Vector2 = _ranges[key]
            var number := SaTyped.real(value, SaTyped.real(default))
            return clampf(number, span.x, span.y)
        if _choices.has(key):
            for id: Variant in _choices[key]:
                if id == value or (typeof(id) != typeof(value) and str(id) == str(value)):
                    return id
            return default
        if default is bool:
            return SaTyped.flag(value)
        if default is Color:
            if value is Color:
                return value
            var fallback: Color = default
            return Color.from_string(SaTyped.text(value), fallback) if value is String else default
        return _copied(value)

    func _get(property: StringName) -> Variant:
        return _held.get(property) if _defaults.has(property) else null

    func _set(property: StringName, value: Variant) -> bool:
        if not _defaults.has(property):
            return false
        _held[property] = _fitted(property, value)
        return true

    static func _copied(held: Variant) -> Variant:
        if held is Array:
            var list: Array = held
            return list.duplicate(true)
        if held is Dictionary:
            var table: Dictionary = held
            return table.duplicate(true)
        return held
