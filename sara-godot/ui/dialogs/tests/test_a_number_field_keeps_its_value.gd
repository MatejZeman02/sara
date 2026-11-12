## Text that is not a number leaves a slider's value where it was.
##
## Typing letters into a slider that needs numbers must not change the value on
## Enter, and an error message should appear and disappear. Seen on the brush
## size in the Tool Options docker, where the value fell to the minimum.
##
## The cause was one line. `to_float()` answers zero for a word and for "1,5",
## and the clamp under it wrote that zero out as the field's minimum, so a word
## typed into the size row became the smallest brush the row allows.
##
## **The rule is read through the widget's own door**, `number_from_text`, and
## the cases below are what a painter actually types: a word, an empty field, a
## number with the spaces a copy and paste brings, and the minimum itself, which
## has to stay reachable, because a rule that refused a real number would be
## worse than the defect.
##
## The line's disappearing is the scenario's half, because a clock needs frames
## and a case gets none:
## `scenarios/letters-in-a-number-field-write-the-minimum.json`.
extends "res://tests/test_framework.gd"

var _previous_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "W4NumberFieldHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        # Freeing the host runs `SaMessage._uninstall`, so the notice goes with
        # it and the next suite installs its own.
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


## A size row at 40 of 100, in the tree, ready to be typed into.
func _slider() -> FactorSlider:
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 40.0
    return slider


## What a painter does: open the field, type, press Return.
func _type(slider: FactorSlider, text: String) -> void:
    slider.start_editing()
    slider._line_edit.text = text
    slider._on_line_edit_submitted(text)


## A word leaves the value as it was and the corner says why. It once read 0.0,
## the row's minimum.
func test_a_word_leaves_the_value_and_the_corner_says_so() -> void:
    SaMessage.install(_host)
    var slider := _slider()
    _type(slider, "abc")

    assert_almost_eq(slider.value, 40.0, 1e-6, "the value is the one that was there")
    assert_eq(slider._label.text, "40.0", "and the box reads it again")
    assert_false(slider._line_edit.visible, "the field is closed")

    var notice := SaMessage.notice_widget()
    assert_not_null(notice, "the message surfaces are installed")
    assert_true(notice.showing(), "and the refusal is a line in the corner")
    assert_true(notice.label.text.contains("not a number"), "saying what was wrong")
    assert_true(notice.label.text.contains("abc"), "and what it was")


## The corner message disappears again. The clock is emitted rather
## than waited out, because a timer needs frames and a case gets none: that the
## line is down when the clock fires is this, and that the clock is seconds long
## is `SaNotice.SECONDS`, held by `test_sa_message.gd`.
func test_the_line_goes_away_on_its_own_clock() -> void:
    SaMessage.install(_host)
    _type(_slider(), "abc")
    var notice := SaMessage.notice_widget()
    assert_true(notice.showing(), "the refusal is up")

    notice._timer.timeout.emit()
    assert_false(notice.showing(), "and it goes without anybody dismissing it")


## The other half of the rule: a number is still taken, and nothing is said.
func test_a_number_is_still_taken() -> void:
    SaMessage.install(_host)
    var slider := _slider()
    _type(slider, "12.5")

    assert_almost_eq(slider.value, 12.5, 1e-6, "a number typed into the field is the value")
    assert_false(SaMessage.notice_widget().showing(), "and nothing is refused")


## The number the defect wrote by accident is one a painter may type on
## purpose, and the rule must not take it away.
func test_nought_typed_is_still_nought() -> void:
    SaMessage.install(_host)
    var slider := _slider()
    _type(slider, "0")

    assert_almost_eq(slider.value, 0.0, 1e-6, "a typed nought is the minimum and not a refusal")
    assert_false(SaMessage.notice_widget().showing(), "with nothing said")


## A number copied from anywhere arrives with the spaces around it, and they are
## the paste's rather than the number's. `is_valid_float()` reads " 42 " as a
## word while `to_float()` reads it as 42, which is why the rule strips first.
func test_a_pasted_number_keeps_its_spaces_and_not_its_value() -> void:
    SaMessage.install(_host)
    var slider := _slider()
    _type(slider, " 42 ")

    assert_almost_eq(slider.value, 42.0, 1e-6, "the edges are stripped and the number is taken")
    assert_false(SaMessage.notice_widget().showing(), "and nothing is refused")


## An empty field is not a nought either.
func test_an_empty_field_changes_nothing() -> void:
    SaMessage.install(_host)
    var slider := _slider()
    _type(slider, "")

    assert_almost_eq(slider.value, 40.0, 1e-6, "an empty field leaves the value alone")
    assert_true(SaMessage.notice_widget().showing(), "and the corner says nothing was typed")


## The other caller of the same commit. The field is left with the pointer or
## with Tab as often as with Return, and the rule is the field's rather than the
## key's. "12px" is what a painter copies off the box, suffix and all, and it is
## a word like any other rather than a silent twelve.
func test_leaving_the_field_refuses_the_same_way() -> void:
    SaMessage.install(_host)
    var slider := _slider()
    slider.start_editing()
    slider._line_edit.text = "12px"

    slider._on_line_edit_focus_exited()
    assert_almost_eq(slider.value, 40.0, 1e-6, "a suffix copied in with the number is not read as twelve")
    assert_true(SaMessage.notice_widget().showing(), "and it is said so")
