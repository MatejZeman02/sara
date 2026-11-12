## The colours a painter works with: the foreground and background pair, the
## swatches they kept, and the colours they last used.
##
## This is the one store behind the pair, the swatches and the recent list, reached as the `SaColors`
## autoload, so a tool, the picker and the router all read the same colours.
## The foreground still goes out as `EventBus.color_picked`, which is what
## every tool listens to, and the background as
## `EventBus.background_color_changed`.
##
## What counts as recent is a colour that was used, not one the wheel passed
## through: the wheel emits on every drag event, so a list fed from those would
## fill with one gesture. The picker says when a gesture ends, the eyedropper
## when it picks, and both go through `note_used()`.
##
## Persisted in its own file, `colors.cfg` under the data root, on every commit rather than
## on every drag event, so a session's colours come back without the disk
## seeing sixty writes a second.
##
## **Every colour here is opaque**, the pair and both lists, whatever route it
## came by. The brush paints the foreground at full alpha and its own opacity,
## so an alpha held here would be shown and never painted: the swatch would draw
## a checker blend of a colour the stroke lays solid. A painter who wants a
## translucent brush has Opacity and Flow. See [method opaque].
##
## **Every colour here is finite** too. A pick of a texel a filter left NaN
## would make the foreground nan, nan, nan, which the hex field shows as
## #000000 and the next stroke paints as black. The pair refuses a colour with a channel
## that is not a number or is infinite and keeps the one it had, and so do the
## listener, the recent list and the load. See [method finite].
##
## **A swatch carries a name**, in [member swatch_names] beside the colours
## rather than in a class of its own, so `lists/swatches` stays the list of
## colours the last build wrote and reads. The names go under a key of their
## own, which that build's `ConfigFile` never asks for, and a file without the
## key reads every swatch as unnamed. Without them a palette of twenty colours
## is told apart by hex alone.
##
## **The foreground is a colour and a paint exposure in stops**, held as
## [member foreground_base], whose peak channel is at most 1, and [member
## exposure_stops], zero or more, and the foreground is the one times two to
## the power of the other. What a painter picks is what they paint, so a pick
## moves the slider and the slider moves the colour. A pick from
## anywhere is split by [method base_of] and [method stops_of], so (16, 0,
## -0.5) reads 4 stops of (1, 0, -0.03125) and (1, 0, 0) reads 0 stops. The
## brushes paint [member foreground] as it stands, and their Exposure option on
## the bar is these stops rather than a multiplier of their own.
class_name SaColorStore
extends Node

const FILE_NAME := "colors.cfg"
const MAX_RECENT: int = 12
const DEFAULT_FOREGROUND := Color.BLACK
const DEFAULT_BACKGROUND := Color.WHITE

signal swatches_changed
signal recent_changed
## The colour part or the stops changed, after the bus heard the foreground.
## The colour docker and its exposure slider follow this rather than the bus,
## because a pick of the colour already in hand moves the stops and leaves the
## foreground, and the bus says nothing then.
signal foreground_changed
## A mask became the paint target, *on* true, or stopped being it, after the
## pair turned grey or came back.
signal masking_changed(on: bool)

## What the brush paints with, [member foreground_base] times two to the power
## of [member exposure_stops]. Announced on the bus as `color_picked`.
##
## Setting it is a pick: the colour is split again, even one equal to the
## foreground, because (1, 0, 0) picked over 1 stop of (0.5, 0, 0) is the same
## light and reads 0 stops. Backed by a field of its own, because the listener
## below has to follow a pick someone else announced without announcing it
## again, and an assignment inside the class goes through the setter like any
## other.
var foreground: Color:
    get:
        return _foreground
    set(value):
        value = opaque(value)
        if not finite(value):
            return
        _split(_masked(value))

## The colour part of the foreground, its peak channel at most 1. The colour
## docker's wheel and sliders write it, and the stops stay. A colour given with
## a peak above 1 is light the painter asked for, so its peak goes into the
## stops rather than being lost: (2, 0, 0) at 1 stop is (1, 0, 0) at 2.
var foreground_base: Color:
    get:
        return _base
    set(value):
        value = opaque(value)
        if not finite(value):
            return
        if masking:
            _split(_masked(exposed(base_of(value), _stops + stops_of(value))))
            return
        _settle(base_of(value), _stops + stops_of(value))

