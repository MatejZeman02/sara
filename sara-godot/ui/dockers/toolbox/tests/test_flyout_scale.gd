## The toolbox flyout renders at the factor its docker renders at.
##
## The defect was a screenshot: the selection flyout with rows about twice the
## size of everything else, icons near 90 px and text near 28 px, beside a docker
## whose own buttons were half that. `SaToolFlyout` is a `PopupPanel`, so it is a
## `Window` with a `content_scale_factor` of its own, and nothing ever wrote one.
## With `embed_subwindows` on, the default, both the docker and the popup are
## embedded and both answer 1.0, so the two agreed by accident and the bug was
## invisible. With it off the docker is an OS window at `SaUI.scale()` and the
## popup was still at 1.0.
##
## A detached `Window` reports `is_embedded()` false, which is the OS-window
## branch of `SaUI.window_scale`, so a docker built outside the tree is where the
## disagreement can be provoked without a second display. `test_ui_scale.gd`
## leans on the same fact.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


## The unit's claim, at a scale that is not 1.0: the popup takes the factor the
## docker takes, and it takes it from the one writer of the UI scale.
func test_the_flyout_takes_the_factor_its_docker_takes() -> void:
    SaUI.os_scale_override = 1.5
    SaUI.user_scale = 1.0

    var docker := _toolbox()
    docker.apply_window_scale()
    assert_almost_eq(docker.content_scale_factor, 1.5, 0.0001, "The docker is at one and a half")

    assert_true(docker.open_flyout(&"fill"), "the fills' flyout opens")
    var flyout: SaToolFlyout = docker._flyouts[&"fill"]
    assert_almost_eq(
        flyout.content_scale_factor,
        docker.content_scale_factor,
        0.0001,
        "and the popup beside it renders at the same factor, which is the whole point"
    )
    assert_almost_eq(
        flyout.content_scale_factor,
        SaUI.window_scale(flyout),
        0.0001,
        "the factor being the one `SaUI` answers for that window, not a number this file chose"
    )
    docker.free()


## A scale change after the flyout was built reaches it, because the factor is
## written on every open rather than once at construction. A painter who moves
## the Interface slider with a flyout in the tree is the case.
func test_a_scale_change_reaches_a_flyout_that_already_exists() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0

    var docker := _toolbox()
    docker.apply_window_scale()
    assert_true(docker.open_flyout(&"fill"), "the flyout opens once")
    var flyout: SaToolFlyout = docker._flyouts[&"fill"]
    assert_almost_eq(flyout.content_scale_factor, 1.0, 0.0001, "at one")

    SaUI.user_scale = 2.0
    docker.apply_window_scale()
    assert_true(docker.open_flyout(&"fill"), "and again after the scale moved")
    assert_almost_eq(flyout.content_scale_factor, 2.0, 0.0001, "the same popup now renders at two")
    assert_almost_eq(docker.content_scale_factor, 2.0, 0.0001, "beside a docker that does too")
    docker.free()


## What the dump says, because the scenario grades this on a number rather than
## on a picture: a row is the same logical height whatever the factor, and the
## height it is drawn at is the one that doubled.
func test_the_report_says_the_factor_and_the_height_a_row_is_drawn_at() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0

    var docker := _toolbox()
    docker.apply_window_scale()
    assert_true(docker.open_flyout(&"fill"), "the flyout opens")

    var report: Dictionary = docker.toolbox_report()["flyout"]
    assert_true(report.has("popup"), "The flyout's own block is in the toolbox report")
    var popup: Dictionary = report["popup"]
    assert_almost_eq(float(popup["content_scale_factor"]), 2.0, 0.0001, "with the factor it renders at")
    assert_eq(int(popup["rows"]), docker._flyout_ids.size(), "the row count the members say")
    assert_almost_eq(
        float(popup["row_height_drawn"]),
        float(popup["row_height"]) * 2.0,
        0.0001,
        "and a drawn height that is the logical one times the factor, which is what the screenshot showed"
    )
    docker.free()
