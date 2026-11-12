## The Swatches strip of the colour picker docker: a heading with the buttons
## that load a GIMP palette into the strip, save one out and clear the strip,
## and under it the kept colours as chips after the + that keeps one.
##
## **A strip under a heading rather than one row.** The chips followed by +,
## Load, Save and Clear with no name would leave an empty row reading as three
## words and a dimmed Clear standing alone, with nothing to say what it is a
## row of. The heading says Swatches and carries the three buttons that act
## on the whole strip. The + is the strip's first cell, because it makes a chip
## and sits where the next chip lands, and an empty strip says so in a muted
## line beside it.
##
## A sibling of `sa_color_picker.gd` rather than lines in it, the way
## `sa_picker_sliders.gd` is. That file lays the rows out and shows a colour,
## and this one owns everything the Swatches row does with a list of them. It
## keeps no colour of its own: [method set_swatches] is handed the store's list,
## and every choice goes out as a signal for `SaColorPicker` to pass on.
##
## **A load asks before it stands on what was kept.** A load adds after the
## swatches already there unless the painter answers otherwise, which is the
## argument `sa_color_store.gd`'s `add_swatches` makes, and the Clear button
## gives the kept ones back, so a load may offer a replace: [SaMessage] asks "replace or add" with Add as the default
## button, so a painter pressing Enter loses nothing, and Replace is the row's
## own Clear and Load in one press. A load into an empty row does not ask,
## because there is nothing to stand on.
##
## A picker that is not in a tree cannot put a window up, and every test builds
## one that way. Such a load takes the answer that changes nothing for what was
## kept, which is Add, and such a clear
## does nothing at all. The suite's own cases call [method answer_load] to say
## what Replace does without a window to press.
##
## **A right press on a chip opens a menu** of Rename and Remove, rather than
## deleting the swatch at once with no word and no way back. Remove says so in
## the canvas corner, and the menu carries Undo remove until the next edit, on
## a chip and on the strip around them, because removing the last chip
## leaves no chip to press. Rename swaps a line edit over the strip, and each
## chip's tooltip is its name before its hex.
class_name SaPaletteRow
extends VBoxContainer

## The "+" button: the painter wants to keep the colour the picker holds. The
## colour is the picker's, so this carries none.
signal add_requested

## A kept chip was left-clicked, which is a painter picking that colour.
signal chip_picked(color: Color)

## Remove was chosen from a kept chip's menu: that swatch is to go.
signal chip_remove_requested(index: int)

## Rename was answered with Enter, or the field let go of the keyboard: the
## swatch at *index* is to be called *called*, which may be empty.
signal chip_rename_requested(index: int, called: String)

## Undo remove was chosen, so the swatch removed last is to come back.
signal undo_remove_requested

## A palette file was read and its colours are to be kept after the ones already
## there, with the names the file gave them. The store's `add_swatches` is what
## hears it.
signal swatches_add_requested(colors: Array, names: Array)

## The painter said Clear, or said Replace to a load, and the kept swatches go.
## Replace sends this and then [signal swatches_add_requested], in that order,
## because a replace is exactly this row's Clear and then its Load.
signal swatches_clear_requested

## The three answers the load question offers, in the order the dialog draws
## them. Add is the default button, so Enter keeps what the painter had.
enum LoadAnswer { REPLACE, ADD, CANCEL }

## The two answers the clear question offers. Cancel is first and is the default
## button, the way the other deletes in Sara ask (`file_menu.gd`'s unsaved
## changes, `brush_preset_tags.gd`'s delete), because Clear is the one thing
## here that cannot be undone.
const CLEAR_CANCEL: int = 0
const CLEAR_CLEAR: int = 1

## A swatch chip is a square this big, logical units.
const CHIP_SIZE: int = 18

## The rows of the right press's menu.
const MENU_RENAME := &"rename"
const MENU_REMOVE := &"remove"
const MENU_UNDO_REMOVE := &"undo_remove"

