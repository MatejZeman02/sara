## The spec's shortest door, from the file a student writes to the texels the GPU
## wrote.
##
## The pixel function is "a kernel that is one function", and everything else is
## the wrapper's: the two images, the params block, `src` with its out-of-bounds
## rule and the dispatch. So this suite reads the spec's own threshold function
## off the page, wraps it, holds the generated source against a committed
## expectation line for line, compiles it and dispatches it over a texture whose
## texels it then reads.
##
## Reading the page rather than copying it is the point, the way
## `test_gmacs_page.gd` reads the `blur_x` listing: a copy would drift the moment
## somebody improved the spec, and the whole claim of this unit is that the
## fourteen words on that page run.
##
## The pixel function itself is written to `user://` and compiled from there, the
## way `test_dialect_kernel.gd` writes its proof kernels, so nothing here ships in
## the tree or in the startup report.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

## The readback the export path does, which is the door hard rule 1 permits a
## test. Nothing the wrapper itself does leaves VRAM.
const SaExportScript = preload("res://core/export/sa_export.gd")

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT

## The page the threshold function is printed on, and the heading whose first
## fence carries it. Named rather than counted, so a listing added above it does
## not silently become the one under test.
const PAGE := "docs/specs/scripting.md"
const PIXEL_HEADING := "## The pixel function, the shortest door"

## What the wrapper writes around that function, committed so a change to the
## generated source is a change somebody has to look at.
const EXPECTATION := "res://tests/data/pixel_function_wrapper.txt"

## Where the pixel functions under test are written.
static var scratch_threshold_path: String = SaDataRoot.path("threshold.gmacs")
static var scratch_reach_path: String = SaDataRoot.path("reach.gmacs")

## A pixel function that reads the source at an offset the slider sets, so one
## kernel answers both halves of the `src` rule: at zero it reads the texel it is
## standing on, and far outside every allocated pixel it reads transparent black.
const REACH_SOURCE := """uniform float shift: hint_range(0, 2000) = 0.0

def pixel(ivec2 at) -> vec4:
    return src(at + ivec2(int(shift), 0))
"""

## The function under the `uniform` lines of the hint cases, which give the
## file the one function the door takes so the only problem left is the hint's.
const PIXEL_TAIL := "\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n"

## A pixel function switched by a drop-down and a checkbox, the two kinds:
## the picked entry of `mode` paints black or white over the source, and a
## ticked `lift` paints a quarter grey over all of it.
static var scratch_switched_path: String = SaDataRoot.path("d68_switched.gmacs")
const SWITCHED_SOURCE := """uniform int mode: hint_enum("Keep", "Black", "White") = 0
uniform bool lift = false

def pixel(ivec2 at) -> vec4:
    if lift:
        return vec4(0.25, 0.25, 0.25, 1.0)
    if mode == 1:
        return vec4(0.0, 0.0, 0.0, 1.0)
    if mode == 2:
        return vec4(1.0, 1.0, 1.0, 1.0)
    return src(at)
"""

## Where Sara's shipped patterns are, every one of them a pixel function.
const PATTERNS := "res://patterns"

## The rectangle the runs cover, at an origin that is not the canvas's own. A
## wrapper that forgot `origin` would read outside the source everywhere and
## answer transparent black, so the offset is part of the proof rather than
## decoration.
const REGION := Rect2i(32, 16, 8, 8)

## Where the light half of the source ends, written out rather than divided,
## because an integer division is a warning the LSP check reports.
const HALF_WIDTH: int = 4

## The two greys the threshold has to separate, either side of the slider's 0.5.
const LIGHT: float = 0.6
const DARK: float = 0.4


## True, after recording why, when this copy of the source has no spec page.
## The cases that wrap the page's own listing have nothing to run without it,
## and every other case carries its own source.
func _lacks_the_page() -> bool:
    var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(PAGE).simplify_path()
    if FileAccess.file_exists(path):
        return false
    skip("the spec page is not in this copy of the source")
    return true


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


## The spec's threshold function, off the page.
func _threshold_source() -> String:
    return _first_fence(_page_text(), PIXEL_HEADING)


func _committed_expectation() -> String:
    var file := FileAccess.open(EXPECTATION, FileAccess.READ)
    assert_not_null(file, "the committed expectation opens")
    return file.get_as_text() if file != null else ""


