## Which lights of the Welcome picture are on show: the season where the painter
## lives, then the sun there, or the hour round the 24 hour circle.
##
## **A light** is one file of the picture with the moment it shows at its
## fullest, and a season it belongs to when its sidecar gives one (`spring`,
## `summer`, `autumn` or `winter`). The moment is a local `hour`, or a `sun`
## height in degrees with a `side`, `rising` or `setting`. A light with no season is every season's, so a night that looks the
## same all year is listed once. `lights_in` reads them from a sidecar and
## `in_season` keeps the ones a season shows.
##
## **The season** is `WelcomeSun`'s, from the date and the side of the equator
## the painter's guessed place is on, and none within the tropics, so a painter
## in Quito never sees snow. A season that is none shows only the lights with
## none. Nothing here asks the painter or leaves the machine.
##
## **The fade** runs within the lights a season shows, so seasons are picked
## first and the moment second. A sidecar whose every light names a `sun` fades
## by the sun (`by_sun`, `reached`, `fade_by_sun`), any other by the clock hour
## (`fade_at`), a sun light in it taking the hour the sun stands there
## on the equator at an equinox, six plus a fifteenth of its height rising and
## eighteen less it setting.
##
## **A moment may hold several lights**, the moods of one hour, and `one_each`
## keeps one of them at each opening by a roll from 0 to 1, each light as
## likely as its `weight` (1 when the sidecar names none), taken in the order of
## their file names. Two moments that list the same moods with the same weights
## pick the same mood from one roll, so a day listed at the rising and the
## setting sun is the same day all through. `roll_once` draws the roll, fixed by
## `SARA_WELCOME_ROLL` in a debug build as `PictureOverlays` reads it.
##
## A debug build takes the hour, the month, the zone and the locale from
## `SARA_WELCOME_HOUR`, `SARA_WELCOME_MONTH`, `SARA_WELCOME_ZONE` and
## `SARA_WELCOME_LOCALE` when they are set (`WelcomeSun` reads them), so a
## scenario's shot is the same at any date and place.
@tool
class_name PictureLights
extends RefCounted

const DAY_HOURS: float = 24.0

## The seasons, northern winter first.
const SEASONS: Array[String] = WelcomeSun.SEASONS

## The two sides of the sun's day a sun light may name.
const SIDES: Array[String] = ["rising", "setting"]


## The country of *locale* as its two capital letters, `CZ` for `cs_CZ`, or
## empty for one that names none. `SaLocation.country_of` has the rule.
static func country_of(locale: String) -> String:
    return SaLocation.country_of(locale)


## The season of *month*, 1 to 12, for a painter whose locale is *locale*, at
## the country's place by `SaLocation.place_of_country`. Empty when the locale names no
## country, a country the table has no zone of, or one within the tropics.
static func season_of(month: int, locale: String) -> String:
    var place := SaLocation.place_of_country(country_of(locale), month)
    if place.how == SaLocation.BY_NOTHING:
        return ""
    return WelcomeSun.season_at(month, place.latitude)


## The lights a sidecar lists under `variants`, by hour. An entry that has no
## bare file name, neither an hour nor a sun with its side, a season that is not
## one of the four, or no picture in *folder* is left out. One with both an hour
## and a sun is the sun's.
static func lights_in(sidecar: Dictionary, folder: String) -> Array[Light]:
    var found: Array[Light] = []
    var listed: Variant = sidecar.get("variants", [])
    if not listed is Array:
        return found
    for entry: Variant in listed:
        if not entry is Dictionary:
            continue
        var item: Dictionary = entry
        var file := str(item.get("file", ""))
        var at: Variant = item.get("hour")
        var height: Variant = item.get("sun")
        var side := str(item.get("side", ""))
        var in_year := str(item.get("season", ""))
        var weight_given: Variant = item.get("weight", 1.0)
        var weight: float = maxf(float(weight_given), 0.0) if weight_given is float or weight_given is int else 1.0
        var bare := not file.is_empty() and file == file.get_file()
        var by_height := (height is float or height is int) and SIDES.has(side)
        var by_hour := at is float or at is int
        if not bare or not (by_height or by_hour) or not ResourceLoader.exists(folder + file):
            continue
        if item.has("season") and not SEASONS.has(in_year):
            continue
        if by_height:
            var sun: float = clampf(float(height), -90.0, 90.0)
            var rising := side == "rising"
            found.append(Light.new(folder + file, equator_hour(sun, rising), in_year, sun, rising, weight))
        else:
            var at_hour: float = at
            found.append(Light.new(folder + file, fposmod(at_hour, DAY_HOURS), in_year, NAN, false, weight))
    found.sort_custom(_earlier)
    return found