## The paint exposure in stops, zero or more. Setting it keeps the colour part
## and moves the foreground with it, so (1, 0, 0) at 1 stop paints (2, 0, 0).
var exposure_stops: float:
    get:
        return _stops
    set(value):
        if not is_finite(value) or masking:
            return
        _settle(_base, value)

## The other colour of the pair, for X to swap in and for tools that take two.
var background: Color:
    get:
        return _background
    set(value):
        value = _masked(opaque(value))
        if not finite(value) or _background.is_equal_approx(value):
            return
        _background = value
        EventBus.background_color_changed.emit(value)

var _foreground: Color = DEFAULT_FOREGROUND
var _background: Color = DEFAULT_BACKGROUND
var _base: Color = DEFAULT_FOREGROUND
var _stops: float = 0.0
## Whether a mask is the paint target of the document [method follow] was
## given, so the pair is grey and [member _kept] holds the colours it had.
var masking: bool:
    get:
        return _kept != null

## The document whose `mask_target` greys the pair, or null.
var _document: SaDocument = null
## The pair as it stood when a mask became the target, or null while none is.
var _kept: KeptPair = null
## The grey rule [method mask_grey] hands out, held while the document's
## colour space stands, or null before one was asked for.
var _mask_grey: MaskGrey = null
## True while the store announces its own foreground, so the listener below
## knows its own echo from a pick someone else sent.
var _announcing: bool = false

## The colours the painter chose to keep, in the order they kept them.
var swatches: Array[Color] = []

## The name of each kept swatch, in step with [member swatches], and an empty
## string for one nobody named. Every edit below fits the two lists together
## first, because a suite and the last build both write the colours alone.
var swatch_names: Array[String] = []

## The swatch Remove took last, for Undo remove to put back where it was, or
## null while there is nothing to give back. Any other edit of the swatches
## clears it, because the place it remembers would then be somewhere else.
var last_removed_swatch: RemovedSwatch = null

## The colours last used, newest first.
var recent: Array[Color] = []

var path: String = SaDataRoot.path(FILE_NAME)


## Nothing to build, and here for the boot mark alone, whose gap since the
## autoload before it is this script's own load.
func _init() -> void:
    SaBootMarks.mark(&"colors_init")


func _ready() -> void:
    SaBootMarks.mark(&"colors_ready_begin")
    load_from(path)
    if not EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.connect(_on_color_picked)
    SaBootMarks.mark(&"colors_ready_end")


## X: the two colours change places.
func swap() -> void:
    var was_foreground := foreground
    foreground = background
    background = was_foreground
    save()


## D: black over white, the pair every painting program resets to.
func reset() -> void:
    foreground = DEFAULT_FOREGROUND
    background = DEFAULT_BACKGROUND
    save()


## Records that *color* was used, so it heads the recent list, once. A colour
## that is not finite was never used, so it is not recorded.
func note_used(color: Color) -> void:
    if not finite(color):
        return
    color = opaque(color)
    _remove_equal(recent, color)
    recent.push_front(color)
    while recent.size() > MAX_RECENT:
        recent.pop_back()
    save()
    recent_changed.emit()


## A swatch Remove took, with its colour, its name and the place it stood.
class RemovedSwatch:
    var color: Color
    var name: String
    var index: int

    func _init(of_color: Color, called: String, at: int) -> void:
        color = of_color
        name = called
        index = at


func add_swatch(color: Color, called: String = "") -> void:
    _fit_names()
    swatches.append(color)
    swatch_names.append(called)
    last_removed_swatch = null
    save()
    swatches_changed.emit()


