## The generated dialog: a module that registers a file's path and gets a filter
## with a slider on it.
##
## The claim of the door is an absence, so most of this suite is about what is
## not there: the fixture module directory holds a `module.gd` and a `.gmacs`
## and no filter class at all, and the dialog it opens is built from the one
## `uniform` line. What a suite can hold is the page half of the dialog, for the
## reason `test_filter_dialog.gd` gives: a `Window` added to the tree maps a
## real OS window and hangs the runner, so the window half is the scenario.
##
## The fixture's threshold is the spec's own listing, and it is read back off
## the page here rather than trusted, the way `test_pixel_function.gd` reads it:
## the file in the tree has to stay the fourteen words the spec is measured
## against.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The readback the export path does, which is the door hard rule 1 permits a
## test. Nothing the filter itself does leaves VRAM.
const SaExportScript = preload("res://core/export/sa_export.gd")

## The dialect's reading of a `uniform` line, for the tag's problem.
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

const FIXTURE_DIR := "res://tests/fixtures/modules/pixel-filter-fixture"
const THRESHOLD_PATH := FIXTURE_DIR + "/threshold.gmacs"
const FIXTURE_MODULE := FIXTURE_DIR + "/module.gd"

## The page the threshold function is printed on, and the heading whose first
## fence carries it.
const PAGE := "docs/specs/scripting.md"
const PIXEL_HEADING := "## The pixel function, the shortest door"

## A pixel function with one of every kind of `uniform` the door takes, written
## to `user://` because it proves the widget rules rather than the spec's
## listing and nothing that is not the spec's listing belongs in the tree.
static var scratch_every_kind_path: String = SaDataRoot.path("w2_every_kind.gmacs")
const EVERY_KIND_SOURCE := """uniform float level: hint_range(0, 1) = 0.5
uniform int steps: hint_range(1, 8) = 3
uniform float gain = 4.0
uniform vec3 tint: source_color = vec3(1.0, 0.5, 0.25)
uniform vec4 wash: source_color = vec4(0.1, 0.2, 0.3, 0.4)
uniform vec2 nudge = vec2(2.0, 3.0)

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at + ivec2(nudge))
    vec3 lit = vec3(step(level, luminance(c.rgb) * gain * float(steps)))
    return vec4(lit * tint * wash.rgb, c.a)
"""

## A pixel function with a range declared each way a line can: the hint with a
## step, a whole number's hint with one, and the `# range` comment that came
## before the hint, which a saved kernel still carries.
static var scratch_ranges_path: String = SaDataRoot.path("d66_every_range.gmacs")
const EVERY_RANGE_SOURCE := """uniform float fine: hint_range(0, 2, 0.25) = 0.5
uniform int stride: hint_range(0, 12, 3) = 6
uniform float legacy = 0.25   # range 0 4

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at * stride)
    return vec4(c.rgb * fine * legacy, c.a)
"""

## A pixel function with a matrix of each size the dialect names: the 3 by 3 with its
## numbers declared one to nine, so the order a grid shows them in is plain,
## and the 5 by 5 and the 7 by 7 with none, which open on a one in the middle.
static var scratch_matrices_path: String = SaDataRoot.path("d70_matrices.gmacs")
const MATRICES_SOURCE := """uniform float small[9] = {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0}
uniform float middle[25]
uniform float large[49]

def pixel(ivec2 at) -> vec4:
    return src(at) * (small[4] + middle[12] + large[24])
"""

## A source that hints a line, so it is read Godot's way: the tagged vector is a
## swatch and the untagged one keeps its declared value with no widget.
static var scratch_tagged_path: String = SaDataRoot.path("d69_tagged.gmacs")
const TAGGED_SOURCE := """uniform float amount: hint_range(0, 1) = 1.0
uniform vec3 tint: source_color = vec3(1.0, 1.0, 1.0)
uniform vec3 offset = vec3(0.0, 0.0, 0.0)

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(c.rgb * tint * amount + offset, c.a)
"""

