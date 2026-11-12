## A layer row's three locks read as off and on, and a group's row draws no
## paint lock.
##
## The toggles drawn at 30 per cent when off read as disabled, so a painter
## could not tell an off lock from one that cannot be pressed. A group's paint
## lock was lit though nobody locked it, and a group should carry no paint lock
## or a neutral mark saying "A group has no pixels of its own to paint on". The
## icons are held to a sensible size against the row.
extends "res://tests/test_framework.gd"

## The rows bind their thumbnails, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const WIDTH := 320


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## Off is drawn at full strength and in a different box from on, so the two
## states differ by look rather than by brightness.
func test_an_off_lock_is_drawn_at_full_strength_in_its_own_box() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    var row := SaLayerRowView.new("Layer 1", 0, false, 0, layer)
    row.refresh(easel.document)

    for which: StringName in row.toggles:
        var btn: Button = row.toggles[which]
        assert_false(btn.button_pressed, "%s starts off" % which)
        assert_almost_eq(btn.modulate.a, 1.0, 0.001, "%s is at full strength while it is off" % which)
        var off := btn.get_theme_stylebox("normal") as StyleBoxFlat
        var on := btn.get_theme_stylebox("pressed") as StyleBoxFlat
        assert_false(off.draw_center, "%s off is an outline with no ground" % which)
        assert_true(on.draw_center, "%s on is filled" % which)
        assert_eq(off.border_color, SaTheme.palette.text_muted, "%s off is outlined in the muted text colour" % which)
        assert_eq(on.bg_color, SaTheme.palette.toggle_on, "%s on is filled with the accent" % which)
        assert_eq(btn.custom_minimum_size.x, float(SaUI.px(SaRowFrame.TOGGLE_SIDE)), "%s is the larger size" % which)
        assert_true(btn.custom_minimum_size.y < float(SaUI.px(SaRowFrame.ROW_HEIGHT)), "inside the same row height")

    layer.is_locked = true
    row.refresh(easel.document)
    var lock: Button = row.toggles[&"paint"]
    assert_true(lock.button_pressed, "a locked layer's paint lock is on")
    assert_almost_eq(lock.modulate.a, 1.0, 0.001, "and at the same strength as an off one")

    row.free()
    easel.free()


## A group's row hides its paint lock, keeps an empty slot of the same width in
## its place, and the slot says why on hover.
func test_a_group_row_shows_no_paint_lock_and_keeps_its_slot() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := SaLayerOps.new(doc).group_active()
    var inner: SaLayer = group.get_child(0) if group.get_child_count() > 0 else doc.active_layer

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, 120)
    EventBus.add_child(viewport)
    var column := VBoxContainer.new()
    column.size = Vector2(WIDTH, 120)
    viewport.add_child(column)
    var group_row := SaLayerRowView.new(str(group.name), 0, true, 0, group)
    var layer_row := SaLayerRowView.new(str(inner.name), 0, false, 1, inner)
    column.add_child(group_row)
    column.add_child(layer_row)
    group_row.refresh(doc)
    layer_row.refresh(doc)
    column.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _sort_children(column)

    assert_true(group.is_locked, "the group still reports locked, which the brush relies on")
    var hidden_lock: Button = group_row.toggles[&"paint"]
    assert_false(hidden_lock.is_visible_in_tree(), "the group's row draws no paint lock")
    assert_not_null(group_row.paint_slot, "it keeps a slot where the lock is")
    assert_true(group_row.paint_slot.is_visible_in_tree(), "and the slot is laid out")
    assert_eq(
        group_row.paint_slot.tooltip_text, "A group has no pixels of its own to paint on", "the slot's tooltip is the sentence"
    )
    assert_null(layer_row.paint_slot, "a layer's row has no slot, it has its lock")

    var layer_lock: Button = layer_row.toggles[&"paint"]
    assert_almost_eq(group_row.paint_slot.size.x, layer_lock.size.x, 0.5, "the slot is as wide as a lock")
    assert_almost_eq(
        group_row.paint_slot.global_position.x, layer_lock.global_position.x, 0.5, "so the paint locks stay in one column"
    )
    var group_alpha: Button = group_row.toggles[&"alpha"]
    var layer_alpha: Button = layer_row.toggles[&"alpha"]
    assert_almost_eq(group_alpha.global_position.x, layer_alpha.global_position.x, 0.5, "and so do the alpha locks")

    viewport.free()
    easel.free()
