## The presets chooser builds its cells a share a frame.
##
## The pictures and the store's reads are sliced, and the scan's
## own frame must be too: building the Brush's fifty-two cells in the call that
## bound the chooser took 29 to 48 ms, and the first brush was applied in that frame
## as well. A grid bound by the boot's scan stands a control of a cell's size
## in for every cell and builds them `SaBrushPresetCells.SLICE_USEC` a frame, the
## ones in sight first, and the first brush has a frame of its own before it.
## The frames themselves are the scenario's,
## `the-frames-after-a-cold-start-s-ready-come-at-the-display-s-rate`.
extends "res://tests/test_framework.gd"

const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The bar's scan applies a brush to a tool machine on a real surface.
const REQUIRES_GPU := true

## As many presets as the Brush's shelf holds.
const COUNT: int = 52

static var scratch_dir: String = SaDataRoot.path("test_p10_cells_in_shares")

var _slots_before: Array = []


func before_each() -> void:
    _clear(scratch_dir)
    _slots_before = SaSettings.brush_slots.duplicate()


func after_each() -> void:
    SaSettings.brush_slots = _slots_before
    _clear(scratch_dir)


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for sub: String in DirAccess.get_directories_at(folder):
        _clear(folder.path_join(sub))
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)


## A store of `COUNT` presets, "Preset 01" up, which sort in the order they are
## numbered.
func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir.path_join("presets")
    for i in COUNT:
        store.save_preset("Preset %02d" % (i + 1), BrushSettingsScript.new())
    return store


## A bare chooser over *store*, building in shares when *shares* is set, with
## *loaded* naming the preset the brush is on in its first entry.
func _chooser(store: SaPresetStore, shares: bool, loaded: Array = [""]) -> SaBrushPresetsChooser:
    var chooser := SaBrushPresetsChooser.new()
    chooser.in_shares = shares
    chooser.bind_store(
        store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new(), func() -> String: return str(loaded[0])
    )
    return chooser


func _building(chooser: SaBrushPresetsChooser) -> int:
    return int(chooser.chooser_report()["building"])


## The grid's children by name, in the grid's order.
func _children(chooser: SaBrushPresetsChooser) -> Array[String]:
    var names: Array[String] = []
    for child in chooser.grid.get_children():
        names.append(String(child.name))
    return names


func _count_prefixed(chooser: SaBrushPresetsChooser, prefix: String) -> int:
    var found := 0
    for child_name: String in _children(chooser):
        if child_name.begins_with(prefix):
            found += 1
    return found


func _cell(chooser: SaBrushPresetsChooser, stored_name: String) -> Node:
    return chooser.grid.get_node_or_null("Cell_" + stored_name.validate_node_name())


## "Fifty-two presets are built over several frames with none past its budget",
## held exactly on a clock this suite turns: each cell costs a fixed time, and no
## share spends more than `SLICE_USEC`, since it stops before the cell that would
## take it past.
func test_fifty_two_presets_are_built_over_several_frames_with_none_past_its_budget() -> void:
    var store := _store()
    var names: Array[String] = []
    names.assign(store.list_names())
    for cell_usec: int in [1500, 900, 4000]:
        var ticks: Array[int] = [0]
        var clock := func() -> int:
            ticks[0] += cell_usec
            return ticks[0]
        var grid := GridContainer.new()
        var stars := SaBrushPresetStars.new()
        stars.begin_build(store)
        var chosen := func(_n: String) -> void: pass
        var menu := func(_n: String, _b: Button) -> void: pass
        var cells := SaBrushPresetCells.new(grid, stars, chosen, menu, clock)
        cells.lay_out(names, store, StateBrushScript, {}, 48, false, "", Vector2(60, 30), false)
        assert_eq(int(cells.report()["building"]), COUNT, "The lay-out builds no cell (%d us a cell)" % cell_usec)
        var shares := 0
        var longest := 0
        var most := 0
        while int(cells.report()["building"]) > 0 and shares < COUNT * 2:
            var before := int(cells.report()["building"])
            var started := ticks[0]
            cells.build(SaBrushPresetCells.SLICE_USEC)
            # The clock is read once as the share starts and once after each
            # cell, so what the share spent is what it moved the clock less
            # that first read.
            longest = maxi(longest, ticks[0] - started - cell_usec)
            most = maxi(most, before - int(cells.report()["building"]))
            shares += 1
        assert_eq(int(cells.report()["building"]), 0, "Every cell is built (%d us a cell)" % cell_usec)
        # As many cells as fit whole in the budget, and one when none does.
        @warning_ignore("integer_division")
        var each := maxi(1, SaBrushPresetCells.SLICE_USEC / cell_usec)
        @warning_ignore("integer_division")
        var wanted := (COUNT + each - 1) / each
        assert_eq(most, each, "a share builds %d cells of %d us" % [each, cell_usec])
        assert_eq(shares, wanted, "over %d frames" % wanted)
        assert_true(longest <= SaBrushPresetCells.SLICE_USEC, "and none spends past its 4 ms: %d us" % longest)
        # The Starred toggle a chooser puts on its top row, which has no row here.
        stars.filter.free()
        grid.free()


