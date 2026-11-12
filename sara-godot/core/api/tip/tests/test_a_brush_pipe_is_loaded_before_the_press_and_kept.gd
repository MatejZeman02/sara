## A brush pipe is loaded before the press and kept when the preset changes,
##
## A knife brush froze Sara for 2.8 s at its first dab, and again each time
## it was chosen back, because its tip, a pipe of 360 cells, was read, parsed and
## uploaded inside the dab and kept by nobody. Here the same shape of pipe is
## built, 360 cells of 256 by 256, and chosen the way the Brush Presets docker
## chooses one: `SaTipCache.load_ahead` on the settings the preset was copied
## onto, then the frames' share of the load by hand, since a test function
## cannot wait for a frame, then the press, which is `SaBrushTipMask.bind`.
##
## **What a load is, counted.** `reads` is every file read the cache began, and
## `SaTexture.allocated_bytes` every texture alive, so a press that loads nothing
## moves neither.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const ScenarioTips = preload("res://harness/scenario/layers/sa_scenario_tips.gd")

## Needs a RenderingDevice: what is kept is textures.
const REQUIRES_GPU := true

## A painter's largest knife, and the cell size the row asks for.
const CELLS := 360
const SIDE := 256
## What one cell holds on the card, `r32g32f`.
const CELL_BYTES := SIDE * SIDE * 8

## The scratch folder every file here is written into and taken out of.
static var scratch_dir: String = SaDataRoot.path("test_n7_tip_cache")

var _compute: SaCompute = null


## The settings a preset is copied onto, as far as the cache reads them.
class Settings:
    extends Resource

    var tip: Resource = null


func before_each() -> void:
    SaTipCache.shared().forget()
    SaStrokeLedger.reset()
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    _compute = SaCompute.new("dab")
    # The one texel a press with no picture binds, made before anything is
    # counted, since it is made once a run rather than by a load.
    SaBrushTipMask.stand_in()


func after_each() -> void:
    SaTipCache.shared().forget()
    SaStrokeLedger.reset()
    _compute = null
    for file: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file))
    DirAccess.remove_absolute(scratch_dir)


## A `.gih` of *cells* cells of *side* by *side*, stepping one per dab, written
## as *file_name* in the scratch folder by the writer the scenario's step uses,
## and its path.
func _pipe(file_name: String, cells: int, side: int) -> String:
    return ScenarioTips.write_pipe(scratch_dir.path_join(file_name), cells, side)


## The knife: the pipe of 360 cells of 256 by 256.
func _knife() -> String:
    return _pipe("knife.gih", CELLS, SIDE)


## The settings a preset with the tip at *path* leaves, or a round one for none.
func _settings(path: String) -> Settings:
    var tip: SaBrushTipScript = SaBrushTipScript.new()
    if not path.is_empty():
        tip.image_path = path
        tip.kind = SaBrushTipScript.Kind.IMAGE
        tip.generator = SaDabGeometry.Generator.IMAGE
    var settings := Settings.new()
    settings.tip = tip
    return settings


## The frames' share of every load under way, until none is, and the longest
## share in microseconds.
##
## A suite draws no frame between two shares, which is a window nobody touches,
## so the cache draws one itself between two that uploaded, as it does in the
## app. Before it did, the device kept the staging memory every upload went
## through and a share here took up to 73 ms. The scenario times the frames in
## the running app.
func _frames_until_loaded(cache: SaTipCache) -> int:
    var deadline := Time.get_ticks_msec() + 60000
    var longest := 0
    while cache.busy() and Time.get_ticks_msec() < deadline:
        var started := Time.get_ticks_usec()
        cache.pump()
        longest = maxi(longest, Time.get_ticks_usec() - started)
        OS.delay_msec(2)
    return longest


## The first dab of a stroke with *settings* in the hand, over the mask held.
func _press(settings: Settings, held: SaBrushTipMask) -> SaBrushTipMask:
    return SaBrushTipMask.bind(_compute, settings.tip, held)


