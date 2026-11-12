## The row under the layer list is plus, an arrow, minus, the four
## operations a painter reaches for most as buttons, and a dropdown
## holding the rest, in place of a row of ten buttons.
##
## Ten buttons took the docker's width and were
## barely used, because a layer is moved by dragging its row and grouped by a
## chord. What this suite holds is that nothing was lost in the move: every
## action the row offered is a button or a menu item that still acts on the
## document. The four buttons themselves are
## `test_the_four_operations_stand_on_the_layers_row.gd`'s.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the docker shows.
const REQUIRES_GPU := true

## The module the two test filters are registered under, the base module's id.
const KIND_OWNER := &"sara-base-modules"

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")


func _docker_on_a_document() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    return docker


## The same, with the skeleton's own layer types bound, so the arrow
## menu has the registry's plain and background descriptors to draw from.
func _docker_with_layer_types() -> LayersDocker:
    var docker := _docker_on_a_document()
    var registries := Fixtures.make_registries()
    docker.bind_registries(registries.blend_modes, registries.layer_types)
    return docker


func _layer_count(doc: SaDocument) -> int:
    var count := 0
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer and not child.is_queued_for_deletion():
            count += 1
    return count


func test_the_row_is_plus_minus_the_four_and_a_dropdown() -> void:
    var docker := _docker_on_a_document()
    var controls: Array[Node] = docker.actions.get_children()
    assert_eq(controls.size(), 6, "Six controls on the row: %s" % [controls])
    assert_true(docker.actions.add_btn == controls[0], "plus first")
    assert_true(docker.actions.add_type_btn == controls[1], "the arrow beside it")
    assert_true(docker.actions.del_btn == controls[2], "minus third")
    assert_true(docker.actions.ground_btn == controls[3], "Ground beside it")
    assert_true(docker.actions.op_buttons == controls[4], "the four in the stretch")
    assert_true(docker.actions.more_btn == controls[5], "and the dropdown at the row's end")
    docker.actions.sync_from_active_layer()
    assert_eq(
        Array(docker.actions.menu_titles()),
        [
            "Rename...",
            "Colour",
            "Blend Group on Its Own",
            "Clip to Layer Below",
            "Move Up",
            "Move Down",
            "Merge Visible",
            "Flatten",
            "Resample to Document Resolution",
            "Rasterize Impasto",
            "Export Effects as LUT...",
            "Lock Layer",
            "Lock Alpha",
            "Clear Layer",
            "Add Mask from Selection",
            "Rasterize Layer",
        ],
        "The dropdown holds the Layer menu's rows with no button on the row, in its order and words, less mask rows it cannot run"
    )
    assert_true(docker.opacity_slider is FactorSlider, "and the opacity is the options bar's slider")
    docker.target_canvas.free()


## The dropdown is a square like the three buttons beside it. It carried
## the word "More", which a button sizes itself around, so it asked for 57
## logical pixels against their 22 and read as a different kind of control.
func test_the_dropdown_is_the_same_square_as_its_neighbours() -> void:
    var docker := _docker_on_a_document()
    var actions := docker.actions
    var square := actions.add_btn.custom_minimum_size
    assert_eq(actions.more_btn.custom_minimum_size, square, "the dropdown declares the plain buttons' floor")
    assert_eq(actions.del_btn.custom_minimum_size, square, "which minus already did")

    # What the control works out for itself, which is the number the word was
    # inflating. A glyph costs a few pixels of style box over the floor, so
    # this is a bound rather than an equality.
    var asked := actions.more_btn.get_combined_minimum_size()
    var plain := actions.add_btn.get_combined_minimum_size()
    assert_true(asked.x <= plain.x + SaUI.px(8), "the dropdown asks for %d px against the plain button's %d" % [asked.x, plain.x])
    assert_eq(actions.more_btn.text, SaLayerActions.MORE_GLYPH, "and it is labelled with the glyph, not the word")
    assert_true(actions.more_btn.tooltip_text.contains("More"), "the word the label dropped is in the tooltip")
    docker.target_canvas.free()


## One click, the plus button itself, always adds a paint layer, named
## in sequence, whatever else the registry has grown.
func test_add_adds_a_plain_layer_named_in_sequence() -> void:
    var docker := _docker_with_layer_types()
    var doc := docker.target_canvas.document
    docker.actions.add_layer()
    assert_eq(doc.active_layer.name, "Layer 2", "the second layer is named in sequence")
    assert_eq(doc.active_layer.layer_type, SaLayerTypeDescriptor.PLAIN, "and it is a plain layer, not the background")
    docker.actions.add_layer()
    assert_eq(doc.active_layer.name, "Layer 3", "and a third click keeps counting")
    docker.target_canvas.free()


