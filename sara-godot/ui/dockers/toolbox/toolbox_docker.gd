## Floating toolbox window for selecting drawing and navigation tools.
##
## The buttons follow the shape the painter drags the docker into: a wide short
## docker is a single row and everything else is one column, the default, under
## the name Follow the shape. A drag never makes a grid.
##
## **Preferences can override it**, with an orientation and a cap on the rows
## or columns the wrap uses. The arithmetic and the two options live in
## [`toolbox_grid.gd`](toolbox_grid.gd).
##
## **One button per group, not per tool, and the groups are the painter's**, so
## a toolbox of many tools stays a few buttons. A button shows its group's
## chosen tool and a right press opens the rest of the group beside it, where
## a tool can be dragged out and dropped into another group. A group is a list of tool
## ids held by [SaToolBoxGroups], the registry's categories until a painter
## drags, and the flyout is [SaToolFlyout], a column of buttons a tool is
## dragged out of and dropped into, on a row or on a button, with a hover over a
## button opening its flyout so a row of it can be reached. Every name below
## that says category means the group.
@tool
extends DockerWindow

class_name ToolBoxDocker

const DockerColumnScroll := preload("res://ui/dockers/docker_column_scroll.gd")

var grid_container: GridContainer
var target_tool_machine: ToolMachine

## The side of the corner mark on a button that has a flyout under it, in
## logical pixels. A category of one draws without it, which is what tells the
## two apart at a glance. Drawn in the muted text colour, because a bright
## corner reads as part of the icon, and the button's tooltip says what it
## promises.
const FLYOUT_MARK_SIDE := 10

## Category -> the one Button drawn for it.
var _buttons: Dictionary = {}
## Category -> Array[SaToolDescriptor], in the order the registry listed them.
var _members: Dictionary = {}
## Category -> the tool id the button is currently showing.
var _faces: Dictionary = {}
## Category -> its [SaToolFlyout], built on first use and kept.
var _flyouts: Dictionary = {}
## The groups in force, an array of arrays of tool ids, and the name each
## answers to, so a rebuild can tell whether the profile moved them.
var _groups: Array = []
var _group_names: Array = []
## Tool id -> its category, so a tool changed by a chord finds its button.
var _tool_category: Dictionary = {}
## The ids of the rows in the flyout that is open, since a member hidden from
## Preferences changes what row 2 means between one press and the next.
var _flyout_ids: Array[String] = []
## The category whose flyout is up, for the capture harness and for closing it.
var _open_flyout: StringName = &""
var _tool_registry: SaToolRegistry = null
var _button_group: ButtonGroup = ButtonGroup.new()
## What the docker last grew to hold, as the orientation, the cap and the number
## of buttons, so a forced layout opens at its tools once and then leaves the
## size to the painter. Empty while the docker follows its own shape.
var _fitted_for: String = ""
## The size the buttons and the flyouts' rows are drawn at, and its menu.
var size_controller: SaToolBoxSize


func _init() -> void:
    size_controller = SaToolBoxSize.new(self)
    size_controller.size_changed.connect(_on_button_size_changed)
    add_child(size_controller)
    var u := SaToolBoxSize.DEFAULT_SIZE
    var m := 2
    # The minimum is one full column plus its margins, and nothing else, so a
    # docker resized or restored down to it still shows its buttons. Whatever
    # else the column asks is asked of it by `enforce_column_minimum`, per scale
    # pass and per layout, with the bar and the scroll in their narrowest form.
    var col_w := u + m * 2
    _init_docker(
        SaDockerIds.TOOLBOX,
        "Toolbox",
        Vector2i(col_w, u * 6 + SaUI.BASE_DRAG_H + m * 2),
        Vector2i(col_w, SaUI.BASE_DRAG_H + u + m * 2)
    )

    # No gap under the bar, which was a strip of empty docker above the buttons.
    var vbox := SaMake.column(_control_node, "VBoxContainer", 0)
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    # A wrench rather than the `tools` glyph. The bar is one button wide and has room for the wrench alone, so its name is said
    # on hover, which `make_drag_bar` does for a bar with an icon.
    drag_handle = DockerUtils.make_drag_bar("Toolbox", false, "wrench")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(null, "MarginContainer", m)
    # Scrolled rather than the window floored at the grid's height.
    DockerColumnScroll.wrap(vbox, margin)

    grid_container = SaMake.grid(margin, "GridContainer", 1)
    grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

    # Buttons are built in _ready from the tool registry, because modules have
    # not registered anything yet when _init runs.

    # The two Preferences rows. Here rather than in `_ready`, because the
    # Preferences window can be opened before this docker has ever been shown and
    # the page would then draw the list with no options above the Hide button.
    # `_instantiate_registered_dockers` builds every registered docker at startup
    # whether it is open or not, so this runs once, early, either way.
    SaToolBoxGrid.register_options()


## The minimum is one button and its margins at the size now chosen, as `_init`
## sets it at the default. The floor is laid again from it by `_fit_to_the_tools`,
## down as well as up, so a docker widened for large buttons can be dragged
## narrow again once they are small.
func _on_button_size_changed(new_size: int) -> void:
    size_controller.apply_to_buttons(_buttons, _flyouts)
    logical_min_size = Vector2i(new_size + 4, SaUI.BASE_DRAG_H + new_size + 4)
    _apply_orientation()
    _fit_to_the_tools()


