## The startup console's two modes.
##
## Human is what a person reads and machine is what a script reads, and the
## rule the two are built to is that they print the same facts. Most of that is
## proved by a capture rather than here, because a primitive prints and GDScript
## cannot capture stdout: `scenarios/console-two-modes.json` takes a log in
## each mode.
##
## What this suite holds is the shape of a machine line and the switch that asks
## for one, which are the two things a caller can get wrong without noticing.
extends "res://tests/test_framework.gd"


## Back to what `run_all.gd` pinned, rather than to "ask the environment": the
## runner holds the human shape for its own report and a suite that left the
## switch open would change the lines `run_tests.sh` parses.
func _restore() -> void:
    SaConsole.machine = 0


## The mode is off unless asked for, and one of the two ways to ask is the
## environment variable, which is how a script starting Sara through a wrapper
## reaches it.
func test_the_machine_mode_is_asked_for_and_never_assumed() -> void:
    var was := OS.get_environment("SARA_CONSOLE")

    OS.set_environment("SARA_CONSOLE", "")
    SaConsole.machine = -1
    assert_false(SaConsole.wants_machine(), "Nothing asked for the machine mode, so it is off")

    OS.set_environment("SARA_CONSOLE", "machine")
    SaConsole.machine = -1
    assert_true(SaConsole.wants_machine(), "and SARA_CONSOLE=machine asks for it")

    OS.set_environment("SARA_CONSOLE", was)
    _restore()


## A machine line is the kind, then a field each, tab separated. No padding, no
## colour, and no empty trailing column for a fact that was not there.
func test_a_machine_line_is_tab_separated_and_plain() -> void:
    var line := SaConsole.machine_text(SaConsole.KIND_FIELD, ["Build", SaConsole.tint("v0.6.0", SaConsole.INFO)])
    assert_eq(line, "field\tBuild\tv0.6.0", "The colour is out and the fields are tabs apart")

    var trimmed := SaConsole.machine_text(SaConsole.KIND_SECTION, ["MODULES", ""])
    assert_eq(trimmed, "section\tMODULES", "A summary that is not there is not a column")

    var kept := SaConsole.machine_text(SaConsole.KIND_ROW, ["paint", "1", "paint"])
    assert_eq(kept, "row\tpaint\t1\tpaint", "and a field between two others stays whatever it is")


## Every line has to survive being read out of `user://logs/godot.log`, which is
## plain text. BBCode is what this file emits and what has to come out, and a
## square bracket that is not BBCode has to stay: a kernel or a module name is
## free to carry one.
func test_only_this_file_s_own_bbcode_is_stripped() -> void:
    assert_eq(SaConsole.plain(SaConsole.bold("SARA", SaConsole.BRAND)), "SARA", "A bold tint comes out clean")
    assert_eq(SaConsole.plain("[i]left alone[/i]"), "[i]left alone[/i]", "and a tag this file never writes is left")
    assert_eq(SaConsole.plain("array[0]"), "array[0]", "as is a bracket that is not a tag at all")


## The logo is ten rows of half blocks, which is the first thing a machine mode
## has to drop. It is dropped by the same call a headless run already used.
func test_the_machine_mode_asks_for_no_banner() -> void:
    SaConsole.machine = 1
    assert_true(SaConsole.wants_machine(), "The mode is on")
    assert_false(SaConsole.wants_banner(), "so there is no logo")
    _restore()


## The glyph carries half its meaning in its colour, which a script cannot see,
## so each one has a word. Every glyph the console prints has to have one or the
## machine line falls back to the character.
func test_every_status_glyph_has_a_word() -> void:
    for glyph: String in ["✓", "✗", "·", "●", "▲"]:
        assert_true(SaConsole.GLYPH_WORDS.has(glyph), "'%s' has a word for a reader with no colour" % glyph)
    var line := SaConsole.machine_text(SaConsole.KIND_ITEM, [SaConsole.GLYPH_WORDS["✗"], "a-module", "no module.gd"])
    assert_eq(line, "item\tfail\ta-module\tno module.gd", "and the word is what a failed module reads as")


## The SHADERS rows dropped the `.gmacs`: every file under
## `shaders/compute/` is one, so the extension is a constant rather than a fact,
## and it was spending six of the eighteen columns the name has.
func test_the_shader_report_names_no_extension() -> void:
    var source := FileAccess.get_file_as_string("res://core/custom-shader/compiler/sa_shader_index.gd")
    assert_false(source.contains('+ ".gmacs"'), "Nothing in the shader report appends the extension to a row")
    assert_true(source.contains("SaConsole.row("), "and the row goes through SaConsole, which is what knows the mode")


## The mark is read from `assets/sa_logo.json` and not held in a script, so a
## missing or damaged asset would print a banner with no mark and nothing else
## would say so. Sixteen rows of at most `WIDTH` cells, every colour tag closed.
func test_the_logo_reads_from_its_asset() -> void:
    var rows := SaLogo.lines()
    assert_eq(rows.size(), 16, "The mark has sixteen rows")
    var tags := RegEx.create_from_string("\\[/?(?:color|bgcolor)(?:=#[0-9a-f]{6})?\\]")
    var widest := 0
    for row: String in rows:
        var shown := tags.sub(row, "", true)
        widest = maxi(widest, shown.length())
        assert_eq(row.count("[color="), row.count("[/color]"), "Every colour tag of a row is closed")
        assert_eq(row.count("[bgcolor="), row.count("[/bgcolor]"), "and so is every background")
    assert_eq(widest, SaLogo.WIDTH, "The widest row is as wide as the mark says")
    assert_true(rows[0].contains("[color=#e9f650]▄[/color]"), "and the top of it is the one the terminal has always shown")
