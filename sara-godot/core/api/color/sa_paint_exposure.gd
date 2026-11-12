## The paint exposure as the door hands it to a module: the foreground's
## brightness in stops.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The foreground is a base colour whose peak is at most one, times two to a
## number of stops, and the store in `SaColors` keeps the two. A brush engine
## shows the stops on the bar as its Exposure and paints the foreground as it
## is, so it asks and moves them here rather than naming the store, which sits
## behind the door.
class_name SaPaintExposure
extends RefCounted

## How far an exposure slider's drag reaches, in stops. Ten stops is a peak of
## 1024, past any light a painter mixes by hand, and a typed number goes on to
## [constant MAX].
const REACH := 10.0
## The most stops a 32-bit float holds as a factor: two to the 127th is the
## largest power of two below its ceiling, and the 128th is infinity. It is the
## hard end of every slider in stops that has no smaller home, the view's
## exposure and the Exposure filter's row among them, so a typed number is
## never cut short of what the value can be (hard rule 5).
const FLOAT_STOPS := 127.0
## The most an exposure slider takes typed, what a float document holds. A
## half precision document holds less, which [method held_by] says.
const MAX := FLOAT_STOPS
## The largest finite half float, the brightest a half precision chunk holds.
const HALF_PEAK := 65504.0


## The stops the foreground is painted at.
static func current() -> float:
    return SaColors.exposure_stops


## Puts the foreground at *stops* over the base colour it has. Below nought is
## nought, since a darker colour is a darker base.
static func move_to(stops: float) -> void:
    SaColors.exposure_stops = stops


## The most stops the foreground can be painted at in a document of colour
## space *space*: [constant FLOAT_STOPS] for a float document, and for a half
## precision one the stops whose peak is [constant HALF_PEAK]. The base
## colour's peak is at most one, so two to the stops is the paint's peak at
## most, and a number past this is one the document's chunks would turn to
## infinity rather than hold. A caller refuses such a number and says why,
## and never cuts it to this.
static func held_by(space: SaColorSpace) -> float:
    if space != null and space.depth == SaColorSpace.Depth.F16:
        return log(HALF_PEAK) / log(2.0)
    return FLOAT_STOPS


## The bar's Exposure row, one for every brush engine, so the one slider reads
## the same number whichever engine is in hand.
##
## Under the key `exposure`, which stored bar orders and visibility already
## name, so they keep their place, and through the settings' `paint_exposure`, which an
## engine forwards to [method current] and [method move_to] and never exports,
## so no preset carries it. Off the editor's page, since it is the colour's. On
## the bar and hidden there by a profile default, because `bar = false` builds
## no control at all and the Preferences row for it would move nothing. Behind
## the advanced check as well, since the option only means something in an HDR
## document: a painter who has not met the idea has no use for it, and one who
## has knows where it went.
##
## *fields* are the engine's own, its page or its bar group, laid over these
## as [method SaOptionSpec.make_float] takes them.
static func option_spec(fields: Dictionary[String, Variant] = {}) -> SaOptionSpec:
    var own: Dictionary[String, Variant] = {
        "property": ^"paint_exposure",
        "soft_max": REACH,
        "in_editor": false,
        "bar": true,
        "advanced": true,
        "bar_hidden": true,
        "bar_after": "flow",
        "suffix": " EV",
        "decimals": 2,
        "tooltip": "The paint exposure in stops: the colour picked, times two to this. A pick brighter than white sets it."
    }
    own.merge(fields, true)
    return SaOptionSpec.make_float(&"exposure", "Exposure", 0.0, MAX, 0.01, own)
