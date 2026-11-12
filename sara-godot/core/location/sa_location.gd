## Where the painter lives: the country set under Preferences > Files >
## Location, or else a guess from the machine's clock, for the Welcome
## picture's sun and an export's metadata.
##
## **Why core.** The guess was the Welcome picture's own, in `ui/welcome/sun`,
## until an export came to write the painter's country. Every export
## makes its metadata in `core/export`, which may not name `ui`, so the place
## came down here, with the table it is read from, and `WelcomeSun` kept the sun
## and the seasons and asks this class where it stands.
##
## **The place** is guessed with nothing asked and nothing leaving the machine
## (`guess`). The first choice is the system's time zone name,
## `Europe/Stockholm`, looked up in `zones.json`, the place of the zone's city.
## Where no name is found, the country of the locale is taken only when the
## clock's offset now is one that country's zones use, since a language setting
## often names another country than the painter's: a painter may run `en_US` in
## Czechia, whose offset no zone of the United States has. Past that, the offset
## and whether daylight saving is on now pick the zones that keep that clock at
## this time of year, and the side of the equator most of them are on is the
## painter's, at the middle latitude of that side's zones and the offset's own
## meridian. When no zone keeps that clock the place is the equator on the
## offset's meridian, which has no season and a sunset near six.
##
## **The zone name, platform by platform**, as read in the running app.
## Godot's own `Time.get_time_zone_from_system()` gives an abbreviation on Linux
## (`{"bias": 120, "name": "CEST"}` in Prague in summer time), so the
## name is read from `TZ` when it names a zone, then from where the symbolic
## link `/etc/localtime` points (`/usr/share/zoneinfo/Europe/Prague` on Linux,
## `/var/db/timezone/zoneinfo/Europe/Prague` on macOS), then from
## `/etc/timezone`. Windows has none of them and Godot gives its display name
## there, such as `Central Europe Daylight Time`, which is read as the Standard
## Time name Windows keys its zones by and looked up in CLDR's table. A Windows
## set to another language gives a translated name that no table holds, and the
## guess goes on to the locale and the offset.
##
## **A country set by hand** wins over the guess (`here`). The painter picks it
## from `choices`, which lists every country of tzdata's `iso3166.tab` under
## the long name tzdata gives it, once for each of its zones whose clock or side
## of the tropics differs from another's, so Australia is asked about and
## Czech Republic is not. A country no zone of the table serves, an island with
## nobody's clock, keeps the guess for the sun and is still its name in an
## export.
@tool
class_name SaLocation
extends RefCounted

const TABLE := "res://core/location/zones.json"

## Where a place came from: the zone name, the locale, the clock's offset,
## nothing at all, and the country set in Preferences.
const BY_ZONE := "zone"
const BY_LOCALE := "locale"
const BY_OFFSET := "offset"
const BY_NOTHING := "nothing"
const BY_CHOICE := "choice"

## How far from the equator the sun stands overhead on one day of the year,
## which is where the seasons start and the zones of a country part.
const TROPIC: float = 23.44

static var _table: Dictionary = {}
static var _choices: Array[Choice] = []


## Where the painter is in *month*: the country and zone Preferences names, or
## the guess when it names none or one the table has no zone for.
static func here(month: int) -> Place:
    var chosen := chosen_place(SaSettings.location_country, SaSettings.location_zone, month)
    if chosen.how == BY_CHOICE:
        return chosen
    return guessed(month)


## The country an export names, by its long name: the one Preferences names, or
## with Automatic the guess's, and empty when the guess found no country.
static func country_here() -> String:
    var code := SaSettings.location_country
    if code.is_empty():
        var month: int = Time.get_datetime_dict_from_system()["month"]
        code = guessed(month).country
    return country_name(code)


## The guess from what this machine says now, *month*'s half of the year
## setting the zone's offset when the zone is named.
static func guessed(month: int) -> Place:
    var clock := Time.get_time_zone_from_system()
    var daylight: bool = Time.get_datetime_dict_from_system().get("dst", false)
    var bias: int = clock.get("bias", 0)
    return guess(system_zone(str(clock.get("name", ""))), OS.get_locale(), bias, daylight, month)


## The place of *country* by its two capitals in *month*, at *zone* when that
## is one of its zones and otherwise at its first, how `BY_CHOICE`. How
## `BY_NOTHING` for no country or one the table has no zone of.
static func chosen_place(country: String, zone: String, month: int) -> Place:
    var zones := zones_for(country)
    if zones.is_empty():
        return Place.new(0.0, 0.0, "", country, 0, BY_NOTHING)
    var named := tz_name(zone)
    var found := place_of_zone(named if zones.has(named) else zones[0], month)
    found.country = country
    found.how = BY_CHOICE
    return found


## The painter's place from what the machine says: *zone* is a tzdata or Windows
## zone name or empty, *locale* the system's, *offset* the clock's minutes
## ahead of UTC now, *daylight* whether daylight saving is on, and *month* the
## month now. The four steps are in this file's header.
static func guess(zone: String, locale: String, offset: int, daylight: bool, month: int) -> Place:
    var named := tz_name(zone)
    if not named.is_empty():
        var found := place_of_zone(named, month)
        found.offset = offset
        return found
    var country := country_of(locale)
    for name in zones_of(country):
        if offsets_of(name).has(offset):
            var kept := place_of_zone(name, month)
            kept.offset = offset
            kept.how = BY_LOCALE
            return kept
    return place_of_clock(offset, daylight, month)