## Rebuilds the buttons from the registry. Connected to its `changed` signal, so a
## tool registered later, a module's among them, still gets a button.
func rebuild_from_registry(registry: SaToolRegistry) -> void:
    if registry == null or grid_container == null:
        return
    if not registry.changed.is_connected(_on_registry_changed):
        registry.changed.connect(_on_registry_changed)
    _tool_registry = registry

    # Out of the grid now and freed at the end of the frame. A button only queued
    # stayed a child until then, so the row counted ten columns for five buttons
    # and each new button found its name taken.
    for child in grid_container.get_children():
        grid_container.remove_child(child)
        child.queue_free()
    _buttons.clear()
    _members.clear()
    _tool_category.clear()
    _flyouts.clear()
    _open_flyout = &""

    # The groups are the profile's, which are the registry's categories in
    # the order the registry listed the first tool of each until a painter
    # drags a tool, and a module that registers late lands after the built-ins.
    # A brush engine has no button of its own, since
    # it paints under the Brush's.
    var descriptors := registry.list_tools()
    var by_id: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        by_id[String(descriptor.id)] = descriptor
    _groups = SaToolBoxGroups.stored(descriptors)
    _group_names = SaToolBoxGroups.names_for(_groups, descriptors)
    for i in _groups.size():
        var category := StringName(_group_names[i])
        _members[category] = [] as Array[SaToolDescriptor]
        for tool_id: String in _groups[i]:
            (_members[category] as Array[SaToolDescriptor]).append(by_id[tool_id])
            _tool_category[tool_id] = category
    for category: StringName in _members:
        _add_category_button(category)
    if descriptors.is_empty():
        _add_empty_state()

    apply_layout_settings()
    if target_tool_machine != null:
        _on_event_tool_changed(String(target_tool_machine.active_tool_name))


func _on_registry_changed() -> void:
    rebuild_from_registry(_tool_registry)
    # After the new buttons have been laid out once, because a grid's minimum
    # is only its own until then.
    grow_to_content.call_deferred()


## Opens the docker at the height of every button it holds until the painter has
## arranged a docker, for a tool a module registers after the layout was placed,
## which the layout's fit could not count. Counted from the registry's buttons,
## never a number, and only as far as the host leaves room.
func grow_to_content() -> void:
    if DockerWindow.painter_sized or grid_container == null:
        return
    var opened := opening_height(size)
    if opened <= 0:
        return
    var host := DockerDragHandle.host_size_of(self)
    if host != Vector2i():
        var factor := SaUI.window_scale(self)
        var top := maxi(position.y, int(ceil(_bar_height() * factor)))
        opened = mini(opened, maxi(host.y - top - int(ceil(SaStatusLine.rows_taken() * factor)), 0))
    if opened > size.y:
        size = Vector2i(size.x, opened)
        # Or the store's settle loop puts the old height back.
        var store := (
            get_tree().root.find_child("DockerLayoutStore", true, false) as DockerLayoutStore if is_inside_tree() else null
        )
        if store != null:
            store.note_placement(self)


## The honest empty state. Every tool ships in a module, so a build with no modules opens with this
## rather than with six buttons, and it has to say why rather than look broken.
## Short, because the docker is one button wide, with the reason in the tip.
##
## The tip speaks to a painter first: a release whose shipped module failed to
## load shows this too, and reinstalling is that painter's way back. The
## README's step is the way back for a copy built from source.
func _add_empty_state() -> void:
    var label := SaMake.label(grid_container, "EmptyState", tr("No tools"))
    label.autowrap_mode = TextServer.AUTOWRAP_WORD
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_STOP
    label.tooltip_text = tr(
        "No tool module is loaded. Reinstall Sara, or for a copy built from source, add sara-base-modules as the README says."
    )


## One button for *category*, showing whichever of its tools was chosen last.
##
## The name is the category's and not the tool's, because a stored docker layout
## and a capture both address a button by name and the face underneath it moves.
func _add_category_button(category: StringName) -> void:
    var btn := SaMake.button(null, String(category).capitalize() + "Btn")
    btn.toggle_mode = true
    # Every category button shows its state: which category is active was the
    # engine's default pressed box, which against a dark docker is no answer.
    SaTheme.make_toggle(btn)
    btn.button_group = _button_group
    btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    grid_container.add_child(btn)
    # Square rather than height-only. A column stretched each button across the
    # docker and nothing noticed, but a row of six in a wide docker collapsed to
    # whatever width was left over, which at the minimum height is a sliver. The
    # corner mark comes with it, sized to match.
    size_controller.size_button(btn)

    btn.pressed.connect(_on_category_button_pressed.bind(category))
    btn.gui_input.connect(_on_category_button_input.bind(category))
    # Answers the hover of a tool in hand, which opens the flyout and shapes
    # the cursor. The drop itself is read off the release, in `_on_tool_released`.
    btn.set_drag_forwarding(Callable(), _can_drop_on_button.bind(category), Callable())
    # The chord is written when the pointer arrives, not now, so one changed in
    # Preferences shows without a restart.
    btn.mouse_entered.connect(_refresh_tooltip.bind(category))
    _buttons[category] = btn
    _sync_category_button(category)