## The same kind of source written before the hints, with none on any line, so
## every vector keeps the swatch a saved kernel had.
static var scratch_untagged_path: String = SaDataRoot.path("d69_untagged.gmacs")
const UNTAGGED_SOURCE := """uniform float amount = 1.0   # range 0 1
uniform vec3 tint = vec3(1.0, 0.5, 0.25)
uniform vec4 wash = vec4(1.0, 1.0, 1.0, 1.0)

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(c.rgb * tint * wash.rgb * amount, c.a)
"""

## A pixel function switched by a drop-down and a checkbox, the two kinds. The
## second entry of `mode` paints black and the third white, and a ticked `lift`
## paints a quarter grey over everything.
static var scratch_switched_path: String = SaDataRoot.path("d68_switched_dialog.gmacs")
const SWITCHED_SOURCE := """uniform int mode: hint_enum("Keep", "Black", "White") = 0
uniform bool lift = false
uniform int count = 2

def pixel(ivec2 at) -> vec4:
    if lift:
        return vec4(0.25, 0.25, 0.25, 1.0)
    if mode == 1:
        return vec4(0.0, 0.0, 0.0, 1.0)
    if mode == 2:
        return vec4(1.0, 1.0, 1.0, 1.0)
    return src(at)
"""

## A pixel function whose body returns the wrong type, for the dimming clause.
static var scratch_broken_path: String = SaDataRoot.path("w2_broken.gmacs")
const BROKEN_SOURCE := """uniform float level: hint_range(0, 1) = 0.5

def pixel(ivec2 at) -> vec4:
    return vec3(level)
"""

var _dialog: SaDialog = null
var _host: VBoxContainer = null


func _tear_down() -> void:
    if _host != null:
        _host.free()
    _host = null
    _dialog = null


# --- The file in the tree is the spec's own listing -------------------------


## The fixture is the page, word for word. A copy that drifted would leave the
## unit proving a threshold the spec never printed.
func test_the_fixtures_pixel_function_is_the_specs_listing() -> void:
    if not _page_is_here():
        skip("the spec page is not in this copy of the source")
        return
    var printed := _first_fence(_page_text(), PIXEL_HEADING)
    assert_true(_file_text(THRESHOLD_PATH).contains(printed.strip_edges()), "the fixture carries the spec's listing")


## The absence the door is about: a module, a pixel function, and no class.
func test_the_fixture_module_has_no_filter_class_beside_it() -> void:
    var here := DirAccess.open(FIXTURE_DIR)
    assert_not_null(here, "the fixture directory opens")
    var scripts: Array[String] = []
    for name in here.get_files():
        if name.ends_with(".gd"):
            scripts.append(name)
    assert_eq(scripts, ["module.gd"] as Array[String], "the only script in the directory is the module itself")
    assert_true(_file_text(FIXTURE_MODULE).contains("SaPixelFilter.new("), "and it registers the file's path")


# --- The dialog the uniforms generate ---------------------------------------


## The unit's own sentence: one slider named `level`, from 0 to 1, at 0.5.
func test_one_uniform_becomes_one_slider_over_its_range() -> void:
    var filter := SaPixelFilter.new(THRESHOLD_PATH)
    assert_eq(filter.title(), "Threshold", "the title is the file's name made readable")
    assert_eq(String(filter.id()), "threshold", "and the registry key follows from it")
    assert_eq(filter.problem(), "", "the spec's own function compiles")

    _build(filter)
    var level := _dialog.row(&"level") as SaSlider
    assert_not_null(level, "the uniform's name is the widget's key")
    assert_eq(_dialog.widget_name(&"level"), "slider", "a ranged uniform is a slider")
    assert_almost_eq(level.min_value, 0.0, 0.001, "the hint's floor")
    assert_almost_eq(level.max_value, 1.0, 0.001, "and its ceiling")
    assert_almost_eq(float(level.value), 0.5, 0.001, "opening at the value the line declared")
    assert_almost_eq(level.soft_max, 0.0, 0.001, "with no soft ceiling below the hard one, the two being equal")
    assert_eq(filter.values(), {"level": 0.5}, "and the kernel is handed what the widget holds")
    _tear_down()