## The arrow's list is the registry's, the background excluded because a
## document already has one. By its id, which is what lets
## the paper through: this case asserted the generated filter, which pinned the
## paper out of the app.
##
## The menu itself is a Window and is not popped here: opening one maps a
## real OS window unless the root viewport embeds subwindows, so this reads
## `_addable_types()`, the list the popup is built from, the way
## `test_layer_types.gd` reads `list_descriptors()` for the same reason.
func test_the_add_type_menu_matches_the_registry() -> void:
    var docker := _docker_with_layer_types()
    var registry := docker.layer_type_registry
    var wanted: Array[StringName] = []
    for descriptor: SaLayerTypeDescriptor in registry.list_descriptors():
        if descriptor.id != &"background":
            wanted.append(descriptor.id)
    var got: Array[StringName] = []
    for descriptor: SaLayerTypeDescriptor in docker.actions._addable_types():
        got.append(descriptor.id)
    assert_eq(got, wanted, "the arrow offers every registered type but the background")
    assert_true(wanted.has(SaLayerTypeDescriptor.PLAIN), "plain is one of them")
    assert_true(wanted.has(&"paper"), "and so is the paper, which stores nothing")
    assert_false(wanted.has(&"background"), "the background is excluded")
    docker.target_canvas.free()


## The arrow's list is the app's own and not an engine
## `PopupMenu`, hung from the arrow so a dump files it there, a row per kind and
## nothing else, each kind's icon a row argument, and a row pressed adds that
## kind. Group is not a row, since it adds nothing.
## Filled rather than opened, for the reason the case above gives.
func test_the_add_type_list_is_the_apps_own_and_adds_the_kind_pressed() -> void:
    var docker := _docker_with_layer_types()
    var actions := docker.actions
    var doc := docker.target_canvas.document

    actions.fill_add_type_menu()
    var list: SaChoicePopup = actions._add_type_menu
    var ids := list.row_ids()

    assert_true(list.get_parent() == actions.add_type_btn, "the list hangs from the arrow")
    assert_eq(actions.find_children("*", "PopupMenu", true, false).size(), 0, "no engine menu is left in the row")
    var addable := actions._addable_types()
    var grounds := (
        SaGeneratedLayer
        . grounds(actions.layer_types)
        . filter(func(ground: SaLayerTypeDescriptor) -> bool: return addable.has(ground))
        . size()
    )
    assert_eq(
        ids.size(),
        actions._addable_types().size() - grounds + 1,
        "a row per kind the registry offers, the grounds one Ground row, and no more"
    )
    assert_false(list.row_labels().has("Group"), "Group, which adds nothing, is not one of them")
    assert_true(ids.has(SaLayerTypeDescriptor.PLAIN), "the plain kind is a row keyed on its own id")
    var icons := {}
    for row: Dictionary in list.row_report():
        icons[String(row["id"])] = String(row["icon"])
    var plain: SaLayerTypeDescriptor = null
    for descriptor: SaLayerTypeDescriptor in actions._addable_types():
        if descriptor.id == SaLayerTypeDescriptor.PLAIN:
            plain = descriptor
    assert_eq(icons.get(String(SaLayerTypeDescriptor.PLAIN), ""), plain.icon_name, "its icon goes through the row")

    assert_true(list.press_row(SaLayerTypeDescriptor.PLAIN), "the plain row takes a press")
    assert_eq(doc.active_layer.name, "Layer 2", "and adds a layer, named in sequence")
    assert_eq(doc.active_layer.layer_type, SaLayerTypeDescriptor.PLAIN, "of that kind")
    docker.target_canvas.free()