## The order of the lights: by hour, then by file name, so the moods of one
## moment always stand in the same order whatever order the sort meets them in.
static func _earlier(a: Light, b: Light) -> bool:
    if a.hour != b.hour:
        return a.hour < b.hour
    return a.path < b.path


## The lights of *lights* with one kept of each moment that holds several, the
## one *roll*, 0 to 1, falls on when the moment's lights stand in a row in
## their order, each as wide as its weight. A moment is the season and the
## sun's height and side, or the hour for a light by the clock. A moment of one
## light keeps it, and the order of the rest is kept.
static func one_each(lights: Array[Light], roll: float) -> Array[Light]:
    var moments := {}
    for light in lights:
        var moment := light.moment()
        if not moments.has(moment):
            moments[moment] = []
        (moments[moment] as Array).append(light)
    var kept: Array[Light] = []
    for light in lights:
        if _picked(moments[light.moment()], roll) == light:
            kept.append(light)
    return kept


## The light of *several* that *roll* falls on, the last for a roll of 1 and
## the first when every weight is naught.
static func _picked(several: Array, roll: float) -> Light:
    if several.size() == 1:
        return several[0]
    var total := 0.0
    for light: Light in several:
        total += light.weight
    if total <= 0.0:
        return several[0]
    var at := clampf(roll, 0.0, 1.0) * total
    var reached_to := 0.0
    for light: Light in several:
        reached_to += light.weight
        if at < reached_to:
            return light
    return several[several.size() - 1]


## A roll for `one_each` at an opening: the debug build's fixed roll when
## `SARA_WELCOME_ROLL` is set, the dice otherwise.
static func roll_once() -> float:
    var fixed := PictureOverlays.fixed_roll()
    return randf() if is_nan(fixed) else fixed


## The hour the sun stands *height* degrees up on the equator at an equinox,
## rising when *rising*: six plus a fifteenth of the height in the morning and
## eighteen less it in the evening.
static func equator_hour(height: float, rising: bool) -> float:
    return 6.0 + height / 15.0 if rising else 18.0 - height / 15.0


## Whether every light of *lights* names a sun, so the fade runs by the sun. No
## light at all is the clock's.
static func by_sun(lights: Array[Light]) -> bool:
    if lights.is_empty():
        return false
    for light in lights:
        if not light.by_sun():
            return false
    return true


## The lights of *lights* whose sun the day of *sky* reaches, between its
## lowest and its highest, so a Swedish midsummer night never shows a night
## light the sun never goes down to. A day that reaches none keeps the one light
## whose height is nearest the sun's now.
static func reached(lights: Array[Light], sky: WelcomeSun.SunNow) -> Array[Light]:
    var kept: Array[Light] = []
    var nearest: Light = null
    for light in lights:
        if light.sun >= sky.lowest and light.sun <= sky.highest:
            kept.append(light)
        if nearest == null or absf(light.sun - sky.height) < absf(nearest.sun - sky.height):
            nearest = light
    if kept.is_empty() and nearest != null:
        kept.append(nearest)
    return kept


## Which two lights of *lights*, every one a sun light the day reaches, the sun
## of *sky* lies between, and how far along. The day is a circle from the
## sun's lowest up its rising side to its highest and down its setting side to
## the lowest again, so the fade runs on through a night that never gets dark.
static func fade_by_sun(lights: Array[Light], sky: WelcomeSun.SunNow) -> Fade:
    var span := maxf(sky.highest - sky.lowest, 0.001)
    var places: Array[float] = []
    for light in lights:
        places.append(_round_the_day(light.sun, light.rising, sky.lowest, sky.highest))
    var ordered: Array[int] = []
    for i in lights.size():
        ordered.append(i)
    ordered.sort_custom(func(a: int, b: int) -> bool: return places[a] < places[b])
    var sorted_places: Array[float] = []
    for i in ordered:
        sorted_places.append(places[i])
    var now := _round_the_day(sky.height, sky.rising, sky.lowest, sky.highest)
    var fade := _fade_round(sorted_places, now, 2.0 * span)
    var first := ordered[fade.first] if fade.first >= 0 else -1
    var second := ordered[fade.second] if fade.second >= 0 else -1
    return Fade.new(first, second, fade.fraction)


