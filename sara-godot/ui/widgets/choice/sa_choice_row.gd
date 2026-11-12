## One row of a `SaChoicePopup`: what it is made of, and how it is read back.
##
## Its own file, which pushed `sa_choice_popup.gd` past the 700 line limit. The
## cut is by responsibility and not by count: this class owns a row's controls
## and their states, and the popup owns the list, the mark, the keyboard and the
## search. Nothing here knows there are other rows.
##
## **A row is controls and not a menu item**, which is the whole design: a label
## `Button` that chooses, an optional shortcut hint at its right, an optional
## `CheckBox` beside it that marks and leaves the popup open, an icon capped at
## `ICON_SIZE` whatever the label's length, and a disabled state that dims. A
## `PopupMenu` item can be told none of those, has no rect for the note mode to
## point at, and draws its icon at the texture's own size.
@tool
class_name SaChoiceRow
extends HBoxContainer

## What a row that opens another list ends in, in the column a command row
## shows its chord, so it reads as a row that opens a list rather than one
## that runs something. One mark for every menu, the Layer menu's rows as
## much as the Filter menu's sections.
const BRANCH_MARK := "›"

## The row's own id, so a walk over the column can name what it found without
## the popup's dictionary. Written by `_init` and never after.
var id: StringName = &""
## The icon name the row was built with, because a `Texture2D` cannot be asked
## its own name back and `row_report` has to print one.
var icon_name: String = ""
## Whether the row takes a press. Read from outside, written here, and asked by
## the popup rather than read off the button, because the mark's own write over
## `modulate` would otherwise be the only record of it.
var disabled: bool = false
## A second name the list's search finds the row by, which the row never shows:
## a blend mode's English name under another language, so a painter following
## an English tutorial who types Multiply finds the row that reads in their own
## language. Empty for a row with one name. Written by `_init` and `refill`.
var other_name: String = ""
## Whether the label button draws flat, so the keyboard's mark can turn that off
## for as long as it is on and put it back afterwards.
var _flat: bool = true
## The focus mode the label button was built with, which a disabled row takes
## away and `refill` puts back when the row takes a press again.
var _focus: Control.FocusMode = Control.FOCUS_ALL


## Everything a row is, in one call, because a row built and then written over is
## how the U group's screenshot happened: an icon assigned onto the button after
## the fact is drawn at the texture's size, and a `disabled` written onto it is a
## state nothing else can see.
##
## *group* is the popup's `ButtonGroup` for a one-of list, or null. *box_tip* is
## the caller's words for the box, or none: a box keeps a favourite in the blend
## list and a lock in the Layers docker's menu, so no one sentence is right for
## every list. *row_other_name* is [member other_name]. Defaulted throughout so `.new()` still works the way Godot
## expects of a Control.
func _init(
    row_id: StringName = &"",
    label: String = "",
    checkable: bool = false,
    checked: bool = false,
    row_icon: String = "",
    hint: String = "",
    is_disabled: bool = false,
    group: ButtonGroup = null,
    box_tip: String = "",
    row_other_name: String = ""
) -> void:
    id = row_id
    icon_name = row_icon
    disabled = is_disabled
    other_name = row_other_name
    name = "Row_" + String(row_id)
    add_theme_constant_override("separation", SaUI.px(4))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var button := SaMake.button(self, "Label", label, label)
    # Every row, icon or none, so a list of mixed rows does not step. The icon is
    # capped rather than the row grown around it, so a row with an icon stands
    # no taller than one without.
    button.custom_minimum_size = Vector2(0.0, float(SaUI.px(SaChoicePopup.ROW_HEIGHT)))
    # Flat in a list whose rows carry a box beside them, because the box is what
    # a painter aims at and two framed controls on one row read as two buttons.
    # Not flat in a one-of list: the pressed stylebox is the mark, and a flat
    # button draws no styleboxes at all, which is what the first capture showed.
    _flat = group == null
    button.flat = _flat
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _focus = button.focus_mode
    if group != null:
        # A toggle in a group, so exactly one row is down and the engine draws
        # its own pressed box on it, which the hover box does not replace.
        # `pressed` still fires on a toggle, so the caller hears the same signal
        # either way.
        button.toggle_mode = true
        button.button_group = group
    if not row_icon.is_empty():
        _draw_icon(button, row_icon)
    if is_disabled:
        button.disabled = true
        button.focus_mode = Control.FOCUS_NONE
    # A row's hovered, chosen and disabled boxes are the menu row family's own
    # fields, and their bases are the push button's, which is what the shared
    # theme once answered a row with.
    SaTheme.make_menu_row(button)

    if not hint.is_empty():
        # After the label rather than inside it, because a `Button` draws one
        # string and a chord written into that string is part of what the
        # type-ahead and the search would then match on.
        var hint_label := SaMake.label(self, "Hint", hint)
        hint_label.set_meta(SaUI.FONT_SCALE_META, 0.85)
        hint_label.modulate = Color(1.0, 1.0, 1.0, hint_alpha(0.55, is_disabled))
        hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    if checkable:
        var box := SaMake.check_box(self, "Check", "", checked)
        box.focus_mode = Control.FOCUS_NONE
        box.tooltip_text = box_tip

    apply_alpha(false)


