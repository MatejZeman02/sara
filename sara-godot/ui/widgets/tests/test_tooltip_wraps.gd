## A tooltip long enough to explain something wraps instead of leaving the
## screen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Godot draws a tooltip as one unwrapped `TooltipLabel`, so
## a first draft of the Levels Channel sentence, 277 characters, was cut off
## at both edges of a 1920 window at once. Nothing in a theme can turn wrapping
## on, `autowrap_mode` being a property of the Label rather than a theme item,
## so `SaTooltip` catches the label on its way into the tree instead.
##
## What is proved here is the width decision and the wrap itself, which is what
## matters. Whether the panel that grows around a wrapped label then
## sits inside the window is a question for a real window with a real pointer
## in it, and `scenarios/a-long-tooltip-is-one-unwrapped-line-and-leaves-the-screen.json`
## is that half.
extends "res://tests/test_framework.gd"

## Three hundred characters, the length of the draft that was cut off, so the case under test
## is that one rather than a shorter one that happens to wrap.
const LONG_TEXT := (
    "Which channel the handles move. Master moves red, green and blue together, a single channel "
    + "shifts the colour of the picture as well as its lightness, and Lightness (Oklab) moves the "
    + "lightness alone and leaves every hue exactly where the painter put it, which is the one to "
    + "reach for when only the tone is wrong."
)

## Short enough that no width Sara could pick would wrap it, so a test that says
## a short tooltip is left alone is not quietly reading the same wide window.
const SHORT_TEXT := "Reset"


## A label dressed as the engine dresses the one it builds: the variation is
## what `SaTooltip` tests, and the font comes with it out of the global theme.
func _tooltip_label(text: String) -> Label:
    var label := Label.new()
    label.theme_type_variation = &"TooltipLabel"
    label.text = text
    return label


func test_a_long_tooltip_wraps_and_takes_the_width_it_was_given() -> void:
    var label := _tooltip_label(LONG_TEXT)
    var unwrapped := label.get_minimum_size().x
    var unwrapped_height := label.get_minimum_size().y
    assert_true(unwrapped > 420.0, "the sentence is wider than the cap unwrapped, measured %d" % int(unwrapped))

    assert_true(SaTooltip.wrap_label(label, 420.0), "a sentence wider than the cap wraps")
    assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "and wraps on word boundaries")
    assert_almost_eq(label.custom_minimum_size.x, 420.0, 0.01, "and is held at the width it was given")
    # The height is asserted by the test below rather than here. A Label shapes
    # against the width it is laid out at, and one that has never been in a tree
    # has no layout to be laid out by, so out here it answers with one line
    # however wide it is told it is.
    assert_true(label.custom_minimum_size.y >= unwrapped_height, "and at least the height of the line it had")
    label.free()


## The half that keeps the two hundred short tooltips already in the tree looking
## the way the painter knows them.
func test_a_short_tooltip_is_left_exactly_as_it_was() -> void:
    var label := _tooltip_label(SHORT_TEXT)
    var before := label.get_minimum_size().x

    assert_false(SaTooltip.wrap_label(label, 420.0), "a sentence narrower than the cap is not touched")
    assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF, "and keeps its one line")
    assert_almost_eq(label.custom_minimum_size.x, 0.0, 0.01, "and is given no floor")
    assert_almost_eq(label.get_minimum_size().x, before, 0.01, "and measures what it measured")
    label.free()


## Wrapping twice would halve the width, `custom_minimum_size.x` being set to the
## cap the second time as well while the label already reports the cap.
func test_a_label_already_wrapped_is_not_wrapped_again() -> void:
    var label := _tooltip_label(LONG_TEXT)
    SaTooltip.wrap_label(label, 420.0)

    assert_false(SaTooltip.wrap_label(label, 210.0), "a label that already wraps is left where it is")
    assert_almost_eq(label.custom_minimum_size.x, 420.0, 0.01, "at the width the first pass gave it")
    label.free()


## The window's half rather than a constant, because the engine places a tooltip
## beside the pointer and needs room on the side the pointer is not on. A cap in
## logical units, not through `SaUI.px`: the panel carries the root's
## `content_scale_factor` of its own, and a physical width would be scaled twice.
func test_the_width_is_the_smaller_of_the_cap_and_half_the_window() -> void:
    var root := Engine.get_main_loop().root as Window
    var window := root.get_visible_rect().size.x

    var wide := SaTooltip.max_width_for(root)
    assert_almost_eq(wide, minf(float(SaTooltip.MAX_WIDTH), window * 0.5), 0.01, "the cap on this window")
    assert_true(wide <= window * 0.5, "and never more than half of it, whatever the window is")


