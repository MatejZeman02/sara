## The kernel prompt names every kind of `uniform` the dialect reads.
##
## The dialect taught `sa_pixel_source.gd` the range hint, the enum, the bool, the
## colour tag and the matrix, and the prompt that Copy the kernel prompt puts on
## the clipboard went on saying that a `vec3` draws a swatch and takes no hint,
## which stopped being true for a source with a hint on any line. A model
## following that sentence writes a file whose vectors have no control.
##
## Two claims. The prompt carries a sentence for each kind, found by the word the
## dialect reads and not by a line number, and a source written to each sentence
## compiles through the pixel function and draws the widget the sentence
## promises. The second half is the harder one, since a prompt can name a hint
## the parser spells differently, so every word is read off `PixelSource`'s own
## constants and not typed here.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

const PROMPT_PATH := "res://core/custom-shader/kernel_prompt.txt"

## A source written to the colour sentence: two tagged vectors, and an untagged
## one beside the hint on `amount`, which the sentence says draws no control.
static var scratch_colour_path: String = SaDataRoot.path("l5_colour.gmacs")
const COLOUR_SOURCE := """uniform float amount: hint_range(0, 1) = 1.0
uniform vec3 tint: source_color = vec3(1.0, 0.5, 0.25)
uniform vec4 wash: source_color = vec4(0.1, 0.2, 0.3, 0.4)
uniform vec3 offset = vec3(0.0, 0.0, 0.0)

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(c.rgb * tint * wash.rgb * amount + offset, c.a)
"""

## A source written to the drop-down and the checkbox sentences.
static var scratch_choice_path: String = SaDataRoot.path("l5_choice.gmacs")
const CHOICE_SOURCE := """uniform int mode: hint_enum("Keep", "Black", "White") = 1
uniform bool lift = true

def pixel(ivec2 at) -> vec4:
    if lift:
        return vec4(0.25, 0.25, 0.25, 1.0)
    return src(at) * float(mode)
"""

## A source written to the matrix sentence, each size read by the formula the
## sentence gives, `row * side + column`, and none with a default but the first.
static var scratch_matrix_path: String = SaDataRoot.path("l5_matrix.gmacs")
const MATRIX_SOURCE := """uniform float blur[9] = {1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0}
uniform float middle[25]
uniform float large[49]

def pixel(ivec2 at) -> vec4:
    return src(at) * (blur[1 * 3 + 2] + middle[2 * 5 + 2] + large[3 * 7 + 3])
"""

var _dialog: SaDialog = null
var _host: VBoxContainer = null


func _tear_down() -> void:
    if _host != null:
        _host.free()
    _host = null
    _dialog = null


# --- The prompt carries a sentence for each kind ----------------------------


## The words the dialect reads, off its own constants, are all in the prompt.
func test_the_prompt_names_every_hint_the_dialect_reads() -> void:
    var text := _prompt_text()
    for hint: String in PixelSource.HINTS:
        assert_true(text.contains(hint), "the prompt names %s" % hint)
    assert_true(text.contains("bool"), "and names bool, which draws a checkbox and takes no hint")
    assert_true(text.contains("checkbox"), "saying what it draws")


## The colour sentence is the rule of a source with a hint, not the one it had.
func test_the_colour_sentence_says_a_vector_needs_the_tag() -> void:
    var flat := _squeezed(_prompt_text())
    var tagging := ": %s after a vec3 or a vec4 makes it a colour picker" % PixelSource.COLOUR_HINT
    assert_true(flat.contains(tagging), "the tag makes the picker")
    assert_true(flat.contains("sRGB encoded as src() hands a pixel"), "and the numbers are the picker's own")
    assert_true(flat.contains("without the tag draws no control"), "an untagged vector draws no control")
    assert_false(flat.contains("draws a colour swatch and takes no hint"), "and the old sentence is gone")


## The matrix sentence names float and each count, and says it is read flat.
func test_the_matrix_sentence_names_float_and_each_count() -> void:
    var flat := _squeezed(_prompt_text())
    assert_true(flat.contains("uniform %s <name>[9], [25] or [49]" % PixelSource.MATRIX_TYPE), "a float array of three counts")
    assert_true(flat.contains("3 by 3, 5 by 5 or 7 by 7"), "and the side each draws")
    assert_true(flat.contains("row by row"), "read row by row")
    assert_true(flat.contains("a one in the middle"), "opening on a one in the middle when no default is written")