## The icon *icon_file* on *button*, capped at `ICON_SIZE`, or no icon when the
## file is not there.
static func _draw_icon(button: Button, icon_file: String) -> void:
    var icon := SaUI.get_icon(icon_file)
    button.icon = icon
    if icon != null:
        # Not expanded. An expanding icon asks for no width of its own and
        # is drawn in what the label leaves, so in a list as wide as its
        # longest label the two longest rows drew theirs at a third of the
        # others' size and started their labels further left. Capped
        # instead, the icon is drawn at `ICON_SIZE` on every row and counted
        # in the row's width. Every icon is imported at 64 pixels, so the
        # cap is what sizes it.
        button.expand_icon = false
        button.add_theme_constant_override("icon_max_width", SaUI.px(SaChoicePopup.ICON_SIZE))


## The row made over into what `_init` would build from these arguments, for a
## list that keeps its rows between opens: the words, the tick, the dim,
## the chord, the icon, the box's words and the second name. Answers false and
## changes nothing when the row is of another shape, a box where it had none, a
## chord where it had none or a toggle where it was plain, and the list builds
## that one afresh.
##
## What an open left on the row goes too: the keyboard's mark, a search's hiding,
## the found mark and the letter's line. The tick slot stays, because the list
## knows only once its build is done whether the menu still wants one, and a
## slot freed here and made again by the first tick row cost every plain row of
## the View menu two nodes an open. `SaChoicePopup` releases it then.
func refill(
    label: String,
    checkable: bool,
    checked: bool,
    row_icon: String,
    hint: String,
    is_disabled: bool,
    group: ButtonGroup,
    box_tip: String,
    row_other_name: String
) -> bool:
    var button := label_button()
    var box := check_box()
    var hint_label := get_node_or_null("Hint") as Label
    var with_hint := not hint.is_empty()
    if button == null or (box != null) != checkable or (hint_label != null) != with_hint or _flat != (group == null):
        return false
    if button.has_theme_stylebox_override("normal"):
        set_highlighted(false)
    visible = true
    if has_meta(SaChoiceSearch.FOUND):
        remove_meta(SaChoiceSearch.FOUND)
    var line := button.get_node_or_null("Underline") as CanvasItem
    if line != null:
        line.visible = false
    # Each written only when it differs. A write the button already holds is
    # not free: a text queues the label's shaping and a theme override taken
    # away tells the whole row its theme changed, which on sixty rows was most
    # of what a kept menu still paid.
    if button.text != label:
        button.text = label
    if button.tooltip_text != label:
        button.tooltip_text = label
    # The mark of a list that chose this row is taken off, and the plain colour
    # `set_current_where` writes on every other row is left for it to find.
    if button.has_theme_color_override("font_color") and button.get_theme_color("font_color") != SaTheme.palette.text_primary:
        button.remove_theme_color_override("font_color")
    if group != null:
        button.button_group = group
    if row_icon != icon_name:
        _draw_icon(button, row_icon)
        icon_name = row_icon
    disabled = is_disabled
    if button.disabled != is_disabled:
        button.disabled = is_disabled
        button.focus_mode = Control.FOCUS_NONE if is_disabled else _focus
    other_name = row_other_name
    if hint_label != null:
        if hint_label.text != hint:
            hint_label.text = hint
        hint_label.modulate = Color(1.0, 1.0, 1.0, hint_alpha(0.55, is_disabled))
    if box != null:
        box.set_pressed_no_signal(checked)
        if box.tooltip_text != box_tip:
            box.tooltip_text = box_tip
    apply_alpha(false)
    return true


