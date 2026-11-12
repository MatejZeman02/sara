## A lab computer's first two launches read "engine and
## autoloads 24531 ms" with every kernel cached, and the line named nothing of
## the other twenty seconds. The ready line now names the engine's own part and
## every span over `SaBootMarks.NAMED_SPAN_USEC` by its marks, and a boot with
## nothing over it reads as the line always did.
##
## The marks here are set at known times through `summary_of`, so nothing in
## this suite reads the boot the process itself went through.
extends "res://tests/test_framework.gd"

const MS := 1000


func test_a_slow_cold_start_names_the_engine_and_every_span_over_the_threshold() -> void:
    var marks: Dictionary[StringName, int] = {
        &"run_log_init": 18000 * MS,
        &"compiler_init_begin": 18010 * MS,
        &"compiler_init_end": 18020 * MS,
        &"event_bus_init": 18030 * MS,
        &"settings_init_begin": 18040 * MS,
        &"settings_init_end": 18900 * MS,
        &"colors_init": 18950 * MS,
        &"boot_scene_ready": 19000 * MS,
        &"kernels_begin": 19100 * MS,
        &"first_frame": 19500 * MS,
        &"kernels_end": 22000 * MS,
        &"main_script_loaded": 23500 * MS,
        &"main_init": 24000 * MS,
        &"ready": 33000 * MS,
    }
    var note := SaBootMarks.summary_of(marks, {&"base": 300 * MS}, 211, 0)
    assert_eq(
        note,
        (
            "engine and autoloads 24000 ms (kernels 2900 ms, 211 cached, 0 compiled, engine 18000 ms, "
            + "settings_init_begin to settings_init_end 860 ms, kernels_end to main_script_loaded 1500 ms), "
            + "main to ready 9000 ms (modules 300 ms)"
        ),
        "The engine and each span over half a second are named, one of half a second and the kernels' frame are not"
    )


func test_a_span_at_the_threshold_is_not_named_and_one_just_over_it_is() -> void:
    var marks: Dictionary[StringName, int] = {
        &"run_log_init": SaBootMarks.NAMED_SPAN_USEC,
        &"event_bus_init": SaBootMarks.NAMED_SPAN_USEC * 2,
        &"main_init": SaBootMarks.NAMED_SPAN_USEC * 3 + 1,
    }
    var note := SaBootMarks.summary_of(marks, {}, 0, 0)
    assert_eq(note, "engine and autoloads 1500 ms (event_bus_init to main_init 500 ms)", note)


func test_a_fast_boot_prints_the_line_as_it_read_before() -> void:
    var marks: Dictionary[StringName, int] = {
        &"run_log_init": 400 * MS,
        &"compiler_init_begin": 410 * MS,
        &"kernels_begin": 450 * MS,
        &"kernels_end": 2100 * MS,
        &"compiler_init_end": 2110 * MS,
        &"event_bus_init": 2120 * MS,
        &"boot_scene_ready": 2500 * MS,
        &"main_init": 2900 * MS,
        &"bootstrap_begin": 3000 * MS,
        &"ready": 4400 * MS,
    }
    var note := SaBootMarks.summary_of(marks, {&"base": 7 * MS}, 226, 26)
    assert_eq(
        note,
        "engine and autoloads 2900 ms (kernels 1650 ms, 226 cached, 26 compiled), main to ready 1500 ms (modules 7 ms)",
        "Nothing over the threshold, so the line is the one it always was"
    )


func test_marks_after_main_init_are_never_named_inside_the_first_half() -> void:
    var marks: Dictionary[StringName, int] = {
        &"run_log_init": 100 * MS,
        &"main_init": 200 * MS,
        &"bootstrap_begin": 5000 * MS,
        &"ready": 6000 * MS,
    }
    assert_eq(
        SaBootMarks.summary_of(marks, {}, 0, 0),
        "engine and autoloads 200 ms, main to ready 5800 ms",
        "The second half's spans belong to the second half"
    )


func test_the_live_boot_reads_through_the_same_line() -> void:
    assert_eq(
        SaBootMarks.summary(),
        SaBootMarks.summary_of(
            SaBootMarks._marks, SaBootMarks.module_usec, SaBootMarks.spirv_cache_hits, SaBootMarks.spirv_compiles
        ),
        "summary is summary_of over this process's own marks"
    )
    assert_true(SaBootMarks.has_mark(SaBootMarks.SARA_BEGINS), "The first autoload marked where Sara's code begins")
