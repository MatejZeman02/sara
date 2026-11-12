## The rename dialog a layer gets from the actions menu: the name in one field
## and the note in a box beneath it, so a painter renaming a layer is the
## painter who wants to see what the layer was noted as.
##
## **It is as tall as what it holds.** The note is one line while it is empty
## and nobody has clicked it, and then it takes the lines its text needs, up to
## `NOTE_MAX_LINES`, with the window following it, so renaming one word does
## not take a fifth of the window.
##
## The inline field in the row stays the fast door and keeps its own argument
## for never writing the note, in `layer_rename.gd`. This is the
## slow door, and it is the only one that carries a note out of a tooltip and
## into a field a painter can edit.
##
## **The write is done here rather than in the docker.** The dialog names the
## document and the layer it was opened on, so the suite proves what Rename writes
## against a real document without a docker on screen, which is a `Window` and
## cannot be added to a test's tree.
##
## **Escape is not read here.** `ShortcutRouter` is the one place that reads
## the key, and a dialog hears it as its close button. Cancel is the button,
## and the close button on the title strip is the same answer.
@tool
class_name SaLayerRenameDialog
extends SaDialogWindow

## The painter confirmed, and both fields are on the layer. The docker listens
## so its rows are rebuilt, because the note's mark is a row's own state.
signal confirmed(layer: SaLayer)

## The most lines the note box grows to, the rest of a long note scrolling in it.
const NOTE_MAX_LINES: int = 5

## The lines an empty note box takes once it has been clicked or tabbed into, so
## there is room to see what is being written. A note that holds text takes the
## lines the text needs instead, and never fewer than one.
const NOTE_LINES_CLICKED: int = 3

## The narrowest the window is dragged to, in logical units.
const FLOOR_WIDTH: int = 320

var _document: SaDocument = null
var _layer: SaLayer = null
var _name_edit: LineEdit = null
var _note_edit: TextEdit = null
var _note_clicked: bool = false
var _ok_button: Button = null


func _init() -> void:
    _init_dialog("LayerRenameDialog", tr("Rename Layer"), Vector2i(420, 160), Vector2i(FLOOR_WIDTH, 120))

    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        margin.add_theme_constant_override(side, SaUI.px(SaTheme.PAD))
    content.add_child(margin)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    column.set_anchors_preset(Control.PRESET_FULL_RECT)
    margin.add_child(column)

    # The label stands beside the field and not above it, which makes the row as
    # high as a field and not as two lines.
    var name_row := SaMake.row(column, "NameRow", SaTheme.GAP)
    var name_label := _heading(tr("Name"))
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_row.add_child(name_label)
    _name_edit = SaMake.line_edit(name_row, "NameEdit")
    _name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # A name typed and submitted from this field is the same answer as the Rename
    # button, because a `LineEdit` eats Return and the dialog's own Enter would
    # never hear it.
    _name_edit.text_submitted.connect(_on_name_submitted)
    first_focus = _name_edit

    # The box names itself while it is empty, so a line of its own for the word
    # Note would only be one more row of a dialog that is meant to be short.
    _note_edit = TextEdit.new()
    _note_edit.name = "NoteEdit"
    # It takes what a window dragged taller gains, which also pins the buttons to
    # the foot without the spacer a gap of its own would cost.
    _note_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _note_edit.placeholder_text = tr("Note")
    _note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _note_edit.text_changed.connect(_size_to_note)
    _note_edit.focus_entered.connect(_on_note_clicked)
    column.add_child(_note_edit)
    _size_the_note()

    var buttons := pinned_buttons(column)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)

    # Named for what it does, as Canvas Size's Resize is. The node keeps the
    # name it had, which the suites press it by.
    _ok_button = SaMake.button(buttons, "OKButton", tr("Rename"))
    _ok_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    _ok_button.pressed.connect(_apply)
    default_button = _ok_button