## The same on the real clock, for the chooser the docker holds: the bind builds
## none, a share of nothing builds one, and a frame's share is the budget and at
## most a cell slower than every one before it in that frame, the slowest of the
## fifty-two built one by one, with 2 ms for a machine other runs share.
func test_on_the_real_clock_a_frame_is_one_share() -> void:
    var store := _store()
    var one_by_one := _chooser(store, true)
    var slowest := 0
    var calls := 0
    while _building(one_by_one) > 0 and calls < COUNT * 2:
        var before := _building(one_by_one)
        var started := Time.get_ticks_usec()
        one_by_one.cells.build(0)
        slowest = maxi(slowest, Time.get_ticks_usec() - started)
        assert_eq(_building(one_by_one), before - 1, "A share of nothing builds one cell")
        calls += 1
    assert_eq(calls, COUNT, "so the fifty-two take fifty-two of them")
    one_by_one.free()

    var chooser := _chooser(store, true)
    assert_eq(_building(chooser), COUNT, "The bind builds no cell")
    assert_eq(_count_prefixed(chooser, "Waiting_"), COUNT, "and stands one in for each")
    var frames := 0
    var longest := 0
    while _building(chooser) > 0 and frames < COUNT * 2:
        var started := Time.get_ticks_usec()
        chooser._process(0.0)
        longest = maxi(longest, Time.get_ticks_usec() - started)
        frames += 1
    assert_eq(_building(chooser), 0, "Every cell is built in the end")
    assert_true(frames > 1, "over more than one frame (%d)" % frames)
    var limit := SaBrushPresetCells.SLICE_USEC + slowest + 2000
    assert_true(longest <= limit, "and no frame's share past the budget and one slow cell: %d us of %d" % [longest, limit])
    chooser.free()


## "Every cell built in the end in order": the grid a chooser builds in shares
## is the grid one builds at once, a picture and a name to every cell.
func test_every_cell_is_built_in_the_end_in_order() -> void:
    var store := _store()
    var at_once := _chooser(store, false)
    var shares := _chooser(store, true)
    var frames := 0
    while _building(shares) > 0 and frames < COUNT * 2:
        shares._process(0.0)
        frames += 1
    assert_eq(_building(shares), 0, "The cells are built within %d frames" % (COUNT * 2))
    assert_eq(_count_prefixed(shares, "Waiting_"), 0, "No stand-in is left")
    assert_eq(_children(shares), _children(at_once), "and the cells are the ones built at once, in their order")
    var names := shares.visible_names()
    assert_eq(names.size(), COUNT, "fifty-two of them")
    for at in names.size():
        var cell := shares.grid.get_child(at)
        assert_not_null(cell.get_node_or_null("Icon"), "'%s' carries its picture's button" % names[at])
        var label := cell.get_node_or_null("Name") as Label
        assert_eq(label.text if label != null else "", names[at], "and its name")
    at_once.free()
    shares.free()


## "The ones in sight first": with the grid scrolled four rows down, the first
## cell built is the first of the fifth row and the rows above still wait.
func test_the_cells_in_sight_are_built_first() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var scroll := ScrollContainer.new()
    scroll.size = Vector2(300, 200)
    host.add_child(scroll)
    var chooser := SaBrushPresetsChooser.new()
    chooser.in_shares = true
    scroll.add_child(chooser)
    chooser.bind_store(_store(), StateBrushScript, func() -> Resource: return BrushSettingsScript.new())

    var columns := chooser.grid.columns
    var stand_in := chooser.grid.get_child(0) as Control
    var pitch := stand_in.custom_minimum_size.y + float(chooser.grid.get_theme_constant("v_separation"))
    var row := 4
    assert_true(COUNT > (row + 1) * columns, "The grid has a fifth row (%d columns)" % columns)
    # Where the scroll would put it, which is a sort the frame this suite never
    # runs would do.
    chooser.position.y = -(row * pitch + 1.0)
    chooser.cells.build(0)
    assert_true(String(chooser.grid.get_child(row * columns).name).begins_with("Cell_"), "The first cell in sight is built")
    assert_true(String(chooser.grid.get_child(0).name).begins_with("Waiting_"), "and the first of the grid still waits")
    assert_eq(_building(chooser), COUNT - 1, "one cell built")

    EventBus.remove_child(host)
    host.free()


