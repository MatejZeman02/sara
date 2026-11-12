## The vectorscope's skin tone line points where darktable's table of
## measured skin colours says skin is, rather than along a broadcast
## vectorscope's I line reasoned into Oklab. What a shot proves is that the
## line is drawn there, and `scenarios/the-skin-tone-line-is-darktables.json`
## is that shot. What it cannot prove is that the number the dump reports is
## the number the kernel draws, which is this file: the mirror in
## `graph_docker.gd` against the kernel's own text, and the line against the
## two nodes of the hue ring that skin sits between.
extends "res://tests/test_framework.gd"

const KERNEL := "res://shaders/compute/graph.gmacs"


## The value of a `const float` in the dialect, or NAN when the kernel does not
## declare one under that name.
func _kernel_const(name: String) -> float:
    var text := FileAccess.get_file_as_string(KERNEL)
    for line in text.split("\n"):
        var trimmed := line.strip_edges()
        if not trimmed.begins_with("const "):
            continue
        var halves := trimmed.split("=", true, 1)
        if halves.size() < 2:
            continue
        var words := halves[0].strip_edges().split(" ", false)
        if words.size() >= 3 and words[2] == name:
            return float(halves[1].strip_edges())
    return NAN


## The Oklab hue of a point on the square the vectorscope is drawn in, where
## up is more b, which is how the kernel lays the plane out.
func _hue_of(unit: Vector2) -> float:
    var centred := unit - Vector2(0.5, 0.5)
    return atan2(-centred.y, centred.x)


func test_the_dump_reports_the_hue_the_kernel_draws() -> void:
    var drawn := _kernel_const("SKIN_HUE")
    assert_false(is_nan(drawn), "the kernel names the skin tone line's hue")
    assert_almost_eq(drawn, GraphDocker.SKIN_HUE, 1e-6, "and the docker's mirror is that number")


## Skin is a light orange, so its line lies between the red node and the
## yellow one. `SaGraphLabels.scope_unit` places a node where the kernel draws
## it, and the linear radius leaves the angle alone either way.
func test_the_line_lies_between_the_red_and_the_yellow_node() -> void:
    var red := _hue_of(SaGraphLabels.scope_unit(Color(1, 0, 0), null, "linear"))
    var yellow := _hue_of(SaGraphLabels.scope_unit(Color(1, 1, 0), null, "linear"))
    var skin := _kernel_const("SKIN_HUE")
    assert_true(red < skin, "the line is further round than red")
    assert_true(skin < yellow, "and short of yellow")
