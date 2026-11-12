## The preferences of a docker summoned under the pointer: how long the pointer
## stays away before it goes back, and how far away, as a fraction of the
## screen's width.
##
## Kept through the door a module keeps its own preferences through, under the
## skeleton's own id, rather than as two properties of `SaSettingsValues`. That
## file stands at the thousand lines `tests/test_file_length.gd` fails a run
## over, and the door is the one a built-in has to use anyway, as
## the gradient's endpoint alphas do.
##
## An object with two properties rather than two calls, because a Preferences
## row binds to an object and a property path and never to a lambda. The
## properties hold nothing: each reads and writes the profile, so the summon's
## frame loop and the page's row always agree.
class_name SaDockerBorrow
extends RefCounted

## The id the skeleton registers its own commands under, whose section of the
## profile the two keys live in.
const MODULE_ID := &"sara-skeleton"
const DWELL_KEY := &"docker_borrow_dwell_ms"
const DISTANCE_KEY := &"docker_borrow_distance"

## A second, and three percent of the screen's width.
const DEFAULT_DWELL_MS: int = 1000
const DEFAULT_DISTANCE: float = 0.03
const MAX_DWELL_MS: int = 10000
const MAX_DISTANCE: float = 0.5

## Milliseconds the pointer stays away from a summoned docker before it goes.
var dwell_ms: int:
    get:
        var stored: Variant = SaSettings.module_preference(MODULE_ID, DWELL_KEY, DEFAULT_DWELL_MS)
        return clampi(int(stored), 0, MAX_DWELL_MS) if stored is int or stored is float else DEFAULT_DWELL_MS
    set(val):
        SaSettings.set_module_preference(MODULE_ID, DWELL_KEY, clampi(val, 0, MAX_DWELL_MS))

## How far the pointer has to be from a summoned docker's rectangle before the
## wait starts, as a fraction of the screen's width.
var distance: float:
    get:
        var stored: Variant = SaSettings.module_preference(MODULE_ID, DISTANCE_KEY, DEFAULT_DISTANCE)
        return clampf(float(stored), 0.0, MAX_DISTANCE) if stored is int or stored is float else DEFAULT_DISTANCE
    set(val):
        SaSettings.set_module_preference(MODULE_ID, DISTANCE_KEY, clampf(val, 0.0, MAX_DISTANCE))