## Every type the parser accepts, and the one it accepts and this door has no
## widget for.
func test_the_widget_follows_the_uniforms_type() -> void:
    var filter := _written(scratch_every_kind_path, EVERY_KIND_SOURCE)
    _build(filter)

    assert_eq(_dialog.widget_name(&"level"), "slider", "a float is a slider")
    assert_eq(_dialog.widget_name(&"steps"), "slider", "an int is a slider too")
    assert_eq(_dialog.widget_name(&"tint"), "color", "a vec3 is the colour swatch")
    assert_eq(_dialog.widget_name(&"wash"), "color", "and so is a vec4")
    assert_null(_dialog.row(&"nudge"), "a vec2 earns no widget, and the record says why")

    var steps := _dialog.row(&"steps") as SaSlider
    assert_almost_eq(steps.step_value, 1.0, 0.001, "a count moves in whole numbers")
    assert_eq(steps.decimal_places, 0, "and is written as one")

    assert_eq(_dialog.row(&"tint").value as Color, Color(1.0, 0.5, 0.25, 1.0), "the swatch opens on the declared vector")
    assert_eq(_dialog.row(&"wash").value as Color, Color(0.1, 0.2, 0.3, 0.4), "alpha and all, where the line declared one")

    var handed := filter.values()
    assert_eq(handed.get("tint"), Vector3(1.0, 0.5, 0.25), "a vec3 is narrowed off the Color, which packs as four floats")
    assert_eq(handed.get("wash"), Color(0.1, 0.2, 0.3, 0.4), "a vec4 is handed the Color whole")
    assert_eq(handed.get("steps"), 3, "an int is handed an int")
    assert_false(handed.has("nudge"), "and the widgetless uniform keeps the value its line declared")
    _tear_down()


## The clamp that would have eaten a value. A uniform with no range parses as
## 0 to 1, and `SaSlider.make` clamps its default into the hard range.
func test_a_default_outside_the_parsed_bounds_survives() -> void:
    var filter := _written(scratch_every_kind_path, EVERY_KIND_SOURCE)
    _build(filter)
    var gain := _dialog.row(&"gain") as SaSlider
    assert_almost_eq(float(gain.value), 4.0, 0.001, "the declared four is what the slider opens at")
    assert_almost_eq(gain.max_value, 4.0, 0.001, "because the hard ceiling was stretched to reach it")
    assert_almost_eq(gain.soft_max, 1.0, 0.001, "and the drag still stops where the parser's bounds do")
    _tear_down()


## Both spellings of a range make the same slider, and a step the hint gave
## reaches it. A float steps by the hint's step and is written with as many
## decimals as the step has, a whole number steps by its own, and the comment,
## which has no room for a step, keeps the slider's default one.
func test_a_hint_and_the_old_comment_both_make_a_slider_and_the_step_reaches_it() -> void:
    var filter := _written(scratch_ranges_path, EVERY_RANGE_SOURCE)
    assert_eq(filter.problem(), "", "every spelling compiles")
    _build(filter)

    var fine := _dialog.row(&"fine") as SaSlider
    assert_eq(_dialog.widget_name(&"fine"), "slider", "the hint makes a slider")
    assert_almost_eq(fine.min_value, 0.0, 0.0001, "from the hint's floor")
    assert_almost_eq(fine.max_value, 2.0, 0.0001, "to its ceiling")
    assert_almost_eq(float(fine.value), 0.5, 0.0001, "opening at the declared value")
    assert_almost_eq(fine.step_value, 0.25, 0.0001, "stepping by the hint's step")
    assert_eq(fine.decimal_places, 2, "written to the step's two decimals")
    assert_almost_eq(float(fine.describe()["step"]), 0.25, 0.0001, "the step the dump reads is the hint's too")

    var stride := _dialog.row(&"stride") as SaSlider
    assert_almost_eq(stride.max_value, 12.0, 0.0001, "a whole number's hint is its ceiling")
    assert_almost_eq(float(stride.value), 6.0, 0.0001, "opening at the declared value")
    assert_almost_eq(stride.step_value, 3.0, 0.0001, "steps by its own step")
    assert_eq(stride.decimal_places, 0, "and is written whole")

    var legacy := _dialog.row(&"legacy") as SaSlider
    assert_eq(_dialog.widget_name(&"legacy"), "slider", "the old comment still makes a slider")
    assert_almost_eq(legacy.max_value, 4.0, 0.0001, "over the comment's numbers")
    assert_almost_eq(float(legacy.value), 0.25, 0.0001, "opening at the declared value")
    assert_almost_eq(legacy.step_value, SaSlider.FINE_STEP, 0.0001, "at the slider's own step, the comment having none")
    assert_eq(filter.values(), {"fine": 0.5, "stride": 6, "legacy": 0.25}, "and the kernel is handed what each holds")
    _tear_down()


