## Android's back gesture, a swipe in from a tablet's edge, never quits Sara.
##
## The engine quits on a go-back request unless told otherwise, and that quit
## passes by Sara's own: no question about unsaved work, no teardown of Sara's
## workers. On the tablet the engine's teardown then freed a worker's script
## object after the script language was gone, and crashed in its render thread
## inside `GDScriptInstance::~GDScriptInstance`. The setting is the project's
## rather than a line in Main, so it holds from the first frame, while the
## welcome window's workers are busiest. The gesture and the crash are proved
## against the APK in the emulator, in the unit's record.
extends "res://tests/test_framework.gd"


func test_the_project_says_a_go_back_request_does_not_quit() -> void:
    var setting: Variant = ProjectSettings.get_setting("application/config/quit_on_go_back", true)
    assert_eq(setting, false, "application/config/quit_on_go_back is off in project.godot")


func test_the_running_tree_took_the_setting() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "the suites run in a scene tree")
    assert_false(tree.quit_on_go_back, "the tree the engine made read the setting before the first frame")
