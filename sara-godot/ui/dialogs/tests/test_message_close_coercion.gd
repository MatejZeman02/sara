## A scenario's `message` step does not crash on a boolean.
##
## `{"message": {"close": true}}` in a scenario file reached
## `String(spec["close"])`, and `String` has no constructor for a boolean, so the
## run printed `Invalid call. Nonexistent 'String' constructor.` and the problem
## dialog the step was asked to close stayed up through every shot after it. The
## match under that line already hid the window for a route it did not know, so
## an unrecognized route was always meant to be tolerated. A non-string simply
## never reached the match.
##
## No window and no tree here: the route and the sentence are both pure, which is
## what makes them assertable without pumping a message queue. The scenario
## `message-step-crashes-on-a-boolean.json` is the same three values on the
## running app.
extends "res://tests/test_framework.gd"


## The three words the step documents still answer for themselves. Without this
## the fix could be a function that hides for everything.
func test_the_three_routes_are_still_themselves() -> void:
    assert_eq(SaMessage.close_route("escape"), "escape", "Escape is a route")
    assert_eq(SaMessage.close_route("button"), "button", "and so is the close button")
    assert_eq(SaMessage.close_route("hide"), "hide", "and hiding is the third")


## The filing itself: a boolean is a word now, not a crash. `str` answers for
## every Variant where `String` answers for three.
func test_a_boolean_is_a_route_word_rather_than_a_crash() -> void:
    assert_eq(SaMessage.close_route(true), "hide", "A boolean falls back to hiding")
    assert_eq(SaMessage.close_route(false), "hide", "and so does the other one")


## An integer and a word nobody knows take the same fallback, because the match
## always had a default arm and the coercion is what kept them from reaching it.
func test_a_number_and_an_unknown_word_hide_as_well() -> void:
    assert_eq(SaMessage.close_route(3), "hide", "A number falls back to hiding")
    assert_eq(SaMessage.close_route("escpae"), "hide", "and so does a typo")


## The other half of the filing, that the step answers its own line. A reply that
## only said "closed by hide" would leave a scenario author reading a shot to
## find out their word was ignored.
func test_a_word_that_was_not_a_route_is_quoted_back() -> void:
    var said := SaMessage.close_reply(true, "hide", "no answer")
    assert_true(said.contains("closed by hide"), "The route taken is named: %s" % said)
    assert_true(said.contains("'true'"), "and the word the scenario wrote is quoted")
    assert_true(said.contains("no answer"), "and what the window answered is kept")


## And a word that was a route earns no quote, so the line a working scenario
## reads back is the one it has always read.
func test_a_real_route_reads_the_way_it_did_before() -> void:
    var said := SaMessage.close_reply("escape", "escape", "0")
    assert_eq(said, "SaCapture: message closed by escape, answered 0", "unchanged: %s" % said)
    assert_false(said.contains("is not a route"), "and nothing is quoted at it")