## A missing root is the offscreen runner and the editor's own tooltips both, and
## a tooltip that fell back to no cap at all would be the defect again.
func test_no_window_still_caps_the_width() -> void:
    assert_almost_eq(SaTooltip.max_width_for(null), float(SaTooltip.MAX_WIDTH), 0.01, "the cap alone")


## The door the fix comes through. Godot offers `_make_custom_tooltip` as a
## virtual on every Control, which cannot be given to the two dozen built-ins
## Sara draws its interface out of, so the label is caught on `node_added`
## instead, before the engine measures the panel around it.
##
## Hung on an autoload rather than on `tree.root`, which refuses a child for the
## whole of this run: the suite is called from `run_all.gd`'s `_ready`, and a
## node readying its children is blocked from taking new ones. `root.add_child`
## there prints "Parent node is busy setting up children" and does nothing, which
## reads exactly like a signal that never fired.
func test_a_tooltip_label_entering_the_tree_is_wrapped() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaTooltip.install(tree)

    var label := _tooltip_label(LONG_TEXT)
    EventBus.add_child(label)
    assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the engine's own label wraps as it arrives")
    assert_almost_eq(
        label.get_combined_minimum_size().x, SaTooltip.max_width_for(tree.root), 0.01, "and is exactly as wide as the cap"
    )
    var one_line := _tooltip_label(SHORT_TEXT)
    EventBus.add_child(one_line)
    assert_true(
        label.get_combined_minimum_size().y >= 3.0 * one_line.get_combined_minimum_size().y,
        (
            "and the panel around it is told the height of every line, not of the first: %d against %d for one"
            % [int(label.get_combined_minimum_size().y), int(one_line.get_combined_minimum_size().y)]
        )
    )
    one_line.free()
    label.free()


## The variation is the test and not the class, so a Label Sara puts on screen
## for its own reasons keeps whatever wrapping its own code chose.
func test_a_label_that_is_not_a_tooltip_is_not_touched() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaTooltip.install(tree)

    var label := Label.new()
    label.text = LONG_TEXT
    EventBus.add_child(label)
    assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF, "an ordinary Label is left alone")
    label.free()


## Installing twice would wrap twice, and the global theme is built more than
## once in a run of this suite.
func test_installing_twice_connects_once() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaTooltip.install(tree)
    SaTooltip.install(tree)

    assert_eq(_tooltip_connections(tree), 1, "one connection, however often it is asked for")


## The engine's own tooltip label is a full-rect child of its panel, and
## wrapping it was a `size.x` write, which `Control::_set_size` warns about on
## every control that is not laid out by a container yet: "Nodes with non-equal
## opposite anchors will have their size overridden after _ready()", once per
## wrapped tooltip, in every run that shows one. `data.size_warning` starts true
## and is cleared by the deferred `ready` signal, so a label built and dressed
## the way the engine dresses one warns here even without the panel around it.
##
## The wrap is a `custom_maximum_size` now, and the label shapes itself inside
## it, so there is no size write left to warn about. The engine writes what it
## warns into `user://logs/godot.log` as it warns, so this suite reads the run's
## own console for both halves of the claim: nothing said, and the label still
## told the height of the wrapped sentence.
func test_wrapping_a_full_rect_label_warns_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaTooltip.install(tree)
    var host := Control.new()
    host.size = Vector2(800.0, 600.0)
    EventBus.add_child(host)
    var label := _tooltip_label(LONG_TEXT)
    label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var one_line := label.get_minimum_size().y

    var before := _log_text()
    host.add_child(label)
    var after := _log_text()

    assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the engine's shape of label wraps as it arrives")
    assert_eq(
        after.length(),
        before.length(),
        "and the engine warns nothing about the width: %s" % after.substr(before.length()).strip_edges()
    )
    assert_almost_eq(label.custom_minimum_size.x, SaTooltip.max_width_for(tree.root), 0.01, "while it is held at the cap")
    assert_true(
        label.custom_minimum_size.y > one_line,
        "and told the height of more than one line: %d against %d" % [int(label.custom_minimum_size.y), int(one_line)]
    )
    host.free()


## Everything the engine has written to its own log so far. A warning, an error
## and a `print` all land there as they happen, which is what makes the console
## of a run readable from inside the run that printed it.
func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## How many of the tree's `node_added` listeners are this class's. Read out by
## method name rather than off the total, because anything else in the suite may
## be listening to the same signal for its own reasons.
func _tooltip_connections(tree: SceneTree) -> int:
    var count := 0
    for connection: Dictionary in tree.node_added.get_connections():
        var callable: Callable = connection["callable"]
        if callable.get_method() == "_on_node_added":
            count += 1
    return count
