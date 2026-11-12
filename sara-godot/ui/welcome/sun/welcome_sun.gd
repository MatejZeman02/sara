## The sun where the painter lives, now, and the season there, for the Welcome
## picture's lights.
##
## **The place** is `SaLocation`'s: the country set under Preferences > Files >
## Location, or its guess from the machine's clock. The guess was this class's
## until an export came to write the painter's country and
## the place went down to `core/location` where an export can read it. The
## header there says what each platform gives for the zone's name.
##
## **The sun** is NOAA's short formula of the sun's place, with no library:
## its height above the horizon in degrees, ignoring the air's bending of light,
## whether it is rising or setting, and the highest and lowest it reaches that
## day (`sky_at`). `sunset_at` gives the minute the sun's top edge goes down,
## with the air, the way a published table counts it.
##
## **The season** is the month turned round in the south, and none within the
## tropics, 23.44 degrees of the equator (`season_at`).
##
## A debug build takes the place from `SARA_WELCOME_ZONE` when it names a zone
## of the table, and then from the country of `SARA_WELCOME_LOCALE` with no
## offset asked, and the local hour and the month from `SARA_WELCOME_HOUR` and
## `SARA_WELCOME_MONTH`, so a scenario's shot is the same at any date and place.
@tool
class_name WelcomeSun
extends RefCounted

## The seasons, northern winter first, so that three months of the calendar from
## December are one step along it.
const SEASONS: Array[String] = ["winter", "spring", "summer", "autumn"]

## How far from the equator the sun stands overhead on one day of the year.
const TROPIC: float = SaLocation.TROPIC

## The height of the sun's middle at a published sunset, its top edge on the
## horizon with the air's bending, in degrees.
const SUNSET_HEIGHT: float = -0.833

const ZONE_VARIABLE := "SARA_WELCOME_ZONE"
const HOUR_VARIABLE := "SARA_WELCOME_HOUR"
const MONTH_VARIABLE := "SARA_WELCOME_MONTH"
const LOCALE_VARIABLE := "SARA_WELCOME_LOCALE"


## The moment the window opens: where the painter is, the time, the season and
## the sun. A debug build takes the variables above in place of the machine's.
static func now() -> Moment:
    var today := Time.get_datetime_dict_from_system()
    var month: int = today["month"]
    var unix := Time.get_unix_time_from_system()
    var place := SaLocation.here(month)
    if OS.is_debug_build():
        var wanted := OS.get_environment(MONTH_VARIABLE)
        if wanted.is_valid_int() and wanted.to_int() >= 1 and wanted.to_int() <= 12:
            month = wanted.to_int()
        if not SaLocation.zone_row(OS.get_environment(ZONE_VARIABLE)).is_empty():
            place = SaLocation.place_of_zone(OS.get_environment(ZONE_VARIABLE), month)
        elif OS.has_environment(LOCALE_VARIABLE):
            place = SaLocation.place_of_country(SaLocation.country_of(OS.get_environment(LOCALE_VARIABLE)), month)
        var hour := OS.get_environment(HOUR_VARIABLE)
        if hour.is_valid_float() or month != today["month"] or OS.has_environment(ZONE_VARIABLE):
            var local := unix + place.offset * 60.0
            var at_hour := fposmod(local, 86400.0) / 3600.0
            if hour.is_valid_float():
                at_hour = hour.to_float()
            unix = local_moment(today["year"], month, mini(today["day"], 28), at_hour, place.offset)
    return Moment.new(place, unix)


## The unix time of *hour*, with minutes as a fraction, on the given day where
## the clock is *offset* minutes ahead of UTC.
static func local_moment(year: int, month: int, day: int, hour: float, offset: int) -> float:
    var midnight := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day})
    return midnight + hour * 3600.0 - offset * 60.0


## The sky at *place* at the unix time *unix*.
static func sky_at(place: SaLocation.Place, unix: float) -> SunNow:
    var sun := _sun_at(unix)
    var minutes := fposmod(unix, 86400.0) / 60.0
    var solar := fposmod(minutes + sun.y + 4.0 * place.longitude, 1440.0)
    var angle := solar / 4.0 - 180.0
    var latitude := deg_to_rad(place.latitude)
    var declination := sun.x
    var lean := sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(deg_to_rad(angle))
    var height := 90.0 - rad_to_deg(acos(clampf(lean, -1.0, 1.0)))
    var turned := absf(place.latitude - rad_to_deg(declination))
    var highest := 90.0 - turned
    var lowest := absf(place.latitude + rad_to_deg(declination)) - 90.0
    return SunNow.new(height, angle < 0.0, lowest, highest)


