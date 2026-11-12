## A checkbox and a switch draw a box of their own, not the push button's.
##
## `SaThemeDefaults.BOXES` leaves `CheckBox` and `CheckButton` out on the reading
## that their boxes are `StyleBoxEmpty` and there was nothing to replace. The
## half that is true is about Godot's own default theme, which a control in the
## tree only reaches after every type of its list has been asked. A `CheckBox`'s
## list is `CheckBox` and then `Button`, the shared theme holds a `Button`, so
## the push button's box answered first and a painter setting Button Normal
## repainted every checkbox and every switch in the interface.
##
## What is held here is the whole of the fix: the family resolves a box of its
## own, none of the push button's state fields reaches it, its ground follows a
## palette switch the way every other default does, and the room it takes in a
## row it sits in does not move.
##
## Every probe is inside the tree. A detached `Control` has no theme owner and
## which is a trap: a probe outside the tree passes for the wrong reason.
extends "res://tests/test_framework.gd"

## The states a control's box is asked for, which is what the engine asks as the
## pointer and the keyboard move.
const STATES: Array[String] = ["normal", "hover", "pressed", "disabled", "focus"]

## The push button's four grounds, the fields the painter owns and the ones
## that would otherwise repaint the whole family. Written out rather than read from
## `SaPalette.BUTTON_GROUNDS`, so a table that changed would not carry this
## test's intent along with it.
const BUTTON_FIELDS: Array[String] = ["button_normal", "button_hover", "button_pressed", "button_disabled"]

## The size each family measures with an empty label, the thing the box may not
## move. `SaUI.px` rather than the numbers, so
## a display scale that doubles them is not a failure here.
const FAMILY_MINIMUM := {
    "CheckBox": Vector2(24, 24),
    "CheckButton": Vector2(28, 18),
}


func _saved() -> Array:
    return [SaUI.shared_theme, SaTheme.palette_id]


func _restore(saved: Array) -> void:
    SaTheme.use_named(String(saved[1]))
    SaUI.shared_theme = saved[0] as Theme


## A fresh shared theme on the main loop, and a `Control` wearing it, which is
## what gives the controls below a theme owner to resolve through.
##
## Built and put back the way `test_theme_defaults` does, because the gate
## runs `res://tests/run_all.tscn` and nothing there has built the theme yet.
func _host(palette_id: String) -> Node:
    SaTheme.use_named(palette_id)
    SaUI.init_global_theme(null)
    var host := Node.new()
    host.name = "D23CheckBoxHost"
    EventBus.add_child(host)
    var root := Control.new()
    root.theme = SaUI.shared_theme
    host.add_child(root)
    return host


func _check_boxes(root: Control) -> Array[Control]:
    var out: Array[Control] = [CheckBox.new(), CheckButton.new()]
    for box: Control in out:
        root.add_child(box)
    return out


## The defect itself: the box a checkbox resolves is the one the shared theme
## holds for `CheckBox`, and the push button's is a different object.
##
## `hover_pressed` is not in either table, so it is not asked for here. The
## engine holds no `hover_pressed` box for a `Button` either and falls back to
## the pressed one, which is a fact about the family that did not change and is
## recorded rather than asserted as part of the fix.
func test_a_check_box_resolves_a_box_of_its_own() -> void:
    var saved := _saved()
    var host := _host("default")
    var root := host.get_child(0) as Control
    var theme := SaUI.shared_theme
    var push := Button.new()
    root.add_child(push)

    for box: Control in _check_boxes(root):
        var cls := box.get_class()
        for state: String in STATES:
            var resolved := box.get_theme_stylebox(state)
            assert_true(theme.has_stylebox(state, cls), "%s: the shared theme holds its own %s box" % [cls, state])
            assert_true(resolved == theme.get_stylebox(state, cls), "%s/%s is the box the theme holds for it" % [cls, state])
            assert_true(
                resolved != push.get_theme_stylebox(state),
                "%s/%s: and a probe under the shared theme no longer reads the push button's" % [cls, state]
            )

    host.free()
    _restore(saved)


## A ground of the palette on every state the family has one. `focus` is the one
## it has none on: the rim-only box the whole table gives every class, whose
## ground is transparent by design.
func test_the_ground_is_the_palettes_and_never_the_engines_grey() -> void:
    var saved := _saved()
    var host := _host("default")
    var root := host.get_child(0) as Control

    for box: Control in _check_boxes(root):
        var cls := box.get_class()
        for state: String in STATES:
            var flat := box.get_theme_stylebox(state) as StyleBoxFlat
            if state == "focus":
                assert_eq(flat.bg_color.a, 0.0, "%s/focus carries the rim and no ground" % cls)
                continue
            assert_true(
                flat.bg_color == SaTheme.palette.get(_field(state)),
                "%s/%s is grounded on the palette, not the engine's grey" % [cls, state]
            )

    host.free()
    _restore(saved)


func _field(state: String) -> String:
    return "switch_" + ("pressed" if state == "hover_pressed" else state)