## Keeps every colour in *colors* after the swatches already kept, then saves
## and announces once.
##
## One call for a whole palette rather than [method add_swatch] in a loop, which
## would write `colors.cfg` and rebuild the chips once per colour: twenty writes
## and twenty rebuilds for a twenty-colour palette, where one of each says the
## same thing. An empty list is not a change, so it writes nothing and tells
## nobody.
##
## After rather than instead of was the only answer until the picker's row grew
## a Clear button: a load that replaced the kept swatches would have thrown away
## colours a painter chose one at a time, and nothing on the row gave them back.
## The button gives them back, so a load may now ask and a painter may answer
## Replace, which is [method clear_swatches] and then this in one press.
## Appending is still what a load does without an answer.
##
## *names* are the palette file's, one per colour, and a colour past their end
## is kept unnamed.
func add_swatches(colors: Array, names: Array = []) -> void:
    if colors.is_empty():
        return
    _fit_names()
    for i in colors.size():
        swatches.append(colors[i])
        swatch_names.append(str(names[i]) if i < names.size() else "")
    last_removed_swatch = null
    save()
    swatches_changed.emit()


## Throws every kept swatch away, then saves and announces once.
##
## The missing half of the argument above: a load may only stand on what was
## kept if something on the row gives it back, and this is that something. The
## picker asks before it calls this, because a clear behind a hover is a clear
## nobody meant.
##
## An empty list is not a change, the way [method add_swatches] says an empty
## palette is not one: there is nothing to throw away, so it writes nothing and
## tells nobody.
func clear_swatches() -> void:
    if swatches.is_empty():
        return
    swatches.clear()
    swatch_names.clear()
    last_removed_swatch = null
    save()
    swatches_changed.emit()


## Takes the swatch at *index* away and remembers it in [member
## last_removed_swatch], which is what makes the removal one an Undo remove
## can give back.
func remove_swatch(index: int) -> void:
    if index < 0 or index >= swatches.size():
        return
    _fit_names()
    last_removed_swatch = RemovedSwatch.new(swatches[index], swatch_names[index], index)
    swatches.remove_at(index)
    swatch_names.remove_at(index)
    save()
    swatches_changed.emit()


## Puts the swatch [method remove_swatch] took back in its place, with its
## name, and answers whether there was one to put back. A list that has grown
## shorter since cannot happen while one is remembered, so the place is only
## clamped for a list a caller assigned by hand.
func undo_remove() -> bool:
    if last_removed_swatch == null:
        return false
    _fit_names()
    var removed := last_removed_swatch
    var at := clampi(removed.index, 0, swatches.size())
    swatches.insert(at, removed.color)
    swatch_names.insert(at, removed.name)
    last_removed_swatch = null
    save()
    swatches_changed.emit()
    return true


## Names the swatch at *index* *called*, trimmed. An empty name is allowed and
## is the swatch unnamed again, its chip read by its hex. The same name is not
## a change, so it writes nothing and tells nobody.
func rename_swatch(index: int, called: String) -> void:
    if index < 0 or index >= swatches.size():
        return
    _fit_names()
    var trimmed := called.strip_edges()
    if swatch_names[index] == trimmed:
        return
    swatch_names[index] = trimmed
    last_removed_swatch = null
    save()
    swatches_changed.emit()


## Pads or cuts [member swatch_names] to the length of [member swatches], an
## added name empty. The two lists are written together everywhere in this
## class, so this answers the ones written elsewhere: a suite assigning the
## colours, and a file from before the names key.
func _fit_names() -> void:
    var count := swatches.size()
    if swatch_names.size() > count:
        swatch_names.resize(count)
    while swatch_names.size() < count:
        swatch_names.append("")


## Tells every listener the pair once, for the tools that registered after the
## store loaded and would otherwise keep their own default until a pick.
func announce() -> void:
    _announce_foreground()
    EventBus.background_color_changed.emit(background)


## The foreground on the bus, with the listener told it is the store's own, so
## the split it was made from stands: 2 stops of (0.5, 0.25, 0) split again
## would read 1 stop of (1, 0.5, 0), the same light and not the painter's
## setting.
func _announce_foreground() -> void:
    _announcing = true
    EventBus.color_picked.emit(_foreground)
    _announcing = false


## Takes *base* and *stops* as the split, the stops at zero or more, and the
## foreground as their product.
func _settle(base: Color, stops: float) -> void:
    stops = maxf(stops, 0.0)
    _take(base, stops, exposed(base, stops))


