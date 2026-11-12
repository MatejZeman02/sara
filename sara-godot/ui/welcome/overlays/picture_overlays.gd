## What the Welcome picture lays over itself by chance: the stars of a night, a
## flock of birds, each a transparent picture the size of the lights that is
## drawn at one opening of the window and not at the next.
##
## **An overlay** is one entry of the sidecar's `overlays`:
##
## [codeblock]
## "overlays": [
##     {"file": "0.18-stars.png", "kind": "stars", "opacity": [0.6, 1.0]},
##     {"file": "0.18-birds-1.png", "kind": "birds", "variants": ["0.18.png"]},
##     {"file": "0.18-birds-2.png", "chance": 0.3, "hours": [5, 9]}
## ]
## [/codeblock]
##
## A `file` is a bare name in the picture's folder. A `chance` from 0 to 1 is
## how often it is drawn at all, an `opacity` of two numbers is the range it is
## drawn at, one number is that opacity and none is a whole one. A `variants`
## list of light files, or an `hours` pair `[from, to]` round the 24 hour
## circle, names the lights it belongs to, and one with neither belongs to them
## all. A `kind` gives the defaults for what the entry leaves out:
## `stars` are drawn three openings in four and belong to the hours from 18 to
## 5, which is dusk and night and not the dawn at 6, and `birds`, like an entry
## of no kind, are drawn one opening in two at any hour, so two flocks make some
## openings birdless and some with both.
##
## Overlays that name one `together`, the one layer exported once per light it
## shows in, share their rolls, so the stars of the dusk and of the night are
## one sky and fade from one into the other at one opacity.
##
## **Every overlay rolls once at each opening** (`roll`), for whether it is
## drawn and for where in its range its opacity falls. One that loses is not
## drawn at all. One that wins is drawn over the lights at that opacity times
## the share of the picture its own lights have at the hour (`share`), so stars
## of the night fade in with the night and out with it. A debug build takes
## both rolls from `SARA_WELCOME_ROLL` when it is set, a number from 0 to 1, so
## a scenario's shot is the same at every run: 0 draws every overlay with any
## chance at its lowest opacity, 1 draws none.
@tool
class_name PictureOverlays
extends Control

const ROLL_VARIABLE := "SARA_WELCOME_ROLL"

## The chances and hours of the kinds a sidecar may name.
const STARS_CHANCE: float = 0.75
const BIRDS_CHANCE: float = 0.5
const STARS_HOURS: Array[float] = [18.0, 5.0]

## The overlays the sidecar lists, in its order, which is the order they are
## drawn in, and the layer each is drawn on.
var overlays: Array[Overlay] = []
var layers: Array[TextureRect] = []

var _dice := RandomNumberGenerator.new()


## The overlays *sidecar* lists, their files in *folder*.
func _init(sidecar: Dictionary = {}, folder: String = "") -> void:
    name = "Overlays"
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlays = overlays_in(sidecar, folder)
    for overlay in overlays:
        var layer := TextureRect.new()
        layer.name = overlay.path.get_file().get_basename()
        layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        layer.visible = false
        add_child(layer)
        layers.append(layer)
    _dice.randomize()


## Rolls every overlay for an opening of the window: the debug build's fixed
## roll when `SARA_WELCOME_ROLL` is set, the dice otherwise.
func roll_now() -> void:
    var fixed := fixed_roll()
    var shared := {}
    for overlay in overlays:
        if not is_nan(fixed):
            overlay.roll(fixed, fixed)
            continue
        var dice := Vector2(_dice.randf(), _dice.randf())
        if not overlay.together.is_empty():
            dice = shared.get(overlay.together, dice)
            shared[overlay.together] = dice
        overlay.roll(dice.x, dice.y)


## Draws each overlay that won its roll over *shown*, the lights on show, at
## *fade* between them and at *hour*, and hides each that lost.
func show_over(shown: Array[PictureLights.Light], fade: PictureLights.Fade, hour: float) -> void:
    for at in overlays.size():
        var overlay := overlays[at]
        var layer := layers[at]
        var alpha := overlay.opacity * share(overlay, shown, fade, hour) if overlay.drawn else 0.0
        layer.visible = alpha > 0.0
        layer.modulate = Color(1.0, 1.0, 1.0, alpha)
        if layer.visible and layer.texture == null:
            layer.texture = load(overlay.path) as Texture2D


## The roll a debug build fixes, NAN when it fixes none.
static func fixed_roll() -> float:
    if not OS.is_debug_build() or not OS.has_environment(ROLL_VARIABLE):
        return NAN
    var said := OS.get_environment(ROLL_VARIABLE)
    return clampf(said.to_float(), 0.0, 1.0) if said.is_valid_float() else NAN