## Puts the face tool's icon, tooltip and flyout mark on *category*'s button.
##
## Called on every rebuild, every face change and every visibility change, since
## all three can change which tool the button stands for and whether the corner
## mark is a promise it can keep.
func _sync_category_button(category: StringName) -> void:
    var btn: Button = _buttons.get(category)
    if btn == null or not is_instance_valid(btn):
        return
    var descriptor := _face_descriptor(category)
    if descriptor == null:
        return
    btn.text = descriptor.display_name
    if descriptor.icon_name != "":
        SaUI.set_button_icon(btn, descriptor.icon_name, descriptor.display_name)
    btn.tooltip_text = _button_tooltip(category)
    var mark := btn.get_node_or_null("FlyoutMark") as Control
    if mark != null:
        mark.visible = _visible_members(category).size() > 1


## The button *tool_id* is drawn by, which is its category's, or null when no
## button draws it. Public because a button is one per group and not one per
## tool, so a caller with a tool id asks here rather than indexing `_buttons`.
func button_for_tool(tool_id: String) -> Button:
    var category := StringName(_tool_category.get(tool_id, &""))
    if category == &"":
        return null
    return _buttons.get(category)


## Which tools *tool_id*'s button stands for, in registry order, including the
## ones Preferences has hidden. A module tool reaching the toolbox means being
## in one of these lists, which is the shape the public-door check reads.
func tools_in_category_of(tool_id: String) -> Array[String]:
    var out: Array[String] = []
    var category := StringName(_tool_category.get(tool_id, &""))
    if category == &"":
        return out
    for descriptor: SaToolDescriptor in _members.get(category, [] as Array[SaToolDescriptor]):
        out.append(String(descriptor.id))
    return out


## Makes *tool_id* the face of its own button, the way picking it from the
## flyout does, so a tooltip or an icon can be read for a tool that is a member
## rather than the one showing.
func show_tool(tool_id: String) -> bool:
    var category := StringName(_tool_category.get(tool_id, &""))
    if category == &"":
        return false
    _faces[category] = tool_id
    _sync_category_button(category)
    return true


## The descriptor the button is showing: the face if it is still a member and
## still visible, else the first member a painter can reach.
func _face_descriptor(category: StringName) -> SaToolDescriptor:
    var members := _visible_members(category)
    if members.is_empty():
        return null
    var face := String(_faces.get(category, ""))
    for descriptor: SaToolDescriptor in members:
        if String(descriptor.id) == face:
            return descriptor
    _faces[category] = String((members[0] as SaToolDescriptor).id)
    return members[0]


## *category*'s tools that Preferences has not hidden, in registry order. A
## hidden tool leaves the flyout as well as the grid, or the flyout would offer
## a row the painter has switched off.
func _visible_members(category: StringName) -> Array[SaToolDescriptor]:
    var out: Array[SaToolDescriptor] = []
    for descriptor: SaToolDescriptor in _members.get(category, [] as Array[SaToolDescriptor]):
        if SaSettings.get_element_visible(SaDockerIds.TOOLBOX, SaToolBoxGrid.layout_entry_for(descriptor)):
            out.append(descriptor)
    return out


func _refresh_tooltip(category: StringName) -> void:
    _sync_category_button(category)


## "Brush (B)" - the shortcut is read from the descriptor's InputMap action, so a
## module tool documents its own key without editing this file.
##
## Through the command registry's formatter rather than by hand, because the
## hand-written version asked for `as_text_keycode()` alone and project.godot
## binds most keys physically: the bucket fill's bracket read "(unset)".
## The InputMap is the live binding, which is what a registered command writes
## its chord into and what an editor rewrites, so reading it at hover is
## reading the registry. The name is read through the catalogue at hover too,
## so a tooltip is in the language set when it shows.
func _tooltip_for(descriptor: SaToolDescriptor) -> String:
    var text := tr(descriptor.display_name)
    var action := descriptor.activate_action
    if String(action).is_empty() or not InputMap.has_action(action):
        return text
    var chord := SaCommandRegistry.format_events(InputMap.action_get_events(action), 1)
    if chord.is_empty():
        return text
    return "%s (%s)" % [text, chord]


## What *category*'s button says on hover: its face as [method _tooltip_for]
## writes it, and for a group the tools a right press opens, "Brush (B). Right
## press for Noise Brush and Smudge."
##
## Nothing else on the button says the flyout is there, and the corner mark
## reads as part of the icon. A flyout row keeps [method _tooltip_for]
## alone, because it is the tool it names.
func _button_tooltip(category: StringName) -> String:
    var face := _face_descriptor(category)
    if face == null:
        return ""
    var others := PackedStringArray()
    for descriptor: SaToolDescriptor in _visible_members(category):
        if descriptor != face:
            others.append(tr(descriptor.display_name))
    if others.is_empty():
        return _tooltip_for(face)
    var listed := others[-1]
    if others.size() > 1:
        listed = tr("%s and %s") % [", ".join(others.slice(0, -1)), listed]
    return tr("%s. Right-click for %s.") % [_tooltip_for(face), listed]


