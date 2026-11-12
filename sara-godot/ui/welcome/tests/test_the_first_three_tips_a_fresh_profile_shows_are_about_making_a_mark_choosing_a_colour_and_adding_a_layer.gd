## The first three tips a fresh profile shows are about making
## a mark, choosing a colour and adding a layer, each by the words the Toolbox,
## the Colour Picker docker and the Layers docker carry, and the twelve older
## tips follow them in their old order.
##
## The words are read from where the app keeps them rather than typed here, so
## a docker renamed in the layout's titles or a toolbox reordered fails this
## suite rather than leaving a tip that names what the screen no longer shows.
extends "res://tests/test_framework.gd"

## The twelve older tips, in the order they stood before the first three.
const OLD_TIPS: Array[String] = [
    "docker_alt_drag",
    "docker_alt_double_click",
    "top_menu_bar",
    "summoned_docker",
    "popup_palette",
    "brush_slots",
    "soft_proof",
    "shape_check",
    "undo_history",
    "recent_presets",
    "tab_hides_the_dockers",
    "maximise_docker",
]

var _saved_tip: String = ""


func before_each() -> void:
    _saved_tip = SaSettings.last_tip_shown
    SaSettings.last_tip_shown = ""


func after_each() -> void:
    SaSettings.last_tip_shown = _saved_tip


func _title(category: StringName) -> String:
    return String(SaSettingsLayout.CATEGORY_TITLES[String(category)])


func test_a_fresh_profile_opens_on_making_a_mark_with_the_brush() -> void:
    var pane := WelcomeTipsPane.new()
    assert_eq(pane.current, 0, "a fresh profile starts on the first tip")
    var tip: Dictionary = pane.tips[0]
    var first_tool := SaToolBoxViews.tool_elements()[0]
    assert_eq(first_tool, "Brush Tool", "the Toolbox's first button is the Brush")
    var text := String(tip["text"])
    assert_true(text.contains(_title(SaDockerIds.TOOLBOX)), "the tip names the Toolbox: %s" % text)
    assert_true(text.contains("first button"), "and its first button")
    assert_true(text.contains("Brush"), "by the Brush's name")
    assert_true(text.contains("drag on the canvas"), "and says a drag on the canvas makes the mark")
    assert_eq(StringName(tip["command"]), &"tool_brush", "the key under it is the Brush's")
    var title := (pane.find_child(WelcomeTipsPane.TITLE, true, false) as Label).text
    assert_eq(title, String(tip["title"]), "and it is the tip on screen")
    pane.free()


func test_the_second_tip_chooses_a_colour_in_the_colour_picker() -> void:
    var pane := WelcomeTipsPane.new()
    var tip: Dictionary = pane.tips[1]
    var text := String(tip["text"])
    var docker := _title(&"ColorPicker")
    assert_eq(docker, "Colour Picker", "the docker the Window menu names Colour Picker")
    assert_true(text.contains(docker + " docker"), "the tip names it so: %s" % text)
    assert_true(text.contains("ring") and text.contains("square"), "and its ring and square")
    assert_true(text.contains("next mark"), "and says they choose the next mark's colour")
    assert_eq(StringName(tip["command"]), &"docker_summon_color_selector", "the key under it shows the docker")
    pane.free()


func test_the_third_tip_adds_a_layer_with_the_plus_in_layers() -> void:
    var pane := WelcomeTipsPane.new()
    var tip: Dictionary = pane.tips[2]
    var text := String(tip["text"])
    var docker := _title(SaDockerIds.LAYERS)
    assert_true(text.contains(docker + " docker"), "the tip names the Layers docker: %s" % text)
    var actions := SaLayerActions.new(null)
    var tooltip := actions.add_btn.tooltip_text
    var drawn := actions.add_btn.icon != null or actions.add_btn.text == "+"
    actions.free()
    assert_true(drawn, "the docker's add button is a plus, drawn or written")
    assert_true(text.contains("plus button (%s)" % tooltip), "and the tip names it by its tooltip, %s" % tooltip)
    assert_true(text.contains("adds a layer"), "says it adds a layer")
    assert_true(text.contains("layer picked"), "and that a mark goes on the layer picked")
    assert_eq(StringName(tip["command"]), &"layer_new_paint", "the key under it adds a paint layer")
    pane.free()


func test_the_twelve_old_tips_follow_in_their_old_order_and_every_id_is_there_once() -> void:
    var pane := WelcomeTipsPane.new()
    var ids: Array[String] = []
    for tip: Dictionary in pane.tips:
        ids.append(String(tip["id"]))
    assert_eq(ids.slice(0, 3), ["make_a_mark", "choose_a_colour", "add_a_layer"], "the three come first")
    assert_eq(ids.slice(3), OLD_TIPS, "and the twelve follow in their old order")
    for id: String in ids:
        assert_eq(ids.count(id), 1, "%s stands once" % id)
    pane.free()
