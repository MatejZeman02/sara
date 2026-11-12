## Base class for unit and integration tests.
extends RefCounted

var passed_count: int = 0
var failed_count: int = 0
var failure_messages: Array[String] = []
var current_test_name: String = ""
var duration_ms: int = 0
## Why a part of this suite did not run on this machine, one reason each, which
## the suite's own line prints so a part left out never reads as a pass.
var skip_reasons: Array[String] = []


## Records that what follows in a case cannot hold on this machine, and why.
## The case returns after calling it, and the reason goes on the suite's line.
func skip(reason: String) -> void:
    if not skip_reasons.has(reason):
        skip_reasons.append(reason)


func assert_true(condition: bool, message: String = "") -> void:
    if condition:
        passed_count += 1
    else:
        failed_count += 1
        var msg: String = "[FAIL] %s: %s" % [current_test_name, message if not message.is_empty() else "Expected true, got false"]
        failure_messages.append(msg)


func assert_false(condition: bool, message: String = "") -> void:
    assert_true(not condition, message if not message.is_empty() else "Expected false, got true")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
    if actual == expected:
        passed_count += 1
    else:
        failed_count += 1
        var msg: String = "[FAIL] %s: Expected '%s', got '%s'. %s" % [current_test_name, str(expected), str(actual), message]
        failure_messages.append(msg)


func assert_almost_eq(actual: float, expected: float, epsilon: float = 0.0001, message: String = "") -> void:
    if abs(actual - expected) <= epsilon:
        passed_count += 1
    else:
        failed_count += 1
        var msg: String = (
            "[FAIL] %s: Expected %.5f (± %.5f), got %.5f. %s" % [current_test_name, expected, epsilon, actual, message]
        )
        failure_messages.append(msg)


func assert_not_null(val: Variant, message: String = "") -> void:
    assert_true(val != null, message if not message.is_empty() else "Expected non-null value")


func assert_null(val: Variant, message: String = "") -> void:
    assert_true(val == null, message if not message.is_empty() else "Expected null value")


## Run all methods starting with 'test_'
## Runs every test_* method and prints one line for the suite.
##
## One line per suite rather than per test: a per-test line pushed the summary
## hundreds of lines up the scrollback, and the individual names only matter when
## something fails - at which point they are printed with their failure.
##
## **A case that waits is waited for.** A case with an `await` in it hands its
## caller a function state at the first one and runs the rest on a later frame.
## Called without an `await` here, the rest of such a case, its assertions and
## its teardown, ran after the whole run or never: a suite's hosts stayed
## under `EventBus` for every suite after them, its listener stayed connected,
## and an assertion after the wait could fail without the run hearing of it. An `await` on a case that never
## waits returns at once, so
## a run whose cases do not wait passes no frame it did not pass before.
func run_all_tests(suite_name: String) -> bool:
    var started := Time.get_ticks_msec()

    for m in get_method_list():
        var m_name: String = m["name"]
        if m_name.begins_with("test_"):
            current_test_name = m_name
            if has_method("before_each"):
                await call("before_each")
            await call(m_name)
            if has_method("after_each"):
                await call("after_each")
            # A save a test left running in the background ends here, so the
            # next test never finds it running and its autosave never skips.
            SaSadFile.finish_saves()

    duration_ms = Time.get_ticks_msec() - started
    _print_suite_line(suite_name)
    return failed_count == 0


func _print_suite_line(suite_name: String) -> void:
    var ok := failed_count == 0
    var total := passed_count + failed_count
    var line := (
        "   %s  %s %s %s %s"
        % [
            SaConsole.tint("✓" if ok else "✗", SaConsole.OK if ok else SaConsole.ERR),
            SaConsole.tint(suite_name.rpad(30), SaConsole.HEAD if ok else SaConsole.ERR),
            SaConsole.tint(str(total).lpad(3), SaConsole.DIM),
            SaConsole.tint("asrt", SaConsole.DIM),
            SaConsole.tint(("%dms" % duration_ms).lpad(7), SaConsole.DIM),
        ]
    )
    if not ok:
        line += "   " + SaConsole.tint("%d failed" % failed_count, SaConsole.ERR)
    if not skip_reasons.is_empty():
        line += "   " + SaConsole.tint("○ skipped here: %s" % " · ".join(skip_reasons), SaConsole.SKIP)
    print_rich(line)

    # Failures print under their suite, indented, so the context is obvious
    # without scrolling back to find which suite they belonged to.
    for msg in failure_messages:
        print_rich("        %s %s" % [SaConsole.tint("└", SaConsole.ERR), SaConsole.tint(msg, SaConsole.DIM)])
