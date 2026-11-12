## A cold start's first frames do not stall after Ready.
##
## A boot with a fresh `--settings-dir` could log "Sara stall: the frames came slow
## for 5.3 s" with no hand on the pen. It was two things,
## and this suite holds each to its fix without frames. The presets chooser drew
## one whole picture a frame, so a picture is now a `Drawing` advanced a step a
## call and the queue `SaBrushPresetPictures` hands the chooser one frame's
## share. The presets scan was one frame of 0.4 to 0.9 s, the store reading each
## preset four times over and writing the shipped ones, so the store reads a
## preset once and the bar does the reads and the writes in slices before the
## scan. The frames themselves are the scenario's,
## `a-cold-starts-first-frames-do-not-stall-after-ready`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A picture is a stroke on a real easel, and the bar builds against a tool
## machine.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d111_cold_start")


func before_each() -> void:
    _clear(scratch_dir)


func after_each() -> void:
    _clear(scratch_dir)


func _store(folder: String = "presets") -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir.path_join(folder)
    return store


## The twenty-one presets the brush ships, the Spatter among them, which is the
## one a picture draws again larger.
func _shipped_store() -> SaPresetStore:
    var store := _store()
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    return store


# --- One read a preset ---------------------------------------------------------


## Every fact a chooser cell asks of a preset comes off one read, and a read
## answered before is answered again with the file gone.
func test_a_presets_facts_are_one_read() -> void:
    var store := _shipped_store()
    var spatter := store.load_preset("Spatter")
    var before := store.loads
    assert_true(store.learn("Spatter"), "The first ask reads the preset")
    assert_false(store.learn("Spatter"), "and the second does not")
    assert_eq(store.loads, before + 1, "one read")
    DirAccess.remove_absolute(store.dir.path_join("Spatter" + SaPresetStore.EXTENSION))
    var tags: PackedStringArray = spatter.get_meta(SaPresetMeta.TAGS_META)
    tags.sort()
    assert_false(tags.is_empty(), "The Spatter carries tags")
    assert_eq(store.tags_for("Spatter"), tags, "The tags come off the one read")
    assert_eq(String(store.engine_for("Spatter")), str(spatter.get_meta(SaPresetMeta.ENGINE_META)), "and the engine")
    assert_eq(store.about_for("Spatter"), SaPresetMeta.description_of(spatter), "and the sentence")
    assert_eq(store.provenance_for("Spatter"), SaPresetMeta.provenance_line(spatter), "and the provenance")
    assert_false(store.erases("Spatter"), "and whether it erases")
    assert_eq(store.loads, before + 1, "and none of them read it again")
    assert_true(store.erases("Eraser"), "The shipped Eraser erases")


## A write is what makes a preset's facts stale, so a saved preset is read again.
func test_a_write_forgets_what_was_read() -> void:
    var store := _store()
    var settings := StampSettingsScript.new()
    store.save_preset("Rubber", settings, PackedStringArray(["one"]))
    assert_false(store.erases("Rubber"), "A brush that paints does not erase")
    settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    store.save_preset("Rubber", settings, PackedStringArray(["two"]))
    assert_true(store.erases("Rubber"), "Saved as an eraser it does")
    assert_eq(store.tags_for("Rubber"), PackedStringArray(["two"]), "with the tags it was saved with")


# --- A picture a step at a time ----------------------------------------------


## Drawn a step a call, a stroke, a stroke climbing the ladder and a tip are each
## the picture `render` and `render_tip` draw at once.
func test_a_picture_drawn_a_step_a_call_is_the_one_drawn_at_once() -> void:
    var store := _shipped_store()
    for preset_name: String in ["Paint", "Spatter"]:
        var settings := store.load_preset(preset_name)
        var drawing := SaPresetThumbs.Drawing.cached(StateBrushScript, settings, false)
        var calls := _advance_by_steps(drawing)
        assert_true(calls > SaPresetThumbs.STEPS, "'%s' took %d calls, an event a call" % [preset_name, calls])
        var at_once := SaPresetThumbs.render(StateBrushScript, settings)
        assert_eq(drawing.picture.get_data(), at_once.get_data(), "and is the stroke render draws, '%s'" % preset_name)
    var tip_settings := store.load_preset("Paint")
    var tip := SaPresetThumbs.Drawing.cached(StateBrushScript, tip_settings, true)
    assert_true(_advance_by_steps(tip) > 1, "A tip is more than one call")
    var tip_at_once := SaPresetThumbs.render_tip(StateBrushScript, tip_settings)
    assert_eq(tip.picture.get_data(), tip_at_once.get_data(), "and is the tip render_tip draws")