## Opens on *layer*, prefilled with the name it carries and the note it was
## left, and centred on the main window, the first time and every time after.
##
## The show is `popup_centered`'s, for the focus and the stacking, and the
## position is written after it from `main_rect`, as the Welcome window
## writes its own, because a window of its own is centred on the screen rather
## than on the main window. What kept it off the middle in the app was the fit a
## frame later, which `host_rect` below answers.
##
## *at_note* is the row's note mark asking: the keyboard lands in the note with
## the caret after its last word, because a painter who pressed the mark came
## to read or write the note and not to change the name, and the title and the
## button say Note and Save, not Rename ("But we are writing a note..."). Every
## other door opens on the name, selected whole so typing replaces it.
##
## Both calls into the tree are guarded, for the reason `layer_rename.gd` gives
## about its own two: a dialog a test builds is never added to a tree, and
## Godot raises on `popup_centered` and on a focus grab there.
func open_for(document: SaDocument, layer: SaLayer, at_note: bool = false) -> void:
    if document == null or layer == null:
        return
    _document = document
    _layer = layer
    _name_edit.text = layer.shown_name()
    _note_edit.text = layer.comment
    _note_clicked = false
    retitle(tr("Layer Note") if at_note else tr("Rename Layer"))
    _ok_button.text = tr("Save") if at_note else tr("Rename")
    _size_the_note()
    first_focus = _name_edit
    if at_note:
        first_focus = _note_edit
    var last_line := _note_edit.get_line_count() - 1
    _note_edit.set_caret_line(last_line)
    _note_edit.set_caret_column(_note_edit.get_line(last_line).length())
    if not is_inside_tree():
        return
    # Sized before it is shown, because a window keeps the size it last had and
    # the note of the layer before this one may have been taller.
    _fit_height(true)
    popup_centered()
    position = centred_in(main_rect(), size)
    if not at_note:
        _name_edit.select_all()


## The base fit, with the note measured first and the height held to the content
## after, because the base only grows a window and a note that wrapped on the
## frame after the show has more lines than it had when it was hidden.
func fit_opening_size() -> void:
    _size_the_note()
    super.fit_opening_size()
    _fit_height(true)


## The note box asks for the lines its text takes, and the window follows.
func _size_to_note() -> void:
    _size_the_note()
    _fit_height(false)


## Clicked or tabbed into: an empty note opens out to a few lines to write in.
## The room stays when the box is left, because a box that shrank on a click
## on Rename would take the button from under the pointer before it was let go.
func _on_note_clicked() -> void:
    _note_clicked = true
    _size_to_note()


## Gives the note box the height of the lines it shows, in the theme's own line
## height, so it follows the font size a painter chose.
func _size_the_note() -> void:
    var chrome := _note_edit.get_theme_stylebox("normal").get_minimum_size().y
    _note_edit.custom_minimum_size.y = ceilf(chrome + float(_note_edit.get_line_height() * _note_lines()))


## How many lines the note box shows: the wrapped lines of its text up to
## `NOTE_MAX_LINES`, one for an empty note nobody has clicked, and
## `NOTE_LINES_CLICKED` once it has been. A window that has not been laid out
## has no width to wrap at, so it counts the lines the text itself breaks into.
func _note_lines() -> int:
    var held := _note_edit.get_total_visible_line_count() if _note_edit.size.x > 0.0 else _note_edit.get_line_count()
    if _note_clicked:
        held = maxi(held, NOTE_LINES_CLICKED)
    return clampi(held, 1, NOTE_MAX_LINES)


## Holds the window to the height its content asks for, shrinking as well as
## growing, which the base fit never does. The width is the one the painter has.
## *about_the_middle* moves the top edge by half the change, as the base fit
## does, for a window that is being opened. A note that grows under a typing
## painter keeps its top edge where it is.
func _fit_height(about_the_middle: bool) -> void:
    if not is_inside_tree() or SaDockerMaximise.is_maximised(self):
        return
    var needed := content_minimum_size()
    logical_min_size = Vector2i(FLOOR_WIDTH, needed.y).max(Vector2i(needed.x, 0))
    logical_size = Vector2i(maxi(logical_size.x, logical_min_size.x), needed.y)
    var before := size
    min_size = SaUI.window_size_for(self, logical_min_size)
    size = SaUI.window_size_for(self, logical_size)
    if about_the_middle and visible:
        var changed := size - before
        @warning_ignore("integer_division")
        position -= Vector2i(changed.x / 2, changed.y / 2)


