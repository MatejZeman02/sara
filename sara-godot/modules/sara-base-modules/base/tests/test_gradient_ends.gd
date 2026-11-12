## The gradient tool's rule for its two ends, beside `SaGradientEnds`: the
## endpoint alphas survive a restart, and the general ramp paths never read or
## write them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The alpha of endpoint colours is remembered in between sessions.
##
## No GPU. A ramp and the module's two preferences, reached the way the module
## reaches them: through a context bound to its id.
extends "res://tests/test_framework.gd"

const MODULE_ID := &"sara-base-modules"

var _start_alpha: Variant = null
var _end_alpha: Variant = null
## Held for the suite's length, because the end rule holds its context weakly.
var _context: SaContext = null
var _ends: SaGradientEnds = null


## The two preferences are global and this suite moves them, so they are put
## back. Without this `test_color_ramp.gd`'s "opens as the two picked colours"
## fails whenever it runs after this file, which is a suite order dependency and
## the worst kind of red.
func before_each() -> void:
    _context = SaContext.new(Callable(), Callable(), MODULE_ID)
    _ends = SaGradientEnds.new(_context)
    _start_alpha = _context.preference(SaGradientEnds.START_ALPHA_KEY)
    _end_alpha = _context.preference(SaGradientEnds.END_ALPHA_KEY)
    # Set as well as saved. The offscreen gate shares its profile with the
    # capture harness, and `scenarios/gradient-saved.json` deliberately leaves
    # a faded far end in it, so a test asserting on a remembered value has to
    # establish the baseline rather than assume the shipped default. This suite
    # passed filtered and failed in the full run until it did.
    _context.set_preference(SaGradientEnds.START_ALPHA_KEY, 1.0)
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, 1.0)


func after_each() -> void:
    _context.set_preference(SaGradientEnds.START_ALPHA_KEY, _start_alpha)
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, _end_alpha)
    _ends = null
    _context = null


## The clause itself. Setting an endpoint's alpha writes the setting, and a ramp
## built afterwards, which is what a fresh launch does, opens with it.
func test_an_endpoint_alpha_is_written_and_read_back() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    ramp.set_stop_alpha(1, 0.0)
    _ends.remember_endpoint_alpha(ramp, 1)

    assert_almost_eq(_ends.end_alpha(), 0.0, 1e-6, "The far end's alpha is remembered")
    assert_almost_eq(_ends.start_alpha(), 1.0, 1e-6, "and the near end's is left alone")

    var fresh := _ends.fresh_ramp(Color.RED, Color.BLUE)
    assert_almost_eq(fresh.color_of(1).a, 0.0, 1e-6, "A ramp built afterwards opens faded out")
    assert_almost_eq(fresh.color_of(0).a, 1.0, 1e-6, "with its near end opaque")
    assert_eq(fresh.color_of(0).r, 1.0, "and the picked colours untouched")
    assert_almost_eq(SaColorRamp.from_pair(Color.RED, Color.BLUE).color_of(1).a, 1.0, 1e-6, "while a plain pair stays opaque")


## Two keys rather than one, because a gradient fading out at the far end is not
## the same picture as one fading in.
func test_the_two_ends_are_remembered_apart() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    ramp.set_stop_alpha(0, 0.25)
    _ends.remember_endpoint_alpha(ramp, 0)
    ramp.set_stop_alpha(1, 0.75)
    _ends.remember_endpoint_alpha(ramp, 1)

    var fresh := _ends.fresh_ramp(Color.GREEN, Color.BLACK)
    assert_almost_eq(fresh.color_of(0).a, 0.25, 1e-6, "The near end came back")
    assert_almost_eq(fresh.color_of(1).a, 0.75, 1e-6, "and so did the far one")