func test_a_pipe_chosen_and_loaded_before_the_press_loads_nothing_inside_it() -> void:
    var cache := SaTipCache.shared()
    var knife := _settings(_knife())
    var before := cache.reads

    SaTipCache.load_ahead(knife)
    assert_true(cache.busy(), "Choosing the preset starts its tip loading")
    assert_eq(cache.reads, before + 1, "with one read of the file")
    var longest := _frames_until_loaded(cache)
    assert_false(cache.busy(), "The load ends over the frames")
    assert_true(longest < 33000, "and no frame's share of it reaches 33 ms, the longest %d µs" % longest)
    assert_true(cache.holds(knife.tip.image_path), "and the pipe is kept")
    assert_eq(cache.held_bytes, CELLS * CELL_BYTES, "every cell of it, 180 MiB")

    var reads := cache.reads
    var allocated := SaTexture.allocated_bytes
    var started := Time.get_ticks_usec()
    var mask := _press(knife, null)
    var took := Time.get_ticks_usec() - started

    assert_eq(cache.reads, reads, "The press reads no file")
    assert_eq(SaTexture.allocated_bytes, allocated, "and makes no texture")
    assert_eq(cache.finished_at_press, 0, "and has no load to finish")
    assert_true(mask.error.is_empty(), "The press binds the pipe: %s" % mask.error)
    assert_eq(mask.pipe_cells.size(), CELLS, "all 360 cells of it")
    assert_true(took < 33000, "inside a frame's budget, %d µs" % took)


func test_another_preset_and_this_one_again_load_nothing_at_all() -> void:
    var cache := SaTipCache.shared()
    var knife := _settings(_knife())
    var paint := _settings("")
    SaTipCache.load_ahead(knife)
    _frames_until_loaded(cache)
    var held := _press(knife, null)

    var reads := cache.reads
    var allocated := SaTexture.allocated_bytes
    SaTipCache.load_ahead(paint)
    held = _press(paint, held)
    assert_false(held.has_image(), "Paint's round tip is in the hand")
    SaTipCache.load_ahead(knife)
    assert_false(cache.busy(), "Choosing the knife again starts no load")
    held = _press(knife, held)

    assert_eq(cache.reads, reads, "Neither the choices nor the presses read the file")
    assert_eq(SaTexture.allocated_bytes, allocated, "and no texture was made")
    assert_eq(held.pipe_cells.size(), CELLS, "The knife's pipe is bound again")
    assert_eq(held.pipe_cell, 0, "on its first cell, a mask of its own rather than the one bound before")


func test_a_changed_modified_time_loads_the_pipe_again() -> void:
    var cache := SaTipCache.shared()
    var path := _knife()
    var knife := _settings(path)
    SaTipCache.load_ahead(knife)
    _frames_until_loaded(cache)
    var before := cache.reads
    var bytes := FileAccess.get_file_as_bytes(path)
    var modified := FileAccess.get_modified_time(path)

    # The same bytes written again a second later, so only the time moves.
    OS.delay_msec(1100)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    assert_true(FileAccess.get_modified_time(path) > modified, "The file's modified time moved")

    SaTipCache.load_ahead(knife)
    assert_true(cache.busy(), "and choosing the preset loads the pipe again")
    assert_eq(cache.reads, before + 1, "with a second read")
    _frames_until_loaded(cache)
    var mask := _press(knife, null)
    assert_eq(cache.reads, before + 1, "which the press does not repeat")
    assert_eq(mask.pipe_cells.size(), CELLS, "and binds")
    assert_eq(cache.held_bytes, CELLS * CELL_BYTES, "The old load is let go of, not kept beside the new")


## Two small pictures and the knife in a cache bound at the knife and one and a
## half small ones: the knife pushes out the small one asked for longest ago,
## which is the first loaded only when nothing asked for it since.
func test_the_cache_past_its_bound_drops_the_least_recently_bound_first() -> void:
    var half_small := 64 * 64 * 4
    var cache := SaTipCache.new(CELLS * CELL_BYTES + half_small * 3)
    var first := _pipe("first.gih", 1, 64)
    var second := _pipe("second.gih", 1, 64)
    var knife := _knife()

    cache.mask_for(first)
    cache.mask_for(second)
    assert_true(cache.holds(first) and cache.holds(second), "Both small ones are kept under the bound")
    cache.mask_for(first)
    cache.mask_for(knife)

    assert_true(cache.holds(knife), "The knife is kept")
    assert_true(cache.holds(first), "and so is the first, asked for again since the second")
    assert_false(cache.holds(second), "The second, bound longest ago, is dropped")
    assert_true(cache.held_bytes <= cache.bound_bytes, "and the cache is back under its bound")

    var alone := SaTipCache.new(half_small)
    alone.mask_for(first)
    assert_true(alone.holds(first), "A picture past the whole bound is kept while it is the last asked for")
    alone.mask_for(second)
    assert_false(alone.holds(first), "and dropped at the next")
    cache.forget()
    alone.forget()