## The dropdown is `SaChoicePopup`, so a row is read through its own
## accessors rather than through `PopupMenu`'s item index.
func test_the_menu_follows_the_active_layer() -> void:
    var docker := _docker_on_a_document()
    var menu := docker.actions.menu
    var actions := docker.actions
    var group_button := actions.op_buttons.button(actions.row_id_of(SaLayerActions.Item.GROUP))
    var isolate_row := actions.row_id_of(SaLayerActions.Item.ISOLATE)
    docker.actions.sync_from_active_layer()
    assert_true(group_button.tooltip_text.begins_with("Group"), "A layer offers Group")
    assert_true(menu.label_button(isolate_row).disabled, "and cannot be isolated")

    actions.toggle_group()
    actions.sync_from_active_layer()
    assert_true(docker.active_layer().is_group, "Group wraps the layer and makes the group active")
    assert_true(group_button.tooltip_text.begins_with("Ungroup"), "so the button reads Ungroup")
    assert_false(menu.label_button(isolate_row).disabled, "and Isolate is offered")

    actions.set_isolated(true)
    actions.sync_from_active_layer()
    assert_true(menu.is_checked(isolate_row), "Isolate shows what the group has")

    actions.toggle_group()
    actions.sync_from_active_layer()
    assert_false(docker.active_layer().is_group, "Ungroup dissolves it")
    docker.target_canvas.free()


func test_the_locks_are_check_items_that_write_the_layer() -> void:
    var docker := _docker_on_a_document()
    var menu := docker.actions.menu
    var actions := docker.actions
    var layer := docker.active_layer()
    var paint_row := actions.row_id_of(SaLayerActions.Item.LOCK_PAINT)
    var alpha_row := actions.row_id_of(SaLayerActions.Item.LOCK_ALPHA)

    actions.press_item(SaLayerActions.Item.LOCK_PAINT)
    assert_true(layer.is_locked, "Lock Layer locks the layer")
    actions.sync_from_active_layer()
    assert_true(menu.is_checked(paint_row), "and the item shows it")

    actions.press_item(SaLayerActions.Item.LOCK_ALPHA)
    assert_true(layer.alpha_locked, "Lock Alpha locks its alpha")
    actions.sync_from_active_layer()
    assert_true(menu.is_checked(alpha_row), "and the item shows it")

    actions.press_item(SaLayerActions.Item.LOCK_PAINT)
    assert_false(layer.is_locked, "Pressing a checked item unlocks")
    docker.target_canvas.free()


func test_the_menu_moves_duplicates_and_merges() -> void:
    var docker := _docker_on_a_document()
    var doc := docker.target_canvas.document
    var actions := docker.actions
    var before := _layer_count(doc)

    actions.press_item(SaLayerActions.Item.DUPLICATE)
    assert_eq(_layer_count(doc), before + 1, "Duplicate adds one")

    var active := doc.active_layer
    var index := active.get_index()
    actions.press_item(SaLayerActions.Item.MOVE_DOWN)
    assert_eq(doc.active_layer.get_index(), index - 1, "Move Down moves it one below")
    actions.press_item(SaLayerActions.Item.MOVE_UP)
    assert_eq(doc.active_layer.get_index(), index, "Move Up brings it back")

    actions.press_item(SaLayerActions.Item.MERGE_DOWN)
    assert_eq(_layer_count(doc), before, "Merge Down folds it into the one below")
    docker.target_canvas.free()


## The lock row is gone from the docker, so the settings must not offer a
## page row for it, and a profile that still lists it is migrated.
func test_the_locks_row_left_the_layout_settings() -> void:
    assert_false(SaSettings.DEFAULT_ORDERS["LayersDocker"].has("Locks"), "Locks is no layout element")
    assert_true(SaSettings.DEFAULT_ORDERS["LayersDocker"].has("Actions"), "the actions row still is")
    assert_true(SaSettings.SETTINGS_VERSION >= 6, "and the version moved so a stored Locks entry is dropped")


## The resize grip is pinned to the docker's bottom-right corner and draws on
## top of whatever the content put there. A reservation `DockerWindow` makes for
## every docker keeps it clear: the content column's bottom is inset by the
## grip's height.
func test_the_column_is_inset_by_the_grip() -> void:
    var docker := _docker_on_a_document()
    var column: Container = docker.content_column()
    var grip: float = docker.resizer.custom_minimum_size.y
    assert_true(grip > 0.0, "the grip declares a height to reserve")

    docker.reserve_grip_corner()
    assert_eq(column.offset_bottom, -grip, "the column stops a grip short of the window's bottom")
    assert_true(docker.min_size.y >= int(grip), "and the window's floor carries the same reservation")

    # Twice, because `apply_window_scale` and the layout pass both call it and a
    # reservation that stacked would walk every docker's floor upwards.
    var floor_after_one := docker.min_size.y
    docker.reserve_grip_corner()
    assert_eq(docker.min_size.y, floor_after_one, "a second call reserves the same corner, not a second one")

    # A grip switched off on the layout page reserves nothing, or every docker
    # pays for a control it does not draw.
    docker.resizer.visible = false
    docker.reserve_grip_corner()
    assert_eq(column.offset_bottom, 0.0, "a hidden grip holds nothing open")

    docker.target_canvas.free()