## *source* written to *path* and loaded, which is the door a module will use.
##
## Untyped, here and at every call, because the pixel function is preloaded by
## path the way the compiler's own halves are and a script reached that way has
## no static type to infer.
func _loaded(path: String, source: String) -> PixelFunction:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
    return PixelFunction.new(path)


## A source texture the size of the region, light on the left half and dark on
## the right, so a threshold has something to separate.
func _two_greys() -> SaTexture:
    var texels := PackedFloat32Array()
    texels.resize(REGION.size.x * REGION.size.y * 4)
    for y in REGION.size.y:
        for x in REGION.size.x:
            var value := LIGHT if x < HALF_WIDTH else DARK
            var at := (y * REGION.size.x + x) * 4
            texels[at] = value
            texels[at + 1] = value
            texels[at + 2] = value
            texels[at + 3] = 1.0
    var source := SaTexture.new(REGION.size, F32)
    GlobalShaderCompiler.get_rd().texture_update(source.rid, 0, texels.to_byte_array())
    return source


## The four channels of one texel, read back the way the export path reads one.
func _texel(texture: SaTexture, at: Vector2i) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var base := (at.y * texture.size.x + at.x) * 16
    return [bytes.decode_float(base), bytes.decode_float(base + 4), bytes.decode_float(base + 8), bytes.decode_float(base + 12)]


# --- The generated source --------------------------------------------------


## What the unit is for. The spec's function in, the committed kernel out, line
## for line so a diff names the line that moved.
func test_the_specs_threshold_wraps_into_the_committed_source() -> void:
    if _lacks_the_page():
        return
    var written := PixelFunction.new(scratch_threshold_path, _threshold_source())
    assert_eq(written.problems.size(), 0, "the spec's own function has nothing wrong with it")

    # A trailing newline is trimmed off both sides rather than compared: what is
    # under test is the kernel's lines, and whether a text file on disk keeps its
    # last one is the reader's business.
    var generated: PackedStringArray = String(written.generated_source).trim_suffix("\n").split("\n")
    var expected: PackedStringArray = _committed_expectation().trim_suffix("\n").split("\n")
    assert_eq(generated.size(), expected.size(), "the generated kernel is %d lines" % expected.size())
    for i in mini(generated.size(), expected.size()):
        assert_eq(generated[i], expected[i], "line %d of the generated kernel" % (i + 1))


## The `uniform` line and its `hint_range`, which becomes a
## slider.
func test_the_uniform_line_and_its_range_become_a_param() -> void:
    if _lacks_the_page():
        return
    var written := PixelFunction.new(scratch_threshold_path, _threshold_source())
    assert_true(_threshold_source().contains(": hint_range(0, 1) = 0.5"), "the spec's listing declares its slider Godot's way")
    assert_eq(written.uniforms.size(), 1, "the spec's function declares one uniform")
    var field: Dictionary = written.uniforms[0]
    assert_eq(String(field["name"]), "level", "named as the file names it")
    assert_eq(String(field["type"]), "float", "and typed as it declares")
    assert_almost_eq(float(field["default"]), 0.5, 0.0001, "the declared value is the default")
    assert_true(bool(field["ranged"]), "the hint was read")
    assert_almost_eq(float(field["minimum"]), 0.0, 0.0001, "from 0")
    assert_almost_eq(float(field["maximum"]), 1.0, 0.0001, "to 1")
    assert_almost_eq(float(field["step"]), 0.0, 0.0001, "with no step, which leaves the slider its own")
    assert_almost_eq(float(written.defaults()["level"]), 0.5, 0.0001, "and the params open at the declared value")


## The `# range` comment the hint replaced is still read, so a kernel saved
## before the hint keeps its slider, and it reads to the very entry the hint does.
## A line with both takes the hint's numbers.
func test_the_old_range_comment_reads_as_the_hint_does() -> void:
    var hinted: Dictionary = PixelSource.uniforms("uniform float level: hint_range(0, 1) = 0.5\n")[0]
    var commented: Dictionary = PixelSource.uniforms("uniform float level = 0.5   # range 0 1\n")[0]
    for key: String in ["name", "type", "default", "minimum", "maximum", "step", "ranged", "line"]:
        assert_eq(commented[key], hinted[key], "the comment and the hint read the same %s" % key)
    assert_true(bool(commented["ranged"]), "and both are ranged")

    var both: Dictionary = PixelSource.uniforms("uniform int count: hint_range(1, 8) = 2   # range 0 100\n")[0]
    assert_almost_eq(float(both["maximum"]), 8.0, 0.0001, "the hint wins over a comment on the same line")
    assert_eq(
        Array(PixelSource.problems("uniform float level = 0.5   # range 0 1\n" + PIXEL_TAIL, "old")),
        [],
        "and the old form is no problem"
    )