## A picture nobody will finish lets go of its easel at once, rather than when
## the queue holding it is dropped by the engine.
func test_an_abandoned_picture_lets_go_of_its_easel() -> void:
    var store := _shipped_store()
    var drawing := SaPresetThumbs.Drawing.cached(StateBrushScript, store.load_preset("Paint"), false)
    for i in 5:
        drawing.advance(0)
    var easel: SaEasel = drawing._paint._easel
    assert_true(is_instance_valid(easel), "A picture under way holds an easel")
    drawing.abandon()
    assert_false(is_instance_valid(easel), "and abandoned it is freed")
    assert_true(drawing.done and drawing.picture == null, "with no picture")


## The chooser's queue draws a frame's share a call and says what it drew.
func test_the_pictures_queue_draws_a_share_a_call() -> void:
    var store := _shipped_store()
    var pictures := SaBrushPresetPictures.new()
    var drawn: Array[String] = []
    var on_drawn := func(stored_name: String, path: String) -> void:
        drawn.append("%s %s" % [stored_name, FileAccess.file_exists(path)])
    pictures.drawn.connect(on_drawn)
    var names: Array[String] = ["Paint", "Sketch"]
    pictures.queue(names, store, StateBrushScript, {}, false)
    assert_eq(pictures.waiting(), 2, "Two pictures wait")
    assert_true(pictures.draw(0), "A share of no time draws a step")
    assert_true(drawn.is_empty(), "and finishes no picture")
    assert_eq(pictures.waiting(), 2, "so both are still to come, one of them under way")
    var calls := 1
    while pictures.draw(0) and calls < 100000:
        calls += 1
    assert_true(calls < 100000, "The pictures are drawn within a hundred thousand calls")
    var expected: Array[String] = ["Paint true", "Sketch true"]
    assert_eq(drawn, expected, "Each is drawn and kept, in order")
    assert_true(calls > 2 * SaPresetThumbs.STEPS, "a step a call, %d calls" % calls)

    pictures.queue(names, store, StateBrushScript, {}, false)
    pictures.draw(0)
    pictures.drop()
    assert_eq(pictures.waiting(), 0, "Dropped, nothing waits")
    assert_false(pictures.draw(0), "and nothing is drawn")


# --- The scan's reads before the scan -----------------------------------------


## Past its deadline the install writes one preset an ask, and the asks together
## write what one ask without a deadline writes.
func test_the_shipped_presets_are_written_one_an_ask_past_the_deadline() -> void:
    var whole := _store("whole")
    var written := whole.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var sliced := _store()
    var asks := 0
    var each := 0
    while asks <= written:
        each = sliced.install_shipped(StampSettingsScript.new(), ShippedPresetsScript, 0)
        if each == 0:
            break
        asks += 1
        assert_eq(each, 1, "An ask past the deadline writes one")
    assert_eq(asks, written, "%d asks for %d presets" % [asks, written])
    assert_eq(sliced.list_names(), whole.list_names(), "and the same presets")


## The held scan's reads are done a preset a call at no budget, and the scan
## after them reads nothing.
func test_the_scan_prepared_in_slices_reads_nothing_itself() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    var presets := bar.preset_box
    presets.hold_scan()
    var store := bar.preset_store
    store.dir = scratch_dir.path_join("presets")
    for preset_name: String in ["Ink", "Chalk", "Mist"]:
        store.save_preset(preset_name, StampSettingsScript.new())
    bar.target_tool_machine = machine
    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    docker.rebind()

    var loads := store.loads
    var calls := 1
    while not presets.prepare_scan(0) and calls < 10:
        calls += 1
    assert_eq(calls, 3, "Three presets, a call each at no budget")
    assert_eq(store.loads, loads + 3, "each read once")
    loads = store.loads
    presets.scan()
    assert_eq(docker.chooser.visible_names().size(), 3, "The scan lists them")
    assert_eq(store.loads, loads, "and reads none of them again")

    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)


## Advances *drawing* with no budget until it is done, and answers the calls.
func _advance_by_steps(drawing: SaPresetThumbs.Drawing) -> int:
    var calls := 1
    while not drawing.advance(0) and calls < 100000:
        calls += 1
    assert_true(calls < 100000, "A drawing ends within a hundred thousand calls")
    return calls


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for sub: String in DirAccess.get_directories_at(folder):
        _clear(folder.path_join(sub))
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)