## The height a shipped layout that gives this docker *given* opens it at, in
## the units its geometry is measured in: its buttons in the shape that
## rectangle makes of them and the grip's corner under them, and nothing more.
## Asked by `SaDockerLayoutRefit.opening_height`.
##
## So the opening size fits exactly what is there, rather than a fixed height
## that leaves half of the docker empty. A docker without this keeps the height the layout gives it, which
## is the answer for one whose content grows with the painting, the library or
## the tool in the hand, so a docker opts in by saying how tall it is rather
## than the layout guessing which ones may shrink.
##
## **In the layout's shape, not the one on screen**, or a toolbox the painter
## had dragged into a row would read the row's height when a layout's column is
## loaded over it, and a rectangle cut to that would stay a row. And 0 when the cut would
## itself turn the column into a row, which keeps the layout's height.
func opening_height(given: Vector2i) -> int:
    if grid_container == null:
        return 0
    var factor := SaUI.window_scale(self)
    var logical := Vector2(given) / factor
    var count := _visible_button_count()
    var button := float(size_controller.current_size)
    var columns := SaToolBoxGrid.columns_for(count, logical.x, logical.y, button)
    var drawn := grid_container.columns
    grid_container.columns = columns
    var opened := int(ceil((column_content_height(self) + _grip_height()) * factor))
    grid_container.columns = drawn
    if SaToolBoxGrid.columns_for(count, logical.x, minf(logical.y, opened / factor), button) != columns:
        return 0
    return opened


## One tool wide, so the bar holds the wrench and the close and no pin, whatever
## the pin switch says.
func apply_pin_button() -> void:
    pin_button.visible = false


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    assert(grid_container != null, "GridContainer node not found")

    _setup_docker_ready()
    size_controller.take_the_bar()

    size_changed.connect(_on_window_size_changed)

    if not EventBus.tool_changed.is_connected(_on_event_tool_changed):
        EventBus.tool_changed.connect(_on_event_tool_changed)

    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.TOOLBOX)
    # A preset loaded over the profile, or a drag on this docker, changes which
    # tools share a button, and a button is built once per group, so the
    # buttons are made again when the profile's groups are not the ones drawn.
    if _tool_registry != null and SaToolBoxGroups.stored(_tool_registry.list_tools()) != _groups:
        rebuild_from_registry(_tool_registry)
        return

    var vbox := get_node_or_null("Control/VBoxContainer")
    if not vbox:
        return
    var margin := vbox.get_node_or_null("Scroll/MarginContainer")
    if not margin:
        return

    var order := SaSettings.get_layout_order(SaDockerIds.TOOLBOX)
    var current_idx := 0
    for element: String in order:
        if element == "Drag Handle" and drag_handle:
            vbox.move_child(drag_handle, current_idx)
            current_idx += 1

    if drag_handle:
        drag_handle.visible = SaSettings.get_element_visible(SaDockerIds.TOOLBOX, "Drag Handle")

    if grid_container:
        # A category button takes the place of its earliest visible member, so
        # the order a painter arranged tools in still decides which button comes
        # first even though the rows and the buttons are not one to one.
        var placed: Dictionary = {}
        var current_btn_idx := 0
        for element: String in order:
            var category := SaToolBoxGrid.category_for_layout_entry(_members, element)
            if category == &"" or placed.has(category):
                continue
            if not SaSettings.get_element_visible(SaDockerIds.TOOLBOX, element):
                continue
            grid_container.move_child(_buttons[category] as Button, current_btn_idx)
            current_btn_idx += 1
            placed[category] = true
        # A category with every member hidden has no row to be placed by and no
        # tool to show, so it comes off rather than drawing an empty square.
        for category: StringName in _buttons:
            var btn: Button = _buttons[category]
            btn.visible = not _visible_members(category).is_empty()
            _sync_category_button(category)

    # Hiding a tool changes how many buttons the row has to hold, so the column
    # cap is stale the moment this runs.
    _apply_orientation()
    _fit_to_the_tools()


func _on_window_size_changed() -> void:
    _apply_orientation()


## The floor is read with the bar and the scroll in their narrowest form, so
## neither holds the docker wider than its buttons.
func enforce_column_minimum() -> void:
    size_controller.fit_edges(0.0)
    super()


## The grip draws over the corner, and `SaToolBoxSize.overlay_the_grip` says why.
func reserve_grip_corner() -> void:
    size_controller.overlay_the_grip()


