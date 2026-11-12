## The popup beside a toolbox button that lists the rest of its group, and the
## place a tool is dragged out of.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A [SaChoicePopup] rather than a `PopupMenu` or a panel of its own**. A
## menu's rows are not Controls, so nothing can be dragged out of one and
## nothing dropped between two of its rows, and a panel of its own would be a
## second copy of the icon cap, the keyboard, the scroll and the scale every
## menu in Sara needs. What is left here is what a toolbox
## flyout has that no other list does: a row is a drag source, a release over it
## is a drop between two tools, and the popup stands beside its button rather
## than under it.
##
## **Owned by the docker, told everything, and says what happened.** The rows
## are built from the descriptors the docker hands over, the tooltips come with
## them, and the two signals carry a row index or a drop back. The docker keeps
## the groups and the faces, and this file keeps nothing the dump would want.
##
## `@tool` because [SaChoicePopup] carries it, and the editor's language server
## warns MISSING_TOOL on a subclass that drops it.
@tool
class_name SaToolFlyout
extends SaChoicePopup

## A row was pressed, by its index in the last `open_beside`. Kept beside the
## base's own `chosen`, which carries the tool id: the docker addresses a row by
## number in its report, in its capture step and in `_flyout_ids`, so the index
## is the door and this file is the one place that turns one into the other.
signal row_picked(row: int)
## The button came up with a tool in hand, at *screen_at* in the root
## window's units. The docker resolves what was under the pointer, because it
## is the one that knows every button and every open flyout.
signal tool_released(tool_id: String, screen_at: Vector2)

## The key the drag data carries. A drop that does not carry it is somebody
## else's drag, a file from the desktop say, and is refused.
const DRAG_KEY := "toolbox_tool"

## The tool ids of the rows, in row order. Read by the docker for its dump and
## for the `pick` step, so the row a number means is decided here once.
var ids: Array[String] = []

## The side of the toolbox's buttons in logical pixels, which a row's height
## follows. Written by the docker before each opening.
var button_size: int = SaUI.BASE_TOOL_BTN


## `super()` and not the implicit call. A subclass that declares `_init` takes
## the base's over: without this line `SaChoicePopup._init` never ran, the panel
## and the scroll were never built, and the first `clear()` was a null column.
func _init() -> void:
    super()
    name = "Flyout"
    chosen.connect(_on_row_chosen)


