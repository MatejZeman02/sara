## The gradient follows the two picked colours until its ramp is edited, says
## which of the two it is doing, and the library's two stock gradients make it
## follow again.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With the foreground yellow and the background magenta a drag lays a yellow
## to magenta ramp, swapping the colours swaps the ramp, and the library lists
## its stock gradients. The tool follows the pair until one edit freezes it for
## the tool's life, and something on screen says which of the two it is doing.
##
## The tool and the ramp row are built bare here, with no GPU, except the last
## case, which drags through a bound machine and reads the layer back. The popup
## the library opens is a `Window`, so pressing a row is `press_row` on the
## detached list, and the shots are
## `scenarios/the-gradient-follows-the-two-colours-until-its-ramp-is-edited-and.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateGradientScript = preload("res://modules/sara-base-modules/base/gradient/state_gradient.gd")

const MODULE_ID := &"sara-base-modules"
const YELLOW := Color(1.0, 1.0, 0.0, 1.0)
const MAGENTA := Color(1.0, 0.0, 1.0, 1.0)
const FOLLOWS := "Follows the colours"
const EDITED := "Edited, choose a stock gradient to follow the colours again"
## What a preference the profile does not hold reads as here. A null default
## reads as no default at all, and the engine prints an error for every read of
## an absent key.
const ABSENT := "absent"

static var scratch_dir: String = SaDataRoot.path("test_s34_ramp_library")

var _was_pair: Array[Color] = []
var _start_alpha: Variant = null
var _end_alpha: Variant = null
## Held for the suite's length, because the end rule holds its context weakly.
var _context: SaContext = null


## The pair, the two remembered alphas and the scratch library are all shared
## with the rest of the run, so each is put back.
func before_each() -> void:
    _was_pair = [SaColors.foreground, SaColors.background]
    _context = SaContext.new(Callable(), Callable(), MODULE_ID)
    _start_alpha = _context.preference(SaGradientEnds.START_ALPHA_KEY, ABSENT)
    _end_alpha = _context.preference(SaGradientEnds.END_ALPHA_KEY, ABSENT)
    # `scenarios/gradient-saved.json` leaves a faded far end in the shared
    # profile, so the baseline is set rather than assumed.
    _context.set_preference(SaGradientEnds.START_ALPHA_KEY, 1.0)
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, 1.0)
    SaColors.foreground = YELLOW
    SaColors.background = MAGENTA
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaColors.foreground = _was_pair[0]
    SaColors.background = _was_pair[1]
    # A null forgets the key, which is how an absent one is put back.
    _context.set_preference(SaGradientEnds.START_ALPHA_KEY, null if _start_alpha is String else _start_alpha)
    _context.set_preference(SaGradientEnds.END_ALPHA_KEY, null if _end_alpha is String else _end_alpha)
    _context = null
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## A gradient tool with no document, and the ramp row bound to it the way the
## module's binder binds it: through the signal the option names.
func _bound(ends: SaGradientEnds = null) -> Dictionary:
    var tool := StateGradientScript.new()
    if ends != null:
        tool.settings = ends
    var control := SaColorRampControl.new(_store(), ends)
    control.follow_tool(tool.following_changed)
    return {"tool": tool, "control": control}


## The pair swapped the way X swaps it, without `swap()`'s write of the colours
## file into the shared profile.
func _swap() -> void:
    var was_foreground := SaColors.foreground
    SaColors.foreground = SaColors.background
    SaColors.background = was_foreground


func _html(color: Color) -> String:
    return color.to_html(false)


func _line(control: SaColorRampControl) -> String:
    return String(control.stop_report()["follow_line"])


## The first clause: foreground yellow, background magenta, and the ramp is
## yellow to magenta, then X and it is magenta to yellow, with the row's bar
## showing the same ramp the drag reads.
func test_the_ramp_follows_the_pair_and_a_swap() -> void:
    var bound := _bound()
    var tool: StateGradientScript = bound["tool"]
    var control: SaColorRampControl = bound["control"]

    assert_eq(_html(tool.ramp.color_of(0)), _html(YELLOW), "The near end is the foreground")
    assert_eq(_html(tool.ramp.color_of(1)), _html(MAGENTA), "and the far end the background")
    assert_eq(_line(control), FOLLOWS, "and the line under the bar says the ramp follows them")

    _swap()
    assert_eq(_html(control.ramp.color_of(0)), _html(MAGENTA), "After X the row's ramp starts magenta")
    assert_eq(_html(control.ramp.color_of(1)), _html(YELLOW), "and ends yellow, without the tool being read")
    assert_eq(_html(tool.ramp.color_of(0)), _html(MAGENTA), "which is the ramp the drag lays")
    control.free()