## The place a clock *offset* minutes ahead of UTC with daylight saving on or
## off stands for in *month*: the side of the equator most of the zones that
## keep that clock then are on, at the middle latitude of that side's zones and
## the offset's meridian, north on a tie. The equator when no zone keeps it.
static func place_of_clock(offset: int, daylight: bool, month: int) -> Place:
    var column := 5 if month >= 4 and month <= 9 else 3
    var north: Array[float] = []
    var south: Array[float] = []
    var zones: Dictionary = table().get("zones", {})
    for name: String in zones:
        var row: Array = zones[name]
        if int(_at(row, column)) == offset and (_at(row, column + 1) != 0.0) == daylight:
            if _at(row, 0) >= 0.0:
                north.append(_at(row, 0))
            else:
                south.append(_at(row, 0))
    var side := north if north.size() >= south.size() else south
    if side.is_empty():
        return Place.new(0.0, offset / 4.0, "", "", offset, BY_NOTHING)
    side.sort()
    return Place.new(side[floori(side.size() / 2.0)], offset / 4.0, "", "", offset, BY_OFFSET)


## The place of the zone *name*, which the table must hold, with the zone's own
## offset in *month*'s half of the year.
static func place_of_zone(name: String, month: int) -> Place:
    var row := zone_row(name)
    if row.is_empty():
        return Place.new(0.0, 0.0, "", "", 0, BY_NOTHING)
    var offset := int(_at(row, 5)) if month >= 4 and month <= 9 else int(_at(row, 3))
    var country := str(row[2]).get_slice(",", 0)
    return Place.new(_at(row, 0), _at(row, 1), tz_name(name), country, offset, BY_ZONE)


## The place of *country*, the one of its zones furthest from the equator, so a
## country that reaches past a tropic has its seasons, or the equator at
## Greenwich for a country the table has no zone of. Brazil is Sao Paulo, the
## United States Alaska, Australia Hobart and Ecuador still within the tropics.
static func place_of_country(country: String, month: int) -> Place:
    var names := zones_of(country)
    if names.is_empty():
        return Place.new(0.0, 0.0, "", "", 0, BY_NOTHING)
    var furthest := names[0]
    for name in names:
        if absf(_at(zone_row(name), 0)) > absf(_at(zone_row(furthest), 0)):
            furthest = name
    var found := place_of_zone(furthest, month)
    found.country = country
    found.how = BY_LOCALE
    return found


## The zones *country* is used in, by its two capitals, the table's order.
static func zones_of(country: String) -> Array[String]:
    var found: Array[String] = []
    if country.is_empty():
        return found
    var zones: Dictionary = table().get("zones", {})
    for name: String in zones:
        if _codes(zones, name).split(",").has(country):
            found.append(name)
    return found


## The zones that are *country*'s own, those it is the first country of, as
## `zone.tab` lists one for each country it keeps a clock in. `Europe/Berlin`
## serves Sweden in `zone1970.tab`, and Sweden's own is `Europe/Stockholm`.
## Every zone it is used in when it is the first of none. An Antarctic station
## comes last: Australia's `Antarctica/Macquarie` keeps Sydney's clock, and a
## choice is named by, and stands the sun at, the first zone of its clock.
static func zones_for(country: String) -> Array[String]:
    var own: Array[String] = []
    var zones: Dictionary = table().get("zones", {})
    var far: Array[String] = []
    for name in zones_of(country):
        if _codes(zones, name).get_slice(",", 0) != country:
            continue
        if name.begins_with("Antarctica/"):
            far.append(name)
        else:
            own.append(name)
    own.append_array(far)
    return own if not own.is_empty() else zones_of(country)


## Every country under its long name, by its two capitals, `iso3166.tab`'s
## order, which is the codes' alphabetical one.
static func countries() -> Dictionary:
    return table().get("countries", {})


## The long name of *country*, empty for no country or one tzdata does not list.
static func country_name(country: String) -> String:
    return str(countries().get(country, ""))


## What the Location picker offers, sorted by name: one `Choice` for each
## country, and one for each zone of a country whose zones keep different
## clocks or stand on different sides of a tropic. A choice names the first of
## the zones that keep its clock, and carries all their places. Built once,
## since the table never changes while Sara runs.
static func choices() -> Array[Choice]:
    if not _choices.is_empty():
        return _choices
    var out: Array[Choice] = []
    var codes: Dictionary = countries()
    var names: Array = codes.keys()
    names.sort_custom(func(a: String, b: String) -> bool: return str(codes[a]).naturalnocasecmp_to(str(codes[b])) < 0)
    for code: String in names:
        var groups: Array[Choice] = []
        var by_clock: Dictionary = {}
        for zone in zones_for(code):
            var row := zone_row(zone)
            var key := "%s/%s/%s/%s/%d" % [row[3], row[4], row[5], row[6], _band(_at(row, 0))]
            if not by_clock.has(key):
                by_clock[key] = Choice.new(code, zone)
                groups.append(by_clock[key])
            var group: Choice = by_clock[key]
            group.places.append(place_name(zone))
        if groups.size() <= 1:
            out.append(Choice.new(code, ""))
        else:
            out.append_array(groups)
    _choices = out
    return out