## Rebuilds the rows for *members* and pops beside *anchor*. *labels* is the
## text per row, the docker's own tooltip string, and *icons* the icon name per
## row, empty for none. Pops only when the anchor is in a tree, because a suite
## builds the docker detached and asks about the rows rather than the screen.
func open_beside(anchor: Control, members: Array, labels: PackedStringArray, icons: PackedStringArray) -> void:
    clear()
    ids.clear()
    for i in members.size():
        var descriptor: SaToolDescriptor = members[i]
        var id := StringName(descriptor.id)
        add_row(
            id, labels[i] if i < labels.size() else descriptor.display_name, false, false, icons[i] if i < icons.size() else ""
        )
        ids.append(String(id))
        var row := label_button(id)
        if row == null:
            continue
        # A row of tools is as tall as the buttons it came out of, which is the
        # only place this list departs from the menu's own `ROW_HEIGHT`: the
        # flyout stands beside a column of buttons and a 24
        # tall row beside them reads as a different control.
        row.custom_minimum_size = Vector2(0.0, float(SaUI.px(button_size)))
        row.set_drag_forwarding(_drag_from.bind(i), _can_drop_on, Callable())
    # A popup is a `Window`, so it renders at a factor of its own and nothing
    # was writing one: with `embed_subwindows` off the docker beside it took
    # `SaUI.scale()` and this took 1.0, which is the flyout of rows about twice
    # the size of everything else, icons near 90 px against a docker whose own
    # buttons are half that. Through `apply_to_window` and nothing else, hard
    # rule 7, and that answers 1.0 for an embedded popup on its own, so the two
    # agree whichever way the setting is.
    #
    # Kept rather than dropped onto the base's `open_under`, which was checked:
    # `open_under` writes the factor and then opens *under* the anchor, and a
    # flyout under a toolbox button covers the next two tools down. So this file
    # keeps its own opening and calls the same one writer.
    #
    # Above the tree check rather than below it, because the factor a popup
    # renders at is a fact about the popup and not about whether it is on
    # screen, and a suite that builds the docker detached asks about it.
    #
    # With the toolbox's extra factor asked for first, the way `open_under` asks
    # for its docker's: a maximised toolbox draws a quarter larger, and a flyout
    # that asked for nothing stayed at 1.0 beside it.
    set_meta(SaUI.EXTRA_SCALE_META, SaUI.extra_scale(anchor.get_window()))
    SaUI.apply_to_window(self)
    if not anchor.is_inside_tree():
        return
    # Beside the button rather than under it, because the toolbox is usually a
    # column against the left edge and a popup below the button covers the
    # next two tools down. The button is measured on the host, since its `size`
    # is in the toolbox's units and a maximised toolbox's are a quarter smaller
    # than the host's, which would put the flyout over the button's right-hand
    # part.
    var span := SaPopupRect.of_anchor(anchor)
    # Zero rather than the anchor's width, which is what `open_under` passes: a
    # list under a button is at least that button wide because a painter aims at
    # the button, and a list beside a 40-pixel square has no such floor. Times
    # the factor, because `popup` measures the window on the host as well.
    var wanted := (Vector2(wanted_size(0.0)) * content_scale_factor).round()
    popup(Rect2i(Vector2i(Vector2(span.end.x, span.position.y)), Vector2i(wanted)))


## Every row as tall as a toolbox button of *side* logical pixels, the flyout
## being open or not, for a size chosen while it is.
func size_rows(side: int) -> void:
    button_size = side
    var row_h := float(SaUI.px(button_size))
    for id_str: String in ids:
        var row := label_button(StringName(id_str))
        if row != null and is_instance_valid(row):
            row.custom_minimum_size = Vector2(0.0, row_h)


## What a dump says about the popup itself: the factor it renders at, and a
## row's height in both the units it is laid out in and the pixels it is drawn
## at. The pair is the claim, because a row is the same logical height whatever
## the factor and a screenshot of a flyout twice the size of its docker is still
## a column of buttons.
func report() -> Dictionary:
    var row_height := 0.0
    if not ids.is_empty():
        var row := label_button(StringName(ids[0]))
        if row != null:
            row_height = row.size.y
    return {
        "content_scale_factor": content_scale_factor,
        "rows": ids.size(),
        "row_height": row_height,
        "row_height_drawn": row_height * content_scale_factor,
        "size": [size.x, size.y],
    }


## The release that ends a drag, taken here rather than left to the engine.
##
## **The engine drops only in the window the drag started in.** An embedded
## window forwards its input to whichever embedded window has focus, and a
## popup takes focus when it opens, so once the hover over a button opens that
## button's flyout, the release goes to the new popup, whose viewport never
## started a drag and does nothing with it: the tool would stay in hand until
## the next press somewhere dropped it on whatever that press hit. Read from the flyout's own `_input`, which is where a
## forwarded release arrives whichever flyout is focused, the release names
## the tool the root is carrying and where the pointer was, and the docker
## finds the row or the button under that point by its rectangle. The
## engine's drag is then cancelled, so nothing drops twice.
##
## The base's `_input` is the menu keyboard, up, down, enter, escape and
## type-ahead, and it answers key events only. It goes first because a release
## it cannot be interested in costs one cast, and because a flyout that ate the
## event before the list saw it would be the one menu in Sara with no keyboard.
func _input(event: InputEvent) -> void:
    super(event)
    var button := event as InputEventMouseButton
    if button == null or button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
        return
    var root := get_tree().root
    var data: Variant = root.gui_get_drag_data()
    if not is_tool_drag(data):
        return
    # The release is in this popup's own units, so it goes through the popup's
    # factor on its way to the host's, which a maximised toolbox makes 1.25.
    var at := Vector2(position) + get_final_transform() * button.position
    # Cancelled before the release is marked handled, never after. A cancelled
    # drag pushes a motion into this focused window to update the cursor, and
    # `push_input` clears the flag on its way in, so a mark made first would be
    # gone and the release would go on to the GUI pass. The drop can take this flyout out
    # of the tree, and that pass then fails on it.
    root.gui_cancel_drag()
    get_viewport().set_input_as_handled()
    tool_released.emit(String((data as Dictionary)[DRAG_KEY]), at)