## The heading's row: the name of the strip, then Load, Save and Clear.
var heading: HBoxContainer
var heading_label: Label
## The strip: + first, the empty line while nothing is kept, then the chips.
var flow: HFlowContainer
## "No swatches kept yet", muted, shown while the strip holds no chip.
var empty_line: Label
## The chips in the store's order, which is the flow's order after its first
## two cells. Kept apart from the flow's children so a rebuild frees the chips
## and leaves the + and the empty line where they are.
var chips: Array[ColorRect] = []
var add_swatch_button: Button
var load_palette_button: Button
var save_palette_button: Button
var clear_palette_button: Button
## The right press's menu, on a chip and on the strip around the chips.
var menu: SaChoicePopup
## The field Rename puts where the strip was. Hidden while nothing is renamed.
var rename_edit: LineEdit
## The chip the field is up for, -1 while it is not.
var renaming: int = -1

## The swatches the store last handed over, which Save writes out and the load
## question reads to know whether there is anything to stand on. Kept here
## rather than read back off the chips, because a chip holds a colour and no
## order the store did not already give it.
var _swatches: Array = []
## Their names, the same length, and empty for one nobody named.
var _names: Array[String] = []
## Whether the store remembers a removed swatch, so the menu offers it back.
var _undo_offered: bool = false
## The chip the open menu is about, -1 for the strip.
var _menu_index: int = -1


func _init() -> void:
    name = "Swatches"
    add_theme_constant_override("separation", DockerUtils.px(SaTheme.GAP_TIGHT))

    heading = SaMake.row(self, "SwatchesHeading", SaTheme.GAP_TIGHT)
    heading_label = SaMake.label(heading, "SwatchesTitle", tr("Swatches"))
    heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaSettingsRows.embolden(heading_label)

    # A way in and a way out for the kept swatches, as a GIMP palette, and a way
    # to empty the strip. Load's tooltip says it asks, because that is the
    # question a painter has before pressing it and the answer is not the one
    # "load" suggests: it may stand on what is kept rather than follow it.
    load_palette_button = _small_button(
        tr("Load"),
        tr("Load a GIMP palette. You choose whether it replaces the swatches or adds to them."),
        _open_palette_dialog.bind(SaFilePicker.Mode.OPEN_FILE)
    )
    load_palette_button.name = "LoadPaletteButton"
    heading.add_child(load_palette_button)

    save_palette_button = _small_button(
        tr("Save"), tr("Save the swatches as a GIMP palette file."), _open_palette_dialog.bind(SaFilePicker.Mode.SAVE_FILE)
    )
    save_palette_button.name = "SavePaletteButton"
    heading.add_child(save_palette_button)

    clear_palette_button = _small_button(tr("Clear", "clear the palette"), tr("Delete every swatch."), _on_clear_pressed)
    clear_palette_button.name = "ClearPaletteButton"
    # Dimmed on the same check its handler makes, so an empty strip offers no
    # Clear that would do nothing. [method set_swatches] keeps it in step.
    clear_palette_button.disabled = _swatches.is_empty()
    heading.add_child(clear_palette_button)

    flow = HFlowContainer.new()
    flow.name = "SwatchesFlow"
    flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(flow)

    add_swatch_button = _small_button("+", tr("Add the foreground colour as a swatch."), _on_add_pressed)
    add_swatch_button.name = "AddSwatchButton"
    flow.add_child(add_swatch_button)

    empty_line = SaMake.label(flow, "SwatchesEmpty", tr("No swatches yet"))
    empty_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    SaTheme.bind_font(empty_line, "text_muted")
    empty_line.visible = _swatches.is_empty()
    # The strip takes the right press too, so Undo remove is in reach once the
    # last chip is gone. Each chip stops its own press first.
    flow.gui_input.connect(_on_strip_input)

    # Made through `SaMake`, so a scenario's `control` step can type a name into
    # it the way the hex box is typed into.
    rename_edit = SaMake.line_edit(self, "SwatchRename")
    rename_edit.visible = false
    rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rename_edit.text_submitted.connect(_on_rename_submitted)
    rename_edit.focus_exited.connect(_on_rename_focus_exited)
    rename_edit.gui_input.connect(_on_rename_input)

    menu = SaChoicePopup.new()
    menu.name = "SwatchMenu"
    menu.chosen.connect(_on_menu_chosen)
    add_child(menu)


