## The kernel prompt: the six things the spec lists, in a file the menu reads
## and nothing the wrapper does not accept.
##
## The six are read off the spec page rather than copied here, the way
## `test_pixel_function.gd` reads the threshold listing off the same page: the
## claim is that the file carries the contract the spec names, so a list typed
## out in this suite would prove only that this suite agrees with itself. The
## page's own parenthesis is the list, and a seventh item added to it fails here
## until somebody writes the section for it.
##
## The second half is the harder claim, "nothing the wrapper does not accept":
## a prompt that told a model to write `image dst` or to declare a `mat3`
## uniform would produce files that do not compile, and the model would be
## following the instructions. So the prompt's own example is loaded through the pixel
## function compiler, and every type and every name it names is checked against what
## `sa_pixel_source.gd` actually reads.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

## The prompt, and the page whose bullet says what has to be in it.
const PROMPT_PATH := "res://core/custom-shader/kernel_prompt.txt"
const PAGE := "docs/specs/scripting.md"

## The sentence the six items are listed in, and the marker that opens it. Named
## rather than counted, so a bullet added above it does not silently become the
## one under test.
const CONTRACT_MARKER := "puts the kernel contract"

## Where the prompt's own example is written, to be compiled as a student's file
## would be.
static var scratch_example_path: String = SaDataRoot.path("w4_prompt_example.gmacs")

# --- The six things the spec lists ------------------------------------------


## The list is the page's, and the page says six.
func test_the_page_lists_six_things() -> void:
    if _lacks_the_page():
        return
    var listed := _contract_items()
    assert_eq(listed.size(), 6, "the spec's parenthesis lists six things: %s" % ", ".join(listed))
    assert_eq(listed[0], "`src`", "and the first of them is src")


## Each of the six has a section of its own in the prompt, headed by the spec's
## own words, so a reader can hold the page and the file side by side.
func test_the_prompt_carries_every_one_of_the_six() -> void:
    if _lacks_the_page():
        return
    var text := _prompt_text()
    for item: String in _contract_items():
        var heading := item.replace("`", "")
        assert_true(_has_heading(text, heading), "the prompt has a section headed '%s'" % heading)


## "The dialect in three lines" is a count, and a count is worth checking: a
## section that grew to eight lines would still pass the heading test above and
## would no longer be what the spec asked for.
func test_the_dialect_section_is_three_lines() -> void:
    var body := _section(_prompt_text(), "the dialect in three lines")
    assert_false(body.is_empty(), "the dialect section has a body")
    assert_eq(_sentence_count(body), 3, "three lines, one per sentence: %s" % body)


## And "the hard rules in one" is the same claim with a smaller number.
func test_the_hard_rules_section_is_one_line() -> void:
    var body := _section(_prompt_text(), "the hard rules in one")
    assert_false(body.is_empty(), "the hard rules section has a body")
    assert_eq(_sentence_count(body), 1, "one line: %s" % body)


# --- Nothing the wrapper does not accept ------------------------------------


## The prompt's own example is a file the door takes, compiled through the
## wrapper exactly as a student's would be. A prompt whose example does not
## compile teaches a model to write files that do not.
func test_the_prompts_example_compiles_through_the_door() -> void:
    var example := _example_from_prompt()
    assert_true(example.contains("def pixel(ivec2 at) -> vec4:"), "the example is a pixel function")
    var file := FileAccess.open(scratch_example_path, FileAccess.WRITE)
    file.store_string(example)
    file.close()

    var written := PixelFunction.new(scratch_example_path)
    assert_eq(Array(written.problems), [], "the example has nothing wrong with it")
    assert_true(written.compile(), "and it compiles: %s" % written.first_error())
    assert_eq(written.uniforms.size(), 1, "its one uniform was read")
    assert_true(bool(written.uniforms[0]["ranged"]), "and the range hint on it was read as a range")
    assert_true(example.contains(": hint_range("), "written as the hint, the way a Godot shader declares a slider")


## Every type the prompt offers is one the params packer can measure. A prompt
## that offered `mat3` would produce a push constant of a size RenderingDevice
## reports as the constant being absent.
func test_the_prompt_offers_only_the_types_the_parser_takes() -> void:
    var offered := _section(_prompt_text(), "the uniform syntax")
    for type_name: String in PixelSource.PARAM_TYPES:
        assert_true(offered.contains(type_name), "the prompt offers %s" % type_name)
    for refused: String in ["mat3", "mat4", "double", "sampler2D"]:
        assert_false(offered.contains(refused), "and does not offer %s, which the parser refuses" % refused)


## The names the prompt promises are written for the student are the two the
## wrapper actually writes, and the names it says are taken are the ones that
## are, `step` and `t` among them.
func test_the_names_the_prompt_promises_are_the_wrappers_own() -> void:
    var text := _prompt_text()
    var wrapper := PixelSource.wrap("probe", "owner_pixels/probe", [])
    for promised: String in ["def src(ivec2 at)", "def luminance(vec3 rgb)"]:
        assert_true(wrapper.contains(promised), "the wrapper writes %s" % promised)
    assert_true(text.contains("luminance(vec3)"), "and the prompt names luminance as already written")
    var taken := "The names %s, %s and %s are taken" % [PixelSource.ORIGIN_FIELD, PixelSource.STEP_FIELD, PixelSource.TIME_FIELD]
    assert_true(text.contains(taken), "the prompt says which names are taken")
    for declared: String in [
        "vec2 %s" % PixelSource.ORIGIN_FIELD, "int %s" % PixelSource.STEP_FIELD, "float %s" % PixelSource.TIME_FIELD
    ]:
        assert_true(wrapper.contains(declared), "and the wrapper declares %s" % declared)