## "A search typed while they build answering from the cells there are": the
## cells already built that match stay the same cells at their new places, and
## the rest of the matches stand in until a share builds them.
func test_a_search_typed_while_they_build_answers_from_the_cells_there_are() -> void:
    var chooser := _chooser(_store(), true)
    for i in 12:
        chooser.cells.build(0)
    assert_eq(_building(chooser), COUNT - 12, "Twelve cells are built")
    var built := {}
    for i in 12:
        var stored_name := "Preset %02d" % (i + 1)
        built[stored_name] = _cell(chooser, stored_name)
        assert_not_null(built[stored_name], "'%s' among them" % stored_name)

    ControlWalker.move(chooser.search_field, "1")
    var wanted: Array[String] = ["Preset 01"]
    for i in range(10, 20):
        wanted.append("Preset %d" % i)
    wanted.append_array(["Preset 21", "Preset 31", "Preset 41", "Preset 51"] as Array[String])
    assert_eq(chooser.visible_names(), wanted, "The search answers at once with the fifteen names holding a 1")
    assert_eq(chooser.grid.get_child_count(), wanted.size(), "and the grid holds fifteen")
    for stored_name: String in ["Preset 01", "Preset 10", "Preset 11", "Preset 12"]:
        var cell := _cell(chooser, stored_name)
        assert_true(cell == built[stored_name], "'%s' is the cell built before the search" % stored_name)
        assert_eq(cell.get_index() if cell != null else -1, wanted.find(stored_name), "at its place in the answer")
    assert_eq(_building(chooser), wanted.size() - 4, "The eleven matches never built still wait")
    assert_eq(_count_prefixed(chooser, "Waiting_"), wanted.size() - 4, "each a stand-in")

    chooser.cells.build(-1)
    var cells: Array[String] = []
    for stored_name: String in wanted:
        cells.append("Cell_" + stored_name.validate_node_name())
    assert_eq(_children(chooser), cells, "and in the end every match is a cell, in order")
    chooser.free()


## A pick builds two cells again, the one losing the mark and the one taking
## it, where it would build all fifty-two.
func test_a_pick_builds_only_the_two_cells_the_mark_moves_between() -> void:
    var loaded: Array = ["Preset 05"]
    var chooser := _chooser(_store(), false, loaded)
    assert_eq(String(chooser.chooser_report()["marked"]), "Preset 05", "Preset 05 is marked")
    var before := {}
    for child in chooser.grid.get_children():
        before[child.name] = child
    loaded[0] = "Preset 20"
    chooser.refresh()
    assert_eq(String(chooser.chooser_report()["marked"]), "Preset 20", "The pick moves the mark")
    var built_again: Array[String] = []
    for child in chooser.grid.get_children():
        if before.get(child.name) != child:
            built_again.append(String(child.name))
    assert_eq(built_again, ["Cell_Preset 05", "Cell_Preset 20"] as Array[String], "and builds those two cells alone")
    chooser.free()


## "The first brush is applied in a frame of its own": the boot's sliced scan
## picks it in the frame after its reads, with the list still held and the
## docker's grid unbound, and binds the grid in shares the frame after.
func test_the_first_brush_is_applied_in_a_frame_of_its_own() -> void:
    SaSettings.brush_slots = SaSettingsBrushSlots.factory()
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
    bar.preset_store.dir = scratch_dir.path_join("shelf")
    bar.preset_store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    bar.target_tool_machine = machine
    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    docker.rebind()

    # Each call is the frame `scan_in_slices` hooks it to, which this suite never
    # runs.
    presets.scan_in_slices()
    var frames := 1
    while presets.selected_preset.is_empty() and presets.scan_held and frames < 500:
        presets._scan_a_slice()
        frames += 1
    var first := SaSettingsBrushSlots.FACTORY[0]
    assert_eq(presets.selected_preset, first, "The sliced scan loads slot 1's preset")
    assert_true(presets.scan_held, "in a frame before the scan")
    assert_null(docker.chooser.store, "with the docker's grid still unbound")
    assert_eq(docker.chooser.grid.get_child_count(), 0, "and not a cell built")

    presets._scan_a_slice()
    assert_false(presets.scan_held, "The next frame scans")
    assert_true(docker.chooser.in_shares, "and the grid it binds builds in shares")
    assert_true(_building(docker.chooser) > 0, "so the frame builds no cell")
    assert_eq(String(docker.chooser.chooser_report()["marked"]), first, "and marks the preset in hand")
    var tree := Engine.get_main_loop() as SceneTree
    assert_false(tree.process_frame.is_connected(presets._scan_a_slice), "The scan is done with the frames")
    docker.chooser.cells.build(-1)
    assert_eq(_building(docker.chooser), 0, "and the cells are built")

    if tree.process_frame.is_connected(presets._scan_a_slice):
        tree.process_frame.disconnect(presets._scan_a_slice)
    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)