## A third number is the slider's step, as in Godot, and the hint's arguments
## may be written with any spacing.
func test_a_hints_third_number_is_the_step() -> void:
    var field: Dictionary = PixelSource.uniforms("uniform float fine:hint_range( -1 , 1.5 , 0.25 )=0.5   # a note\n")[0]
    assert_true(bool(field["ranged"]), "the hint was read")
    assert_almost_eq(float(field["minimum"]), -1.0, 0.0001, "from its first number")
    assert_almost_eq(float(field["maximum"]), 1.5, 0.0001, "to its second")
    assert_almost_eq(float(field["step"]), 0.25, 0.0001, "stepping by its third")
    assert_almost_eq(float(field["default"]), 0.5, 0.0001, "and opening at the value after it")
    var bare: Dictionary = PixelSource.uniforms("uniform int count: hint_range(1, 8)\n")[0]
    assert_eq(bare["default"], 0, "a hint with no value after it opens at zero, as a bare line does")


## A hint this door cannot read is refused by the line it is on, rather than
## dropped, because a dropped one opens a slider from 0 to 1 and says nothing.
func test_a_hint_that_cannot_be_read_is_a_problem() -> void:
    var refused := {
        "uniform float level: hint_rnage(0, 1) = 0.5": "hint_rnage",
        "uniform float level: hint_range(1) = 0.5": "a lowest, a highest",
        "uniform float level: hint_range(0, 1, 0) = 0.5": "step above nought",
        "uniform vec3 tint: hint_range(0, 1)": "only float, int, uint",
        "uniform float level: = 0.5": "no hint after it",
        "uniform float level: hint_range(0, 1) =": "a default this cannot read",
    }
    for line: String in refused:
        var said := PixelSource.problems(line + "\n" + PIXEL_TAIL, "hinted")
        assert_eq(said.size(), 1, "one problem for `%s`: %s" % [line, said])
        if said.size() == 1:
            assert_true(said[0].contains("line 1"), "on the line it is written on")
            assert_true(said[0].contains(String(refused[line])), "saying %s: %s" % [refused[line], said[0]])


## A `hint_enum` is read as its labels in order and a `bool` as the value its
## line declared, which is what the dialog and the notebook build their
## drop-down and checkbox from.
func test_a_hint_enum_reads_its_labels_and_a_bool_its_value() -> void:
    var fields := PixelSource.uniforms(SWITCHED_SOURCE)
    var mode: Dictionary = fields[0]
    assert_eq(mode["type"], "int", "the drop-down's uniform is an int")
    assert_eq(Array(mode["choices"] as PackedStringArray), ["Keep", "Black", "White"], "its labels in the order written")
    assert_eq(mode["default"], 0, "opening on the index its line declared")
    assert_false(bool(mode["ranged"]), "and it is no slider")
    var lift: Dictionary = fields[1]
    assert_eq(lift["type"], "bool", "a bool is a uniform of its own type")
    assert_eq(lift["default"], false, "read as the false its line declared")
    assert_eq(PixelSource.uniforms("uniform bool on = true\n")[0]["default"], true, "and a true as true")
    assert_eq(PixelSource.uniforms("uniform bool on\n")[0]["default"], false, "with no value a box opens unticked")
    var quoted: Dictionary = PixelSource.uniforms('uniform int pick: hint_enum("a, b", "c # d")\n')[0]
    assert_eq(Array(quoted["choices"] as PackedStringArray), ["a, b", "c # d"], "a comma or a hash inside a label stays in it")
    assert_eq(Array(PixelSource.problems(SWITCHED_SOURCE, "switched")), [], "and the whole file has nothing wrong with it")


