## A stroke's answer says the largest alpha it laid.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Dabbing nine presets at opacity 1.0 and most laid two
## thirds of that or less, Sparse Specks nothing, while every answer read
## healthy. `SaScenarioAlphaLaid` reads the step a stroke wrote into the
## history against the layer now and gives the stroke's line its clause. Here
## the step is a hard path fill, which records the whole chunks where a brush's
## commit records the part it touched, so the suite needs a document and no
## window. The door
## stroke itself is read in a running Sara by
## `scripts/test_a_brush_preset_at_a_small_radius_lays_the_opacity_asked_or_its_answer_says_what_it_laid.py`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AlphaLaid = preload("res://harness/scenario/sa_scenario_alpha_laid.gd")
const ScenarioPath = preload("res://harness/scenario/sa_scenario_path.gd")
const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _doc: SaDocument = null
var _kept_foreground: Color


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _doc = _surface.get_document()
    _kept_foreground = SaColors.foreground


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


## Fills the square *width* pixels wide at *at* hard in *colour*.
func _fill(at: Vector2i, width: int, colour: Color) -> void:
    SaColors.foreground = colour
    var square := [[at.x, at.y], [at.x + width, at.y], [at.x + width, at.y + width], [at.x, at.y + width]]
    ScenarioPath.fill(_doc, {"polygon": square, "antialias": false})


func test_the_clause_names_the_largest_alpha_and_the_texels() -> void:
    assert_eq(AlphaLaid.clause(0.0, 0, 0), ", laid nothing on the layer", "Nothing changed")
    assert_eq(AlphaLaid.clause(0.724, 11, 0), ", largest alpha laid 0.72 over 11 texels", "Paint laid")
    assert_eq(AlphaLaid.clause(1.0, 1, 0), ", largest alpha laid 1.00 over 1 texel", "One texel in the singular")
    assert_true(AlphaLaid.clause(0.0, 0, 4).contains("lowered the alpha of 4 texels"), "An eraser's stroke lowers")
    assert_eq(AlphaLaid.clause(0.0, 0, 0, 412), ", recoloured 412 texels", "Opaque paint recoloured")
    assert_eq(AlphaLaid.clause(0.0, 0, 0, 1), ", recoloured 1 texel", "One recoloured texel in the singular")


func test_a_fill_of_nine_texels_reads_as_nine_at_its_alpha() -> void:
    var held := AlphaLaid.before(_doc)
    _fill(Vector2i(100, 100), 3, Color(0.5, 0.5, 0.5, 1.0))
    assert_eq(AlphaLaid.after(_doc, held), ", largest alpha laid 1.00 over 9 texels", "The fill's nine texels")


func test_a_fill_across_four_chunks_is_counted_in_each() -> void:
    var held := AlphaLaid.before(_doc)
    _fill(Vector2i(254, 254), 4, Color(0.2, 0.2, 0.2, 1.0))
    assert_eq(AlphaLaid.after(_doc, held), ", largest alpha laid 1.00 over 16 texels", "The sixteen texels over the corner")


func test_paint_laid_again_over_itself_is_not_counted() -> void:
    _fill(Vector2i(100, 100), 3, Color(0.5, 0.5, 0.5, 1.0))
    var held := AlphaLaid.before(_doc)
    _fill(Vector2i(100, 100), 4, Color(0.5, 0.5, 0.5, 1.0))
    assert_eq(AlphaLaid.after(_doc, held), ", largest alpha laid 1.00 over 7 texels", "Only the seven new texels")


func test_a_step_that_never_came_is_nothing_laid() -> void:
    var held := AlphaLaid.before(_doc)
    assert_false(AlphaLaid.pending(_doc, held), "Nothing is being laid")
    assert_eq(AlphaLaid.after(_doc, held), ", laid nothing on the layer", "and nothing was")


## A stroke of one colour over an opaque patch of another
## changes no alpha and reads as recoloured, never as laid nothing.
func test_a_fill_of_another_colour_over_opaque_paint_reads_as_recoloured() -> void:
    _fill(Vector2i(100, 100), 4, Color(0.8, 0.1, 0.1, 1.0))
    var held := AlphaLaid.before(_doc)
    _fill(Vector2i(100, 100), 4, Color(0.1, 0.1, 0.8, 1.0))
    assert_eq(AlphaLaid.after(_doc, held), ", recoloured 16 texels", "The sixteen opaque texels took the blue")