## A pick of *color*, finite and opaque, split into its colour part and stops,
## and kept as given rather than as their product, which a peak like 3 would
## round in its last bit. *aloud* is false for a pick the bus already
## carried, which every tool has heard.
func _split(color: Color, aloud: bool = true) -> void:
    _take(base_of(color), stops_of(color), color, aloud)


## The split and the foreground it paints. The bus hears the foreground only
## when it moved and *aloud*, [signal foreground_changed] whenever either
## half did, and the bar's Exposure reads the stops again on
## `tool_options_moved`, which is what moves it under a pick without the tool
## in hand knowing.
func _take(base: Color, stops: float, painted: Color, aloud: bool = true) -> void:
    var stops_moved := not is_equal_approx(stops, _stops)
    var split_moved := stops_moved or not _base.is_equal_approx(base)
    var painted_moved := not _foreground.is_equal_approx(painted)
    _base = base
    _stops = stops
    _foreground = painted
    if painted_moved and aloud:
        _announce_foreground()
    if split_moved:
        foreground_changed.emit()
    if stops_moved:
        EventBus.tool_options_moved.emit()


func save() -> void:
    var config := ConfigFile.new()
    # The pair the painter chose, not the greys a mask shows over it, so a
    # session that ends with a mask as the target opens on the colours.
    config.set_value("pair", "foreground", _kept.painted if masking else foreground)
    config.set_value("pair", "foreground_base", _kept.base if masking else _base)
    config.set_value("pair", "exposure_stops", _kept.stops if masking else _stops)
    config.set_value("pair", "background", _kept.background if masking else background)
    _fit_names()
    config.set_value("lists", "swatches", swatches)
    config.set_value("lists", "swatch_names", swatch_names)
    config.set_value("lists", "recent", recent)
    var err := SaConfigLadder.write(config, path)
    if err != OK:
        SaProblems.report("SaColorStore", tr("Colours could not be saved to '%s' (%s).") % [path, error_string(err)])


## Reads the colours, or the backup the last save kept when the file is there
## but does not parse, which a crash in the middle of a write leaves. The
## unreadable file is moved aside first, so the next pick saves beside it and
## never over it, and the painter is told where it is. A missing file is a first
## run and says nothing.
func load_from(from_path: String) -> void:
    path = from_path
    var ladder := SaConfigLadder.new(path)
    if ladder.outcome == SaConfigLadder.Outcome.MISSING:
        return
    if ladder.outcome == SaConfigLadder.Outcome.DEFAULTS:
        _say_unreadable(ladder)
        return
    _read(ladder.config)
    if ladder.outcome == SaConfigLadder.Outcome.RESTORED:
        # Written back at once, or the next launch finds no file and starts
        # on defaults with the recovered swatches left only in the backup.
        save()
        _say_unreadable(ladder)


## Tells the painter the file did not parse, what they have instead, and where
## the unreadable file is kept, since what broke it may be one line they can
## repair by hand.
func _say_unreadable(ladder: SaConfigLadder) -> void:
    var cause := error_string(ladder.error)
    if ladder.outcome == SaConfigLadder.Outcome.RESTORED:
        SaProblems.report(
            "SaColorStore",
            (
                tr("Colours could not be read (%s). The swatches came back from the last save, the unreadable file is at %s.")
                % [cause, ladder.broken_path]
            )
        )
        return
    SaProblems.report(
        "SaColorStore",
        (
            tr("Colours could not be read (%s). The defaults are in use, and the swatches are in the unreadable file at %s.")
            % [cause, ladder.broken_path]
        )
    )


func _read(config: ConfigFile) -> void:
    foreground = config.get_value("pair", "foreground", DEFAULT_FOREGROUND)
    _load_split(config)
    background = config.get_value("pair", "background", DEFAULT_BACKGROUND)
    swatches.assign(SaTyped.list(config.get_value("lists", "swatches", [])).filter(finite).map(opaque))
    swatch_names.clear()
    for called: Variant in SaTyped.list(config.get_value("lists", "swatch_names", [])):
        swatch_names.append(str(called))
    _fit_names()
    last_removed_swatch = null
    recent.assign(SaTyped.list(config.get_value("lists", "recent", [])).filter(finite).map(opaque))
    swatches_changed.emit()
    recent_changed.emit()


