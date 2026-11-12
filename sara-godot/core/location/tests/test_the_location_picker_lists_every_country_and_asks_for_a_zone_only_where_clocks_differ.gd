## The Location picker lists every country of tzdata's
## `iso3166.tab` under its long name, and a country whose zones keep different
## clocks, or stand on both sides of a tropic, once for each, named by the
## places of the zones.
extends "res://tests/test_framework.gd"


func _rows_of(country: String) -> Array[SaLocation.Choice]:
    var out: Array[SaLocation.Choice] = []
    for choice in SaLocation.choices():
        if choice.country == country:
            out.append(choice)
    return out


func test_every_country_is_listed_under_tzdatas_long_name() -> void:
    assert_eq(SaLocation.countries().size(), 249, "iso3166.tab's 249 countries")
    assert_eq(SaLocation.country_name("CZ"), "Czech Republic", "the long name, as the list names it")
    var listed: Dictionary = {}
    for choice in SaLocation.choices():
        listed[choice.country] = true
    assert_eq(listed.size(), 249, "every country is a row of the picker")
    var first := SaLocation.choices()[0]
    assert_eq(SaLocation.country_name(first.country), "Afghanistan", "sorted by name")


func test_a_country_with_one_clock_is_one_row_and_asks_no_zone() -> void:
    for country: String in ["CZ", "SE", "DE", "JP"]:
        var rows := _rows_of(country)
        assert_eq(rows.size(), 1, "%s is one row" % country)
        assert_eq(rows[0].zone, "", "and asks no zone")
    assert_eq(SaLocation.chosen_place("SE", "", 6).zone, "Europe/Stockholm", "Sweden stands at its own zone, not Berlin's")
    var zealand := _rows_of("NZ")
    assert_eq(zealand.size(), 2, "New Zealand is asked, since the Chatham Islands keep a clock of their own")
    assert_eq(zealand[0].places, ["Auckland"] as Array[String], "Auckland first")


func test_a_country_over_several_clocks_is_asked_which() -> void:
    var australia := _rows_of("AU")
    assert_true(australia.size() >= 5, "Australia is asked about, %d rows" % australia.size())
    var places: Array[String] = []
    for row in australia:
        places.append_array(row.places)
    for city: String in ["Perth", "Sydney", "Darwin", "Brisbane", "Adelaide"]:
        assert_true(places.has(city), "%s is one of its places" % city)
    var brazil := _rows_of("BR")
    var zones: Array[String] = []
    for row in brazil:
        zones.append(row.zone)
        zones.append_array(row.places)
    assert_true(zones.has("Sao Paulo") and zones.has("Belem"), "Brazil's -3 parts at the tropic: %s" % ", ".join(zones))
    var united := _rows_of("US")
    assert_true(united.size() >= 6 and united.size() < 20, "the United States by its clocks, %d rows" % united.size())


func test_an_antarctic_station_never_names_a_countrys_clock() -> void:
    for row in _rows_of("AU"):
        assert_false(row.zone.begins_with("Antarctica/"), "an Australian row stands at %s" % row.zone)
        if row.places.has("Sydney"):
            assert_eq(row.places.back(), "Macquarie", "Macquarie keeps Sydney's clock, named last")


func test_a_chosen_country_is_the_place_and_automatic_is_none() -> void:
    var perth := SaLocation.chosen_place("AU", "Australia/Perth", 6)
    assert_eq(perth.how, SaLocation.BY_CHOICE, "a country set is chosen")
    assert_eq(perth.zone, "Australia/Perth", "at the zone picked")
    assert_eq(SaLocation.chosen_place("", "", 6).how, SaLocation.BY_NOTHING, "Automatic chooses nothing")
    assert_eq(SaLocation.place_name("America/Indiana/Tell_City"), "Tell City", "a zone is named by its last part")