## The second clause: after a stop is edited the line says so, and a later
## colour change leaves the ramp alone.
func test_an_edit_stops_the_following_and_the_line_says_so() -> void:
    var bound := _bound()
    var tool: StateGradientScript = bound["tool"]
    var control: SaColorRampControl = bound["control"]
    var heard: Array[bool] = []
    tool.following_changed.connect(func(following: bool) -> void: heard.append(following))

    control.select_stop(0)
    control.set_selected_color(Color(0.9, 0.5, 0.1))
    assert_eq(heard, [false] as Array[bool], "The edit is announced once")
    assert_eq(_line(control), EDITED, "and the line says the ramp is edited and how to follow again")
    assert_false(bool(control.stop_report()["following"]), "and the dump agrees")

    SaColors.foreground = Color(0.1, 0.2, 0.9)
    _swap()
    assert_eq(_html(tool.ramp.color_of(0)), _html(Color(0.9, 0.5, 0.1)), "A later colour change leaves the edited stop")
    assert_eq(_html(tool.ramp.color_of(1)), _html(MAGENTA), "and the far one where the edit found it")
    control.free()


## A gradient loaded from the library is an edit as well, which is the frozen
## orange the sweep met: the ramp is that file's stops, not the pair.
func test_a_saved_gradient_loaded_stops_the_following() -> void:
    var bound := _bound()
    var tool: StateGradientScript = bound["tool"]
    var control: SaColorRampControl = bound["control"]
    control.save_ramp("Sunset")

    assert_true(control.load_ramp("Sunset"), "A saved gradient loads")
    assert_eq(_line(control), EDITED, "and the ramp no longer follows")
    SaColors.foreground = Color(0.0, 0.5, 0.0)
    assert_eq(_html(tool.ramp.color_of(0)), _html(YELLOW), "so a new foreground is not taken")
    control.free()


## The third clause: choosing Foreground to Background in the library resumes
## following, on a ramp an edit gave a third stop.
func test_foreground_to_background_resumes_the_following() -> void:
    var bound := _bound()
    var tool: StateGradientScript = bound["tool"]
    var control: SaColorRampControl = bound["control"]
    control.select_stop(control.add_stop_at(0.5))
    control.set_selected_color(Color(0.2, 0.8, 0.3))
    SaColors.foreground = Color(0.1, 0.2, 0.9)

    var list := control.find_child("RampLibraryList", true, false) as SaChoicePopup
    control.fill_library()
    assert_true(list.press_row(&"stock:foreground_to_background"), "The stock row takes the press")

    assert_eq(tool.ramp.size(), 2, "The ramp is two stops again")
    assert_eq(_html(tool.ramp.color_of(0)), _html(Color(0.1, 0.2, 0.9)), "the foreground as it is now")
    assert_eq(_html(tool.ramp.color_of(1)), _html(MAGENTA), "and the background")
    assert_eq(_line(control), FOLLOWS, "and the line says it follows")
    _swap()
    assert_eq(_html(tool.ramp.color_of(0)), _html(MAGENTA), "A later swap is followed")
    assert_almost_eq(tool.ramp.color_of(1).a, 1.0, 1e-6, "with the far end opaque")
    control.free()


## The fourth clause: Foreground to Transparent drags a fade from the foreground
## to nothing, and keeps fading while it follows the colours.
func test_foreground_to_transparent_fades_the_far_end_and_follows() -> void:
    var bound := _bound()
    var tool: StateGradientScript = bound["tool"]
    var control: SaColorRampControl = bound["control"]

    assert_true(control.choose_stock(SaGradientEnds.TO_TRANSPARENT), "The stock gradient is chosen")
    assert_almost_eq(tool.ramp.color_of(0).a, 1.0, 1e-6, "The near end is opaque")
    assert_almost_eq(tool.ramp.color_of(1).a, 0.0, 1e-6, "and the far end is nothing")
    assert_eq(_html(tool.ramp.color_of(0)), _html(YELLOW), "from the foreground")
    assert_eq(_line(control), FOLLOWS, "and it follows the colours")

    SaColors.foreground = Color(0.1, 0.2, 0.9)
    assert_eq(_html(tool.ramp.color_of(0)), _html(Color(0.1, 0.2, 0.9)), "A new foreground is followed")
    assert_almost_eq(tool.ramp.color_of(1).a, 0.0, 1e-6, "and the far end still fades")
    control.free()


## The fifth clause: the library lists both stock rows on a fresh profile, not
## one dimmed row saying nothing was saved.
func test_the_library_lists_both_stock_rows_on_a_fresh_profile() -> void:
    var bound := _bound()
    var control: SaColorRampControl = bound["control"]
    var list := control.find_child("RampLibraryList", true, false) as SaChoicePopup

    control.fill_library()
    var labels := list.row_labels()
    assert_eq(labels, ["Foreground to Background", "Foreground to Transparent"] as Array[String], "Both stock rows")
    assert_false(labels.has("No saved gradients"), "and no row saying the library is empty")
    assert_false(list.is_disabled(list.row_ids()[0]), "and the rows take a press")

    control.save_ramp("Dusk")
    control.fill_library()
    assert_eq(list.row_labels().size(), 3, "A saved gradient lists below them")
    assert_eq(String(list.row_ids()[2]), "Dusk", "under its own name")
    control.free()