func _small_button(label: String, hint: String, on_pressed: Callable) -> Button:
    var button := Button.new()
    button.text = label
    button.tooltip_text = hint
    button.custom_minimum_size = Vector2(DockerUtils.px(24), DockerUtils.px(24))
    button.focus_mode = Control.FOCUS_NONE
    button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    button.pressed.connect(on_pressed)
    return button


func _on_add_pressed() -> void:
    add_requested.emit()


## Rebuilds the swatch chips from the list the store holds, after the + and the
## empty line, each named by *names* where the list has one. *undo_offered*
## says the store remembers a removed swatch, so the menu carries Undo remove.
## Left click picks the colour, right click opens the menu.
func set_swatches(list: Array, names: Array = [], undo_offered: bool = false) -> void:
    _swatches = list.duplicate()
    _names.clear()
    for i in _swatches.size():
        _names.append(str(names[i]) if i < names.size() else "")
    _undo_offered = undo_offered
    clear_palette_button.disabled = _swatches.is_empty()
    empty_line.visible = _swatches.is_empty()
    for chip in chips:
        flow.remove_child(chip)
        chip.queue_free()
    chips.clear()
    for i in list.size():
        var chip := ColorRect.new()
        chip.color = list[i]
        chip.custom_minimum_size = Vector2(DockerUtils.px(CHIP_SIZE), DockerUtils.px(CHIP_SIZE))
        # Centred on the line the + sets, which is a button's height rather
        # than a chip's.
        chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        chip.name = "SwatchChip%d" % i
        chip.tooltip_text = chip_tooltip(chip.color, _names[i])
        chip.gui_input.connect(_on_chip_input.bind(i, chip.color))
        flow.add_child(chip)
        chips.append(chip)


## "Name, #hex" for a named swatch and "#hex" for one without a name, so a
## palette of twenty colours reads as twenty names.
static func chip_tooltip(color: Color, called: String) -> String:
    var hex := "#" + color.to_html(false)
    return hex if called.is_empty() else "%s, %s" % [called, hex]


func _on_chip_input(event: InputEvent, index: int, chip_color: Color) -> void:
    var mb := event as InputEventMouseButton
    if mb == null or not mb.pressed:
        return
    if mb.button_index == MOUSE_BUTTON_LEFT:
        chip_picked.emit(chip_color)
    elif mb.button_index == MOUSE_BUTTON_RIGHT:
        var source: Control = flow
        if index < chips.size():
            source = chips[index]
        open_menu(index, SaPopupRect.at_press(mb, source))


## A right press on the strip between the chips, which offers what is left
## when no chip is under the pointer: Undo remove, or nothing. A chip stops its
## own press, so this never hears one.
func _on_strip_input(event: InputEvent) -> void:
    var mb := event as InputEventMouseButton
    if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
        open_menu(-1, SaPopupRect.at_press(mb, flow))


## Opens the menu for the chip at *index*, or for the strip when it is -1, and
## answers whether it opened. The strip's menu with nothing to undo would be
## empty, so it stays shut.
##
## At *at* when a right press gave one, the press measured by
## `SaPopupRect.at_press`, so the menu opens at the pointer as every right-click
## menu does. A position read off the press as it came, in the docker
## window's units, opened it eight hundred pixels from the chip once, which is
## why the menu went under the chip through `open_under`. Under the chip still
## when no point is given, which is how a suite asks for it.
func open_menu(index: int, at: Variant = null) -> bool:
    if not fill_menu(index):
        return false
    var anchor: Control = flow
    if _menu_index >= 0:
        anchor = chips[_menu_index]
    var where: Variant = null
    if at is Vector2i:
        where = Vector2(at as Vector2i)
    menu.open_under(anchor, where)
    return true


## The menu's rows for the chip at *index*, or for the strip at -1, without
## opening it, which is the half a suite can run on a row outside the tree.
## False when there is nothing to offer.
func fill_menu(index: int) -> bool:
    var on_chip := index >= 0 and index < _swatches.size()
    if not on_chip and not _undo_offered:
        return false
    _menu_index = index if on_chip else -1
    menu.clear()
    if on_chip:
        menu.add_row(MENU_RENAME, tr("Rename"))
        menu.add_row(MENU_REMOVE, tr("Remove"))
    if _undo_offered:
        menu.add_row(MENU_UNDO_REMOVE, tr("Undo remove"))
    return true