## The split the last session saved, when it is one and makes the foreground
## just read. A file from before the stops, or one edited by hand so the two
## disagree, keeps the split of the foreground, which is a pick's.
func _load_split(config: ConfigFile) -> void:
    # A null default is no default to `ConfigFile`, which reports the missing key
    # as an error, so the keys are asked for first.
    if not (config.has_section_key("pair", "foreground_base") and config.has_section_key("pair", "exposure_stops")):
        return
    var base: Variant = config.get_value("pair", "foreground_base")
    var stops: Variant = config.get_value("pair", "exposure_stops")
    if not (base is Color and (stops is float or stops is int)):
        return
    var given: Color = base
    var kept := opaque(given)
    var kept_stops: float = stops
    if not finite(kept) or not is_finite(kept_stops) or kept_stops < 0.0 or _peak(kept) > 1.0 + 1e-6:
        return
    if exposed(kept, kept_stops).is_equal_approx(_foreground):
        _settle(kept, kept_stops)


## The eyedropper, a palette and the door announce a pick on the bus. The store
## splits it without announcing it again, ignores its own announcement, and
## keeps what it had for a colour that is not finite. While a mask is the target
## the pick is kept as its grey and not announced again: a tool that heard the
## colour paints its lightness into the mask at dab time, which is that grey.
func _on_color_picked(color: Color) -> void:
    if _announcing or not finite(color):
        return
    _split(_masked(opaque(color)), false)


## Follows *document*'s `mask_target`, the one the main window paints, and lets
## go of the one followed before, giving the kept pair back if its mask was the
## target. The shortcut router calls it as it binds, since it holds the canvas.
func follow(document: SaDocument) -> void:
    if is_instance_valid(document) and document == _document:
        return
    if is_instance_valid(_document) and _document.mask_target_changed.is_connected(_on_mask_target_changed):
        _document.mask_target_changed.disconnect(_on_mask_target_changed)
        _document.tree_exiting.disconnect(_on_document_exiting)
    _document = document
    if document != null:
        document.mask_target_changed.connect(_on_mask_target_changed)
        # A document that goes away with a mask as its target would leave the
        # pair grey for good, so its leaving gives the pair back.
        document.tree_exiting.connect(_on_document_exiting)
    _on_mask_target_changed(document.mask_target if document != null else null)


## Asked a frame late, because a canvas moved to another parent leaves the tree
## and comes back with its document, which is still the one to follow.
func _on_document_exiting() -> void:
    _let_go_unless_back.call_deferred()


func _let_go_unless_back() -> void:
    if not (is_instance_valid(_document) and _document.is_inside_tree()):
        follow(null)


## What Escape does first in the main window: clears the mask target of the
## document followed, which gives the pair back through the listener, and says
## whether there was one to clear.
func leave_mask() -> bool:
    if not is_instance_valid(_document) or _document.mask_target == null:
        return false
    _document.mask_target = null
    return true


func _on_mask_target_changed(mask: SaMask) -> void:
    if mask != null and _kept == null:
        _kept = KeptPair.new(_base, _stops, _foreground, _background)
        _split(_masked(_foreground))
        background = _background
        masking_changed.emit(true)
    elif mask == null and _kept != null:
        var kept := _kept
        _kept = null
        _take(kept.base, kept.stops, kept.painted)
        background = kept.background
        masking_changed.emit(false)


## *color* as a brush paints it into a mask while one is the target, as it is
## otherwise. `state_brush.gd` turns the picked colour into the document's
## numbers and paints its lightness there, from 0 to 1, as coverage. The grey
## returned is the neutral the pickers can show for that coverage: the display
## grey whose own lightness in the document is the same, so a pick of it paints
## what it shows and turning it grey again leaves it as it is.
func _masked(color: Color) -> Color:
    if _kept == null:
        return color
    var space: SaColorSpace = _document.color_space if is_instance_valid(_document) else null
    if space == null:
        var value := clampf(color.v, 0.0, 1.0)
        return Color(value, value, value, 1.0)
    var grey := _grey_of(space, _cover(space, color))
    return Color(grey, grey, grey, 1.0)