## Hands the grid the columns `SaToolBoxGrid` works out from the docker's
## rectangle, both sides, plus its buttons their width in them.
##
## A forced orientation also hands it how much room the host leaves, so the
## tools wrap rather than run past the docker's edge.
func _apply_orientation() -> void:
    if grid_container == null:
        return
    # Window.size is physical for a real OS window and logical for an embedded one
    # while the button metrics are always logical, so both sides are divided first.
    var logical := Vector2(size) / SaUI.window_scale(self)
    var count := _visible_button_count()
    var forced := SaToolBoxGrid.orientation() != SaToolBoxGrid.FOLLOW_SHAPE
    var room := _room_for_the_grid() if forced else Vector2.INF
    var gap := Vector2(grid_container.get_theme_constant(&"h_separation"), grid_container.get_theme_constant(&"v_separation"))
    var button := float(size_controller.current_size)
    grid_container.columns = SaToolBoxGrid.columns_for(count, logical.x, logical.y, button, room, gap)
    SaToolBoxGrid.apply_button_width(grid_container, _buttons, grid_container.columns, count)


## The longest the grid may run along each axis, in logical units, and infinite
## where there is no host to ask.
##
## The host less what the docker stands around the grid in, which is measured
## off the column rather than counted: the margins, the drag bar and the grip
## are whatever the theme and the scale made them. The bar is taken off the
## host's height as well, since a docker is never placed above it.
func _room_for_the_grid() -> Vector2:
    var host := DockerDragHandle.host_size_of(self)
    if host == Vector2i():
        return Vector2.INF
    var around := (
        Vector2(column_min_width(self), column_content_height(self) + _grip_height())
        - (grid_container.get_combined_minimum_size())
    )
    return Vector2(host) / SaUI.window_scale(self) - around - Vector2(0.0, _bar_height())


## Opens a forced orientation at what its tools need, and keeps its floor.
##
## **The floor is set again on every pass, down as well as up.**
## `enforce_column_minimum` only ever raises, and it ran on a scale pass alone,
## so a row forced on after the docker was drawn had a floor under its own
## width and a docker dragged narrower cut its last tools off. Starting from the
## declared floor lets the same pass take it back when the painter changes the
## orientation to one that wants less.
##
## **The size grows once for each layout and never shrinks.** Along the long
## side of the forced layout, to what the column asks and no further than the
## host, and then it is the painter's to drag: growing again on every setting
## written would fight a hand that had just made the docker small. Where the
## host is too short the grid has already wrapped to more columns or rows, so
## what is asked fits.
func _fit_to_the_tools() -> void:
    var declared := SaUI.window_size_for(self, logical_min_size)
    min_size = Vector2i(declared.x, min_size.y)
    enforce_column_minimum()
    if SaToolBoxGrid.orientation() == SaToolBoxGrid.FOLLOW_SHAPE:
        _fitted_for = ""
        return
    var layout := "%s %d %d" % [SaToolBoxGrid.orientation(), SaToolBoxGrid.max_lines(), _visible_button_count()]
    if layout == _fitted_for:
        return
    _fitted_for = layout
    var wanted := SaUI.window_size_for(self, Vector2i(column_min_width(self), column_content_height(self) + _grip_height()))
    var host := DockerDragHandle.host_size_of(self)
    var grown := Vector2i(maxi(size.x, wanted.x), maxi(size.y, wanted.y))
    if host != Vector2i():
        var limit := host - Vector2i(0, int(ceil(_bar_height() * SaUI.window_scale(self))))
        grown = Vector2i(maxi(size.x, mini(wanted.x, limit.x)), maxi(size.y, mini(wanted.y, limit.y)))
    if grown == size:
        return
    size = grown
    if is_embedded() and host != Vector2i():
        # As little as it takes to stay on the host and under the bar, or over
        # it where the painter put it, and a host too short for both keeps the
        # title strip.
        var top := mini(int(ceil(_bar_height())), maxi(position.y, 0))
        position = Vector2i(clampi(position.x, 0, maxi(host.x - size.x, 0)), maxi(mini(position.y, host.y - size.y), top))


## What the column leaves clear at its foot for the grip, which is nothing, since
## the grip draws over the last button's corner.
func _grip_height() -> int:
    return 0


## The rows under the menu bar a docker is never placed over, in the host's
## units, and none for a docker that is an OS window of its own.
func _bar_height() -> float:
    if not is_embedded() or not SaDialogWindow.top_inset.is_valid():
        return 0.0
    return float(int(SaDialogWindow.top_inset.call()))


func _visible_button_count() -> int:
    return SaToolBoxGrid.visible_button_count(grid_container)


