## A stroke's line names the opening, each turn and the closing of its
## pressure, so the note's pen line of 0.2, 0.6, 1.0 and 0.3 no longer reads
## "pressure 0.20 to 0.30" with its peak gone.
##
## The running app proves the line in
## `scenarios/a-strokes-line-names-every-turn-of-its-pressure.json`. The
## clause itself is a pure reading of the verdict, graded here.
extends "res://tests/test_framework.gd"

const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")


func _clause(pressures: Array) -> String:
    return ScenarioStroke.pressure_clause({"pressures": pressures})


func test_the_notes_stroke_names_its_peak() -> void:
    assert_eq(_clause([0.2, 0.6, 1.0, 0.3]), "pressure 0.20 to 1.00 to 0.30", "The peak of the note's stroke is named")


func test_a_one_way_stroke_reads_as_it_did() -> void:
    assert_eq(_clause([0.2, 0.4, 0.6, 1.0]), "pressure 0.20 to 1.00", "A ramp up names its two ends")
    assert_eq(_clause([1.0, 0.7, 0.5, 0.1]), "pressure 1.00 to 0.10", "and a ramp down its two ends")
    assert_eq(_clause([0.8, 0.8, 0.8]), "pressure 0.80", "and a constant stroke one value")
    assert_eq(
        ScenarioStroke.pressure_clause({"pressure": 0.2, "pressure_last": 0.3}),
        "pressure 0.20 to 0.30",
        "and a report written before the turns were named reads as the two ends it named"
    )
    assert_eq(ScenarioStroke.pressure_clause({"pressure": 0.5}), "pressure 0.50", "or as its one value")


func test_a_plateau_is_not_a_turn() -> void:
    assert_eq(_clause([0.2, 0.5, 0.5, 0.8]), "pressure 0.20 to 0.80", "A plateau on the way up is not a turn")
    assert_eq(_clause([0.2, 1.0, 1.0, 0.3]), "pressure 0.20 to 1.00 to 0.30", "and a flat peak is one turn")
    assert_eq(_clause([0.5, 0.501, 0.9]), "pressure 0.50 to 0.90", "and values equal at two decimals are one run")


func test_a_stroke_that_turns_twice_names_both() -> void:
    assert_eq(
        _clause([0.1, 0.9, 0.4, 0.7]),
        "pressure 0.10 to 0.90 to 0.40 to 0.70",
        "A rise, a fall and a rise name the peak and the trough"
    )
    assert_eq(_clause([0.5, 1.0, 0.5]), "pressure 0.50 to 1.00 to 0.50", "and ends that agree still show the turn between")
