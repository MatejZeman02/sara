## Info shows the last three distinct pop-up messages at its foot, newest
## first, and a Copy button puts them on the clipboard.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A notice leaves the canvas corner after a moment, so the docker keeps what
## was said. A line said again is shown once, and the row is an element the
## painter can hide like the docker's sections. No window and no GPU.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

var _copied := ""
var _saved_clipboard: Callable


func before_each() -> void:
    SaNoticeLog.clear()
    _copied = ""
    _saved_clipboard = SaInfoMessages.clipboard
    SaInfoMessages.clipboard = func(text: String) -> void: _copied = text


func after_each() -> void:
    SaInfoMessages.clipboard = _saved_clipboard
    SaNoticeLog.clear()


func _shown(docker: InfoDocker) -> Array:
    docker.messages.refresh()
    var out: Array = []
    for line in docker.messages.lines:
        if line.visible:
            out.append(line.text)
    return out


func test_the_last_three_distinct_messages_are_shown_newest_first() -> void:
    var docker: InfoDocker = DOCKER.new()
    assert_eq(_shown(docker), [], "Nothing said, nothing shown")
    assert_true(docker.messages.copy_button.disabled, "and Copy is dimmed with nothing to copy")
    for line: String in ["one", "two", "two", "three", "four"]:
        SaMessage.notice(line)
    assert_eq(_shown(docker), ["four", "three", "two"], "three, newest first, the repeated one once")
    SaMessage.notice("two")
    assert_eq(_shown(docker), ["two", "four", "three"], "a line said again moves to the front and is not kept twice")
    docker.free()


func test_copy_puts_the_messages_on_the_clipboard() -> void:
    var docker: InfoDocker = DOCKER.new()
    SaMessage.notice("a")
    SaMessage.notice("b")
    docker.messages.refresh()
    assert_false(docker.messages.copy_button.disabled, "Copy is live once there is something")
    docker.messages.copy_button.pressed.emit()
    assert_eq(_copied, "b\na", "the clipboard holds the lines, newest first")
    docker.free()


func test_the_row_is_a_layout_element_the_painter_can_hide() -> void:
    var docker: InfoDocker = DOCKER.new()
    assert_true(SaSettings.get_layout_order(SaDockerIds.INFO).has(SaInfoMessages.ELEMENT), "Preferences lists the Messages row")
    for preset_name: String in ["default", "full", "krita", "photoshop", "procreate", "clip_studio", "minimalistic", "useful"]:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load("res://layouts/%s.cfg" % preset_name), OK, "%s reads" % preset_name)
        assert_true(cfg.get_value("_layout_visibility_", "InfoDocker/Messages", false), "%s shows the row" % preset_name)
        assert_true(Array(cfg.get_value("_layout_order_", "InfoDocker", [])).has("Messages"), "%s orders the row" % preset_name)
    docker.free()
