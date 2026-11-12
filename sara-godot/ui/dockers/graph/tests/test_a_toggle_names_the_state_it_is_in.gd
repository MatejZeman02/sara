## The graph docker's two toggles between named states show the name of
## the state the docker is in, and a press changes it to the other.
extends "res://tests/test_framework.gd"


func _toggle(docker: GraphDocker, node_name: String) -> Button:
    var toggle := docker.find_child(node_name, true, false) as Button
    assert_not_null(toggle, "%s is on the row" % node_name)
    return toggle


func test_the_scale_toggle_reads_log_at_rest_and_lin_pressed() -> void:
    var docker := GraphDocker.new()
    var toggle := _toggle(docker, "ScaleToggle")
    assert_eq(toggle.text, "Log", "At rest the default scale is the log one and it says so")
    toggle.button_pressed = true
    assert_eq(docker.scale, "linear", "A press makes the scale linear")
    assert_eq(toggle.text, "Lin", "and the button reads Lin")
    assert_true(toggle.tooltip_text.contains("logarithmic"), "with the tooltip naming what a press gives now")
    toggle.button_pressed = false
    assert_eq(docker.scale, "log", "Pressed back the scale is log")
    assert_eq(toggle.text, "Log", "and the button reads Log")
    assert_true(toggle.tooltip_text.contains("linear"), "with the tooltip naming the other")
    docker.free()


func test_the_scale_toggle_follows_the_scale_set_from_outside() -> void:
    var docker := GraphDocker.new()
    var toggle := _toggle(docker, "ScaleToggle")
    docker.show_scale("linear")
    assert_eq(toggle.text, "Lin", "The door's switch to linear reads Lin without a click")
    docker.show_scale("log")
    assert_eq(toggle.text, "Log", "and back to log reads Log")
    docker.free()


func test_the_white_toggle_reads_rgb_at_rest_and_w_pressed() -> void:
    var docker := GraphDocker.new()
    docker.show_mode("waveform")
    var toggle := _toggle(docker, "WhiteToggle")
    assert_eq(toggle.text, "RGB", "A waveform opens on the three traces and the button says RGB")
    assert_true(toggle.tooltip_text.contains("Oklab lightness"), "with the tooltip naming the white trace a press gives")
    toggle.button_pressed = true
    assert_eq(docker.graph_mode, "waveform_white", "A press makes the trace white")
    assert_eq(toggle.text, "White", "and the button reads White")
    toggle.button_pressed = false
    assert_eq(docker.graph_mode, "waveform", "Pressed back the traces are three")
    assert_eq(toggle.text, "RGB", "and the button reads RGB")
    docker.show_mode("waveform_white")
    assert_eq(toggle.text, "White", "The list's row for the white trace reads White on the button too")
    docker.show_mode("waveform")
    assert_eq(toggle.text, "RGB", "and its other row reads RGB")
    docker.free()