## The coverage a brush paints *color* as into a mask of a document in *space*.
static func _cover(space: SaColorSpace, color: Color) -> float:
    return clampf(space.lightness(space.from_display(color)), 0.0, 1.0)


## The display grey whose own coverage in *space* is *cover*.
##
## The lightness of a display grey rises with it, so halving the interval finds
## the grey to well under a step of an 8 bit channel.
static func _grey_of(space: SaColorSpace, cover: float) -> float:
    var low := 0.0
    var high := 1.0
    for _step in 24:
        var middle := (low + high) * 0.5
        if _cover(space, Color(middle, middle, middle)) < cover:
            low = middle
        else:
            high = middle
    return (low + high) * 0.5


## The rule [method _masked] applies, in the pieces a shader can draw it with
## for every pixel under a cover.
##
## A picker greyed for a mask shows what lies under it as the grey the brush
## would paint there, which is this rule once a pixel. Handing over the
## document's own numbers and this store's own table of greys is what keeps the
## cover and a pick through it from drifting apart, where a formula written
## again in a shader would drift the day a document's space changed. Held while
## the space stands, because the table costs a bisection an entry.
func mask_grey() -> MaskGrey:
    var space: SaColorSpace = _document.color_space if is_instance_valid(_document) else null
    if _mask_grey == null or not _mask_grey.fits(space):
        _mask_grey = MaskGrey.new(space)
    return _mask_grey


## The rule a mask's grey follows, as numbers a shader takes as uniforms.
##
## The coverage of a display colour is [method _cover]'s, in the pieces that
## compute it: the colour decoded from the display curve, carried by
## [member carry], put through [member shape] a channel at a time and weighed.
## For an Oklab document that is Oklab's own L, the cone responses cube rooted
## and weighed, and the cover carries the weights and the cone matrix itself
## since [SaOklab] holds them nowhere a shader can read. For an RGB document it
## is the luminance of the stored triple, [member weights] being the Y row of
## the document's matrix and [member shape] its own curve. With no document at
## all it is the colour's own peak, which is what [method _masked] takes then.
##
## [member greys] is the display grey of each coverage, evenly spaced, by the
## same bisection a pick goes through.
class MaskGrey:
    extends RefCounted

    ## No document: the coverage is the colour's own peak, and the grey is it.
    const PEAK: int = 0
    ## An Oklab document: the coverage is Oklab's own L.
    const OKLAB: int = 1
    ## An RGB document: the coverage is the luminance of the stored triple.
    const LUMINANCE: int = 2

    ## How many greys the table holds. A cover reads it by halves between the
    ## two entries nearest, and the grey of a coverage bends gently enough over
    ## a 256th that the halving lands far inside one step of an 8 bit channel.
    const STEPS: int = 256

    ## Which coverage the document asks for: [constant PEAK], [constant OKLAB]
    ## or [constant LUMINANCE].
    var rule: int = PEAK

    ## What a decoded display colour is carried by before the shape: the matrix
    ## into linear sRGB for an Oklab document, which is where Oklab is defined,
    ## and nothing at all for the rest.
    var carry := Basis()

    ## What the shape's three numbers are weighed by, for an RGB document. An
    ## Oklab document's weights are Oklab's own and the cover carries them.
    var weights := Vector3.ONE

    ## The display curve to undo, as the four numbers [SaTransferFunction] is:
    ## slope, where its toe ends in display values, gain and exponent.
    var display_curve := Vector4.ONE

    ## The curve the carried values go through, the same four numbers, with the
    ## toe measured in linear values because this one is applied rather than
    ## undone.
    var shape := Vector4.ONE

    ## The display grey of each coverage from 0 to 1, [constant STEPS] of them.
    var greys := PackedFloat32Array()

    ## The space the numbers above were read from, or null for no document.
    var _space: SaColorSpace = null

    func _init(space: SaColorSpace) -> void:
        _space = space
        var display := SaTransferFunction.srgb()
        display_curve = Vector4(display.slope, display.threshold, display.gain, display.exponent)
        if space == null:
            shape = _curve(SaTransferFunction.linear())
            greys = PackedFloat32Array()
            greys.resize(STEPS)
            for i in STEPS:
                greys[i] = float(i) / float(STEPS - 1)
            return
        if space.coordinates == SaColorSpace.Coordinates.OKLAB:
            rule = OKLAB
            carry = space.to_linear_srgb_matrix()
            # A cone response cube rooted is this one shape at gain 1 and
            # exponent 3, which is the curve `gamma30` already is, so the cover
            # needs no second kind of nonlinearity for Oklab.
            shape = _curve(SaTransferFunction.gamma30())
        else:
            rule = LUMINANCE
            shape = _curve(space.transfer)
            var xyz := space.rgb_to_xyz()
            weights = Vector3(
                (xyz * Vector3(1.0, 0.0, 0.0)).y, (xyz * Vector3(0.0, 1.0, 0.0)).y, (xyz * Vector3(0.0, 0.0, 1.0)).y
            )
        greys = PackedFloat32Array()
        greys.resize(STEPS)
        for i in STEPS:
            greys[i] = SaColorStore._grey_of(space, float(i) / float(STEPS - 1))

    ## Whether these numbers are still the ones *space* asks for.
    func fits(space: SaColorSpace) -> bool:
        if space == null or _space == null:
            return space == _space
        return space == _space or _space.matches(space)

    ## *curve* as the four numbers a shader applies it by, its toe in the linear
    ## values it is given rather than in the display ones it returns.
    static func _curve(curve: SaTransferFunction) -> Vector4:
        return Vector4(curve.slope, curve.linear_threshold(), curve.gain, curve.exponent)