## An `int` with a `hint_enum` is a drop-down of its labels and a `bool` a
## checkbox, while an `int` with no hint stays a slider. A picked entry is
## handed to the kernel as its index and a ticked box as true.
func test_a_choice_is_a_drop_down_and_a_bool_a_checkbox() -> void:
    var filter := _written(scratch_switched_path, SWITCHED_SOURCE)
    assert_eq(filter.problem(), "", "both kinds compile")
    _build(filter)

    assert_eq(_dialog.widget_name(&"mode"), "dropdown", "a hint_enum makes a drop-down")
    assert_eq(_dialog.widget_name(&"lift"), "checkbox", "a bool makes a checkbox")
    assert_eq(_dialog.widget_name(&"count"), "slider", "and an int with no hint keeps its slider")
    var labels: Array[String] = []
    for choice: Dictionary in _dialog.row(&"mode").choices:
        labels.append(str(choice["label"]))
    assert_eq(labels, ["Keep", "Black", "White"] as Array[String], "the drop-down lists the labels in order")
    assert_eq(filter.values(), {"mode": 0, "lift": false, "count": 2}, "opening on the declared entry and an unticked box")

    _dialog.row(&"mode").drive(2)
    _dialog.row(&"lift").drive(true)
    assert_true(_dialog.rerun_pending, "a pick and a tick ask for a run")
    var handed := filter.values()
    assert_eq(handed.get("mode"), 2, "the picked entry is handed as its index")
    assert_eq(typeof(handed.get("mode")), TYPE_INT, "a whole number")
    assert_eq(handed.get("lift"), true, "and the ticked box as true")
    _tear_down()


## Moving a widget is what asks for the rerun, which is the whole of the
## preview following a drag.
func test_moving_a_generated_slider_asks_for_one_rerun() -> void:
    var filter := SaPixelFilter.new(THRESHOLD_PATH)
    _build(filter)
    assert_eq(_dialog.runs, 0, "nothing has run yet")
    (_dialog.row(&"level") as SaSlider).write(0.9)
    assert_true(_dialog.rerun_pending, "the change asked for a run")
    _dialog.flush_rerun()
    assert_eq(_dialog.runs, 1, "one run, at the end of the frame")
    assert_almost_eq(float(filter.values()["level"]), 0.9, 0.001, "and the kernel is handed the new value")
    _tear_down()


## A matrix is a grid of number fields, as wide as the matrix is, its
## numbers in the order the kernel reads them, row by row.
func test_a_matrix_uniform_is_a_grid_of_numbers_row_by_row() -> void:
    var filter := _written(scratch_matrices_path, MATRICES_SOURCE)
    assert_eq(filter.problem(), "", "three matrices compile")
    _build(filter)

    for name: String in ["small", "middle", "large"]:
        assert_eq(_dialog.widget_name(StringName(name)), "custom", "%s is a widget of the filter's own" % name)
    var sides := {"small": 3, "middle": 5, "large": 7}
    for name: String in sides:
        var grid := _dialog.row(StringName(name)).custom_control as GridContainer
        assert_not_null(grid, "%s draws a grid" % name)
        if grid == null:
            continue
        var side: int = sides[name]
        assert_eq(grid.columns, side, "%s is %d to a row" % [name, side])
        assert_eq(grid.get_child_count(), side * side, "and %d by %d in all" % [side, side])

    var small := _dialog.row(&"small").custom_control as GridContainer
    var shown: Array[String] = []
    for entry in small.get_children():
        shown.append((entry as LineEdit).text)
    assert_eq(shown, ["1", "2", "3", "4", "5", "6", "7", "8", "9"] as Array[String], "the numbers in the order written")
    var large := _dialog.row(&"large").custom_control as GridContainer
    assert_eq((large.get_child(24) as LineEdit).text, "1", "a matrix with no default holds a one in the middle")
    assert_eq((large.get_child(23) as LineEdit).text, "0", "and nought beside it")
    assert_eq(filter.values()["small"], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], "the kernel is handed them in order")
    _tear_down()