## A choice or a box this door cannot read is refused by its line.
func test_a_choice_or_a_box_that_cannot_be_read_is_a_problem() -> void:
    var refused := {
        'uniform float mode: hint_enum("A", "B")': "only int",
        "uniform int mode: hint_enum(A, B)": "one quoted label per entry",
        "uniform int mode: hint_enum()": "one quoted label per entry",
        "uniform bool lift = maybe": "a default this cannot read as a bool",
    }
    for line: String in refused:
        var said := PixelSource.problems(line + "\n" + PIXEL_TAIL, "switched")
        assert_eq(said.size(), 1, "one problem for `%s`: %s" % [line, said])
        if said.size() == 1:
            assert_true(said[0].contains("line 1"), "on the line it is written on")
            assert_true(said[0].contains(String(refused[line])), "saying %s: %s" % [refused[line], said[0]])


## Every pattern Sara ships opens with its sliders, each declared with the hint
## now, and the old comment gone from all of them.
func test_every_shipped_pattern_declares_its_sliders_with_the_hint() -> void:
    var names := DirAccess.get_files_at(PATTERNS)
    var patterns := 0
    for file_name in names:
        if file_name.get_extension() != "gmacs":
            continue
        patterns += 1
        var path := PATTERNS.path_join(file_name)
        var written := PixelFunction.new(path)
        assert_eq(Array(written.problems), [], "%s has nothing wrong with it" % file_name)
        assert_true(written.uniforms.size() >= 2, "%s declares its tile and a slider of its own" % file_name)
        for raw_field: Variant in written.uniforms:
            var field: Dictionary = raw_field
            assert_true(bool(field["ranged"]), "%s's %s opens as a slider" % [file_name, field["name"]])
            assert_true((field["hints"] as Dictionary).has("hint_range"), "declared with the hint")
        assert_false(FileAccess.get_file_as_string(path).contains("# range"), "and %s carries no range comment" % file_name)
    assert_eq(patterns, 5, "the five shipped patterns were read")


## The params block carries the wrapper's own field and the student's, and the
## student never sees either declaration.
func test_the_params_block_is_the_wrappers_and_the_students() -> void:
    if _lacks_the_page():
        return
    var written := PixelFunction.new(scratch_threshold_path, _threshold_source())
    assert_true(written.generated_source.contains("    vec2 origin"), "the wrapper declares the run's origin")
    assert_true(written.generated_source.contains("    float level"), "and the student's uniform beside it")
    assert_false(written.generated_source.contains("uniform float level"), "the uniform line itself is not carried over")


## A file that is not a pixel function is refused by name, before anything is
## generated from it.
func test_a_file_without_the_function_is_refused() -> void:
    var written := PixelFunction.new(SaDataRoot.path("not_a_pixel.gmacs"), "vec4 c = vec4(0.0)\n")
    assert_eq(written.problems.size(), 1, "one problem, and it is the missing function")
    assert_true(String(written.problems[0]).contains("def pixel"), "which the message names")


## A uniform of a type the push constant packer cannot measure is a problem
## rather than a block whose size is a guess.
func test_a_uniform_of_an_unknown_type_is_refused() -> void:
    var written := PixelFunction.new(
        scratch_threshold_path, "uniform mat3 warp\n\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n"
    )
    assert_eq(written.problems.size(), 1, "one problem")
    assert_true(String(written.problems[0]).contains("line 1"), "naming the student's own line")
    assert_true(String(written.problems[0]).contains("mat3"), "and the type it cannot take")


# --- The kernel that comes out of it ---------------------------------------


## The spec's threshold, compiled and dispatched over the region, at the slider's
## own default. The light half comes back white and the dark half black, which is
## what `step(level, luminance(c.rgb))` says and nothing the wrapper wrote.
func test_the_wrapped_threshold_separates_the_two_greys() -> void:
    if _lacks_the_page():
        return
    var written := _loaded(scratch_threshold_path, _threshold_source())
    assert_true(written.compile(), "the generated kernel compiled")

    var source := _two_greys()
    var target := SaTexture.new(REGION.size, F32)
    target.clear(Color(1, 0, 0, 1))
    written.run(source, target, REGION)

    var light := _texel(target, Vector2i(1, 1))
    assert_almost_eq(float(light[0]), 1.0, 0.001, "a grey above the level thresholds to white")
    assert_almost_eq(float(light[3]), 1.0, 0.001, "and keeps the alpha it had")
    var dark := _texel(target, Vector2i(6, 1))
    assert_almost_eq(float(dark[0]), 0.0, 0.001, "a grey below it thresholds to black")
    assert_almost_eq(float(dark[3]), 1.0, 0.001, "and keeps its alpha too")