## Carries out a row of the menu. Public because it is how a suite chooses one
## without a window to press in.
func choose(id: StringName) -> void:
    var index := _menu_index
    _menu_index = -1
    if id == MENU_RENAME and index >= 0:
        begin_rename(index)
    elif id == MENU_REMOVE and index >= 0:
        chip_remove_requested.emit(index)
    elif id == MENU_UNDO_REMOVE:
        undo_remove_requested.emit()


func _on_menu_chosen(id: StringName) -> void:
    choose(id)


## Swaps the field over the strip with the swatch's name in it, all of it
## selected so typing replaces it. Enter applies, Escape cancels, and the field
## letting go of the keyboard applies, which is what the layer rename does.
func begin_rename(index: int) -> void:
    if index < 0 or index >= _swatches.size():
        return
    renaming = index
    rename_edit.text = _names[index]
    rename_edit.placeholder_text = "#" + (_swatches[index] as Color).to_html(false)
    flow.visible = false
    rename_edit.visible = true
    if rename_edit.is_inside_tree():
        rename_edit.grab_focus()
    rename_edit.select_all()


## Applies the field: the name goes out to the store and the strip comes back.
func commit_rename() -> void:
    if renaming < 0:
        return
    var index := renaming
    var called := rename_edit.text.strip_edges()
    _end_rename()
    chip_rename_requested.emit(index, called)


## Throws the field away and leaves the name as it was.
func cancel_rename() -> void:
    if renaming >= 0:
        _end_rename()


## Puts the strip back. The index is cleared before the focus goes, because
## letting go of the focus raises `focus_exited`, which would otherwise read as
## a second answer to the one being carried out.
func _end_rename() -> void:
    renaming = -1
    rename_edit.visible = false
    flow.visible = true
    if rename_edit.is_inside_tree() and rename_edit.has_focus():
        rename_edit.release_focus()


func _on_rename_submitted(_text: String) -> void:
    commit_rename()


func _on_rename_focus_exited() -> void:
    commit_rename()


## Escape is taken here, the way the layer rename takes it, so the key goes no
## further than the field. The router hands a docker's key to the field before
## it lets the focus go (`shortcut_router.gd`'s `_release_text_focus`), so this
## runs first and the release finds nothing left to apply.
func _on_rename_input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
        return
    cancel_rename()
    rename_edit.accept_event()


## The strip for the state dump: each chip's tooltip and where it is, the open
## menu's rows, and the rename field. Rectangles are in the docker window's
## coordinates, which is what a scenario adds the window's position to before
## it presses at one.
func report() -> Dictionary:
    var listed: Array = []
    for chip in chips:
        listed.append({"tooltip": chip.tooltip_text, "rect": var_to_str(chip.get_global_rect())})
    return {
        "chips": listed,
        "undo_offered": _undo_offered,
        "menu_open": menu.visible,
        "menu_rows": menu.row_labels(),
        "renaming": renaming,
        "rename_text": rename_edit.text,
        "rename_focused": rename_edit.is_inside_tree() and rename_edit.has_focus(),
        "rename_rect": var_to_str(rename_edit.get_global_rect()),
        "strip_rect": var_to_str(flow.get_global_rect()),
    }


## Puts a file picker up for a `.gpl`, to open one or to write one, the way the
## reference docker's does.
##
## A scenario answers it with `{"file_picker": {"choose": "/path"}}`, which
## reaches the same two calls a painter's choice does.
func _open_palette_dialog(mode: SaFilePicker.Mode) -> void:
    var filters := PackedStringArray(["*.gpl ; " + tr("GIMP palette")])
    var chosen := save_palette_path if mode == SaFilePicker.Mode.SAVE_FILE else load_palette_path
    SaFilePicker.open(self, mode, filters, chosen)