## What the docker is currently laid out as, for the capture harness. `shape` is
## the word a person would use for the rectangle, `columns` and `rows` are what
## the grid actually did about it, and `buttons` is each visible button's drawn
## rect, because "a row" is a claim about where the buttons ended up rather than
## about a number the docker holds.
##
## Each button also carries its `tooltip`. A tooltip is the one thing neither a
## shot nor a dump could show, so a chord in brackets was ungradable
## from a run, and the house shape for it is the `tooltip`
## key `ToolOptionsDocker.capture_state` puts on every Tool Options row.
func toolbox_report() -> Dictionary:
    if grid_container == null:
        return {"present": false}
    var visible_count := _visible_button_count()
    var columns := grid_container.columns
    var rows := 0 if visible_count == 0 else int(ceil(float(visible_count) / float(columns)))
    var shape := SaToolBoxGrid.shape_of(columns, visible_count)
    var rects: Array = []
    for child in grid_container.get_children():
        if not (child is Control) or not (child as Control).visible:
            continue
        var control := child as Control
        var entry := {
            "name": String(control.name),
            "position": [control.position.x, control.position.y],
            "size": [control.size.x, control.size.y],
            "tooltip": control.tooltip_text,
        }
        # Which category the button stands for, which of its tools it is
        # showing, and the tools behind it. A flyout is a claim about where
        # twelve tools went when five buttons are drawn, and a screenshot of
        # five squares grades that claim poorly.
        var category := _category_of_button(control)
        if category != &"":
            var face := _face_descriptor(category)
            entry["category"] = String(category)
            entry["face"] = String(face.id) if face != null else ""
            var member_ids: Array = []
            for descriptor: SaToolDescriptor in _visible_members(category):
                member_ids.append(String(descriptor.id))
            entry["members"] = member_ids
            entry["has_flyout"] = member_ids.size() > 1
            # Composed here rather than read off the button, because the
            # button's own text is only rebuilt on hover and on a rebuild, so
            # after a rebind it is stale until a pointer visits it. This is the
            # function the hover calls, so a dump says what a hover would show
            # and a run can grade a chord without a mouse.
            if face != null:
                entry["tooltip"] = _button_tooltip(category)
        # Where a pointer has to land to press this button, so the capture aims
        # at what the docker says and reads no member of it. `rect` is on the
        # host, where an injected event is addressed, and `rect_in_window` is in
        # the docker's own viewport, which is where a docker the desktop gave a
        # window of its own takes a pushed event. In a tree only: a suite builds
        # the docker detached, and a screen position asked of a detached Control
        # is an engine error.
        if control.is_inside_tree():
            entry["rect"] = _rect_as_array(SaPopupRect.of_anchor(control))
            entry["rect_in_window"] = _rect_as_array(control.get_global_rect())
        rects.append(entry)
    return {
        "present": true,
        "shape": shape,
        "columns": columns,
        "rows": rows,
        "visible_buttons": visible_count,
        # What Preferences asked for, beside what the grid did about it. A shape
        # alone cannot say whether a two-row toolbox is two rows because the
        # painter asked or because the docker happens to be that wide.
        "orientation": SaToolBoxGrid.orientation(),
        "max_lines": SaToolBoxGrid.max_lines(),
        "tools": _tool_category.size(),
        "window_size": [size.x, size.y],
        "logical_size": [size.x / SaUI.window_scale(self), size.y / SaUI.window_scale(self)],
        "buttons": rects,
        "flyout": _flyout_report(),
        # The groups as lists of ids, in button order, which is the claim a drop
        # makes and the thing a fresh preset has to show as the registry's.
        "groups": _groups.duplicate(true),
        "group_names": _group_names.duplicate(),
    }


## The open flyout, or that there is none. `members` is what the menu is showing
## rather than what the category holds, so a row hidden from Preferences is
## absent here too and the two can be read against each other.
func _flyout_report() -> Dictionary:
    if _open_flyout == &"":
        return {"open": false}
    var flyout: SaToolFlyout = _flyouts.get(_open_flyout)
    var live := flyout != null and is_instance_valid(flyout)
    # Every row of the popup with its rectangle on the host, in row order, which
    # is what a press or a drag onto a row aims at. From the popup's own `ids`
    # and not from `_flyout_ids`, because the rectangles are of the rows it is
    # showing.
    var row_rects: Array = []
    if live:
        for row in flyout.ids.size():
            var control := flyout.row_control(row)
            if control == null or not control.is_inside_tree():
                continue
            row_rects.append({"id": flyout.ids[row], "rect": _rect_as_array(SaPopupRect.of_anchor(control))})
    return {
        "open": live and flyout.visible,
        "category": String(_open_flyout),
        "members": _flyout_ids.duplicate(),
        "popup": flyout.report() if live else {},
        "row_rects": row_rects,
    }


static func _rect_as_array(rect: Rect2) -> Array:
    return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _category_of_button(control: Control) -> StringName:
    for category: StringName in _buttons:
        if _buttons[category] == control:
            return category
    return &""


## A left press picks the tool the button is showing.
func _on_category_button_pressed(category: StringName) -> void:
    var descriptor := _face_descriptor(category)
    if descriptor != null:
        _select_tool(String(descriptor.id))


## A right press opens the flyout instead, and does not change the tool.
##
## On the button rather than on the docker, because `gui_input` gives the button
## the press before the tool machine ever sees it and a right press that reached
## the canvas would open the tool context menu over the toolbox.
func _on_category_button_input(event: InputEvent, category: StringName) -> void:
    var button_event := event as InputEventMouseButton
    if button_event == null or not button_event.pressed:
        return
    if button_event.button_index != MOUSE_BUTTON_RIGHT:
        return
    open_flyout(category)
    # On the button and not on `self`: the handler is the button's `gui_input`,
    # and a `DockerWindow` is a Window, which has no `accept_event`.
    var btn: Button = _buttons.get(category)
    if btn != null and is_instance_valid(btn):
        btn.accept_event()