## The same kernel with the slider moved above both greys, which is the param
## reaching the dispatch rather than the default being baked in.
func test_the_slider_moves_the_threshold() -> void:
    if _lacks_the_page():
        return
    var written := _loaded(scratch_threshold_path, _threshold_source())
    assert_true(written.compile(), "the generated kernel compiled")

    var source := _two_greys()
    var target := SaTexture.new(REGION.size, F32)
    target.clear(Color(1, 0, 0, 1))
    written.run(source, target, REGION, {"level": 0.7})

    assert_almost_eq(float(_texel(target, Vector2i(1, 1))[0]), 0.0, 0.001, "the light grey is below 0.7 now")
    assert_almost_eq(float(_texel(target, Vector2i(6, 1))[0]), 0.0, 0.001, "and the dark one still is")


## A picked entry reaches the kernel as its index and a ticked box as true,
## through the push constant's 32-bit word for a `bool`. Unticked again, the
## box is nought, so the entry it hid paints once more.
func test_a_picked_entry_reaches_the_kernel_as_its_index_and_a_ticked_box_as_true() -> void:
    var written := _loaded(scratch_switched_path, SWITCHED_SOURCE)
    assert_true(written.compile(), "the generated kernel compiled: %s" % written.first_error())

    var source := _two_greys()
    var target := SaTexture.new(REGION.size, F32)
    var painted := {}
    for name: String in ["keep", "black", "white", "lifted", "white unlifted"]:
        var values: Dictionary = {
            "keep": {},
            "black": {"mode": 1},
            "white": {"mode": 2},
            "lifted": {"mode": 2, "lift": true},
            "white unlifted": {"mode": 2, "lift": false},
        }[name]
        target.clear(Color(1, 0, 0, 1))
        written.run(source, target, REGION, values)
        painted[name] = float(_texel(target, Vector2i(1, 1))[0])
    assert_almost_eq(float(painted["keep"]), LIGHT, 0.001, "the first entry keeps the source")
    assert_almost_eq(float(painted["black"]), 0.0, 0.001, "the second entry arrives as 1")
    assert_almost_eq(float(painted["white"]), 1.0, 0.001, "and the third as 2")
    assert_almost_eq(float(painted["lifted"]), 0.25, 0.001, "a ticked box arrives as true")
    assert_almost_eq(float(painted["white unlifted"]), 1.0, 0.001, "and an unticked one as false")


## `src` at the pixel it is standing on, which is the control for the case below.
func test_src_reads_the_source_at_the_canvas_pixel() -> void:
    var written := _loaded(scratch_reach_path, REACH_SOURCE)
    assert_true(written.compile(), "the generated kernel compiled")

    var source := _two_greys()
    var target := SaTexture.new(REGION.size, F32)
    target.clear(Color(1, 0, 0, 1))
    written.run(source, target, REGION, {"shift": 0.0})

    assert_almost_eq(float(_texel(target, Vector2i(1, 1))[0]), LIGHT, 0.001, "the light half came through")
    assert_almost_eq(float(_texel(target, Vector2i(6, 1))[0]), DARK, 0.001, "and the dark half with it")


## The rule the spec states: `src` outside every allocated pixel is transparent
## black, not the edge and not what happened to be in the target.
func test_src_outside_the_source_reads_transparent_black() -> void:
    var written := _loaded(scratch_reach_path, REACH_SOURCE)
    assert_true(written.compile(), "the generated kernel compiled")

    var source := _two_greys()
    var target := SaTexture.new(REGION.size, F32)
    target.clear(Color(1, 0, 0, 1))
    written.run(source, target, REGION, {"shift": 1000.0})

    for at: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(6, 1), Vector2i(7, 7)]:
        var texel := _texel(target, at)
        assert_almost_eq(float(texel[0]), 0.0, 0.001, "%s reads no colour" % at)
        assert_almost_eq(float(texel[3]), 0.0, 0.001, "and no alpha")


