## The Layer menu: the operations on the stack, each one a history step.
##
## Its rows are `SaLayerMenuRows`, which the Layers docker's More menu is drawn
## from too, so the two read one job under one name in one order. Rename,
## Blend Group on Its Own and the kinds of layer are the list's own rows, and
## so is Ground, which opens the list of every ground beside the menu, and
## Duplicate To, which opens the list of the other open documents. The mask's
## rows and the conversions sit under a submenu each.
##
## The two flips come after the list, under Flip, a command list of this
## menu's own, because they move the pixels rather than the stack and the More
## menu beside the stack is not where a painter looks for them. Their commands
## say Flip Layer, so the Shortcuts page tells them from the Image menu's two,
## and the rows here leave the word to the menu. The smart layer's rows follow
## them under Smart Layer for the same reason: Make Smart Layer, and Edit Smart
## Layer Contents, Reset Transform and Convert to Ordinary Layer dimmed while
## the active layer carries no live transform, which is every ordinary layer,
## since a transform of one is written into its pixels when it is confirmed.
## Edit Smart Layer Contents is lit while the contents are open, to close them.
## Share Source with a Copy follows them, lit on a smart layer, and Make Source
## Independent, lit on one that shares its source with another. The linked
## file's rows close the same submenu: Link to File..., lit on a smart layer,
## and Reload Linked File, Make Path Absolute, Make Path Relative, Embed Linked
## File and Clear Override, lit on a layer linked to a file.
class_name SaLayerMenu
extends SaMenu

const ID_FLIP_HORIZONTAL := 444
const ID_FLIP_VERTICAL := 445
const ID_BAKE_TRANSFORM := 447
const ID_MAKE_SMART := 436
const ID_RESET_TRANSFORM := 437
const ID_EDIT_CONTENTS := 438
const ID_LINK_SMART := 439
const ID_UNLINK_SOURCE := 435
const ID_LINK_FILE := 421
const ID_RELOAD_LINK := 422
const ID_LINK_ABSOLUTE := 423
const ID_LINK_RELATIVE := 424
const ID_EMBED_LINK := 425
const ID_CLEAR_OVERRIDE := 426

## The submenus' rows, past the kinds of layer, which count upwards from 450,
## by enough that a module would need a hundred kinds to reach them.
const ID_MASK_GROUP := 560
const ID_CONVERT_GROUP := 561
const ID_FLIP_GROUP := 562
const ID_SMART_GROUP := 563
const ID_VIA_GROUP := 565
const ID_ARRANGE_GROUP := 566
const ID_LOCK_GROUP := 567
const ID_KINDS_GROUP := 568

## The list's rows that go under a submenu, group -> their ids. Rasterize
## Layer turns a filter's layer into paint, so it is a conversion, though the
## list keeps it among the mask's rows for the Layers docker's More menu.
const LIST_GROUPS: Dictionary = {
    ID_MASK_GROUP:
    [
        &"layer_mask_add",
        &"layer_mask_add_from_selection",
        &"layer_mask_delete",
        &"layer_mask_apply",
        &"layer_mask_invert",
        &"layer_mask_disable",
        &"layer_mask_to_selection",
    ],
    ID_CONVERT_GROUP: [&"layer_bake", &"layer_rasterize_impasto", &"layer_rasterize", &"layer_export_lut"],
    ID_VIA_GROUP: [&"layer_via_copy", &"layer_via_cut", &"layer_via_seamless_cut"],
    ID_ARRANGE_GROUP: [&"layer_move_up", &"layer_move_down"],
    ID_LOCK_GROUP: [&"layer_lock", &"layer_alpha_lock"],
}

## The submenus that stand after a row of the list rather than where their
## first row stood, group -> that row. The mask's stands with the group and
## the clip, the rows that decide what a layer shows, as Photoshop's Layer
## Mask stands above its arrange and merge rows.
const STANDS_AFTER: Dictionary = {ID_MASK_GROUP: &"layer_clip_to_below"}

## What the rows are drawn for, Main's document and kinds when null, and set by
## a suite, which has no Main to ask.
var document: SaDocument = null
var layer_types: SaLayerTypeRegistry = null