## The row Control for *row*, for a capture that aims a pointer at it. The
## label button rather than the `HBoxContainer` around it, because the button is
## what carries the drag and what a pointer has to land on for one to start.
func row_control(row: int) -> Control:
    if row < 0 or row >= ids.size():
        return null
    return label_button(StringName(ids[row]))


## A row was chosen by its id, which is the tool's, and the docker wants the
## index. The base has already hidden the list, the way every menu in Sara does
## on a choice, and the docker's `_flyout_ids` outlives the hiding.
func _on_row_chosen(id: StringName) -> void:
    var row := ids.find(String(id))
    if row >= 0:
        row_picked.emit(row)


## What a drag out of row *row* carries: the tool id under the key, and a
## preview of the row's icon so the painter sees the tool move.
func _drag_from(_at: Vector2, row: int) -> Variant:
    if row < 0 or row >= ids.size():
        return null
    # `is_inside_tree` beside the icon check, because `set_drag_preview` refuses
    # a source out of a tree and refuses one with no drag running, and a preview
    # built for a refusal is a `TextureRect` nobody ever parents: three leaked
    # objects and a CanvasItem RID at exit, which is what the suite saw the first
    # time it asked this method for the drag data of a detached docker.
    var source := row_control(row) as Button
    if source != null and source.icon != null and source.is_inside_tree():
        var preview := TextureRect.new()
        preview.texture = source.icon
        preview.custom_minimum_size = Vector2(SaUI.px(button_size), SaUI.px(button_size))
        preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        preview.modulate.a = 0.8
        source.set_drag_preview(preview)
    return {DRAG_KEY: ids[row]}


## The cursor's answer while a tool passes over a row. The drop itself is
## [method _input]'s, for the reason given there.
func _can_drop_on(_at: Vector2, data: Variant) -> bool:
    return is_tool_drag(data)


## Which row *screen_at* is on, and whether its upper half, as `[row, before]`,
## or `[-1, false]` for a point outside every row.
##
## Asked of the rows by id and not of the column's children, because the engine
## parents a drag's preview under the source's root Control, which is inside
## this popup, and the preview sits under the pointer by definition: counting
## every child would make every release a hit on the picture of the tool in
## hand.
func row_at(screen_at: Vector2) -> Array:
    for i in ids.size():
        var control := label_button(StringName(ids[i]))
        # Out of a tree beside null, because `get_screen_position` on a detached
        # Control is an engine error in the console and a Vector2.ZERO back,
        # which reads as a rectangle at the origin that a point could land in.
        # A suite builds the docker detached and asks this method what is under
        # a point, and the answer there is "no row" rather than a screenful of
        # red.
        if control == null or not control.is_inside_tree():
            continue
        # On the host, like the point, since a row's `size` is in this popup's units
        # and a flyout on a maximised toolbox draws it a quarter taller.
        var rect := SaPopupRect.of_anchor(control)
        if rect.has_point(screen_at):
            return [i, screen_at.y < rect.position.y + rect.size.y * 0.5]
    return [-1, false]


## Whether *data* is a tool being dragged from a flyout.
static func is_tool_drag(data: Variant) -> bool:
    return data is Dictionary and (data as Dictionary).has(DRAG_KEY)