## A number typed into a field reaches that entry of the matrix and asks for one
## rerun, a fraction is read as one, and leaving a field that shows a rounded
## number keeps every decimal it held.
func test_a_number_typed_into_a_grid_reaches_its_entry() -> void:
    var filter := _written(scratch_matrices_path, MATRICES_SOURCE)
    _build(filter)
    var small := _dialog.row(&"small").custom_control as GridContainer
    var sixth := small.get_child(5) as LineEdit
    sixth.text_submitted.emit("1/9")
    assert_true(_dialog.rerun_pending, "the change asked for a run")
    _dialog.flush_rerun()
    assert_eq(_dialog.runs, 1, "one run")
    var handed: Array = filter.values()["small"]
    assert_almost_eq(float(handed[5]), 1.0 / 9.0, 0.0000001, "the sixth entry is a ninth, every decimal of it")
    assert_eq(handed.slice(0, 5), [1.0, 2.0, 3.0, 4.0, 5.0], "and the entries before it are as they were")
    assert_eq(sixth.text, "0.1111", "shown to four decimals")

    sixth.focus_exited.emit()
    assert_almost_eq(float(filter.values()["small"][5]), 1.0 / 9.0, 0.0000001, "leaving the field rounds nothing")
    sixth.text = "a lot"
    sixth.text_submitted.emit(sixth.text)
    assert_eq(sixth.text, "0.1111", "text that is no number puts the number back")
    assert_false(_dialog.rerun_pending, "and asks for nothing")
    _tear_down()


## The dialog every window makes keeps a matrix in the filter's store, so a
## preset and a record carry it the way they carry a slider.
func test_a_matrix_is_kept_in_the_filters_store() -> void:
    var filter := _written(scratch_matrices_path, MATRICES_SOURCE)
    _host = VBoxContainer.new()
    _dialog = SaDialog.for_filter(filter)
    _dialog.realize(_host)
    var small := _dialog.row(&"small").custom_control as GridContainer
    (small.get_child(0) as LineEdit).text_submitted.emit("-2")
    assert_eq(filter.store.read(&"small")[0], -2.0, "the typed number is in the store")
    assert_eq(filter.parameters()["small"][0], -2.0, "and in what a preset saves")
    assert_eq(filter.values()["small"][0], -2.0, "and in what the kernel is handed")
    _tear_down()


# --- The run, on a document -------------------------------------------------


## The dispatch a widget change causes, over the context's rectangle and into the
## preview, with the texels read back afterwards through the export door.
func test_the_run_thresholds_the_layer_at_the_sliders_value() -> void:
    var easel := SaEasel.create_default(Vector2i(1024, 1024))
    var doc: SaDocument = easel.document
    var layer: SaLayer = doc.active_layer
    # 0.4 grey has a luminance of 0.4 by the wrapper's own weights, so it falls
    # between the slider positions below and nothing else about the picture has
    # to change. `step(level, x)` is 1 at or above the level and 0 under it.
    layer.get_or_create_chunk(Vector2i(1, 1)).clear(Color(0.4, 0.4, 0.4, 1.0))

    var filter := SaPixelFilter.new(THRESHOLD_PATH)
    _build(filter)
    var ctx := SaFilterContext.new(doc, layer)
    filter.run(ctx)
    assert_eq(ctx.rect, Rect2i(256, 256, 256, 256), "the run covered the layer's allocated bounds and no more")
    assert_almost_eq(_shown(ctx).r, 0.0, 0.001, "at the default level of 0.5 the grey is below the step and goes out")

    (_dialog.row(&"level") as SaSlider).write(0.2)
    _dialog.flush_rerun()
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 1.0, 0.001, "a level under the grey lets it through, which is the drag the preview follows")

    (_dialog.row(&"level") as SaSlider).write(0.8)
    _dialog.flush_rerun()
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 0.0, 0.001, "and one over it puts the grey out again")
    assert_almost_eq(_shown(ctx).a, 1.0, 0.001, "with the alpha the layer had, either way")
    _tear_down()
    # `SaEasel` is a Node and this one was never in a tree, so nothing else is
    # going to free it, which is `test_pixel_function.gd`'s own ending.
    easel.free()