## A check box or a switch that is on, with the pointer
## over it, drew no box at all. The engine holds a `hover_pressed` box of its own
## for the two, which is empty, and a theme with none of its own leaves it so,
## so the ground vanished the moment a painter reached for an On switch. It is
## the ground a pressed one has, in every palette, and it is a box.
func test_a_hovered_check_box_that_is_on_keeps_its_ground() -> void:
    var saved := _saved()
    for id: String in SaTheme.PALETTES:
        var host := _host(id)
        var root := host.get_child(0) as Control
        for box: Control in _check_boxes(root):
            var cls := box.get_class()
            var resolved := box.get_theme_stylebox("hover_pressed")
            assert_true(resolved is StyleBoxFlat, "%s/%s: hover_pressed is a painted box, not the engine's empty one" % [id, cls])
            var flat := resolved as StyleBoxFlat
            if flat != null:
                assert_eq(flat.bg_color, SaTheme.palette.switch_pressed, "%s/%s: grounded as a pressed one is" % [id, cls])
                assert_eq(flat.border_color, SaTheme.palette.border_selected, "%s/%s: with the pressed rim" % [id, cls])
        host.free()
    _restore(saved)


## The rule behind HP, held for every class `SaThemeDefaults` paints: a class
## that answers `hover_pressed` at all answers it with a box. A `Button` and its
## kin answer none and fall through to `pressed`, which is the half that was
## measured to be fine.
func test_no_painted_class_answers_hover_pressed_with_an_empty_box() -> void:
    var saved := _saved()
    var host := _host("default")
    var root := host.get_child(0) as Control
    for cls: String in SaThemeDefaults.BOXES:
        if not ClassDB.can_instantiate(cls):
            continue
        var made := ClassDB.instantiate(cls) as Object
        var node := made as Control
        if node == null:
            if made != null and not made is RefCounted:
                made.free()
            continue
        root.add_child(node)
        if node.has_theme_stylebox("hover_pressed"):
            assert_false(node.get_theme_stylebox("hover_pressed") is StyleBoxEmpty, "%s: hover_pressed is not empty" % cls)
    host.free()
    _restore(saved)


## The bug's second half. The four push button grounds are palette fields a
## painter sets, and this is what setting one may not reach.
func test_no_push_button_field_reaches_the_family() -> void:
    var saved := _saved()
    var host := _host("default")
    var root := host.get_child(0) as Control
    var boxes := _check_boxes(root)
    var before: Array[String] = []
    for box: Control in boxes:
        before.append((box.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.to_html())

    var garish := [Color("#FF0000"), Color("#00FF00"), Color("#0000FF"), Color("#FFFF00")]
    for i: int in BUTTON_FIELDS.size():
        SaTheme.set_color(BUTTON_FIELDS[i], garish[i] as Color)
    SaThemeDefaults.paint_colors(SaUI.shared_theme)

    for i: int in boxes.size():
        var box := boxes[i]
        var ground := (box.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
        assert_eq(ground.to_html(), before[i], "%s did not move when the push button's grounds were set" % box.get_class())
        for colour: Color in garish:
            assert_true(ground != colour, "%s draws none of the push button's own grounds" % box.get_class())

    host.free()
    _restore(saved)


## A default that did not follow a switch would be the same bug with a different
## constant in it.
func test_the_family_follows_a_palette_switch() -> void:
    var saved := _saved()
    var host := _host("default")
    var root := host.get_child(0) as Control
    var boxes := _check_boxes(root)
    var dark: Array[String] = []
    for box: Control in boxes:
        dark.append((box.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.to_html())

    SaTheme.use_named("paper")
    SaThemeDefaults.paint_colors(SaUI.shared_theme)

    for i: int in boxes.size():
        var box := boxes[i]
        var ground := (box.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
        assert_eq(ground, SaTheme.palette.bg_panel, "%s reads Paper White's panel colour" % box.get_class())
        assert_true(ground.to_html() != dark[i], "rather than the one the dark palette left there")

    host.free()
    _restore(saved)


## The boxes this adds carry the table's own four logical pixels, and the room
## the control takes in a row it sits in is what it was, which is the thing a
## padding change would have moved.
##
## The engine's own `CheckButton` box reads six pixels at the side and its
## control still measures the same as one wearing four, so the box and the
## control are separate measures and the second is the one a row sees.
func test_the_room_each_control_takes_in_a_row_does_not_move() -> void:
    var saved := _saved()
    var host := _host("default")
    var root := host.get_child(0) as Control
    for box: Control in _check_boxes(root):
        var cls := box.get_class()
        var resolved := box.get_theme_stylebox("normal")
        assert_eq(resolved.get_margin(SIDE_LEFT), float(SaUI.px(4)), "%s wears the table's margin" % cls)
        assert_eq(resolved.get_margin(SIDE_TOP), float(SaUI.px(SaThemeDefaults.MARGIN_Y)), "%s: and its vertical one" % cls)
        var wanted: Vector2 = FAMILY_MINIMUM[cls]
        assert_eq(
            box.get_combined_minimum_size(),
            Vector2(SaUI.px(int(wanted.x)), SaUI.px(int(wanted.y))),
            "%s measures the same in a row as it did" % cls
        )
    host.free()
    _restore(saved)
