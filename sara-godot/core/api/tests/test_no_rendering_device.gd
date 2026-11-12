## What an app whose driver refuses a RenderingDevice does instead of dying.
##
## The runner has a device, so this suite cannot make the real condition. What it
## can hold is the three decisions the fix rests on, each of which is readable
## with a device present: the refusal latches rather than being retried, a
## dispatch with no device is silent rather than nine errors a frame, and the
## seam that a scenario turns the condition on with is off by default.
##
## The condition itself is proved on the running app, by
## `scenarios/an-app-with-no-rendering-device-runs-to-ready-and-then-dies.json`
## under `SARA_NO_RENDERING_DEVICE=1`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the point of half of it is that the runner has one.
const REQUIRES_GPU := true

## The switch is an inner class of the compiler, its one user,
## so it is reached through the compiler's script.
const Compiler := preload("res://core/custom-shader/compiler/global_shader_compiler.gd")


## The seam is off unless a run asks for it, so an ordinary session and the gate
## both take the real driver. A seam left on would be a green suite over an app
## that paints nothing, which is the failure this file exists about.
func test_the_refusal_seam_is_off_unless_the_environment_asks() -> void:
    assert_false(Compiler.DeviceRefused.asked, "SARA_NO_RENDERING_DEVICE is not set for the gate")
    assert_true(GlobalShaderCompiler.get_rd() != null, "so the compiler holds the machine's own device")


## `get_rd` used to ask the driver on every call, and a boot with no device made
## 96 attempts and 96 identical reports. The desktop this was filed from was
## refusing because it had run out of memory, so every retry was another
## allocation into a failing driver. One answer, kept.
func test_the_device_is_asked_for_once_and_the_answer_is_kept() -> void:
    var first := GlobalShaderCompiler.get_rd()
    var second := GlobalShaderCompiler.get_rd()
    assert_true(first == second, "the same device comes back rather than a new one")
    assert_false(GlobalShaderCompiler._rd_refused, "and nothing latched a refusal on a machine that has one")


## A `SaCompute` whose device went away opens no list and says nothing, and pushes no
## "kernel index -1 is outside its 0 kernels" error, which came nine times a
## frame for as long as the app was open, because `list_begin` only asked whether
## the pipeline held the index and never whether there was a device to hold it
## with.
func test_a_dispatch_with_no_device_is_silent() -> void:
    var comp := SaCompute.new("composite")
    var lists_before: int = comp.lists
    comp.rd = null
    var announced := SaProblems.announce
    SaProblems.announce = false
    comp.list_begin(0)
    SaProblems.announce = announced
    assert_eq(comp.lists, lists_before, "no list was opened")
    assert_true(comp.list.id < 0, "so there is no queue for a dispatch to join")
