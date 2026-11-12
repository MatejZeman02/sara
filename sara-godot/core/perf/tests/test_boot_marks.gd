## SaBootMarks: a boot phase timed from outside itself as it happens,
## rather than reasoned about after the fact.
##
## Builds a Main and calls `_ready()` on it by hand, the way
## `test_ui_components.gd` already does: `res://tests/run_all.tscn` is the
## scene the gate actually runs, so nothing here boots `Main` unless a test
## does. `GlobalShaderCompiler` and `SaSettings` are autoloads and have already
## run before any suite starts, so their marks are in the table before this
## suite's own `_ready()` call adds the rest.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const MainScript = preload("res://ui/main/main.gd")

## Every mark this suite's own boot is expected to reach. `door_listening`
## needs `--capture` and `document_loaded` needs an opened document, so
## neither belongs here, and `first_frame_after_ready` is written off the
## engine's own next frame rather than synchronously within `_ready()`, so it
## is never asserted present (see the last test below).
##
## The marks sit either side of every autoload's `_init` and
## `_ready`, one where the main scene's load ends, and the four that split
## `modules_registered` to `layout_restored`. `boot_finished` is, the
## last stage's end. The marks `SaBoot` writes, the first frame among them, need
## the main scene, which a suite never runs.
const EXPECTED_MARKS: PackedStringArray = [
    "compiler_init_begin",
    "kernels_begin",
    "kernels_end",
    "spirv_cache_pruned",
    "compiler_init_end",
    "event_bus_init",
    "module_loader_init",
    "settings_init_begin",
    "settings_init_end",
    "settings_apply_init",
    "colors_init",
    "main_scene_loaded",
    "main_init",
    "settings_ready_begin",
    "settings_loaded",
    "settings_apply_ready_begin",
    "settings_apply_ready_end",
    "colors_ready_begin",
    "colors_ready_end",
    "bootstrap_begin",
    "ui_built",
    "modules_registered",
    "router_commands_begin",
    "modules_bootstrapped",
    "blend_favourites_canonical",
    "dockers_menu_built",
    "layout_restored",
    "ready",
    "boot_finished",
]

static var scratch_test_docker_layout_path: String = SaDataRoot.path("test_m4_docker_layout.cfg")


func test_every_mark_this_boot_reaches_is_present_by_name() -> void:
    if FileAccess.file_exists(scratch_test_docker_layout_path):
        DirAccess.remove_absolute(scratch_test_docker_layout_path)
    var main := MainScript.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = scratch_test_docker_layout_path
    var finished: Array[bool] = [false]
    var on_finished := func() -> void: finished[0] = true
    EventBus.boot_finished.connect(on_finished)
    main._ready()
    EventBus.boot_finished.disconnect(on_finished)
    # A `Main` outside a tree has no frame to wait for between its stages, so
    # the whole boot runs inside the one call and says so before it returns.
    assert_true(finished[0], "boot_finished was emitted before _ready() returned")

    for wanted in EXPECTED_MARKS:
        assert_true(SaBootMarks.has_mark(StringName(wanted)), "'%s' was never installed" % wanted)

    if FileAccess.file_exists(scratch_test_docker_layout_path):
        DirAccess.remove_absolute(scratch_test_docker_layout_path)
    main.free()


## The line printed the time since `Main._ready` began, 1.96 s
## on the laptop against a `ready` mark of 5.76 s. It reads the mark now, in
## both console forms, and the suite reads the figure back out of the text.
func test_the_ready_line_prints_the_ready_mark_within_a_millisecond() -> void:
    _boot_once()
    var ready_mark: float = SaBootMarks.table()["marks"][&"ready"]
    var figure := SaBootMarks.ready_line_ms()
    var note := SaBootMarks.summary()

    var human := SaConsole.plain(SaConsole.ready_text(figure, note))
    var found := RegEx.create_from_string("Ready in (\\d+) ms").search(human)
    assert_true(found != null, "The human line carries a figure: %s" % human)
    if found != null:
        var printed := found.get_string(1).to_int()
        assert_true(absf(printed - ready_mark) <= 1.0, "Printed %d ms against a ready mark of %s ms" % [printed, ready_mark])

    var machine := SaConsole.machine_text(SaConsole.KIND_READY, [str(figure), note]).split("\t")
    assert_eq(machine[0], SaConsole.KIND_READY, "The machine line is a ready line")
    assert_true(absf(machine[1].to_int() - ready_mark) <= 1.0, "The machine line's figure is the ready mark")