# --- A source written to each sentence --------------------------------------


## The tagged vectors are swatches and the untagged one beside a hint has none.
func test_a_source_written_to_the_colour_sentence_draws_a_swatch_and_no_control() -> void:
    var filter := _written(scratch_colour_path, COLOUR_SOURCE)
    assert_eq(filter.problem(), "", "the colour source compiles")
    _build(filter)
    assert_eq(_dialog.widget_name(&"amount"), "slider", "the hint_range float is a slider")
    assert_eq(_dialog.widget_name(&"tint"), "color", "a tagged vec3 is a colour picker")
    assert_eq(_dialog.widget_name(&"wash"), "color", "and so is a tagged vec4")
    assert_null(_dialog.row(&"offset"), "an untagged vec3 beside a hint draws no control")
    var handed := filter.values()
    assert_eq(handed.get("tint"), Vector3(1.0, 0.5, 0.25), "the kernel gets the numbers the picker opens on")
    assert_false(handed.has("offset"), "and the untagged one keeps the value written")
    _tear_down()


## The enum is a drop-down of its labels and the bool a checkbox.
func test_a_source_written_to_the_choice_sentences_draws_a_drop_down_and_a_checkbox() -> void:
    var filter := _written(scratch_choice_path, CHOICE_SOURCE)
    assert_eq(filter.problem(), "", "the choice source compiles")
    _build(filter)
    assert_eq(_dialog.widget_name(&"mode"), "dropdown", "a hint_enum on an int is a drop-down")
    assert_eq(_dialog.widget_name(&"lift"), "checkbox", "a bool is a checkbox")
    assert_eq(filter.values(), {"mode": 1, "lift": true}, "the kernel gets the entry's index and the box's state")
    _tear_down()


## Each count is a grid as wide as its side, and with no default it holds a one
## in the middle and nought round it.
func test_a_source_written_to_the_matrix_sentence_draws_a_grid_of_its_side() -> void:
    var filter := _written(scratch_matrix_path, MATRIX_SOURCE)
    assert_eq(filter.problem(), "", "three matrices read by row * side + column compile")
    _build(filter)
    var sides := {"blur": 3, "middle": 5, "large": 7}
    for name: String in sides:
        var side: int = sides[name]
        var grid := _dialog.row(StringName(name)).custom_control as GridContainer
        assert_not_null(grid, "%s draws a grid" % name)
        if grid == null:
            continue
        assert_eq(grid.columns, side, "%s is %d to a row" % [name, side])
        assert_eq(grid.get_child_count(), side * side, "and %d by %d in all" % [side, side])
    var handed := filter.values()
    assert_eq(handed["blur"], [1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0], "the braces are read row by row")
    var middle: Array = handed["middle"]
    assert_eq(middle.size(), 25, "twenty-five numbers")
    assert_eq(middle[12], 1.0, "a one in the middle")
    assert_eq(middle.count(0.0), 24, "and nought everywhere else")
    _tear_down()


# --- Helpers ----------------------------------------------------------------


func _build(filter: SaPixelFilter) -> void:
    _host = VBoxContainer.new()
    _dialog = SaDialog.new(filter.build)
    _dialog.declare_rows()
    _dialog.realize(_host)


## *source* written to *path* and made into a filter, the door a module uses with
## a file it shipped.
func _written(path: String, source: String) -> SaPixelFilter:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
    return SaPixelFilter.new(path)


func _prompt_text() -> String:
    var file := FileAccess.open(PROMPT_PATH, FileAccess.READ)
    assert_not_null(file, "the prompt opens at %s" % PROMPT_PATH)
    return file.get_as_text() if file != null else ""


## Runs of whitespace as single spaces, edges trimmed, so a sentence the file
## wrapped at eighty columns is one string.
func _squeezed(text: String) -> String:
    var collapse := RegEx.new()
    collapse.compile("\\s+")
    return collapse.sub(text, " ", true).strip_edges()