## The rectangle this dialog is fitted and kept in: the main window less its
## top bar, as for every other dialog, rather than the Layers docker it is a
## child of.
##
## Rename Layer opened at 24,236 at 1920 by 1080, over Brush Presets across the
## window from the docker, and 262 wide where it asks for 420. The
## inherited host is `SaDockerMaximise.host_rect`, which measures the viewport
## of the window's parent, and the parent of this one is the docker, a window
## that embeds nothing. So the fit on the frame after the show took the docker's
## 310 less two margins for the width, and kept the window inside 0 to 310 of a
## space that is the main window's. Every dialog `MainDialogs` opens is a child
## of the main window, which is why this one alone met it.
func host_rect() -> Rect2i:
    return below_the_bar(main_rect())


## The main window's rectangle in the space this window's `position` is
## measured in. Embedded, that is the viewport the engine embeds it in, the
## first one up from its parent that takes subwindows, which is the main window
## and never the docker. A window of its own measures the main window where it
## stands on the screen.
func main_rect() -> Rect2i:
    if not is_embedded():
        var main := get_tree().root
        return Rect2i(main.position, main.size)
    var host := get_parent().get_viewport()
    while host != null and not host.gui_embed_subwindows and host.get_parent() != null:
        host = host.get_parent().get_viewport()
    return Rect2i(host.get_visible_rect()) if host != null else Rect2i()


## Where a window of *window_size* stands to have its middle on *host*'s.
static func centred_in(host: Rect2i, window_size: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return host.position + Vector2i((host.size.x - window_size.x) / 2, (host.size.y - window_size.y) / 2)


## Rename, and Enter from the name field. The name goes through the same filter the
## inline field applies, so the two doors agree about what a name may be. An
## empty one is not a name, which is the cancel the inline field already
## answers with, and nothing at all is written for it.
##
## The name and the note are one Rename Layer step, the one the inline field
## records, so an undo gives both back. A dialog that changed neither adds none.
func _apply() -> void:
    var layer := _layer
    if not is_instance_valid(layer):
        hide()
        return
    var wanted := SaLayerRename.sanitize_name(_name_edit.text)
    if wanted.is_empty():
        hide()
        return
    SaLayerOps.new(_document).rename(layer, wanted, _note_edit.text)
    hide()
    confirmed.emit(layer)


func _on_name_submitted(_text: String) -> void:
    _apply()


func _heading(label: String) -> Label:
    var heading := Label.new()
    heading.text = label
    heading.add_theme_color_override("font_color", SaTheme.palette.text_muted)
    return heading


## Drives the rename dialog: what the window holds and what one of its buttons
## does. The window is a `Window` of its own, so an injected click and an
## injected key do not reach it, and this is the door a scenario uses instead.
##
## A spec with no `key` only reads the two fields back, which is the shot of the
## dialog prefilled. `name` and `note` write the fields, `focus: note` puts the
## keyboard in the note box as a click on it does, and `key` is `ok` or
## `cancel`, the two buttons a painter can press, or `enter`, the key in the
## Name field.
static func capture_dialog(tree: SceneTree, spec: Dictionary) -> String:
    var dialog := tree.root.find_child("LayerRenameDialog", true, false) as SaLayerRenameDialog
    if dialog == null:
        return "SaCapture: no rename dialog is open"
    if spec.has("name"):
        dialog._name_edit.text = String(spec["name"])
    if spec.has("note"):
        dialog._note_edit.text = String(spec["note"])
        # Written by code, so the box does not say its text changed.
        dialog._size_to_note()
    if String(spec.get("focus", "")) == "note":
        dialog._note_edit.grab_focus()
    var answered := String(spec.get("key", ""))
    match answered:
        "ok":
            dialog._apply()
        "enter":
            dialog._name_edit.text_submitted.emit(dialog._name_edit.text)
        "cancel":
            dialog.hide()
        "":
            pass
        var other:
            return "SaCapture: no rename answer called '%s'" % other
    var layer := dialog._layer
    if not is_instance_valid(layer):
        return "SaCapture: rename dialog answered '%s', and its layer is gone" % answered
    # Which field holds the keyboard, because a caret is a pixel wide in a shot
    # and the note mark's whole promise is that it lands in the note.
    var focus := dialog.gui_get_focus_owner()
    return (
        "SaCapture: rename dialog answered '%s', fields '%s' and '%s', layer '%s' holds %d note chars, focus on '%s'"
        % [
            answered,
            dialog._name_edit.text,
            dialog._note_edit.text,
            layer.shown_name(),
            layer.comment.length(),
            str(focus.name) if focus != null else "",
        ]
    )
