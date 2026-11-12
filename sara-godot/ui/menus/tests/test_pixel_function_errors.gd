## What a student sees when their kernel does not compile.
##
## Three things are promised and this suite reads back all three. "Errors
## come back as the compiler's own text with the line number shifted to the
## student's file" is the first case, on a pixel function whose third line
## returns the wrong type. "A kernel that failed to compile is greyed in the
## menu with the first error as its tooltip" is the menu case, on a real
## `SaFilterMenu` filled from a real registry. And the recompile that clears it
## is the last case, which rewrites the file and asks again.
##
## Every case here provokes a compile error on purpose, so `SaProblems.announce`
## is off while it happens: the transcript should show the assertion and not the
## alarm it was checking for.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## A pixel function whose third line hands a `vec3` back from a function
## declared `vec4`. Three lines, so the error is on the last of them and the
## line the compiler names is not the line the function opens on.
static var scratch_broken_path: String = SaDataRoot.path("w3_broken.gmacs")
const BROKEN_SOURCE := """def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return c.rgb
"""

## The same file with the mistake corrected, which is what the student saves
## before opening the menu again.
const FIXED_SOURCE := """def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(c.rgb, 1.0)
"""

## The line the error is on, in the student's own file.
const BROKEN_LINE: int = 3

## A module's own kernel, rather than a pixel function, so the clause about
## both doors is read back on both. Its second kernel line names something
## nothing declares.
static var scratch_kernel_path: String = SaDataRoot.path("w3_broken_kernel.gmacs")
const KERNEL_SOURCE := """kernel w3_probe

image dst


def w3_probe():
    image_store(dst, pixel, w3_no_such_name)
"""
const KERNEL_LINE: int = 7


## The filter the menu case registers, which reports whatever it is given.
class SaidFilter:
    extends SaFilter
    var said: String = ""

    func _init(problem_text: String) -> void:
        said = problem_text

    func title() -> String:
        return "Said Filter"

    func problem() -> String:
        return said

    func run(_ctx: SaFilterContext) -> void:
        pass


## *source* on disk at *path*, and the pixel function read from it.
func _written(path: String, source: String) -> PixelFunction:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
    return PixelFunction.new(path)


## Compiles *made* with the alarm off, because every case here fails on purpose.
func _quietly(made: PixelFunction) -> bool:
    var announced := SaProblems.announce
    SaProblems.announce = false
    var compiled: bool = made.compile()
    SaProblems.announce = announced
    return compiled


# --- The message ------------------------------------------------------------


## The core claim: the compiler's own text, and the line number
## shifted off the generated kernel and onto the file the student has open.
func test_a_type_error_names_the_students_file_and_line() -> void:
    var made := _written(scratch_broken_path, BROKEN_SOURCE)

    assert_false(_quietly(made), "a kernel that does not compile is not a kernel")
    assert_false(made.compile_error.is_empty(), "and the compiler's message was kept rather than only logged")
    assert_true(
        made.compile_error.contains("[%s:%d]" % [scratch_broken_path.get_file(), BROKEN_LINE]),
        "naming the student's file and their line 3: %s" % made.compile_error
    )
    assert_true(made.compile_error.contains("return"), "and glslang's own words about what is wrong with it")


## The tooltip is one line, and it is the line that says something. glslang
## opens with `Failed parse:`, which a menu row would be worse for carrying.
func test_the_first_error_is_the_first_line_that_says_something() -> void:
    var made := _written(scratch_broken_path, BROKEN_SOURCE)
    _quietly(made)

    var first: String = made.first_error()
    assert_true(first.begins_with("ERROR:"), "the first error is an error line: %s" % first)
    assert_false(first.contains("\n"), "and one line, which is what a tooltip can hold")
    assert_true(first.contains("[%s:%d]" % [scratch_broken_path.get_file(), BROKEN_LINE]), "still naming the file and the line")


## A pixel function is one of the two doors the clause names. This is the other:
## a module's own `.gmacs`, whose message the compiler kept for the same reason
## and which anything can now read back by shader name.
func test_a_modules_own_kernel_keeps_its_message_too() -> void:
    var file := FileAccess.open(scratch_kernel_path, FileAccess.WRITE)
    file.store_string(KERNEL_SOURCE)
    file.close()

    var announced := SaProblems.announce
    SaProblems.announce = false
    GlobalShaderCompiler.compile_compute_shader(scratch_kernel_path)
    SaProblems.announce = announced

    var said: String = GlobalShaderCompiler.compile_error("w3_broken_kernel")
    assert_false(said.is_empty(), "the compiler kept what it said about a module's kernel")
    assert_true(
        said.contains("[%s:%d]" % [scratch_kernel_path.get_file(), KERNEL_LINE]),
        "naming the file and the line the mistake is on: %s" % said
    )


