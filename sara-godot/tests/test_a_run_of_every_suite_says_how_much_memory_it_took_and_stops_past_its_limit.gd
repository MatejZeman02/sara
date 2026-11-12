## A run of every suite says how much memory it took, names
## the suites that grew it most, and fails once it passes a limit.
##
## A run can be killed by the out of memory killer with the engine at about
## 10 GB resident, and nothing in the run's output would say which suite had
## grown it. `Memory` in `tests/run_all.gd` reads the
## resident set after each suite, and run_tests.sh hands it the limit.
extends "res://tests/test_framework.gd"

const Runner = preload("res://tests/run_all.gd")


func test_the_resident_set_and_its_peak_are_read_on_linux() -> void:
    if OS.get_name() != "Linux":
        skip("the resident set is read from /proc, which only Linux has")
        return
    var now := Runner.Memory.resident_mib()
    assert_true(now > 0.0, "the run's resident set is read, %.1f MiB" % now)
    assert_true(Runner.Memory.peak_mib() >= now, "the peak is at least what the run holds now")


func test_a_run_under_its_limit_passes_and_reports_its_peak() -> void:
    var memory := Runner.Memory.new(null, 1 << 30)
    assert_true(memory.note("test_a_small_suite", memory.reading()), "a suite under the limit lets the run go on")
    assert_true(memory.within_limit(), "a run under its limit is within it")
    var report := memory.report()
    assert_true(report[0].begins_with("Memory: peak resident "), "the report opens with the peak: %s" % report[0])
    assert_true(report[0].contains("limit %d MiB" % (1 << 30)), "and says the limit")
    assert_true(report[2].ends_with("test_a_small_suite"), "and names the suite: %s" % report[2])


func test_the_report_names_the_suites_that_grew_the_resident_set_most_first() -> void:
    var memory := Runner.Memory.new(null, 0)
    var before := memory.reading()
    # Readings made by hand, so the order does not hang on what the allocator
    # happens to give back.
    for grown: int in 12:
        before["resident"] = memory.reading()["resident"] - grown
        memory.note("test_suite_%02d" % grown, before)
    var report := memory.report()
    assert_eq(report.size(), 2 + Runner.Memory.NAMED, "the peak, a heading and ten suites")
    assert_true(report[2].ends_with("test_suite_11"), "the suite that grew most comes first: %s" % report[2])
    assert_true(report[11].ends_with("test_suite_02"), "and the tenth is the tenth most: %s" % report[11])
    assert_true(report[0].contains("no limit"), "a run with no limit says so")


func test_a_suite_that_takes_the_run_past_its_limit_stops_it_and_is_named() -> void:
    if OS.get_name() != "Linux":
        skip("the resident set is read from /proc, which only Linux has")
        return
    var memory := Runner.Memory.new(null, 1)
    assert_false(memory.note("test_the_suite_that_held_it", memory.reading()), "a suite past the limit stops the run")
    assert_eq(memory.crossed_by, "test_the_suite_that_held_it", "the suite that crossed it is named")
    assert_false(memory.within_limit(), "the run is not within its limit")
    assert_true(memory.report()[-1].contains("after test_the_suite_that_held_it"), "and the report's last line says after which")


func test_run_tests_sh_hands_the_run_its_limit() -> void:
    var script := FileAccess.get_file_as_string("res://run_tests.sh")
    assert_true(script.contains("DEFAULT_TEST_MEMORY_LIMIT_MB="), "run_tests.sh sets a default limit")
    assert_true(script.contains("export SARA_TEST_MEMORY_LIMIT_MB"), "and hands it to the engine")