## Nothing before a registry is bound, since the words are the commands'.
##
## **The list's rows a painter reaches for stay on the menu**, the new layers
## and the lists beside them, the merges and the clear, and the rows of one
## kind go under a submenu each where the first of them stood, the copies of a
## selection's, the stack order's, the conversions' and the locks'. The mask's
## stands after the clip, as a mask follows the clip in the menus a painter
## knows, and after them come the flips' and the smart layer's, which holds
## the linked file's rows too. As one list the menu ran forty-nine rows, past
## a laptop's screen, and with fewer submenus some rows found no letter.
func _add_items() -> void:
    var rows: Array = _list().rows(false) if commands != null else []
    var grouped: Dictionary = {}
    for row: Variant in rows:
        if row is SaLayerMenuRows.Row and _group_of(row) >= 0:
            var group := _group_of(row)
            if not grouped.has(group):
                grouped[group] = []
            grouped[group].append(row)
    var line_waiting := false
    for row: Variant in rows:
        if row is StringName:
            line_waiting = item_count() > 0
            continue
        var drawn: SaLayerMenuRows.Row = row
        var group := _group_of(drawn)
        # A submenu stands where the first of its rows stood, the rest of its
        # rows having gone under it, or after the row it is placed after.
        if group >= 0 and (grouped[group][0] != drawn or STANDS_AFTER.has(group)):
            continue
        if line_waiting:
            add_separator()
            line_waiting = false
        if group >= 0:
            _add_list_group(group, _group_words(group), grouped[group])
        else:
            drawn.draw(popup, key(drawn.number))
        for placed: int in STANDS_AFTER:
            if STANDS_AFTER[placed] == drawn.id and grouped.has(placed):
                _add_list_group(placed, _group_words(placed), grouped[placed])
    add_separator()
    begin_group(ID_FLIP_GROUP, tr("Flip"), tr("Flip the layer's pixels."))
    add_commands(
        [
            [ID_FLIP_HORIZONTAL, &"layer_flip_horizontal", "Flip Horizontally"],
            [ID_FLIP_VERTICAL, &"layer_flip_vertical", "Flip Vertically"],
        ]
    )
    end_group()
    # The linked file's rows are a smart layer's as well, under a line, as
    # Photoshop's relink and embed rows stand under its Smart Objects.
    var sentence := tr("Keep the layer's contents apart from its transform, or read them from a file on disk.")
    begin_group(ID_SMART_GROUP, tr("Smart Layer"), sentence)
    add_commands(
        [
            [ID_MAKE_SMART, &"layer_make_smart"],
            [ID_EDIT_CONTENTS, SaEditSmartLayerContents.COMMAND],
            [ID_RESET_TRANSFORM, &"layer_reset_transform"],
            [ID_BAKE_TRANSFORM, &"layer_bake_transform"],
            LINE,
            [ID_LINK_SMART, &"layer_link_smart"],
            [ID_UNLINK_SOURCE, &"layer_unlink_source"],
            LINE,
            [ID_LINK_FILE, &"layer_link_file"],
            [ID_RELOAD_LINK, &"layer_reload_link"],
            LINE,
            [ID_LINK_ABSOLUTE, &"layer_link_absolute"],
            [ID_LINK_RELATIVE, &"layer_link_relative"],
            [ID_EMBED_LINK, &"layer_embed_link"],
            [ID_CLEAR_OVERRIDE, &"layer_clear_override"],
        ]
    )
    end_group()


## The words the submenu of the list's rows *group* is shown under, and the
## sentence on its hover. Layer via
## Copy goes under New Layer via as Photoshop's goes under New, and the stack's
## order under Arrange as Photoshop's does.
func _group_words(group: int) -> PackedStringArray:
    match group:
        ID_MASK_GROUP:
            return [tr("Mask"), tr("Add, apply or change the layer's mask.")]
        ID_CONVERT_GROUP:
            return [tr("Convert"), tr("Turn the layer into paint at the document's resolution, or export its effects.")]
        ID_VIA_GROUP:
            return [tr("New Layer via"), tr("Copy or cut the selection onto a layer of its own.")]
        ID_LOCK_GROUP:
            return [tr("Lock"), tr("Lock the layer's pixels, or only where they are clear.")]
        ID_KINDS_GROUP:
            var sentence := tr("Add a layer of another kind, an adjustment, an effect, a ground or one a module adds.")
            return [tr("Other Layers"), sentence]
    return [tr("Arrange"), tr("Move the layer up or down the stack.")]