## Shift on a stock row deletes nothing, there being no file, and still chooses.
func test_a_stock_row_has_no_file_to_delete() -> void:
    var bound := _bound()
    var tool: StateGradientScript = bound["tool"]
    var control: SaColorRampControl = bound["control"]
    control.set_selected_color(Color(0.9, 0.5, 0.1))

    assert_false(control.delete_ramp("foreground_to_background"), "No file is behind a stock row")
    assert_true(control.choose_stock(SaGradientEnds.TO_BACKGROUND), "and choosing it still works")
    assert_true(tool.ramp_is_default, "the ramp following again")
    assert_false(control.choose_stock(&"sunset"), "A name that is no stock gradient is refused")
    control.free()


## A stock choice is remembered as the ends' alphas, so the next launch opens on
## it and a fade chosen once does not come back after Foreground to Background.
func test_a_stock_choice_is_remembered_for_the_next_launch() -> void:
    var ends := SaGradientEnds.new(_context)
    var bound := _bound(ends)
    var control: SaColorRampControl = bound["control"]

    control.choose_stock(SaGradientEnds.TO_TRANSPARENT)
    assert_almost_eq(ends.end_alpha(), 0.0, 1e-6, "Foreground to Transparent remembers the faded far end")
    assert_almost_eq(ends.fresh_ramp(YELLOW, MAGENTA).color_of(1).a, 0.0, 1e-6, "which a fresh launch opens with")

    control.choose_stock(SaGradientEnds.TO_BACKGROUND)
    assert_almost_eq(ends.end_alpha(), 1.0, 1e-6, "and Foreground to Background puts it back to opaque")
    assert_almost_eq(ends.start_alpha(), 1.0, 1e-6, "with the near end opaque in both")
    control.free()


## A ramp handed to the tool whole is an edit too, and is announced as one.
func test_a_ramp_assigned_whole_stops_the_following() -> void:
    var tool := StateGradientScript.new()
    var heard: Array[bool] = []
    tool.following_changed.connect(func(following: bool) -> void: heard.append(following))

    tool.ramp = SaColorRamp.from_pair(Color.BLACK, Color.WHITE)
    assert_false(tool.ramp_is_default, "The tool no longer follows")
    assert_eq(heard, [false] as Array[bool], "and said so once")
    SaColors.foreground = Color(0.5, 0.0, 0.0)
    assert_eq(_html(tool.ramp.color_of(0)), _html(Color.BLACK), "so a new foreground is not taken")


## A row bound to a bare ramp, as the older suites build one, has no tool to
## make follow: no line, and the stock rows answer false.
func test_a_row_with_no_tool_shows_no_line_and_its_stock_rows_do_nothing() -> void:
    var control := SaColorRampControl.new(_store())
    control.bind_ramp(SaColorRamp.from_pair(Color.RED, Color.BLUE))

    assert_eq(_line(control), "", "No line")
    assert_null(control.stop_report()["following"], "and nothing to say about following")
    assert_false(control.choose_stock(SaGradientEnds.TO_BACKGROUND), "A stock row with no tool behind it does nothing")
    assert_eq(_html(control.ramp.color_of(0)), _html(Color.RED), "and leaves the ramp alone")
    control.free()


## The clause on the canvas: a drag lays yellow to magenta, X, and the next drag
## lays magenta to yellow. Read back as which channels are high, so the check
## holds whatever transfer the document stores in.
func test_a_drag_lays_the_pair_and_after_a_swap_the_swapped_pair() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        skip("no RenderingDevice, the drag half needs one")
        return
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"gradient")
    var tool: StateGradientScript = machine.get_tool(&"gradient")
    var document: SaDocument = surface.get_document()
    var width := float(document.canvas_size.x)

    assert_true(tool.draw_between(Vector2(0.0, 10.0), Vector2(width, 10.0)), "The first drag lands")
    var near := _texel_of(document.active_layer, 1, 10)
    var far := _texel_of(document.active_layer, int(width) - 2, 10)
    assert_true(near.g > 0.8 and near.b < 0.2, "It starts yellow, got %s" % near)
    assert_true(far.g < 0.2 and far.b > 0.8, "and ends magenta, got %s" % far)

    _swap()
    assert_true(tool.draw_between(Vector2(0.0, 10.0), Vector2(width, 10.0)), "The drag after X lands")
    near = _texel_of(document.active_layer, 1, 10)
    far = _texel_of(document.active_layer, int(width) - 2, 10)
    assert_true(near.g < 0.2 and near.b > 0.8, "It starts magenta, got %s" % near)
    assert_true(far.g > 0.8 and far.b < 0.2, "and ends yellow, got %s" % far)
    Fixtures.teardown(surface, machine)


## The texel at *x*, *y* of *layer*, or transparent where it holds no chunk. A
## readback, which is a test's to make and never a stroke's.
func _texel_of(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )
