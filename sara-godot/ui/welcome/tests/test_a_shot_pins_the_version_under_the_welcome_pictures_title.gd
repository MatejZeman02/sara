## The version under the Welcome picture's title, and the minor
## whose picture is picked by it, are in a record set of the window, so a debug
## build takes them from `SARA_WELCOME_VERSION` when it is set, and a run without
## the variable shows the running version as it always did.
##
## `scripts/sara_shot.py` sets the variable for every shot, and
## `scripts/check_shots.py the-welcome-window-opens-on-a-painted-picture` is
## what finds a version bump leaving the set matching.
extends "res://tests/test_framework.gd"


func test_with_the_variable_unset_the_label_is_the_running_version() -> void:
    var before := OS.get_environment(WelcomePicture.VERSION_VARIABLE)
    OS.unset_environment(WelcomePicture.VERSION_VARIABLE)
    var band := WelcomePicture.new()
    var running := str(ProjectSettings.get_setting("application/config/version"))
    assert_eq(band.version_line.text, running, "the label says what project.godot says")
    band.free()
    if not before.is_empty():
        OS.set_environment(WelcomePicture.VERSION_VARIABLE, before)


func test_with_the_variable_set_the_label_and_the_pick_follow_it() -> void:
    var before := OS.get_environment(WelcomePicture.VERSION_VARIABLE)
    OS.set_environment(WelcomePicture.VERSION_VARIABLE, "0.18.4")
    var band := WelcomePicture.new()
    assert_eq(band.version_line.text, "0.18.4", "the label says the version the variable names")
    assert_eq(band.key, "0.18", "and the picture is that minor's")
    band.free()
    if before.is_empty():
        OS.unset_environment(WelcomePicture.VERSION_VARIABLE)
    else:
        OS.set_environment(WelcomePicture.VERSION_VARIABLE, before)


func test_a_version_handed_to_the_constructor_wins_over_the_variable() -> void:
    var before := OS.get_environment(WelcomePicture.VERSION_VARIABLE)
    OS.set_environment(WelcomePicture.VERSION_VARIABLE, "0.18.4")
    var band := WelcomePicture.new("0.99.3")
    assert_eq(band.version_line.text, "0.99.3", "a suite's own version is not overridden")
    band.free()
    if before.is_empty():
        OS.unset_environment(WelcomePicture.VERSION_VARIABLE)
    else:
        OS.set_environment(WelcomePicture.VERSION_VARIABLE, before)