## The submenu the list's row *row* goes under, or -1 for one that stays on
## the menu. A kind's row is known by its number, since its id is whatever its
## module registered, and the Ground row stands with them as a kind of layer.
static func _group_of(row: SaLayerMenuRows.Row) -> int:
    if row.number >= SaLayerMenuRows.FIRST_KIND or row.id == SaLayerMenuRows.GROUND:
        return ID_KINDS_GROUP
    for group: int in LIST_GROUPS:
        if LIST_GROUPS[group].has(row.id):
            return group
    return -1


## A submenu of the list's own rows, *rows* in the list's order.
func _add_list_group(group: int, words: PackedStringArray, rows: Array) -> void:
    begin_group(group, words[0], words[1])
    for drawn: SaLayerMenuRows.Row in rows:
        drawn.draw(popup, key(drawn.number))
    end_group()


## The list's command at *item_id*, or this menu's own flips'.
func command_at(item_id: int) -> StringName:
    var id := _list().id_at(item_id)
    return id if commands != null and commands.has(id) else super(item_id)


## Every tick put back to what the layer now says.
func sync_ticks() -> void:
    for row: Variant in _list().rows(false):
        if row is SaLayerMenuRows.Row and row.tick:
            set_item_checked(row.number, row.ticked)


## The popup's `branched` is connected here, as the Filter menu connects it,
## because `SaMenu` hears only the presses that close the menu.
func populate() -> void:
    super()
    if popup != null and not popup.branched.is_connected(_on_branched):
        popup.branched.connect(_on_branched)


func _on_branched(row_id: StringName) -> void:
    on_id_pressed(id_of(row_id))


## Fills the Ground row's list and opens it beside the row, and answers it,
## which a suite presses without a window on screen. A pick there runs through
## the rows, as a pick from the docker's arrow does.
func show_grounds() -> SaChoicePopup:
    var row := key(SaLayerMenuRows.number_of(SaLayerMenuRows.GROUND))
    return _list().open_grounds(_list_holding_or_menu(row), _on_ground_chosen, row)


## Fills the Duplicate To row's list of the other open documents and opens it
## beside the row, and answers it, as [method show_grounds] does.
func show_duplicate_to() -> SaChoicePopup:
    var row := key(SaLayerMenuRows.number_of(SaLayerMenuRows.DUPLICATE_TO))
    return _list().open_duplicate_to(_list_holding_or_menu(row), row)


## The list that holds *row*, a submenu's or the menu's own, which is what a
## row's own list opens beside.
func _list_holding_or_menu(row: StringName) -> SaChoicePopup:
    var holder := list_holding(popup, row)
    return holder if holder != null else popup


func _on_ground_chosen(id: StringName) -> void:
    SaUsageTally.menu_row(String(popup.name), String(id))
    _list().run(id, main_scene())


## Rename opens the Layers docker's own dialog, so both doors write through one
## window, Ground opens its list, deferred as the Filter menu's sections are
## because the list takes the focus, and a kind that holds filters opens the
## filter browser under Main, as the docker's arrow does.
func _pressed(item_id: int) -> void:
    var id := _list().id_at(item_id)
    if id == SaLayerMenuRows.GROUND:
        show_grounds.call_deferred()
    elif id == SaLayerMenuRows.DUPLICATE_TO:
        show_duplicate_to.call_deferred()
    elif id != SaLayerMenuRows.RENAME:
        _list().run(id, main_scene())
        sync_ticks()
    elif main_scene() != null and main_scene().get("layers_docker") != null:
        (main_scene().get("layers_docker") as LayersDocker).open_rename_dialog()


func _list() -> SaLayerMenuRows:
    var kinds := layer_types
    if kinds == null and main_scene() != null and main_scene().get("registries") != null:
        kinds = (main_scene().get("registries") as SaRegistries).layer_types
    return SaLayerMenuRows.new(document if document != null else main_document(), commands, kinds)