## Takes back what `reserve_tick_slot` did: the box goes back to the row's end
## at its own width, and an empty slot goes.
func release_tick_slot() -> void:
    var box := check_box()
    if box != null and box.custom_minimum_size.x != 0.0:
        box.custom_minimum_size.x = 0.0
        move_child(box, get_child_count() - 1)
    var slot := get_node_or_null("TickSlot")
    if slot != null:
        remove_child(slot)
        slot.queue_free()


## Puts the row's tick at its left, or an empty slot of the same width where it
## has none, so a menu's labels start at one x. Called by the popup on every row
## once any row has a box.
func reserve_tick_slot() -> void:
    var box := check_box()
    if box != null:
        box.custom_minimum_size.x = float(SaUI.px(SaChoicePopup.TICK_SLOT))
        move_child(box, 0)
        return
    if get_node_or_null("TickSlot") != null:
        return
    var slot := Control.new()
    slot.name = "TickSlot"
    slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    slot.custom_minimum_size = Vector2(float(SaUI.px(SaChoicePopup.TICK_SLOT)), 0.0)
    add_child(slot)
    move_child(slot, 0)


## The button carrying the label, which is never null on a built row.
func label_button() -> Button:
    return get_node_or_null("Label") as Button


## The check box beside the label, or null when the row carries none.
func check_box() -> CheckBox:
    return get_node_or_null("Check") as CheckBox


## The shortcut written at the row's right, or "".
func hint_text() -> String:
    var label := get_node_or_null("Hint") as Label
    return label.text if label != null else ""


## Whether the keyboard is resting on this row, drawn as a box behind the label.
##
## A box rather than the row's focus, because a search field that has just been
## typed into cannot give its focus away and go on taking letters: the first
## letter would filter the list, the filter move the highlight, the highlight
## grab focus, and the second letter go to a button.
func set_highlighted(on: bool) -> void:
    var button := label_button()
    if button == null:
        return
    if not on:
        button.remove_theme_stylebox_override("normal")
        button.flat = _flat
        return
    var box := StyleBoxFlat.new()
    box.bg_color = SaTheme.palette.border_secondary
    box.set_corner_radius_all(SaUI.px(3))
    button.add_theme_stylebox_override("normal", box)
    # A flat `Button` draws no stylebox at all, whatever is overridden on it, so
    # the flatness goes for as long as the mark is on and comes back with it.
    button.flat = false


## How opaque a secondary cell is drawn, a chord or a kind or a place: *live* is
## what a pressable row draws it at, and a row that takes no press scales that by
## the disabled fade, so a disabled hint is never the brighter of the two.
static func hint_alpha(live: float, dim: bool) -> float:
    return live * SaChoicePopup.DISABLED_ALPHA if dim else live


## The row's fade: the disabled dim wins over the chosen mark, because a row a
## painter cannot press has to say so whatever else is true of it. Called on
## every pass of the popup's `set_current_where`, which would otherwise undo the
## dim.
func apply_alpha(chosen: bool) -> void:
    var button := label_button()
    if button == null:
        return
    var alpha := SaChoicePopup.PLAIN_ALPHA
    if disabled:
        alpha = SaChoicePopup.DISABLED_ALPHA
    elif chosen:
        alpha = SaChoicePopup.CHOSEN_ALPHA
    button.modulate = Color(1.0, 1.0, 1.0, alpha)
