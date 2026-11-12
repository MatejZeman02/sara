## A blend mode naming a kernel its shader lacks is reported where the painter
## sees it at boot.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `Main._bootstrap_modules` has asked `SaRegistries.validate()` since the
## module API landed, and sent each answer to `push_error`, a terminal line. It
## goes through `SaProblems.report` now, which keeps the line for the problems
## window the main window attaches. What is here is that door, driven with a
## registry the way the registry suite builds one, because the boot itself needs a `Main`
## in a tree. The launch is the scenario's.
extends "res://tests/test_framework.gd"

## `validate()` asks the shader compiler which kernels a shader has.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _was_announcing: bool = true
var _had_sink: bool = false


func before_each() -> void:
    _was_announcing = SaProblems.announce
    _had_sink = SaProblems.has_sink()
    # Provoked on purpose, so the transcript shows the assertion and not the
    # alarm. No sink in a suite, so a report lands in `pending` where a test can
    # read it.
    SaProblems.announce = false
    SaProblems.pending = PackedStringArray()


func after_each() -> void:
    SaProblems.announce = _was_announcing
    SaProblems.pending = PackedStringArray()


## A mode naming `hardmix` where the shader's kernel is `hard_mix` reaches
## the problems surface as a fault with the shader in the line.
##
## The refusal comes one step early: the registry turns the
## descriptor down as it arrives rather than keeping it for `validate()` to
## report, so this is the same fault at the door it now comes from and
## `validate()` has nothing left to say about it.
func test_a_mode_naming_a_missing_kernel_is_reported_as_a_fault() -> void:
    if _had_sink:
        return
    var registries := Fixtures.make_registries()
    var typo := SaBlendModeDescriptor.create(&"d8_hard_mix_typo", "hardmix", "blend-kernel-fixture/kept_hard_mix")
    assert_false(registries.blend_modes.register(typo, &"d8_test"), "the registry refuses the descriptor")
    assert_false(registries.blend_modes.has(&"d8_hard_mix_typo"), "so no layer can name a mode that is not there")

    var problems := Main.report_registry_problems(registries)

    assert_eq(problems, [] as Array[String], "and validation has nothing left to report")
    assert_eq(SaProblems.pending.size(), 1, "the line registration wrote is the one kept for the window")
    if SaProblems.pending.size() == 1:
        var line := SaProblems.pending[0]
        assert_true(line.begins_with("SaBlendModeRegistry: "), "under the registry's own name")
        assert_true(line.contains("hardmix"), "naming the kernel it asked for")
        assert_true(line.contains("blend-kernel-fixture/kept_hard_mix"), "and the shader it looked in")


## The shipped registry reports nothing, so a painter with no broken module sees
## no window at boot.
func test_the_shipped_registry_reports_nothing() -> void:
    if _had_sink:
        return
    var registries := Fixtures.make_registries()

    var problems := Main.report_registry_problems(registries)

    assert_eq(problems, [] as Array[String], "every built-in mode and layer type resolves")
    assert_eq(SaProblems.pending.size(), 0, "and nothing is kept for the window")


## No registries is no report rather than a crash, for a boot that failed before
## the registries existed.
func test_no_registries_reports_nothing() -> void:
    assert_eq(Main.report_registry_problems(null), [] as Array[String], "nothing to validate")