## Shows *category*'s other tools beside its button. False when the category has
## fewer than two tools a painter can reach, which is a plain button and says so
## by having no corner mark.
func open_flyout(category: StringName) -> bool:
    var members := _visible_members(category)
    var btn: Button = _buttons.get(category)
    if members.size() < 2 or btn == null or not is_instance_valid(btn):
        # Cleared on the way out as well, or a refusal reports the rows of
        # whichever flyout was open last and reads as if it had opened.
        _flyout_ids.clear()
        _open_flyout = &""
        return false
    var labels := PackedStringArray()
    var icons := PackedStringArray()
    for descriptor: SaToolDescriptor in members:
        labels.append(_tooltip_for(descriptor))
        icons.append(descriptor.icon_name)
    var flyout := _flyout_for(category)
    # The rows are built whether or not there is a screen to put them on, and
    # only the popping needs one: a suite builds this docker detached, where
    # `get_screen_position` is an error and `popup` has no tree to reach. What
    # a test asks about is the rows and the face, which are decided here.
    flyout.open_beside(btn, members, labels, icons)
    _flyout_ids = flyout.ids.duplicate()
    _open_flyout = category
    return true


## The flyout for *category*, built once and kept. A child of the button, so
## it follows it into and out of the tree and a rebuild frees both together.
func _flyout_for(category: StringName) -> SaToolFlyout:
    var existing: SaToolFlyout = _flyouts.get(category)
    if existing != null and is_instance_valid(existing):
        return existing
    var flyout := SaToolFlyout.new()
    flyout.button_size = size_controller.current_size
    flyout.row_picked.connect(_on_flyout_id_pressed)
    flyout.tool_released.connect(_on_tool_released)
    flyout.popup_hide.connect(_on_flyout_hidden.bind(category))
    (_buttons[category] as Button).add_child(flyout)
    _flyouts[category] = flyout
    return flyout


## Shuts every flyout, which a drop does: the one the tool left and the one
## it landed in are both stale the moment the groups change.
func close_flyouts() -> void:
    for category: StringName in _flyouts:
        var flyout: SaToolFlyout = _flyouts[category]
        if flyout != null and is_instance_valid(flyout) and flyout.visible:
            flyout.hide()
    _open_flyout = &""
    _flyout_ids.clear()


## A row of the open flyout was pressed: that tool becomes the button's face and
## the active tool, which is one gesture and so one call rather than two.
func _on_flyout_id_pressed(id: int) -> void:
    if id < 0 or id >= _flyout_ids.size():
        return
    var tool_id: String = _flyout_ids[id]
    var category := StringName(_tool_category.get(tool_id, &""))
    if category != &"":
        _faces[category] = tool_id
        _sync_category_button(category)
    _select_tool(tool_id)


## A press outside the popup closes it, which Godot does on its own. Here so
## the dump stops claiming one is open, and by category because a drag holds
## two open and the one hiding may not be the one the dump calls open.
func _on_flyout_hidden(category: StringName) -> void:
    if _open_flyout == category:
        _open_flyout = &""


## A tool in hand over *category*'s button: the drop is welcome, and the
## button's flyout opens under the pointer so a row of it can be the target.
## Opened on the hover and not on the drop, because "between the brush and
## the eraser" is a place inside the flyout and the flyout has to be up for
## the pointer to get there. The one the tool came from stays up: hiding the
## source of a drag mid-drag is a way to lose the drag.
func _can_drop_on_button(_at: Vector2, data: Variant, category: StringName) -> bool:
    if not SaToolFlyout.is_tool_drag(data):
        return false
    if _open_flyout != category and _visible_members(category).size() > 1:
        var flyout: SaToolFlyout = _flyouts.get(category)
        var already := flyout != null and is_instance_valid(flyout) and flyout.visible
        if not already:
            open_flyout(category)
    return true


## A release over this window with a tool in hand, resolved the way a flyout
## resolves one, and for the reason [method SaToolFlyout._input] gives.
func _input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button == null or button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
        return
    var data: Variant = get_tree().root.gui_get_drag_data()
    if not SaToolFlyout.is_tool_drag(data):
        return
    get_viewport().set_input_as_handled()
    get_tree().root.gui_cancel_drag()
    _on_tool_released(String((data as Dictionary)[SaToolFlyout.DRAG_KEY]), release_point(button.position))


## Where a point in this docker's own units lands on the host, the space
## `release_target` measures its buttons in. Through the final transform as the
## flyout does, since the event arrives in the docker's units and a maximised or
## scaled toolbox draws them larger, and a plain sum would put a release in a
## button's far part beside it.
func release_point(local: Vector2) -> Vector2:
    return Vector2(position) + get_final_transform() * local


## The button came up with *tool_id* in hand at *screen_at*: a row of an open
## flyout takes it before or after itself, a button takes it on its middle
## third and opens a new group on its first or last third, the docker's own
## empty space gives it a group of its own at the end, and outside the docker
## the tool goes back where it was. Which is which is
## [method SaToolBoxGroups.release_target]'s.
##
## A release that changes nothing leaves the flyout standing, because a painter
## who has just pulled one tool out of a group of five wants the other four
## still in front of them.
func _on_tool_released(tool_id: String, screen_at: Vector2) -> void:
    var target := SaToolBoxGroups.release_target(
        screen_at, _groups, _group_names, _flyouts, _buttons, grid_container.columns, drop_area_screen_rect()
    )
    if target.is_empty():
        return
    move_tool(tool_id, target[0], target[1], target[2])