## The pair as a mask found it: the foreground's split and the colour it
## painted, and the background.
class KeptPair:
    extends RefCounted

    var base: Color
    var stops: float
    var painted: Color
    var background: Color

    func _init(kept_base: Color, kept_stops: float, kept_painted: Color, kept_background: Color) -> void:
        base = kept_base
        stops = kept_stops
        painted = kept_painted
        background = kept_background


## The stops a pick of *color* reads: the base 2 logarithm of its peak channel
## when that is above 1, and 0 for any other, so (16, 0, -0.5) reads 4 and
## (1, 0, 0) reads 0.
static func stops_of(color: Color) -> float:
    var peak := _peak(color)
    return log(peak) / log(2.0) if peak > 1.0 else 0.0


## The colour part of a pick of *color*: divided by its peak channel when that
## is above 1, and as it is otherwise, alpha 1 either way. (16, 0, -0.5) gives
## (1, 0, -0.03125).
static func base_of(color: Color) -> Color:
    var peak := _peak(color)
    if peak <= 1.0:
        return opaque(color)
    return Color(color.r / peak, color.g / peak, color.b / peak, 1.0)


## *base* times two to the power of *stops*, alpha 1, the colour a brush
## paints.
static func exposed(base: Color, stops: float) -> Color:
    var gain := pow(2.0, stops)
    return Color(base.r * gain, base.g * gain, base.b * gain, 1.0)


static func _peak(color: Color) -> float:
    return maxf(color.r, maxf(color.g, color.b))


## *color* with its alpha at 1.0 and its channels as they were, above 1.0
## included, because hard rule 5 is about the colour and the alpha is not
## part of it here.
##
## The setters, the listener, the recent list and the load are where the store
## drops it, and they are enough for what the store holds. They are not enough for what the bus
## carries: a pick announced on `color_picked` reaches the swatch, the picker
## and every tool as it was emitted, before or after the store hears it, and an
## echo from here would land between them in no fixed order. So a feature that
## announces a colour of its own on the bus, the eyedropper and the Reference
## docker's sample, drops the alpha through this before it emits.
static func opaque(color: Color) -> Color:
    return Color(color, 1.0)


## Whether *color*'s three channels are numbers that are not infinite. The
## alpha is not asked, because [method opaque] drops it. The one test for a
## colour a store refuses, so a feature that announces on the bus itself, the
## eyedropper, refuses the same ones before it emits.
static func finite(color: Color) -> bool:
    return is_finite(color.r) and is_finite(color.g) and is_finite(color.b)


static func _remove_equal(list: Array[Color], color: Color) -> void:
    for i in range(list.size() - 1, -1, -1):
        if list[i].is_equal_approx(color):
            list.remove_at(i)
