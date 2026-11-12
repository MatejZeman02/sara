## Regression cases for the brush editor.
##
## Only some of what driving the editor showed is a case a headless suite can
## hold. A suite runs inside `run_all._ready`, where `add_child` is refused, so a
## `Window` never reaches a viewport and never reports its own state. The brush
## editor is a `Window` and the preset chooser lives in a popup, so those checks
## are scenarios run from a deleted profile instead.
##
## A dab with no size is still stamped unless the floor holds. The case below
## holds the walk's half of that. The engines' half, the stroke that lays no dab,
## is `test_a_stroke_under_a_zero_size_curve_lays_no_dab.gd` beside this file,
## since it needs the GPU this suite does without.
extends "res://tests/test_framework.gd"


## A size curve that reads zero at full pressure asks the walk for no spacing.
##
## The walk alone cannot say whether a dab is stamped, since it counts every
## offer it makes. What it can say is that a dab of no size asks for a step of
## nothing, which is why the engines' floor has to come before the dispatch,
## and the suite beside this file holds that floor. The numbers on the
## running app are `scenarios/curve-options.json`'s, quoted there.
func test_a_dab_of_no_size_asks_for_no_spacing() -> void:
    var walk := SaStrokeDistance.effective_spacing(0.0, 0.0, 1.0)
    assert_true(walk.distance.x <= 0.0, "a dab of no size asks for no spacing at all")