## A shader that compiles leaves nothing behind, so a row that was dimmed
## yesterday is not dimmed by a message nobody cleared.
func test_a_kernel_that_compiles_says_nothing() -> void:
    var made := _written(scratch_broken_path, FIXED_SOURCE)

    assert_true(_quietly(made), "the corrected file compiles")
    assert_eq(made.compile_error, "", "and answers no message")
    assert_eq(made.first_error(), "", "so a menu row has nothing to carry")


# --- The menu ---------------------------------------------------------------


## "Greyed in the menu with the first error as its tooltip." A dimmed control is
## a disabled one, so the row is both.
func test_the_menu_dims_a_broken_filter_and_says_why() -> void:
    var registry := SaFilterRegistry.new()
    registry.register(SaidFilter.new("ERROR: 0:9 [broken.gmacs:3]: 'return' : type does not match"), &"w3-fixture")
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registry

    # The filter names no section, so its row is in Other's list.
    var popup := menu.show_section(menu.section_item(SaFilterRegistry.OTHER))
    var index := SaMenu.key(SaFilterMenu.ID_FILTER_BASE)
    assert_true(popup.row_ids().has(index), "the filter kept its entry although its kernel failed")
    assert_true(popup.is_disabled(index), "and the entry is dimmed, which is disabled")
    assert_eq(
        popup.label_button(index).tooltip_text,
        "ERROR: 0:9 [broken.gmacs:3]: 'return' : type does not match",
        "with the first error as the tooltip rather than who registered it"
    )
    bar.free()


## The row of a filter with nothing wrong with it is untouched, the earlier
## assertion read again from this side.
func test_a_filter_with_no_problem_keeps_its_row_live() -> void:
    var registry := SaFilterRegistry.new()
    registry.register(SaidFilter.new(""), &"w3-fixture")
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registry

    # The filter names no section, so its row is in Other's list.
    var popup := menu.show_section(menu.section_item(SaFilterRegistry.OTHER))
    var index := SaMenu.key(SaFilterMenu.ID_FILTER_BASE)
    assert_false(popup.is_disabled(index), "nothing is wrong with it, so nothing is dimmed")
    var tooltip := popup.label_button(index).tooltip_text
    assert_eq(tooltip, "Added by w3-fixture.", "and the tooltip is still who put it there")
    bar.free()


## Opening the menu fills it again, which is what makes a filter that has fixed
## itself live without a restart. The filter is asked once per fill, so a menu
## opened twice asks twice.
func test_opening_the_menu_asks_every_filter_again() -> void:
    var registry := SaFilterRegistry.new()
    var filter := SaidFilter.new("ERROR: 0:9 [broken.gmacs:3]: broken")
    registry.register(filter, &"w3-fixture")
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registry
    # The filter names no section, so its row is in Other's list.
    var popup := menu.show_section(menu.section_item(SaFilterRegistry.OTHER))
    var row := SaMenu.key(SaFilterMenu.ID_FILTER_BASE)
    assert_true(popup.is_disabled(row), "dimmed while it is broken")

    filter.said = ""
    # The rebuild the bar does before every open, where this menu hangs
    # its own `about_to_popup` handler for exactly this.
    menu.populate()
    menu.show_section(menu.section_item(SaFilterRegistry.OTHER))

    assert_false(popup.is_disabled(row), "and live on the next open, with no restart")
    bar.free()


# --- The fix ----------------------------------------------------------------


## The last clause: the student saves the file and the door reads it again, so
## the kernel that could not run now runs.
func test_fixing_the_file_clears_it_and_the_kernel_runs() -> void:
    var made := _written(scratch_broken_path, BROKEN_SOURCE)
    assert_false(_quietly(made), "broken to start with")

    var file := FileAccess.open(scratch_broken_path, FileAccess.WRITE)
    file.store_string(FIXED_SOURCE)
    file.close()

    assert_true(made.reload_if_changed(), "the door noticed the file had changed")
    assert_eq(made.first_error(), "", "and the message is gone rather than kept from before")
    assert_false(made.reload_if_changed(), "a file that has not changed since is read and left alone")

    var source := SaTexture.new(Vector2i(8, 8), F32)
    source.clear(Color(0.25, 0.5, 0.75, 0.5))
    var target := SaTexture.new(Vector2i(8, 8), F32)
    target.clear(Color(0.0, 0.0, 0.0, 0.0))
    made.run(source, target, Rect2i(0, 0, 8, 8))

    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(target.rid, 0)
    assert_almost_eq(bytes.decode_float(0), 0.25, 0.001, "the corrected kernel wrote the colour it was handed")
    assert_almost_eq(bytes.decode_float(12), 1.0, 0.001, "with the alpha its own third line sets")