## A stop in the middle is not an endpoint, and remembering its alpha would mean
## adding a stop changed what the next launch opens with.
func test_a_middle_stop_s_alpha_is_not_remembered() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    var middle := ramp.add_stop(0.5, Color.GREEN)
    ramp.set_stop_alpha(middle, 0.1)
    _ends.remember_endpoint_alpha(ramp, middle)

    assert_almost_eq(_ends.start_alpha(), 1.0, 1e-6, "The near end is untouched")
    assert_almost_eq(_ends.end_alpha(), 1.0, 1e-6, "and so is the far one")


## The gradient tool re-seeds its untouched ramp from the picker on every read,
## and that re-seed must not undo the remembered alphas: it writes colours.
func test_reseeding_from_the_picker_keeps_the_remembered_alphas() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    ramp.set_stop_alpha(1, 0.0)
    _ends.remember_endpoint_alpha(ramp, 1)

    _ends.reseed(ramp, Color.GREEN, Color.WHITE)
    assert_eq(ramp.color_of(0).r, 0.0, "The near stop took the new colour")
    assert_eq(ramp.color_of(1).r, 1.0, "and so did the far one")
    assert_almost_eq(ramp.color_of(1).a, 0.0, 1e-6, "with the remembered alpha still on it")


## A ramp of more than two stops is not re-seeded at all: it has been edited, so
## the picked pair is not what it holds.
func test_a_reseed_leaves_an_edited_ramp_alone() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    ramp.add_stop(0.5, Color.GREEN)

    _ends.reseed(ramp, Color.WHITE, Color.BLACK)
    assert_eq(ramp.color_of(0), Color.RED, "The near stop kept what it had")
    assert_eq(ramp.size(), 3, "and the ramp kept its stops")


## `from_pair` and `set_stop_alpha` are the general paths and stay pure. If
## they read or wrote the profile, two suites would go red on nothing they test: `test_color_ramp` and
## `test_gradient`
## both build a ramp and assert on its alpha, and whichever of them ran after a
## suite that had faded an end got that suite's value. The app has the same
## coupling in it, one process and one profile, so this is a rule rather than a
## test artefact.
func test_the_general_ramp_paths_do_not_touch_the_profile() -> void:
    _context.set_preference(SaGradientEnds.START_ALPHA_KEY, 0.3)
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, 0.6)

    var plain := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    assert_eq(plain.color_of(0).a, 1.0, "A plain pair takes the colours' own alpha")
    assert_eq(plain.color_of(1).a, 1.0, "at both ends")

    plain.set_stop_alpha(0, 0.9)
    assert_almost_eq(_ends.start_alpha(), 0.3, 1e-6, "and setting one writes nothing")

    var seeded := _ends.fresh_ramp(Color.RED, Color.BLUE)
    assert_almost_eq(seeded.color_of(0).a, 0.3, 1e-6, "Only the gradient's own constructor reads them")
    assert_almost_eq(seeded.color_of(1).a, 0.6, 1e-6, "at both ends")


## An end rule with no context, a test's or a control built outside the module,
## opens opaque and writes nothing into the module's preferences.
func test_an_end_rule_without_a_context_remembers_nothing() -> void:
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, 0.4)
    var bare := SaGradientEnds.new()
    var ramp := bare.fresh_ramp(Color.RED, Color.BLUE)
    assert_almost_eq(ramp.color_of(1).a, 1.0, 1e-6, "A bare rule opens its far end opaque")
    ramp.set_stop_alpha(1, 0.1)
    bare.remember_endpoint_alpha(ramp, 1)
    assert_almost_eq(_ends.end_alpha(), 0.4, 1e-6, "and remembers nothing into the module's own")


## The remembered value is the module's preference and nothing else: a profile
## edited by hand into a string or out of range reads back as a usable alpha.
func test_a_stored_alpha_that_is_not_one_reads_back_clamped() -> void:
    _context.set_preference(SaGradientEnds.START_ALPHA_KEY, 3.0)
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, "faded")
    assert_almost_eq(_ends.start_alpha(), 1.0, 1e-6, "Out of range is clamped")
    assert_almost_eq(_ends.end_alpha(), 1.0, 1e-6, "and a string is opaque")