## Reads the palette at *path* and asks for its colours to be kept. Answers how
## many it asked for, which is 0 when the file refused, and the refusal has
## already been said through [SaProblems] by the reader.
##
## Read with no colour space, which is sRGB and the identity, because the store
## keeps colours as a screen shows them: the eyedropper converts a document's
## texel to display before it hands one over, and the fill converts the
## foreground back into the document when it paints. So a `.gpl`'s eight bits
## and a kept swatch are already in the same space, and no document has to be
## open for a palette to load.
##
## When the row is not empty the painter is asked which of the two a load means,
## and the ask carries [constant LoadAnswer.CANCEL] and [constant
## LoadAnswer.ADD], so Escape keeps everything and Enter adds.
func load_palette_path(path: String) -> int:
    var palette := SaPaletteFile.read_file(path)
    if palette == null:
        return 0
    var colors: Array = []
    var names: Array = []
    for swatch in palette.swatches:
        colors.append(swatch.color)
        names.append(read_name(swatch))
    if colors.is_empty():
        return 0
    if _swatches.is_empty() or not is_inside_tree():
        swatches_add_requested.emit(colors, names)
        return colors.size()
    SaMessage.confirm(
        self,
        tr("Load Palette"),
        tr("Replace the swatches, or add these after them?"),
        PackedStringArray([tr("Replace"), tr("Add"), tr("Cancel")]),
        answer_load.bind(colors, names),
        LoadAnswer.CANCEL,
        LoadAnswer.ADD
    )
    return colors.size()


## The name a palette file's colour is kept under, empty for one the file left
## unnamed. GIMP writes "Untitled" for a colour without one, and Sara's own
## palettes from before names named each colour by its hex, so both read as no
## name rather than as a tooltip saying the same thing twice.
static func read_name(swatch: SaPaletteFile.Swatch) -> String:
    var called := swatch.name.strip_edges()
    if called == SaPaletteFile.UNNAMED_COLOUR or called.to_lower() == "#" + swatch.color.to_html(false):
        return ""
    return called


## Carries out the answer to the load question.
##
## Replace is the row's own two steps in one press, in the order a painter would
## make them, and Cancel is the one answer that keeps the list as it was.
##
## Public because it is the door a test reaches a replace through: a picker
## outside a tree has no window to ask in, and a scenario answers by pressing a
## button rather than by calling this.
func answer_load(answer: int, colors: Array, names: Array = []) -> void:
    if answer == LoadAnswer.CANCEL:
        return
    if answer == LoadAnswer.REPLACE:
        swatches_clear_requested.emit()
    swatches_add_requested.emit(colors, names)


## Writes the kept swatches to *path* as a GIMP palette. False when the file
## could not be written, which the writer has already reported.
##
## Named after the file, which is what GIMP shows a palette as, and each colour
## by the name the painter gave it. One without a name is written as GIMP's own
## "Untitled", which [method read_name] reads back as no name. The hex stood
## there while the store kept no names.
func save_palette_path(path: String) -> bool:
    var written: Array[SaPaletteFile.Swatch] = []
    for i in _swatches.size():
        var called := _names[i] if i < _names.size() and not _names[i].is_empty() else SaPaletteFile.UNNAMED_COLOUR
        written.append(SaPaletteFile.Swatch.new(_swatches[i], called))
    var palette := SaPaletteFile.new(path.get_file().get_basename(), SaPaletteFile.DEFAULT_COLUMNS, written)
    return palette.write_file(path)


## Clear empties the row, so it asks first and asks only when there is something
## to throw away. A clear behind a hover is a clear nobody meant, which is the
## argument `main_dockers.gd` makes about a delete, and a question over an empty
## row would be a question about nothing.
func _on_clear_pressed() -> void:
    if _swatches.is_empty() or not is_inside_tree():
        return
    SaMessage.confirm(
        self,
        tr("Clear Swatches"),
        tr_n("Delete %d swatch?", "Delete all %d swatches?", _swatches.size()) % _swatches.size(),
        PackedStringArray([tr("Cancel"), tr("Clear", "clear the palette")]),
        _on_clear_answered,
        CLEAR_CANCEL,
        CLEAR_CANCEL
    )


func _on_clear_answered(index: int) -> void:
    if index == CLEAR_CLEAR:
        swatches_clear_requested.emit()