## The one word in front of the blend dropdown reads "Blend", and not "Layer".
## The tooltip says it is the layer's mode.
func test_the_blend_row_reads_blend() -> void:
    var docker := _docker_on_a_document()
    var blend_box: Control = docker.get_node("Control/VBoxContainer/MarginContainer/InnerVBox/BlendOpacityRow/BlendBox")
    var labels: Array[String] = []
    for child in blend_box.get_children():
        if child is Label:
            labels.append((child as Label).text)
    assert_eq(labels, ["Blend"] as Array[String], "one Label in front of the blend dropdown, reading Blend")
    assert_eq(blend_box.get_child(0).name, &"BlendLabel", "in front of it")
    assert_true(docker.blend_mode_opt.get_parent() == blend_box, "and the dropdown is still the row")
    docker.target_canvas.free()


## An icon must not make Duplicate and Clear tower over Merge Down, because an icon assigned straight onto a
## row's button is drawn at the texture's own size and the row grows around it.
## The icon goes through `add_row` now, so the list caps it.
func test_the_iconed_rows_are_no_taller_than_the_rows_beside_them() -> void:
    var docker := _docker_on_a_document()
    var menu := docker.actions.menu
    var actions := docker.actions

    actions.sync_from_active_layer()
    var plain := menu.label_button(actions.row_id_of(SaLayerActions.Item.RENAME))
    for item: SaLayerActions.Item in [SaLayerActions.Item.CLEAR, SaLayerActions.Item.MOVE_UP, SaLayerActions.Item.MOVE_DOWN]:
        var button := menu.label_button(actions.row_id_of(item))
        assert_not_null(button.icon, "%s carries its icon" % actions.row_id_of(item))
        assert_false(button.expand_icon, "not expanded into what the label leaves, which would draw it small")
        assert_eq(
            int(button.get_theme_constant("icon_max_width")),
            SaChoicePopup.ICON_SIZE,
            "capped at the list's own size rather than the texture's"
        )
        assert_eq(button.custom_minimum_size.y, plain.custom_minimum_size.y, "so it is the height of the row with no icon")

    docker.target_canvas.free()


## The dim is the list's own state now, not a write over its controls, so
## `is_disabled`, the fade, the refusal to be pressed and the dump all agree.
## Isolate Group is the row the screenshot showed dimmed and nothing reported.
func test_isolate_group_is_disabled_in_the_list_rather_than_on_its_button() -> void:
    var docker := _docker_on_a_document()
    var menu := docker.actions.menu
    var actions := docker.actions
    var isolate_row := actions.row_id_of(SaLayerActions.Item.ISOLATE)

    actions.sync_from_active_layer()

    assert_true(menu.is_disabled(isolate_row), "A layer that is not a group cannot be isolated")
    assert_almost_eq(
        menu.label_button(isolate_row).modulate.a, SaChoicePopup.DISABLED_ALPHA, 0.001, "the row is dimmed to say so"
    )
    assert_true(menu.check_box(isolate_row).disabled, "and the box beside it is dead too")
    assert_false(actions.press_item(SaLayerActions.Item.ISOLATE), "Pressing it does nothing")

    var report := menu.row_report()
    var isolate_entry := {}
    for entry: Dictionary in report:
        if String(entry["id"]) == String(isolate_row):
            isolate_entry = entry
    assert_true(bool(isolate_entry["disabled"]), "and the dump says the row is dimmed")

    actions.toggle_group()
    actions.sync_from_active_layer()

    assert_false(menu.is_disabled(isolate_row), "A group can be isolated")
    assert_false(menu.check_box(isolate_row).disabled, "from either half of the row")
    assert_almost_eq(menu.label_button(isolate_row).modulate.a, SaChoicePopup.PLAIN_ALPHA, 0.001, "and the dim is gone with it")

    docker.target_canvas.free()