## The place a zone is named by, its last part with spaces:
## `America/Indiana/Tell_City` is Tell City.
static func place_name(zone: String) -> String:
    return zone.get_slice("/", zone.get_slice_count("/") - 1).replace("_", " ")


## The offsets the zone *name* keeps in January and July, in minutes.
static func offsets_of(name: String) -> Array[int]:
    var row := zone_row(name)
    if row.is_empty():
        return []
    return [int(_at(row, 3)), int(_at(row, 5))]


## The table's row of *name* after its links and Windows' names are followed,
## empty for a name it has none of.
static func zone_row(name: String) -> Array:
    var zones: Dictionary = table().get("zones", {})
    return zones.get(tz_name(name), [])


## The tzdata name *name* stands for, itself for one of the table's zones, the
## zone a link or a Windows name points at, and empty for none. A Windows name
## in daylight saving is read as its Standard Time name.
static func tz_name(name: String) -> String:
    var zones: Dictionary = table().get("zones", {})
    if zones.has(name):
        return name
    var links: Dictionary = table().get("links", {})
    var linked: String = links.get(name, "")
    if not linked.is_empty():
        return linked
    var windows: Dictionary = table().get("windows", {})
    var standard := name.replace("Daylight Time", "Standard Time").replace("Summer Time", "Standard Time")
    return windows.get(standard, "")


## The zone name the system gives: `TZ` when it names one, the target of
## `/etc/localtime` after its `zoneinfo/`, `/etc/timezone`, and last
## *godot_name*, Godot's own, which is an abbreviation on Linux and a display
## name on Windows. Empty when none of them is one of the table's.
static func system_zone(godot_name: String) -> String:
    var tried: Array[String] = [OS.get_environment("TZ").trim_prefix(":")]
    var etc := DirAccess.open("/etc")
    if etc != null and etc.is_link("/etc/localtime"):
        var target := etc.read_link("/etc/localtime")
        if target.contains("zoneinfo/"):
            tried.append(target.get_slice("zoneinfo/", target.get_slice_count("zoneinfo/") - 1))
    if FileAccess.file_exists("/etc/timezone"):
        tried.append(FileAccess.get_file_as_string("/etc/timezone").strip_edges())
    tried.append(godot_name)
    for name in tried:
        if not tz_name(name).is_empty():
            return name
    return ""


## The country of *locale* as its two capital letters, `CZ` for `cs_CZ`, or empty
## for one that names none, such as `C`, `en` or `sr_Latn`. A hyphen is read as
## an underscore and the encoding or modifier a POSIX locale carries is left off.
static func country_of(locale: String) -> String:
    var parts := locale.replace("-", "_").get_slice(".", 0).get_slice("@", 0).split("_")
    var last := parts[parts.size() - 1]
    if parts.size() > 1 and last.length() == 2 and _is_capitals(last):
        return last
    return ""


## The table of zones, read once.
static func table() -> Dictionary:
    if _table.is_empty():
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
        _table = parsed if parsed is Dictionary else {"zones": {}}
    return _table


## Whether *text* is capital letters of the alphabet and nothing else.
static func _is_capitals(text: String) -> bool:
    for i in text.length():
        if text.unicode_at(i) < 65 or text.unicode_at(i) > 90:
            return false
    return true


## Which side of the tropics *latitude* is on, south, within or north, as -1,
## 0 or 1, since the seasons part there.
static func _band(latitude: float) -> int:
    if absf(latitude) < TROPIC:
        return 0
    return 1 if latitude > 0.0 else -1


## A place on the earth: its latitude and longitude in degrees, east and north
## positive, the zone and the country it was found by, empty when none, the
## clock's offset from UTC there in minutes, and which step found it.
class Place:
    var latitude: float
    var longitude: float
    var zone: String
    var country: String
    var offset: int
    var how: String

    func _init(at_latitude: float, at_longitude: float, in_zone: String, in_country: String, clock: int, by: String) -> void:
        latitude = at_latitude
        longitude = at_longitude
        zone = in_zone
        country = in_country
        offset = clock
        how = by


## One entry of the Location picker: a country by its two capitals, the zone
## it stands at or empty for a country with one clock, and the places of the
## zones that keep that clock, which name the entry.
class Choice:
    var country: String
    var zone: String
    var places: Array[String] = []

    func _init(of_country: String, at_zone: String) -> void:
        country = of_country
        zone = at_zone


## The number in a zone row's column, which the JSON reader gives as a Variant.
static func _at(row: Array, column: int) -> float:
    var number: float = row[column]
    return number


## The country codes of a zone, its first the country it belongs to.
static func _codes(zones: Dictionary, name: String) -> String:
    var row: Array = zones[name]
    var codes: String = row[2]
    return codes
