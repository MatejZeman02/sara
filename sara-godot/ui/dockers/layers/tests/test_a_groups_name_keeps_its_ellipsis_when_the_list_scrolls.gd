## A group's name keeps its ellipsis when the list scrolls.
##
## With Krita's `.ora` open, once the
## Layers list was long enough for a scrollbar, the top group's name read
## "Group", its " 3" cut off with no ellipsis, while "Paint Lay..." kept its
## own. It might seem the group's row lost the overrun when the scrollbar
## took its width. It did not, and the fault is not the group's: a name and its
## row are the same label whatever the row is. Godot's plain
## `OVERRUN_TRIM_ELLIPSIS` adds its ellipsis only while the text it keeps is six
## characters or more, so a seven character name is cut to "Group" at every
## width under its own and says nothing, and a longer name loses the ellipsis
## in the last few pixels before it. A scrollbar is only what made the row
## narrow enough to show it.
##
## The row is drawn here into a viewport, inside the real list with a group on
## top and more rows than the list is tall, and the name's pixels are compared
## with the same label cut per character and given no ellipsis. A label whose
## ellipsis is missing draws exactly what the plain cut draws, so a picture that
## differs at every width the name does not fit is a name cut with a mark.
## `scenarios/a-groups-name-in-layers-keeps-its-ellipsis-when-the-list-scrolls.json`
## photographs the same in the running app.
extends "res://tests/test_framework.gd"

## The rows carry a thumbnail each, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The name that showed the fault, and the shortest a name can be and still lose
## its ellipsis to Godot's six character rule.
const NAME := "Group 3"

## Short of the rows' height, so the list scrolls and shows its bar.
const LIST_HEIGHT := 110

## The widths the list is drawn at, widest first. The name fits at the widest and
## is cut at the rest, whatever the interface scale the machine gives the tests.
const WIDEST := 420
const NARROWEST := 150
const STEP := 3

## Narrower than this the label has no room for the ellipsis itself, and a cut
## with nothing to show is not the fault.
const ELLIPSIS_ROOM := 24.0


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## A docker whose list holds a group named NAME, isolated as in the fault
## and the top row, over four more rows. Returns the easel, the canvas, the
## docker and the group, the first three freed in reverse.
func _docker_with_a_group_on_top() -> Array:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    for i in 4:
        ops.add()
    var group := ops.group_active()
    assert_not_null(group, "the last layer added went into a group, which is above the rest")
    group.name = NAME
    group.isolated = true

    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    return [easel, canvas, docker, group]


## Sorts every container under *node*, outside in, so the rectangles below it are
## the ones the running app would draw. A test cannot await a frame.
func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## Frees what the helper built and the viewport that held the list, in the order
## that leaves nothing standing.
func _free(parts: Array, viewport: SubViewport) -> void:
    viewport.free()
    (parts[1] as SaCanvas).free()
    (parts[2] as LayersDocker).free()
    (parts[0] as SaEasel).free()


## The row that carries *layer*, or null.
func _row_of(list: SaLayerList, layer: SaLayer) -> SaRowFrame:
    for i: int in list.row_count():
        if list.layer_at(i) == layer:
            return list.rows[i]
    return null


## The name's own rectangle out of one drawing of the viewport. A suite runs
## inside one frame, so the label is told to draw itself rather than left to the
## deferred redraw that a `force_draw` would find still waiting.
func _name_pixels(viewport: SubViewport, label: Label) -> PackedByteArray:
    RenderingServer.canvas_item_clear(label.get_canvas_item())
    label.notification(CanvasItem.NOTIFICATION_DRAW)
    RenderingServer.force_draw(false, 0.0)
    var rect := Rect2i(label.get_global_rect())
    return viewport.get_texture().get_image().get_region(rect).get_data()


func test_a_group_name_that_does_not_fit_ends_in_a_mark_at_every_width() -> void:
    var parts := _docker_with_a_group_on_top()
    var docker: LayersDocker = parts[2]
    var group: SaLayer = parts[3]
    var list: SaLayerList = docker.item_list
    list.get_parent().remove_child(list)
    list.owner = null

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDEST, LIST_HEIGHT)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    viewport.add_child(list)

    var row := _row_of(list, group)
    assert_not_null(row, "the group has a row in the list")
    if row == null:
        _free(parts, viewport)
        return
    assert_true(row.is_group, "and it is a group's")
    assert_true(row.isolated_mark.visible, "isolated, which is the mark that shares the row with the name")
    assert_eq(row.lbl.text, NAME, "under the name that showed the fault")

    var font := row.lbl.get_theme_font("font")
    var font_size := row.lbl.get_theme_font_size("font_size")
    var name_width := font.get_string_size(NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

    var built := row.lbl.text_overrun_behavior
    var checked := 0
    var unmarked: Array[int] = []
    var scrolled := true
    for width in range(WIDEST, NARROWEST, -STEP):
        viewport.size = Vector2i(width, LIST_HEIGHT)
        list.size = Vector2(width, LIST_HEIGHT)
        _sort_children(viewport)
        scrolled = scrolled and list.get_v_scroll_bar().visible
        var room := row.lbl.size.x
        if room >= name_width or room < ELLIPSIS_ROOM:
            continue
        checked += 1
        var as_built := _name_pixels(viewport, row.lbl)
        row.lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
        var plainly_cut := _name_pixels(viewport, row.lbl)
        row.lbl.text_overrun_behavior = built
        if as_built == plainly_cut:
            unmarked.append(width)

    assert_true(scrolled, "The list is past its height at every width, so its scrollbar takes its share of the row")
    assert_true(checked >= 8, "and the sweep met the name cut at %d widths, which is enough to mean the range" % checked)
    assert_true(unmarked.is_empty(), "The name ends in a mark at every one of them, and did not at %s" % str(unmarked))

    _free(parts, viewport)


func test_the_row_asks_for_the_cut_that_always_marks() -> void:
    var row := SaRowFrame.new(NAME, 0, true, 0)
    assert_eq(
        row.lbl.text_overrun_behavior,
        TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE,
        "The plain ellipsis is not enough: it leaves a name of six characters or fewer kept with no mark"
    )
    assert_eq(row.lbl.text_overrun_behavior, SaTheme.TEXT_CUT, "and it is the cut every name in Sara asks for, from one place")
    row.free()