## The list is built again on every open, so the rows a rebuild produces are the
## same rows in the same order and every accessor still finds them.
func test_a_rebuild_leaves_the_same_rows_in_the_same_order() -> void:
    var docker := _docker_on_a_document()
    var actions := docker.actions
    var before := Array(actions.menu_titles())

    actions.sync_from_active_layer()
    actions.sync_from_active_layer()

    assert_eq(Array(actions.menu_titles()), before, "Two more builds leave the same rows")
    assert_eq(
        actions.menu.row_ids().size(),
        SaLayerActions.ROW_IDS.size() - SaLayerOpButtons.ENTRIES.size() - SaLayerMenuRows.ON_A_MASK.size() + 1,
        "and one row per id the four buttons and a layer with no mask leave and the Colour row, so nothing was added twice"
    )
    assert_true(actions.press_item(SaLayerActions.Item.CLEAR), "and a row built by the last pass still presses")

    docker.target_canvas.free()


## Every row that needs a document is dimmed without one, which the old writes
## did to the buttons and the list could not report.
func test_a_docker_with_no_document_dims_every_row_that_needs_one() -> void:
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    docker._ready()
    var actions := docker.actions

    actions.sync_from_active_layer()

    for item: SaLayerActions.Item in [SaLayerActions.Item.CLEAR, SaLayerActions.Item.MOVE_UP, SaLayerActions.Item.MOVE_DOWN]:
        assert_true(actions.menu.is_disabled(actions.row_id_of(item)), "%s needs a document" % actions.row_id_of(item))
        assert_false(actions.press_item(item), "and cannot be pressed without one")
    # The four on the row are dimmed buttons rather than dimmed rows.
    for item: SaLayerActions.Item in [
        SaLayerActions.Item.DUPLICATE, SaLayerActions.Item.GROUP, SaLayerActions.Item.MERGE_DOWN, SaLayerActions.Item.MASK_ADD
    ]:
        assert_true(actions.on_row(item).disabled, "%s needs a document" % actions.row_id_of(item))
        assert_false(actions.press_item(item), "and cannot be pressed without one")

    docker.free()


## The two test filters, as the base module registers them: a blur, which reads
## its neighbours and an adjustment layer holds, and Wrap Offset, which reads
## the whole layer and an adjustment layer refuses. The docker's easel runs
## them, so the refusal is asked of the pass the compositor builds.
func _kind_filters(docker: LayersDocker) -> SaFilterRegistry:
    var filters := SaFilterRegistry.new()
    filters.register(SaGaussianBlurFilter.new(), KIND_OWNER)
    filters.register(SaWrapOffsetFilter.new(), KIND_OWNER)
    docker.target_canvas.easel.compositor.filter_chain.registry = filters
    return filters


## What the arrow's row for *kind_id* opened, pointed at *filters*. A docker out
## of the tree hosts the browser itself, which is where a suite reaches it, and
## has no registries for it to be pointed at.
func _browser_from_the_arrow(docker: LayersDocker, kind_id: StringName, filters: SaFilterRegistry) -> SaLayerKindBrowser:
    docker.actions.fill_add_type_menu()
    assert_true(docker.actions._add_type_menu.press_row(kind_id), "the %s row takes a press" % kind_id)
    var browser := docker.actions.get_node_or_null(SaLayerKindBrowser.HOME) as SaLayerKindBrowser
    assert_not_null(browser, "and opens the filter browser for its kind")
    if browser != null:
        browser.browser.watch(filters, SaCommandRegistry.new())
    return browser


## Every kind the arrow offers says on hover what a layer of it does, and
## so does the Layer menu's row for it, both from the kind's own hint, so a
## module's kind carries one through the door a built-in's does.
func test_every_kind_on_the_arrow_says_what_it_does() -> void:
    var docker := _docker_with_layer_types()
    var types := docker.actions.layer_types
    docker.actions.fill_add_type_menu()
    var list: SaChoicePopup = docker.actions._add_type_menu
    assert_eq(list.row_ids().size(), 5, "Paint Layer, Adjustment Layer, Effect Layer, Frame Layer and Ground")
    assert_eq(list.label_button(SaLayerMenuRows.GROUND).tooltip_text, SaGroundChoice.SENTENCE, "Ground says what it does")
    var grounds := docker.actions.open_grounds()
    for id: StringName in grounds.row_ids():
        assert_eq(grounds.label_button(id).tooltip_text, types.get_descriptor(id).hint, "and so does each ground in its list")
    for id: StringName in list.row_ids():
        if id == SaLayerMenuRows.GROUND:
            continue
        var hint := types.get_descriptor(id).hint
        assert_false(hint.is_empty(), "%s has a hint" % id)
        assert_eq(list.label_button(id).tooltip_text, hint, "and the arrow's row shows it on hover")
    var kinds := 0
    for row: Variant in SaLayerMenuRows.new(docker.target_canvas.document, null, types).rows(false):
        if row is SaLayerMenuRows.Row and row.number >= SaLayerMenuRows.FIRST_KIND:
            kinds += 1
            assert_eq(row.sentence, types.get_descriptor(row.id).hint, "the Layer menu's %s row shows it too" % row.id)
    assert_eq(kinds, 3, "on each of the three kinds the Layer menu adds beside New Layer, the grounds behind Ground")
    docker.target_canvas.free()


