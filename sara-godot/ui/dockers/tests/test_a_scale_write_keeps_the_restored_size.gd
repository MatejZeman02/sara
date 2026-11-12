## A UI scale write keeps the size a docker was restored or dragged to.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaSettings` emits `ui_scale_changed` for a write of the scale it already
## holds, and `DockerWindow._on_ui_scale_changed` answers it with
## `apply_window_scale`, which re-derives `size` from `logical_size`. Nothing
## ever wrote `logical_size` after the constructor, so that was the number the
## docker opened at and never the one a stored layout restored or a painter
## dragged: four of the six dockers a fresh profile opens lost their size to a
## `prefs` step, and every committed scenario begins with one.
##
## The fix is that `logical_size` follows the window. `_track_logical_size` reads
## the size back in logical units whenever anything other than the class itself
## writes it, so re-deriving is a no-op at an unchanged scale and the right
## multiplication at a changed one. The scale that has actually moved is the case
## that had to keep working, and it is the third test below.
##
## **The divisor is the scale the size was measured in**, not the one
## `SaUI.window_scale` answers now. Toggling embedded subwindows changes that
## answer a frame before the geometry is re-derived, and the fourth test is that
## frame: a host-logical size read as if it were physical shrinks the docker by
## the scale factor every time the painter leaves embedded mode.
##
## What the assembled dockers do, at 1.0 and at 1.5, embedded and as real
## windows, is `scenarios/ui-scale-write-drops-restored-docker-sizes.json`.
## `@tool` because the fixture extends `DockerWindow`, which is a tool script,
## for the reason `test_scale_change_keeps_the_column_floor.gd` gives.
@tool
extends "res://tests/test_framework.gd"


## The least docker `apply_window_scale` will run over: a content column with the
## drag bar in it, and no wrap, so the window's size is only ever what a test or
## the class itself put there.
class RestoredDocker:
    extends DockerWindow

    var column: VBoxContainer = null

    func _init() -> void:
        _init_docker("RestoredDocker", "Restored", Vector2i(120, 90), Vector2i(80, 60))
        wrap_controls = false
        column = VBoxContainer.new()
        column.custom_minimum_size = Vector2i(40, 36)
        add_child(column)
        drag_handle = PanelContainer.new()
        column.add_child(drag_handle)

    func content_column() -> Container:
        return column


var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


## A docker at scale 1 that a layout has just restored to 340 by 260, which is
## the state every one of these starts from.
func _restored() -> RestoredDocker:
    var docker := RestoredDocker.new()
    docker.apply_window_scale()
    docker.size = Vector2i(340, 260)
    docker._track_logical_size()
    return docker


## The tracker itself. A restore writes `size` and nothing else, and the logical
## size is that size at a scale of 1.
func test_a_restore_is_read_back_as_the_logical_size() -> void:
    var docker := _restored()
    assert_eq(docker.logical_size, Vector2i(340, 260), "The restored size is what the docker now calls its own")
    docker.free()


## The defect, in one assertion. Before the fix this came back at the constructor's
## 120 by 90.
func test_a_scale_write_of_the_scale_already_held_moves_nothing() -> void:
    var docker := _restored()
    docker.apply_window_scale()
    assert_eq(docker.size, Vector2i(340, 260), "A write of the scale already held leaves the restored size alone")
    assert_eq(docker.logical_size, Vector2i(340, 260), "and the logical size with it")
    docker.free()


## The half that had to keep working: a scale that really moved multiplies the
## size the docker is at, and the logical size stays where the restore put it.
func test_a_real_scale_change_multiplies_the_restored_size() -> void:
    var docker := _restored()
    SaUI.user_scale = 1.5
    docker.apply_window_scale()
    assert_eq(docker.size, Vector2i(510, 390), "The physical size follows the scale")
    assert_eq(docker.logical_size, Vector2i(340, 260), "and the logical size is still the one it was restored at")

    SaUI.user_scale = 1.0
    docker.apply_window_scale()
    assert_eq(docker.size, Vector2i(340, 260), "and back down again, so two writes do not compound")
    docker.free()


## The frame the embedded switch opens. `SaUI.window_scale` answers 1 for an
## embedded window and the display's scale for a real one, so it changes the
## moment the setting is flipped, before `_apply_embed_subwindows` re-derives the
## geometry. The size in hand is still measured in the old scale, and dividing it
## by the new one is a docker a third narrower on every flip.
func test_the_tracker_divides_by_the_scale_the_size_was_measured_in() -> void:
    var docker := _restored()
    SaUI.user_scale = 1.5
    docker._track_logical_size()
    assert_eq(docker.logical_size, Vector2i(340, 260), "The size was measured at 1, so it is 340 by 260 logical")
    docker.free()


## A docker that has never been scaled has no scale to divide by, and keeps what
## its constructor declared rather than reading a raw constructor size as though
## it were physical.
func test_a_window_that_has_never_been_scaled_is_left_alone() -> void:
    var docker := RestoredDocker.new()
    docker.size = Vector2i(340, 260)
    docker._track_logical_size()
    assert_eq(docker.logical_size, Vector2i(120, 90), "No applied scale, no reading")
    docker.free()


## The wiring, read off the source for the reason
## `test_scale_change_keeps_the_column_floor.gd` gives: the effect needs a
## shown window and a settled layout, and a suite that awaits one drops every
## assertion after the await. The running app answers the rest in the scenario.
func test_the_docker_connects_the_tracker_and_still_re_derives_on_a_scale_change() -> void:
    var source := FileAccess.get_file_as_string("res://ui/dockers/docker_window.gd")
    assert_false(source.is_empty(), "docker_window.gd is readable")
    assert_true(
        source.contains("size_changed.connect(_track_logical_size)"),
        "_setup_docker_ready connects the tracker, or nothing ever writes logical_size again"
    )
    assert_true(
        _body_of(source, "func _on_ui_scale_changed").contains("apply_window_scale()"),
        "the scale handler still re-derives, or a real scale change stops reaching the dockers"
    )
    assert_false(
        _body_of(source, "func _on_ui_font_scale_changed").contains("apply_window_scale()"),
        "and the font handler still does not, because the font scale is not the window scale"
    )
    var derive := _body_of(source, "func apply_window_scale")
    assert_true(
        derive.contains("_deriving_geometry = true") and derive.contains("_deriving_geometry = false"),
        "and its own writes are guarded, or the tracker reads the derivation back as a painter's resize"
    )


## Everything in *source* from the line declaring *header* to the next `func`.
func _body_of(source: String, header: String) -> String:
    var parts := source.split(header)
    assert_eq(parts.size(), 2, "%s is declared exactly once" % header)
    if parts.size() != 2:
        return ""
    return parts[1].split("\nfunc ")[0]
