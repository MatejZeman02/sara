## A country set under Preferences > Files > Location is where
## the Welcome picture's sun and seasons stand, in place of the guess from the
## time zone, and Automatic goes back to the guess.
##
## The machine is made a Prague one through `TZ`, the first name
## `SaLocation.system_zone` reads, so the guess is the same on any machine, and
## June through `SARA_WELCOME_MONTH`, which a debug build reads.
extends "res://tests/test_framework.gd"

const FOLDER := "res://ui/welcome/sun/tests/pictures/"
const VARIABLES: Array[String] = [
    "TZ", WelcomeSun.MONTH_VARIABLE, WelcomeSun.ZONE_VARIABLE, WelcomeSun.LOCALE_VARIABLE, WelcomeSun.HOUR_VARIABLE
]

var _environment: Dictionary = {}
var _country: String = ""
var _zone: String = ""


func before_each() -> void:
    for name in VARIABLES:
        _environment[name] = null
        if OS.has_environment(name):
            _environment[name] = OS.get_environment(name)
        OS.unset_environment(name)
    _country = SaSettings.location_country
    _zone = SaSettings.location_zone
    OS.set_environment("TZ", "Europe/Prague")
    OS.set_environment(WelcomeSun.MONTH_VARIABLE, "6")


func after_each() -> void:
    for name in VARIABLES:
        if _environment[name] == null:
            OS.unset_environment(name)
        else:
            OS.set_environment(name, _environment[name])
    SaSettings.location_country = _country
    SaSettings.location_zone = _zone


func test_new_zealand_set_on_a_prague_machine_in_june_is_winter_and_automatic_is_summer() -> void:
    SaSettings.location_country = ""
    var guessed := WelcomeSun.now()
    assert_eq(guessed.place.zone, "Europe/Prague", "the machine is a Prague one")
    assert_eq(guessed.season, "summer", "and June there is summer")

    SaSettings.location_country = "NZ"
    var moment := WelcomeSun.now()
    assert_eq(moment.place.how, SaLocation.BY_CHOICE, "the set country wins over the guess")
    assert_eq(moment.place.zone, "Pacific/Auckland", "at New Zealand's zone")
    assert_eq(moment.season, "winter", "and June there is winter")
    var band := WelcomePicture.new("0.1.0", FOLDER)
    assert_eq(band.season, "winter", "which is the season the Welcome picture opens in")
    band.free()

    SaSettings.location_country = ""
    assert_eq(WelcomeSun.now().season, "summer", "Automatic goes back to the guess")
    var again := WelcomePicture.new("0.1.0", FOLDER)
    assert_eq(again.season, "summer", "and the picture with it")
    again.free()


func test_a_zone_picked_of_a_country_with_several_is_the_one_the_sun_stands_at() -> void:
    SaSettings.location_country = "AU"
    SaSettings.location_zone = "Australia/Perth"
    assert_eq(WelcomeSun.now().place.zone, "Australia/Perth", "the zone picked")
    assert_eq(WelcomeSun.now().place.offset, 480, "on Perth's clock")
    SaSettings.location_zone = "Europe/Prague"
    assert_eq(WelcomeSun.now().place.country, "AU", "a zone not of the country is read as none")
    assert_eq(SaLocation.zones_for("AU").has(WelcomeSun.now().place.zone), true, "and the country's first stands in")


func test_a_country_no_zone_serves_keeps_the_guess_for_the_sun() -> void:
    SaSettings.location_country = "BV"
    assert_false(SaLocation.country_name("BV").is_empty(), "Bouvet Island is a country of the list")
    assert_eq(WelcomeSun.now().place.zone, "Europe/Prague", "and with no clock of its own the sun stays at the guess")