## The prompt tells a model not to declare or write an image, which is the
## clause the spec's `dst` earns: the wrapper owns the store.
func test_the_prompt_forbids_what_the_wrapper_owns() -> void:
    var body := _section(_prompt_text(), "dst")
    assert_true(body.contains("You never name it"), "the prompt says dst is not the student's to name")
    assert_true(body.contains("Do not declare an"), "and says not to declare an image")
    var wrapper := PixelSource.wrap("probe", "owner_pixels/probe", [])
    assert_true(wrapper.contains("image %s" % PixelSource.TARGET_IMAGE), "because the wrapper declares it")
    assert_true(wrapper.contains("image_store(%s" % PixelSource.TARGET_IMAGE), "and writes it")


# --- The menu row -----------------------------------------------------------


## The file the menu reads is the file this suite read, and the row that copies
## it is on the menu with an id nothing else uses. The menu is Modules, in its Develop
## section, and the Filter menu draws no row for it.
func test_the_menu_reads_the_committed_file() -> void:
    assert_eq(SaModulesMenu.PROMPT_PATH, PROMPT_PATH, "the menu points at the committed prompt")
    assert_eq(SaModulesMenu.prompt_text(), _prompt_text(), "and reads it whole")
    assert_true(SaModulesMenu.DEVELOP_ROWS.has([SaModulesMenu.ID_COPY_PROMPT, &"filter_copy_prompt"]), "the row is under Develop")
    var ids: Array[int] = []
    for row: Array in SaModulesMenu.DEVELOP_ROWS:
        ids.append(row[0])
    assert_eq(ids.count(SaModulesMenu.ID_COPY_PROMPT), 1, "and the section's other rows do not share its id")
    assert_true(SaModulesMenu.ID_COPY_PROMPT < SaModulesMenu.ACTION_ID_BASE, "nor can a module's action reach it")


## The capture door a scenario reads the clipboard through, which is a different
## clipboard from the `clipboard` step's.
func test_the_capture_door_measures_both_sides() -> void:
    var said := SaModulesMenu.capture("file")
    assert_true(said.contains("the kernel prompt holds"), "the file side answers a measurement: %s" % said)
    assert_true(said.contains("first line: Write one pixel function"), "and the first line of the prompt")
    assert_true(SaModulesMenu.capture("nonsense").contains("no kernel_prompt command"), "an unknown word says so")


# --- Helpers ----------------------------------------------------------------


func _prompt_text() -> String:
    var file := FileAccess.open(PROMPT_PATH, FileAccess.READ)
    assert_not_null(file, "the prompt opens at %s" % PROMPT_PATH)
    return file.get_as_text() if file != null else ""


func _page_text() -> String:
    var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(PAGE).simplify_path()
    var file := FileAccess.open(path, FileAccess.READ)
    assert_not_null(file, "the spec page opens at %s" % path)
    return file.get_as_text() if file != null else ""


## True, after recording why, when this copy of the source has no spec page.
func _lacks_the_page() -> bool:
    if FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("..").path_join(PAGE).simplify_path()):
        return false
    skip("the scripting spec is not in this copy of the source")
    return true


## The six things, off the page: the parenthesis after the marker, split on the
## commas the page wrote, with the line wrapping undone first.
func _contract_items() -> PackedStringArray:
    var flat := " ".join(_page_text().split("\n"))
    var at := flat.find(CONTRACT_MARKER)
    assert_true(at >= 0, "the page still says '%s'" % CONTRACT_MARKER)
    var opened := flat.find("(", at)
    var closed := flat.find(")", opened)
    var out := PackedStringArray()
    for part in flat.substr(opened + 1, closed - opened - 1).split(","):
        out.append(_squeezed(String(part)))
    return out


## A heading in the prompt is a line at the left margin, so a phrase quoted
## inside a paragraph is not mistaken for one.
func _has_heading(text: String, heading: String) -> bool:
    for line in text.split("\n"):
        if line == heading:
            return true
    return false


## The indented body under *heading*, up to the next line at the left margin.
func _section(text: String, heading: String) -> String:
    var inside := false
    var out := PackedStringArray()
    for line in text.split("\n"):
        if line == heading:
            inside = true
            continue
        if not inside:
            continue
        if line.strip_edges() != "" and not line.begins_with(" "):
            break
        out.append(line.strip_edges())
    return _squeezed(" ".join(out))


## The fenced example in the prompt: the indented block above the first heading,
## with one level of indentation taken off so it is the file a student writes.
func _example_from_prompt() -> String:
    var out := PackedStringArray()
    for line in _prompt_text().split("\n"):
        if line.begins_with("    "):
            out.append(line.substr(4))
        elif not out.is_empty() and line.strip_edges().is_empty():
            out.append("")
        elif not out.is_empty():
            break
    return "\n".join(out)


## Sentences, which is what a line of prose is once the file has been wrapped to
## eighty columns and the count the spec gives is no longer the count of
## newlines.
func _sentence_count(body: String) -> int:
    var found := 0
    for i in body.length():
        if body[i] == "." and (i + 1 >= body.length() or body[i + 1] == " "):
            found += 1
    return found


## Runs of whitespace as single spaces, edges trimmed.
func _squeezed(text: String) -> String:
    var collapse := RegEx.new()
    collapse.compile("\\s+")
    return collapse.sub(text, " ", true).strip_edges()