## The press that comes before the load ends: it finishes the load rather than
## starting a second, and says so, in the trail while the frame is out and in
## the stroke's line.
func test_a_press_before_the_load_ends_finishes_it_and_says_so() -> void:
    var cache := SaTipCache.shared()
    var path := _knife()
    var knife := _settings(path)
    var before := cache.reads
    var finished := cache.finished_at_press
    SaTipCache.load_ahead(knife)
    assert_true(cache.busy(), "The load is under way")

    SaStrokeLedger.frame_drawn(40)
    SaStrokeLedger.left_button(_button(true), 41)
    SaStrokeLedger.event_arrived(false, 41)
    var mask := _press(knife, null)
    SaStrokeLedger.dab_dispatched(1, 41)

    assert_eq(cache.reads, before + 1, "The press read nothing of its own")
    assert_eq(cache.finished_at_press, finished + 1, "and finished the load it found")
    assert_false(cache.busy(), "so no load is left")
    assert_eq(mask.pipe_cells.size(), CELLS, "and the pipe is bound whole")
    assert_true(SaTrail.last().contains("knife.gih"), "The trail stands at the load, read '%s'" % SaTrail.last())

    SaStrokeLedger.frame_drawn(41)
    SaStrokeLedger.left_button(_button(false), 42)
    SaStrokeLedger.frame_drawn(42)
    var stroke := SaStrokeLedger.last_stroke
    assert_eq(stroke["longest_tip"], "knife.gih", "The stroke's longest frame names the load")
    assert_true(stroke["longest_tip_usec"] > 0, "with its time")
    var line := SaStrokeLedger.line_of(stroke)
    assert_true(line.contains(" of it loading the tip knife.gih"), "and its line says so: %s" % line)


## The press that comes once the file is read and while its cells are: it
## waits for the cells. It used to read the file a second time, which put a
## second set of slots beside the first and stopped on the empty ones, a script
## error in the running app with a knife pressed 40 frames after its choice.
func test_a_press_while_the_cells_are_read_waits_for_them() -> void:
    var cache := SaTipCache.shared()
    var knife := _settings(_knife())
    var finished := cache.finished_at_press
    SaTipCache.load_ahead(knife)
    cache.pump()
    # The file is read in milliseconds and its 360 cells in tenths of a second,
    # so the next frame's share finds the read done and the cells under way.
    OS.delay_msec(100)
    cache.pump()
    assert_true(cache.busy(), "The cells are still being read")

    var mask := _press(knife, null)
    assert_eq(cache.finished_at_press, finished + 1, "The press finished the load")
    assert_true(mask.error.is_empty(), "without an error: %s" % mask.error)
    assert_eq(mask.pipe_cells.size(), CELLS, "and bound the pipe whole")


## A stroke whose frames held no load says nothing of one.
func test_a_stroke_with_no_load_names_none() -> void:
    SaStrokeLedger.frame_drawn(50)
    SaStrokeLedger.left_button(_button(true), 51)
    SaStrokeLedger.event_arrived(false, 51)
    SaStrokeLedger.dab_dispatched(1, 51)
    SaStrokeLedger.frame_drawn(51)
    SaStrokeLedger.left_button(_button(false), 52)
    SaStrokeLedger.frame_drawn(52)
    var line := SaStrokeLedger.line_of(SaStrokeLedger.last_stroke)
    assert_false(line.contains("loading the tip"), "No load, no word of one: %s" % line)


## The Load Tip action's road: the chosen file is loaded off the stroke and
## handed on once it is kept.
func test_a_tip_loaded_ahead_is_handed_on_once_it_is_kept() -> void:
    var cache := SaTipCache.shared()
    var path := _pipe("small.gih", 4, 64)
    var handed: Array[String] = []
    cache.ahead(path, func() -> void: handed.append(path))
    assert_true(handed.is_empty(), "Nothing is handed on while the load is under way")
    _frames_until_loaded(cache)
    assert_eq(handed, [path] as Array[String], "and the path once it is kept")
    assert_true(cache.holds(path), "kept")


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event