## The overlays a sidecar lists under `overlays`. An entry with no bare file
## name, or no picture in *folder*, is left out.
static func overlays_in(sidecar: Dictionary, folder: String) -> Array[Overlay]:
    var found: Array[Overlay] = []
    var listed: Variant = sidecar.get("overlays", [])
    if not listed is Array:
        return found
    for entry: Variant in listed:
        if not entry is Dictionary:
            continue
        var item: Dictionary = entry
        var file := str(item.get("file", ""))
        if file.is_empty() or file != file.get_file() or not ResourceLoader.exists(folder + file):
            continue
        var stars := str(item.get("kind", "")) == "stars"
        var chance := clampf(_number(item.get("chance"), STARS_CHANCE if stars else BIRDS_CHANCE), 0.0, 1.0)
        var low := 1.0
        var high := 1.0
        var range_given: Variant = item.get("opacity")
        if range_given is Array and (range_given as Array).size() == 2:
            low = clampf(_number(range_given[0], 1.0), 0.0, 1.0)
            high = clampf(_number(range_given[1], 1.0), 0.0, 1.0)
        elif range_given is float or range_given is int:
            low = clampf(float(range_given), 0.0, 1.0)
            high = low
        var hours: Array[float] = []
        var hours_given: Variant = item.get("hours")
        if hours_given is Array and (hours_given as Array).size() == 2:
            hours = [_number(hours_given[0], 0.0), _number(hours_given[1], 0.0)]
        elif stars and not item.has("variants"):
            hours = STARS_HOURS.duplicate()
        var variants := PackedStringArray()
        var variants_given: Variant = item.get("variants")
        if variants_given is Array:
            for variant: Variant in variants_given:
                variants.append(str(variant))
        var together := str(item.get("together", ""))
        found.append(Overlay.new(folder + file, chance, minf(low, high), maxf(low, high), hours, variants, together))
    return found


## How much of the picture *overlay*'s own lights make up at *fade* between
## *shown*: the first light's share is what the second leaves of it and the
## second's is the fade's fraction. With no lights on show, the plain picture,
## an overlay is whole if it belongs to *hour* and absent if not.
static func share(overlay: Overlay, shown: Array[PictureLights.Light], fade: PictureLights.Fade, hour: float) -> float:
    if shown.is_empty() or fade.first < 0:
        return 1.0 if overlay.variants.is_empty() and overlay.at_hour(hour) else 0.0
    var first := 1.0 if overlay.belongs_to(shown[fade.first]) else 0.0
    if not fade.faded():
        return first
    var second := 1.0 if overlay.belongs_to(shown[fade.second]) else 0.0
    return lerpf(first, second, fade.fraction)


static func _number(given: Variant, otherwise: float) -> float:
    return float(given) if given is float or given is int else otherwise


## One overlay: its file with its folder, its chance, its opacity range, the
## hours and the light files it belongs to, the name it rolls together under,
## and what its last roll came to.
class Overlay:
    var path: String
    var chance: float
    var low: float
    var high: float
    var hours: Array[float]
    var variants: PackedStringArray
    var together: String
    var drawn: bool = false
    var opacity: float = 0.0

    func _init(
        overlay_path: String,
        overlay_chance: float,
        lowest: float = 1.0,
        highest: float = 1.0,
        in_hours: Array[float] = [],
        of_variants: PackedStringArray = PackedStringArray(),
        rolls_with: String = ""
    ) -> void:
        path = overlay_path
        chance = overlay_chance
        low = lowest
        high = highest
        hours = in_hours
        variants = of_variants
        together = rolls_with

    ## Rolls once: drawn when *draw*, from 0 up to but not 1, falls under the
    ## chance, at the opacity *pick* of the way up its range. A chance of 1 is
    ## drawn at every roll of the dice and one of 0 at none.
    func roll(draw: float, pick: float) -> void:
        drawn = draw < chance
        opacity = lerpf(low, high, clampf(pick, 0.0, 1.0)) if drawn else 0.0

    ## Whether *light* is one of the overlay's: named in its variants, or at an
    ## hour in its hours, or any light when it names neither.
    func belongs_to(light: PictureLights.Light) -> bool:
        if not variants.is_empty():
            return variants.has(light.path.get_file())
        return at_hour(light.hour)

    ## Whether *hour* is within the overlay's hours round the circle, ends
    ## included, and true when it names none.
    func at_hour(hour: float) -> bool:
        if hours.is_empty():
            return true
        var from := fposmod(hours[0], PictureLights.DAY_HOURS)
        var to := fposmod(hours[1], PictureLights.DAY_HOURS)
        var at := fposmod(hour, PictureLights.DAY_HOURS)
        return at >= from and at <= to if from <= to else at >= from or at <= to
