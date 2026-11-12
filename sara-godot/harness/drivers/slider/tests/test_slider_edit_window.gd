## `slider_edit` can name the window its slider is in.
##
## The Brush Editor builds its rows with the Tool Options docker's own
## `ToolOptionControls`, so both windows carry a `HardnessSlider`, and the
## docker is in the tree first. A bare name found the docker's every time, so
## no scenario could drag a slider in the editor. `SaSliderEdit.find_named` is
## the lookup `capture_edit` uses, and it takes any node, so the two windows here
## are built detached under a plain node: a `Window` in a headless tree maps a
## real OS window and the run blocks. What the drag does in
## the running editor is `scenarios/slider-edit-cannot-reach-a-brush-editor-slider.json`.
extends "res://tests/test_framework.gd"


## A root holding two windows named the way the app names them, each with a
## slider of the same name, the docker's first.
func _two_windows() -> Dictionary:
    var root := Node.new()
    root.name = "Root"
    var docker := Window.new()
    docker.name = "ToolOptionsDocker"
    var docker_slider := FactorSlider.new()
    docker_slider.name = "HardnessSlider"
    docker.add_child(docker_slider)
    root.add_child(docker)
    var editor := Window.new()
    editor.name = "SaBrushEditorWindow"
    var editor_slider := FactorSlider.new()
    editor_slider.name = "HardnessSlider"
    editor.add_child(editor_slider)
    root.add_child(editor)
    return {"root": root, "docker": docker_slider, "editor": editor_slider}


func test_a_bare_name_finds_the_first_window_as_it_always_did() -> void:
    var built := _two_windows()
    var found := SaSliderEdit.find_named(built["root"], "HardnessSlider")
    assert_true(found == built["docker"], "With no window named, the docker's slider is the one found, as ever")
    (built["root"] as Node).free()


func test_naming_the_editors_window_finds_the_editors_slider() -> void:
    var built := _two_windows()
    var found := SaSliderEdit.find_named(built["root"], "HardnessSlider", "SaBrushEditorWindow")
    assert_true(found == built["editor"], "Naming the Brush Editor's window finds its own Hardness slider")
    assert_false(found == built["docker"], "and not the docker's")
    (built["root"] as Node).free()


func test_naming_the_dockers_window_still_finds_the_dockers_slider() -> void:
    var built := _two_windows()
    var found := SaSliderEdit.find_named(built["root"], "HardnessSlider", "ToolOptionsDocker")
    assert_true(found == built["docker"], "Naming the docker's window finds the docker's slider")
    (built["root"] as Node).free()


func test_a_window_that_is_not_there_finds_nothing_rather_than_falling_back() -> void:
    var built := _two_windows()
    var found := SaSliderEdit.find_named(built["root"], "HardnessSlider", "NoSuchWindow")
    assert_null(found, "A window name that matches nothing finds no slider, rather than quietly taking the docker's")
    (built["root"] as Node).free()


func test_the_step_says_which_window_it_could_not_find_a_slider_in() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var said := SaSliderEdit.capture_edit(tree, {"name": "HardnessSlider", "window": "NoSuchWindow", "read": true})
    assert_eq(
        said,
        "SaCapture: no FactorSlider called 'HardnessSlider' in a window called 'NoSuchWindow'",
        "The step names the window it looked in"
    )