# --- The colour tag ---------------------------------------------------------


## A source that hints anything is read Godot's way: `source_color` makes the
## swatch and an untagged vector earns no widget, keeping its declared value.
func test_a_hinted_source_gives_a_swatch_to_the_tagged_vector_alone() -> void:
    var filter := _written(scratch_tagged_path, TAGGED_SOURCE)
    assert_eq(filter.problem(), "", "the tag is a hint the dialect takes")
    _build(filter)
    assert_eq(_dialog.widget_name(&"tint"), "color", "the tagged vec3 is the swatch")
    assert_null(_dialog.row(&"offset"), "the untagged vec3 earns no widget in a hinted source")
    assert_false(filter.values().has("offset"), "and keeps the value its line declared")
    _tear_down()


## A source with no hint on any line keeps the rule a saved kernel was written
## under, every `vec3` and `vec4` a swatch.
func test_a_source_with_no_hint_keeps_every_vectors_swatch() -> void:
    var filter := _written(scratch_untagged_path, UNTAGGED_SOURCE)
    _build(filter)
    assert_eq(_dialog.widget_name(&"tint"), "color", "an untagged vec3 is still a swatch")
    assert_eq(_dialog.widget_name(&"wash"), "color", "and so is an untagged vec4")
    assert_eq(_dialog.widget_name(&"amount"), "slider", "beside the old comment's slider")
    _tear_down()


## The tag on a type that is no colour is a problem naming the line, the way a
## `hint_range` on a vector is.
func test_the_tag_on_a_scalar_is_a_problem_naming_its_line() -> void:
    var source := "uniform float level: source_color = 0.5\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n"
    var said := PixelSource.problems(source, "x")
    assert_eq(said.size(), 1, "one problem")
    assert_true(said[0].contains("line 1") and said[0].contains("source_color"), "naming the line and the hint: %s" % said)


## The maintainers' ruling, "picker only": a picked colour reaches the kernel as the
## very numbers the swatch shows, with no conversion to linear light. White
## times the tint is the tint, so the texel the run shows is the pick itself.
func test_a_picked_colour_reaches_the_kernel_as_the_numbers_the_swatch_shows() -> void:
    var easel := SaEasel.create_default(Vector2i(1024, 1024))
    var doc: SaDocument = easel.document
    var layer: SaLayer = doc.active_layer
    layer.get_or_create_chunk(Vector2i(1, 1)).clear(Color(1.0, 1.0, 1.0, 1.0))

    var filter := _written(scratch_tagged_path, TAGGED_SOURCE)
    _build(filter)
    var picked := Color(0.25, 0.5, 0.75, 1.0)
    _dialog.row(&"tint").write(picked)
    assert_eq(filter.values().get("tint"), Vector3(0.25, 0.5, 0.75), "the kernel is handed the swatch's numbers")
    var ctx := SaFilterContext.new(doc, layer)
    filter.run(ctx)
    var shown := _shown(ctx)
    assert_almost_eq(shown.r, 0.25, 0.0001, "red as picked, not linearised to 0.05")
    assert_almost_eq(shown.g, 0.5, 0.0001, "green as picked, not 0.21")
    assert_almost_eq(shown.b, 0.75, 0.0001, "blue as picked, not 0.52")
    _tear_down()
    easel.free()