## The spec asks for "depth-two `.gmacs`", which is a kernel that compiles for
## whatever depth the document declares rather than for one of them. The wrapper
## writes a bare `image`, so the format is the placeholder token the compiler
## substitutes per variant, and the same generated source runs on an F16 document
## without a line of it changing.
func test_the_wrapped_kernel_runs_at_the_documents_other_depth() -> void:
    if _lacks_the_page():
        return
    var written := _loaded(scratch_threshold_path, _threshold_source())
    assert_true(written.compile(), "the generated kernel compiled")

    var texels := PackedByteArray()
    texels.resize(REGION.size.x * REGION.size.y * 8)
    for i in REGION.size.x * REGION.size.y:
        for channel in 3:
            texels.encode_half(i * 8 + channel * 2, LIGHT)
        texels.encode_half(i * 8 + 6, 1.0)
    var source := SaTexture.new(REGION.size, F16)
    GlobalShaderCompiler.get_rd().texture_update(source.rid, 0, texels)
    var target := SaTexture.new(REGION.size, F16)
    target.clear(Color(0, 0, 0, 0))
    written.run(source, target, REGION)

    var wrote := GlobalShaderCompiler.get_rd().texture_get_data(target.rid, 0)
    assert_almost_eq(wrote.decode_half(8 * 9), 1.0, 0.001, "a grey above the level thresholds to white at F16 too")
    assert_almost_eq(wrote.decode_half(8 * 9 + 6), 1.0, 0.001, "and keeps its alpha")


# --- Over a filter's rectangle ---------------------------------------------


## The run a filter makes, over the rectangle the context answers rather than
## over a rectangle this file chose. Two chunks of the layer are painted, so the
## rectangle is the allocated bounds and the two flat colours either side of the
## threshold say whether the dispatch landed where it was aimed.
func test_the_run_covers_the_rectangle_the_context_answers() -> void:
    if _lacks_the_page():
        return
    var easel := SaEasel.create_default(Vector2i(1024, 1024))
    var doc: SaDocument = easel.document
    var layer: SaLayer = doc.active_layer
    layer.get_or_create_chunk(Vector2i(1, 1)).clear(Color(1.0, 0.0, 0.0, 1.0))
    layer.get_or_create_chunk(Vector2i(2, 1)).clear(Color(0.0, 1.0, 0.0, 1.0))

    var written := _loaded(scratch_threshold_path, _threshold_source())
    assert_true(written.compile(), "the generated kernel compiled")
    var ctx := SaFilterContext.new(doc, layer)
    written.run_on(ctx)

    assert_eq(ctx.rect, Rect2i(256, 256, 512, 256), "the run covered the layer's allocated bounds")
    assert_eq(ctx.shown_rect, ctx.rect, "and the preview was handed that same rectangle")
    var image := SaExportScript.get_texture_image_float(ctx.shown)
    # Red is 0.2126 of the way to white by the wrapper's own luminance and green
    # is 0.7152, so the default level of 0.5 falls between the two chunks.
    assert_almost_eq(image.get_pixel(8, 8).r, 0.0, 0.001, "the red chunk is below the level")
    assert_almost_eq(image.get_pixel(264, 8).r, 1.0, 0.001, "and the green one above it")
    assert_almost_eq(image.get_pixel(264, 8).a, 1.0, 0.001, "with the alpha the layer had")
    easel.free()


# --- The line map ----------------------------------------------------------


## The clause the whole import mechanism exists for: glslang counts lines in the
## text it was handed, and every line of the student's body has to come back as
## their own file and their own line.
func test_the_line_map_names_the_students_file_and_line() -> void:
    if _lacks_the_page():
        return
    var written := _loaded(scratch_threshold_path, _threshold_source())
    assert_true(written.compile(), "the generated kernel compiled")

    var origins: Array = GlobalShaderCompiler.source.line_map(written.shader_name)
    assert_false(origins.is_empty(), "the compiler kept a line map for the generated kernel")

    # The body's third line is `def pixel(...)`, and its fourth is the first line
    # of the function. Found rather than counted, because the wrapper's own
    # length is not what this case is about.
    var at := -1
    for i in origins.size():
        if String(origins[i][0]).get_file() == "threshold.gmacs" and int(origins[i][1]) == 4:
            at = i
            break
    assert_true(at >= 0, "line 4 of the student's file is in the map")

    var glsl_line := at + GlobalShaderCompiler.source.PREAMBLE_LINES + 1
    var located: String = GlobalShaderCompiler.source.locate_glsl_error(
        "ERROR: 0:%d: 'src' : no matching overload" % glsl_line, written.shader_name
    )
    assert_true(located.contains("[threshold.gmacs:4]"), "and glslang's own line comes back as that file and line")