## Everything below the drag bar, in screen units: the surface a release means
## "a group of its own" on rather than "put it back".
##
## The scroll and not `grid_container`, which was the first try and is a column
## exactly one button wide: the grid takes its width from the buttons it holds,
## so half the dark area a painter reads as the toolbox sat outside it and a
## release there put the tool back. The scroll fills the docker under the bar,
## which is the whole of what the docker looks like.
##
## Empty when the docker has no screen to be on, because a suite builds it
## detached and [method SaToolBoxGroups.empty_drop_target] reads a zero-sized
## rectangle as no space at all rather than as one around the origin.
func drop_area_screen_rect() -> Rect2:
    var scroll := get_node_or_null("Control/VBoxContainer/Scroll") as Control
    if scroll == null or not scroll.is_inside_tree():
        return Rect2()
    return SaPopupRect.of_anchor(scroll)


## Moves *tool_id* into the group at *group_index* at *slot*, or into a new
## group at that index, saves the groups and the order, and draws the buttons
## again. The one door every drop goes through, and the one the capture step
## drives, so a scenario and a pointer change the same thing.
func move_tool(tool_id: String, group_index: int, slot: int, as_new_group: bool) -> bool:
    if not _tool_category.has(tool_id) or _tool_registry == null:
        return false
    # Read before the save, because the rebuild the save sets off frees every
    # button and every flyout hanging off one and clears `_open_flyout` with
    # them, so the name of the list to put back has to be taken first.
    var was_open := _open_flyout
    var moved := SaToolBoxGroups.moved(_groups, tool_id, group_index, slot, as_new_group)
    if moved == _groups:
        return true
    SaToolBoxGroups.save(moved, _tool_registry.list_tools())
    # `profile_changed` has rebuilt the buttons by now, and the check in
    # `apply_layout_settings` is what makes this second call harmless.
    apply_layout_settings()
    _reopen_flyout_after_move(tool_id, was_open)
    return true


## The list to put back over the rebuilt buttons after a drop: the group the
## tool now belongs to, and failing that the one that was open before.
##
## The tool's own group first, because a drop into another group is a painter
## looking at where it landed. It refuses when that group has one tool, which
## is every un-group, and then the list that was open comes back so the next
## tool can be pulled out of it without opening it again. Both refuse when the
## group they name is down to one member, and nothing is shown, which is
## honest: a flyout of one row is a button.
func _reopen_flyout_after_move(tool_id: String, was_open: StringName) -> void:
    if is_inside_tree():
        # One frame first. The save has just built every button again and the
        # grid has not laid them out yet, so a button asked for its screen
        # position now answers where the last layout pass left it: the flyout
        # would open beside the first square of the column whichever group it
        # was for. A `Container` sorts its children in the layout pass, and
        # there is no way to ask for one now, so the frame is waited for.
        await get_tree().process_frame
        if not is_inside_tree():
            return
    var landed := StringName(_tool_category.get(tool_id, &""))
    if landed != &"" and open_flyout(landed):
        return
    if was_open != &"" and _buttons.has(was_open):
        open_flyout(was_open)


## `registered_tools` is keyed by StringName, and a Dictionary does not treat a
## String and a StringName as the same key - so the id must be converted, not
## passed through as the String the button was bound with.
##
## The Brush's button picks the engine the Brush last painted with, which is
## the registry's to answer, so a painter on a noise preset who took the eraser
## comes back to the noise preset rather than to the stamp.
func _select_tool(tool_id: String) -> void:
    if target_tool_machine == null:
        return
    var id := StringName(tool_id)
    if target_tool_machine.registered_tools.has(id):
        target_tool_machine.set_active_tool(_tool_registry.picked(id) if _tool_registry != null else id)
    else:
        push_warning("ToolBox: '%s' has a button but no instance on this surface." % tool_id)


## A tool became active, from anywhere: a chord, a menu row, the flyout, or a
## quick action held down. Its category's button lights and takes its face, so
## pressing B and then pressing the paint button twice paints rather than
## bouncing back to whatever the button happened to be showing.
##
## A brush engine lights the Brush's button, which is the tool it paints as.
func _on_event_tool_changed(tool_name: String) -> void:
    var shown := String(SaToolRegistry.tool_in(_tool_registry, StringName(tool_name)))
    var active := StringName(_tool_category.get(shown, &""))
    if active != &"":
        _faces[active] = shown
        _sync_category_button(active)
    for category: StringName in _buttons:
        var btn: Button = _buttons[category]
        btn.set_pressed_no_signal(category == active)


## The toolbox's own account of its layout, for the state dump, or nothing when
## the docker is not built, the way the minimap's block is.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script.
static func capture_state(root: Window) -> Dictionary:
    var docker := root.find_child(SaDockerIds.TOOLBOX, true, false)
    if docker == null or not docker.has_method("toolbox_report"):
        return {}
    return docker.call("toolbox_report")