## The pick and the tick reach the dispatch, read back off the preview.
func test_a_picked_entry_and_a_ticked_box_change_the_preview() -> void:
    var easel := SaEasel.create_default(Vector2i(1024, 1024))
    var doc: SaDocument = easel.document
    var layer: SaLayer = doc.active_layer
    layer.get_or_create_chunk(Vector2i(1, 1)).clear(Color(0.4, 0.4, 0.4, 1.0))

    var filter := _written(scratch_switched_path, SWITCHED_SOURCE)
    _build(filter)
    var ctx := SaFilterContext.new(doc, layer)
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 0.4, 0.001, "the first entry keeps the layer")

    _dialog.row(&"mode").drive(1)
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 0.0, 0.001, "the second entry reaches the kernel as 1")

    _dialog.row(&"mode").drive(2)
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 1.0, 0.001, "the third as 2")

    _dialog.row(&"lift").drive(true)
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 0.25, 0.001, "a ticked box reaches it as true")

    _dialog.row(&"lift").drive(false)
    filter.run(ctx)
    assert_almost_eq(_shown(ctx).r, 1.0, 0.001, "and unticked as false again")
    _tear_down()
    easel.free()


# --- What a broken file does ------------------------------------------------


## The module clause through this door: a file that does not compile registers all the
## same and answers why, so the menu dims the row rather than losing it.
func test_a_pixel_function_that_does_not_compile_answers_why() -> void:
    var filter := _written(scratch_broken_path, BROKEN_SOURCE)
    var said := filter.problem()
    assert_true(said.contains("ERROR:"), "the compiler's own text, not a summary of it")
    assert_true(said.contains("w2_broken.gmacs:4"), "naming the student's file and the line they wrote it on")

    _build(filter)
    assert_not_null(_dialog.row(&"level"), "and the dialog is still generated, so a fix is one reopen away")
    _tear_down()


# --- Helpers ----------------------------------------------------------------


func _build(filter: SaPixelFilter) -> void:
    _host = VBoxContainer.new()
    _dialog = SaDialog.new(filter.build)
    _dialog.declare_rows()
    _dialog.realize(_host)


## *source* written to *path* and made into a filter, which is the door a module
## uses with a file it shipped instead.
func _written(path: String, source: String) -> SaPixelFilter:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
    return SaPixelFilter.new(path)


## Texel (8, 8) of chunk (1, 1) as the last run's recorded pass draws it, run
## the way the compositor's preview runs one. A pixel function records a pass
## rather than showing a texture. The export path's readback
## is the door hard rule 1 permits a test.
func _shown(ctx: SaFilterContext) -> Color:
    var recorded := ctx.point
    assert_not_null(recorded, "the run recorded a pass")
    if recorded == null:
        return Color.TRANSPARENT
    var layer: SaLayer = ctx.layer
    var grid := Vector2i(1, 1)
    var center := layer.get_field(grid)
    var mask: SaTexture = ctx.document.selection.texture_for(grid)
    var compute := ctx.kernel(recorded.shader)
    var drawn: SaTexture = null
    if recorded is SaNeighbourhoodPass:
        drawn = SaTexture.new(center.size, center.format)
        var whole := Rect2i(Vector2i.ZERO, center.size)
        SaNeighbourhoodPass.Runner.new().run(recorded, compute, drawn, center, layer.get_field, grid, whole, mask)
    else:
        drawn = SaPointPreview.new().chunk(compute, center, mask, Rect2i(), recorded, grid)
    return SaExportScript.get_texture_image_float(drawn).get_pixel(8, 8)


func _file_text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    assert_not_null(file, "%s opens" % path)
    return file.get_as_text() if file != null else ""


## A source copy leaves the specs out, so what compares the page to a fixture
## has nothing to compare it with there.
func _page_is_here() -> bool:
    return FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("..").path_join(PAGE).simplify_path())


func _page_text() -> String:
    var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(PAGE).simplify_path()
    var file := FileAccess.open(path, FileAccess.READ)
    assert_not_null(file, "the spec page opens at %s" % path)
    return file.get_as_text() if file != null else ""


## The first fenced block under *heading*, as the page prints it.
func _first_fence(text: String, heading: String) -> String:
    var inside_section := false
    var inside_fence := false
    var out := ""
    for line in text.split("\n"):
        if line.begins_with("## "):
            if inside_section:
                break
            inside_section = line.strip_edges() == heading
            continue
        if not inside_section:
            continue
        if line.begins_with("```"):
            if inside_fence:
                return out
            inside_fence = true
            continue
        if inside_fence:
            out += line + "\n"
    return out
