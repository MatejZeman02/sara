## A `note` step naming a docker was refused with a message about a
## control that does not exist.
##
## `ToolBoxDocker` is what `docker`, `docker_resize` and `hide` all take and what
## the docker scenarios drive. The `note` step cast the node to `Control`, a docker is
## a `Window`, and the cast answered null, so the step said "no control called
## 'ToolBoxDocker' to note" about a node that is there. The refusal itself is
## right, because `SaNoteMode.freeze` reads `get_global_rect()` and hangs the
## overlay on `get_window()`, neither of which a Window answers the way a Control
## does. The message was not.
##
## No device and no tree: the complaint is a string a caller reads, which is what
## makes it assertable at all.
extends "res://tests/test_framework.gd"


## The two sentences a step can earn, and that they are two.
func test_a_missing_name_and_a_window_read_differently() -> void:
    var window := Window.new()
    window.name = "ToolBoxDocker"
    var missing := SaCaptureNotes.target_complaint("Nonesuch", null)
    var wrong_kind := SaCaptureNotes.target_complaint("ToolBoxDocker", window)

    assert_false(missing.is_empty(), "A name nothing answers to is a complaint")
    assert_false(wrong_kind.is_empty(), "and so is a node that cannot be frozen on")
    assert_false(missing == wrong_kind, "and the two are not the same sentence")
    window.free()


## The half the filing is about: the message has to say the node was found.
## "no control called 'ToolBoxDocker'" sent a reader looking for a typo in a
## name that is correct.
func test_the_window_complaint_says_what_the_node_is() -> void:
    var window := Window.new()
    window.name = "ToolBoxDocker"
    var said := SaCaptureNotes.target_complaint("ToolBoxDocker", window)
    assert_true(said.contains("ToolBoxDocker"), "The complaint names the target: %s" % said)
    assert_true(said.contains("Window"), "and says what it is")
    assert_true(said.contains("Control"), "and what a note wants instead")
    assert_false(said.contains("no control called"), "and does not claim the name is unknown")
    window.free()


## A node with a `class_name` is described by both names, because knowing a
## `DockerWindow` is a `Window` is the half that explains the refusal.
func test_a_scripted_node_is_described_by_its_own_name_and_the_engine_class() -> void:
    var docker := DockerWindow.new()
    docker.name = "ToolBoxDocker"
    var said := SaCaptureNotes.target_complaint("ToolBoxDocker", docker)
    assert_true(said.contains("DockerWindow"), "The script's own name is in it: %s" % said)
    assert_true(said.contains("which is a Window"), "and the engine class under it")
    docker.free()


## And a Control earns nothing, so the step runs. Without this the fix could be
## a complaint for every target.
func test_a_control_is_no_complaint_at_all() -> void:
    var button := Button.new()
    button.name = "SecondRowCheck"
    assert_eq(SaCaptureNotes.target_complaint("SecondRowCheck", button), "", "A Control is what a note freezes on")
    button.free()