## The unix time the sun goes down at *place* on the local day of *unix*, by
## the place's own offset, NAN on a day it never sets or never rises there.
static func sunset_at(place: SaLocation.Place, unix: float) -> float:
    var day := floorf((unix + place.offset * 60.0) / 86400.0) * 86400.0
    var noon := day + 43200.0 - place.longitude * 240.0
    var at := noon
    for i in 2:
        var sun := _sun_at(at)
        var latitude := deg_to_rad(place.latitude)
        var reach := cos(deg_to_rad(90.0 - SUNSET_HEIGHT)) / (cos(latitude) * cos(sun.x)) - tan(latitude) * tan(sun.x)
        if absf(reach) > 1.0:
            return NAN
        var solar_noon := noon - sun.y * 60.0
        at = solar_noon + rad_to_deg(acos(reach)) * 240.0
    return at


## The season of *month*, 1 to 12, at *latitude*: none within the tropics or
## for a month that is not one, and in the south two seasons along.
static func season_at(month: int, latitude: float) -> String:
    if absf(latitude) < TROPIC or month < 1 or month > 12:
        return ""
    var step := floori((month % 12) / 3.0)
    if latitude < 0.0:
        step += 2
    return SEASONS[step % SEASONS.size()]


## The sun's declination in radians and the equation of time in minutes at the
## unix time *unix*, by NOAA's formula.
static func _sun_at(unix: float) -> Vector2:
    var century := (unix / 86400.0 + 2440587.5 - 2451545.0) / 36525.0
    var mean_long := deg_to_rad(fposmod(280.46646 + century * (36000.76983 + century * 0.0003032), 360.0))
    var anomaly := deg_to_rad(357.52911 + century * (35999.05029 - 0.0001537 * century))
    var eccentric := 0.016708634 - century * (0.000042037 + 0.0000001267 * century)
    var centre := (
        sin(anomaly) * (1.914602 - century * (0.004817 + 0.000014 * century))
        + sin(2.0 * anomaly) * (0.019993 - 0.000101 * century)
        + sin(3.0 * anomaly) * 0.000289
    )
    var node := deg_to_rad(125.04 - 1934.136 * century)
    var apparent := deg_to_rad(rad_to_deg(mean_long) + centre - 0.00569 - 0.00478 * sin(node))
    var seconds := 21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))
    var obliquity := deg_to_rad(23.0 + (26.0 + seconds / 60.0) / 60.0 + 0.00256 * cos(node))
    var declination := asin(sin(obliquity) * sin(apparent))
    var y := pow(tan(obliquity / 2.0), 2.0)
    var equation := (
        y * sin(2.0 * mean_long)
        - 2.0 * eccentric * sin(anomaly)
        + 4.0 * eccentric * y * sin(anomaly) * cos(2.0 * mean_long)
        - 0.5 * y * y * sin(4.0 * mean_long)
        - 1.25 * eccentric * eccentric * sin(2.0 * anomaly)
    )
    return Vector2(declination, 4.0 * rad_to_deg(equation))


## The sun at one place and time: its height in degrees, whether it is rising,
## and the lowest and highest it reaches that day.
class SunNow:
    var height: float
    var rising: bool
    var lowest: float
    var highest: float

    func _init(sun_height: float, sun_rising: bool, day_lowest: float, day_highest: float) -> void:
        height = sun_height
        rising = sun_rising
        lowest = day_lowest
        highest = day_highest


## Where and when the Welcome window opened: the place, the unix time, the
## local hour with minutes as a fraction, the month, the season and the sky.
class Moment:
    var place: SaLocation.Place
    var unix: float
    var hour: float
    var month: int
    var season: String
    var sky: WelcomeSun.SunNow

    func _init(at_place: SaLocation.Place, at_unix: float) -> void:
        place = at_place
        unix = at_unix
        var local := Time.get_datetime_dict_from_unix_time(int(unix + place.offset * 60.0))
        hour = fposmod(unix + place.offset * 60.0, 86400.0) / 3600.0
        month = local["month"]
        season = WelcomeSun.season_at(month, place.latitude)
        sky = WelcomeSun.sky_at(place, unix)