func test_the_note_splits_the_boot_where_main_begins() -> void:
    _boot_once()
    var t := SaBootMarks.table()
    var marks: Dictionary = t["marks"]
    assert_false(t.has("engine_to_ready_ms"), "The old name, which measured Main._ready alone, is gone")
    assert_true(t.has("bootstrap_to_ready_ms"), "and the span it measured has a name that says so")
    assert_eq(t["engine_to_main_init_ms"], marks[&"main_init"], "The first half is the main_init mark itself")
    assert_true(
        absf(t["engine_to_main_init_ms"] + t["main_init_to_ready_ms"] - marks[&"ready"]) < 0.001,
        "and the two halves add up to the ready mark"
    )
    var note := SaBootMarks.summary()
    assert_true(note.begins_with("engine and autoloads "), "The note leads with the first half: %s" % note)
    assert_true(note.contains("(kernels "), "with the kernels inside it: %s" % note)
    assert_true(note.contains(", main to ready "), "and then the second half: %s" % note)


func _boot_once() -> void:
    if SaBootMarks.has_mark(&"ready"):
        return
    var main := MainScript.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = scratch_test_docker_layout_path
    main._ready()
    if FileAccess.file_exists(scratch_test_docker_layout_path):
        DirAccess.remove_absolute(scratch_test_docker_layout_path)
    main.free()


func test_marks_are_non_decreasing_and_a_repeat_keeps_the_first() -> void:
    var marks: Dictionary = SaBootMarks.table()["marks"]
    var previous_name := ""
    var previous_value := -1.0
    # Dictionary order is insertion order, and every mark is inserted the
    # instant the boot reaches it, so the table itself is the proof.
    for name: StringName in marks:
        var value: float = marks[name]
        assert_true(
            value >= previous_value, "'%s' (%s ms) comes before '%s' (%s ms)" % [name, value, previous_name, previous_value]
        )
        previous_name = name
        previous_value = value

    var ready_before: float = SaBootMarks.table()["marks"].get(&"ready", -1.0)
    SaBootMarks.mark(&"ready")
    var ready_after: float = SaBootMarks.table()["marks"].get(&"ready", -1.0)
    assert_eq(ready_after, ready_before, "A second mark of an installed name keeps the first")


func test_kernels_begin_is_before_kernels_end() -> void:
    var marks: Dictionary = SaBootMarks.table()["marks"]
    assert_true(marks.has("kernels_begin") and marks.has("kernels_end"), "Both kernel marks are present")
    assert_true(marks["kernels_begin"] <= marks["kernels_end"], "kernels_begin is not after kernels_end")
    assert_true(SaBootMarks.table().has("kernels_ms"), "and the pair earns kernels_ms")


## Both counters are process-wide and every suite that compiles a test kernel
## moves one of them, so nothing this test measures in isolation says how many
## the *boot* compiled. What is provable is the accounting itself: recompiling
## one real, already-compiled file has to move the sum by exactly its own
## kernel count, whichever of the two paths it actually took.
func test_hits_plus_compiles_account_for_a_recompile() -> void:
    var hits_before := SaBootMarks.spirv_cache_hits
    var compiles_before := SaBootMarks.spirv_compiles
    # clear_chunk, the one kernel in clear.gmacs, which every composite pass
    # dispatches and which boot has therefore already compiled once.
    GlobalShaderCompiler.compile_compute_shader("res://shaders/compute/clear.gmacs")
    var moved := (SaBootMarks.spirv_cache_hits - hits_before) + (SaBootMarks.spirv_compiles - compiles_before)
    assert_eq(moved, 1, "clear.gmacs declares one kernel, and _compile_spirv took exactly one path for it")


## `first_frame_after_ready` is written off the engine's own next draw, which
## this test cannot `await` without dropping every assertion after it,
## so this proves nothing about whether it
## ever fires. What has to hold is that a table read before it exists reports
## the boot honestly instead of a zero nothing measured.
func test_a_missing_first_frame_mark_is_omitted_not_a_zero() -> void:
    var t := SaBootMarks.table()
    if not (t["marks"] as Dictionary).has("first_frame_after_ready"):
        assert_false(t.has("first_frame_ms"), "No first_frame_ms without the mark behind it")


## Quoted in the unit's record, once, as the test's own contribution to it.
func test_the_table_prints_once_for_the_record() -> void:
    print("SaBootMarks.table(): " + JSON.stringify(SaBootMarks.table()))