## Adjustment Layer on the arrow opens the filter browser rather than
## adding a layer that does nothing, listing the filters an adjustment layer can
## hold, and the one picked there makes the layer, named for the filter and
## holding it, as one step.
func test_an_adjustment_layer_is_added_through_the_browser() -> void:
    var docker := _docker_with_layer_types()
    var doc := docker.target_canvas.document
    var filters := _kind_filters(docker)
    var before := _layer_count(doc)
    var below := doc.active_layer
    var browser := _browser_from_the_arrow(docker, SaBackdropLayer.TYPE_ID, filters)
    if browser == null:
        docker.target_canvas.free()
        return
    assert_eq(_layer_count(doc), before, "The row adds nothing before a filter is picked")
    assert_eq(browser.title, "Add Adjustment Layer", "The browser says what it adds")
    var blur := SaFilterRegistry.key_for(KIND_OWNER, SaGaussianBlurFilter.new())
    var wrap_key := SaFilterRegistry.key_for(KIND_OWNER, SaWrapOffsetFilter.new())
    var listed: Array = browser.describe()["listed"]
    assert_true(listed.has(String(blur)), "It lists the blur: %s" % [listed])
    assert_false(listed.has(String(wrap_key)), "and leaves off Wrap Offset, which reads the whole layer")

    (browser.browser._rows[blur] as Button).pressed.emit()
    browser.open_selected()

    var made := doc.active_layer
    assert_eq(_layer_count(doc), before + 1, "The pick adds one layer")
    assert_true(made == browser.made, "which the browser made")
    assert_true(made.is_adjustment(), "an adjustment layer")
    assert_eq(String(made.name), "Gaussian Blur", "named for its filter")
    assert_eq(made.filters.size(), 1, "holding one filter")
    if made.filters.size() == 1:
        assert_eq(made.filters[0].key, blur, "the one picked")
    assert_eq(made.get_index(), below.get_index() + 1, "above the layer the painter was on")
    assert_eq(doc.undo_redo.get_current_action_name(), SaFilterConversion.ADD_LAYER, "as the Filter dialog's Layer way adds it")
    doc.undo()
    assert_eq(_layer_count(doc), before, "and one undo takes it away")
    docker.target_canvas.free()


## Effect Layer does the same with every filter listed, since an effect
## layer runs over its input what a paint layer runs, and the layer it makes
## reads the layer the painter was on.
func test_an_effect_layer_is_added_through_the_browser() -> void:
    var docker := _docker_with_layer_types()
    var doc := docker.target_canvas.document
    var filters := _kind_filters(docker)
    var before := _layer_count(doc)
    var below := doc.active_layer
    var browser := _browser_from_the_arrow(docker, SaEffectLayer.TYPE_ID, filters)
    if browser == null:
        docker.target_canvas.free()
        return
    assert_eq(browser.title, "Add Effect Layer", "The browser says what it adds")
    var wrap_key := SaFilterRegistry.key_for(KIND_OWNER, SaWrapOffsetFilter.new())
    var listed: Array = browser.describe()["listed"]
    assert_eq(listed.size(), 2, "It lists both filters: %s" % [listed])

    (browser.browser._rows[wrap_key] as Button).pressed.emit()
    browser.open_selected()

    var made := doc.active_layer
    assert_eq(_layer_count(doc), before + 1, "The pick adds one layer")
    assert_true(made.is_effect(), "an effect layer")
    assert_eq(String(made.name), "Wrap Offset", "named for its filter")
    assert_eq(made.filters.size(), 1, "holding one filter")
    if made.filters.size() == 1:
        assert_eq(made.filters[0].key, wrap_key, "the one picked")
    assert_true(SaEffectLayer.input_of(made) == below, "reading the layer the painter was on")
    assert_eq(doc.undo_redo.get_current_action_name(), "Add Effect Layer", "as one step")
    doc.undo()
    assert_eq(_layer_count(doc), before, "which one undo takes away")
    doc.redo()
    assert_true(doc.active_layer == made and made.filters.size() == 1, "and one redo brings back with its filter")
    docker.target_canvas.free()