## The lights of *by_hour* that *season* shows: its own and the ones with no
## season, in the order they came. An empty season, a painter on the equator's
## band or with no country, shows summer's, the season the picture was first
## painted in.
static func in_season(by_hour: Array[Light], season: String) -> Array[Light]:
    var held := season if not season.is_empty() else "summer"
    var shown: Array[Light] = []
    for light in by_hour:
        if light.season.is_empty() or light.season == held:
            shown.append(light)
    return shown


## Which two lights *at_hour* lies between and how far along: the first pair, in
## the order of the hours, whose span holds it, then the pair that closes the
## circle round midnight. With six and eighteen that is 0 at 6:00, a half at
## 12:00, 1 at 18:00 and a half at 0:00. One light has no second to fade to.
static func fade_at(by_hour: Array[Light], at_hour: float) -> Fade:
    var hours: Array[float] = []
    for light in by_hour:
        hours.append(light.hour)
    return _fade_round(hours, at_hour, DAY_HOURS)


## The fade on a circle *period* long through the places *places*, in order:
## the first pair whose span holds *at*, then the pair that closes the circle.
static func _fade_round(places: Array[float], at: float, period: float) -> Fade:
    if places.size() < 2:
        return Fade.new(places.size() - 1, -1, 0.0)
    var wanted := fposmod(at, period)
    for i in places.size() - 1:
        var from := places[i]
        var to := places[i + 1]
        if wanted >= from and wanted <= to:
            return Fade.new(i, i + 1, _along(from, to, wanted))
    var last := places.size() - 1
    var dusk := places[last]
    if wanted < dusk:
        wanted += period
    return Fade.new(last, 0, _along(dusk, places[0] + period, wanted))


## Where a sun *height* degrees up on its *rising* or setting side is round a
## day whose sun runs from *lowest* to *highest*: up from naught at the lowest
## on the rising side, and back down to twice the span on the setting side. A
## height the day does not reach is held at its nearer end.
static func _round_the_day(height: float, rising: bool, lowest: float, highest: float) -> float:
    var held := clampf(height, lowest, highest)
    if rising:
        return held - lowest
    return 2.0 * highest - lowest - held


## How far *at* is from *from* to *to*, 0 to 1, and 0 for a span with no length.
static func _along(from: float, to: float, at: float) -> float:
    if to <= from:
        return 0.0
    return clampf((at - from) / (to - from), 0.0, 1.0)


## One picture of the day: the file, with its folder, the hour it shows at,
## the season it belongs to, empty for every season, and for a sun light the
## sun's height and side, NAN for a light by the hour. Its weight is how likely
## it is among the lights of its moment.
class Light:
    var path: String
    var hour: float
    var season: String
    var sun: float
    var rising: bool
    var weight: float

    func _init(
        light_path: String,
        light_hour: float,
        light_season: String = "",
        light_sun: float = NAN,
        on_rising: bool = false,
        light_weight: float = 1.0
    ) -> void:
        path = light_path
        hour = light_hour
        season = light_season
        sun = light_sun
        rising = on_rising
        weight = light_weight

    func by_sun() -> bool:
        return not is_nan(sun)

    ## The moment the light shows at, as a key two lights of one moment share.
    func moment() -> String:
        if by_sun():
            return "%s sun %s %s" % [season, sun, rising]
        return "%s hour %s" % [season, hour]


## Which two lights are on show and how far the second is over the first. The
## second is -1 when there is nothing to fade to.
class Fade:
    var first: int
    var second: int
    var fraction: float

    func _init(first_light: int, second_light: int, along: float) -> void:
        first = first_light
        second = second_light
        fraction = along

    func faded() -> bool:
        return second >= 0
