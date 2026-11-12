## An on or off choice in a dialog is a switch.
##
## Export's Roll off highlights was a switch with its words on its left, a
## filter's Preview was a check box in a bordered bar the width of the dialog,
## and the welcome window's Show this at start a check box in a box of its own.
## Now `SaMake.switch` makes the one control all three are, the filter's Preview
## switch sits in a row whose label column carries its words, and the welcome
## window's words are a label beside its switch. What the three look like is
## the scenario's, `scenarios/an-on-or-off-choice-is-a-switch-in-every-dialog.json`.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)


func test_the_library_makes_a_switch() -> void:
    var parent := VBoxContainer.new()
    var made := SaMake.switch(parent, "KeepSwitch", "", true)
    assert_true(made is CheckButton, "A switch is a CheckButton")
    assert_true(made.get_parent() == parent, "added to the parent it was handed")
    assert_eq(String(made.name), "KeepSwitch", "under the name it was given")
    assert_eq(made.text, "", "with no words of its own when none are asked for")
    assert_true(made.button_pressed, "and on when asked")
    assert_eq(SaMake.kind_of(made), SaMake.Kind.TOGGLE, "and the walker prints it as the toggle it is")
    parent.free()


## Gaussian Blur declares its slider alone, so the switch is the one the dialog
## adds, which is the row every filter that leaves its frame out gets.
func test_the_preview_is_a_switch_with_its_words_on_its_left() -> void:
    var dialog := SaDialog.for_filter(SaGaussianBlurFilter.new())
    var host := VBoxContainer.new()
    dialog.realize(host)
    var box: Variant = dialog.canvas_box
    assert_true(box is CheckButton, "The Preview control is a switch")
    assert_false(box is CheckBox, "and not a check box")
    var switch := dialog.canvas_box
    assert_eq(switch.text, "", "It carries no words of its own")
    assert_true(switch.button_pressed, "and starts on")
    var row := _row_named(dialog, "canvas_preview")
    assert_not_null(row, "The switch is a row of the dialog")
    var labels := row.line.get_child(0) as Control
    assert_true(labels.visible, "whose label column is shown")
    var title := labels.find_child("Title", true, false) as Label
    assert_eq(title.text, "Preview on canvas", "and says what the switch is about")
    assert_true(row.line.get_children().find(switch) > labels.get_index(), "on the switch's left")
    assert_eq(
        switch.size_flags_horizontal,
        Control.SIZE_SHRINK_BEGIN,
        "and the switch keeps its own width, so its box rims the switch and not a bar across the dialog"
    )
    host.free()


func test_the_welcome_window_says_show_this_at_start_with_a_switch() -> void:
    var window := SaWelcomeWindow.new()
    var box: Variant = window.show_at_start
    assert_true(box is CheckButton, "Show this at start is a switch")
    assert_false(box is CheckBox, "and not a check box")
    var switch := window.show_at_start
    assert_eq(switch.text, "", "It carries no words of its own")
    var buttons := switch.get_parent()
    var words := buttons.get_child(switch.get_index() - 1) as Label
    assert_not_null(words, "the words are a label")
    assert_eq(words.text, "Show this at start", "saying what the switch does")
    assert_eq(String(words.name), "ShowAtStartLabel", "just before it, on its left")
    var kept := SaSettings.welcome_at_start
    switch.button_pressed = not kept
    assert_eq(SaSettings.welcome_at_start, not kept, "and the switch still writes the preference")
    SaSettings.welcome_at_start = kept
    window.free()


## The switch drives the canvas the way the box did: on, the window hands the
## run's pass to the compositor, and off, it takes it back.
func test_the_preview_switch_still_takes_the_filter_off_the_canvas() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "N106TestHost"
    EventBus.add_child(host)
    var easel := Bench.easel(Vector2i(256, 256))
    easel.document.fill_layer(PAINT, easel.document.active_layer)
    Bench.composite(easel)
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var registry := SaFilterRegistry.new()
    registry.register(InvertFilter.new(), Bench.OWNER)
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.watch(registry)
    host.add_child(window)

    window.open_filter(Bench.INVERT)
    var preview := easel.compositor.point_preview
    assert_true(window.dialog.canvas_box is CheckButton, "The opened dialog's Preview is a switch")
    assert_true(bool(window.describe()["on_canvas"]), "on, the filter is drawn on the canvas")
    assert_not_null(preview.for_document(easel.document), "through the compositor's point preview")
    window.dialog.canvas_box.button_pressed = false
    assert_false(bool(window.describe()["on_canvas"]), "Switched off, it is not")
    assert_null(preview.for_document(easel.document), "and the compositor holds no pass for the document")
    window.dialog.canvas_box.button_pressed = true
    assert_true(bool(window.describe()["on_canvas"]), "and on again, it is back")
    window.cancel_filter()

    window.free()
    canvas.free()
    easel.free()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding


static func _row_named(dialog: SaDialog, widget: String) -> SaPageRow:
    for one: SaPageRow in dialog.rows():
        if dialog.widget_name(one.key) == widget:
            return one
    return null
