## The File menu: new, new from the clipboard, open, recent files, import, save, save as, save as JPEG
## XL, Export and Export Target, Close and Quit,
## which opens one dialog rather than a row for each format, and under it Export Frames..., while the document holds a simulation.
##
## **The rows, and nothing else**. Every row but the recent files is a command,
## whose words, chord and sentence the row reads from the registry. How a
## document comes in and goes out, and the guard every destructive path runs
## through, is `SaDocumentFiles`, which main builds beside the shortcut router.
## A row asks it at the moment of the press, so a menu on a bar nobody put in a
## tree finds none and does nothing.
class_name SaFileMenu
extends SaMenu

const ID_NEW := 199
const ID_OPEN := 200
const ID_SAVE := 201
const ID_EXPORT := 202
const ID_SAVE_AS := 205
const ID_IMPORT := 206
const ID_QUIT := 207
## Export Frames..., shown under Export only while it is enabled.
const ID_EXPORT_FRAMES := 208
const ID_SAVE_AS_JPEG_XL := 209
const ID_NEW_FROM_CLIPBOARD := 210
const ID_EXPORT_TARGETS := 211
const ID_CLOSE := 212

## Recent entries take ids from here, one per row, in the list's own order.
const ID_RECENT_BASE := 250

const RECENT_SUBMENU := "RecentSubMenu"

## The paths behind the recent rows, in row order, as they were when the menu
## was last built.
var _recent_paths: Array = []


func _init(menu_popup: SaChoicePopup) -> void:
    super(menu_popup)
    if not SaSettings.recent_files_changed.is_connected(populate):
        SaSettings.recent_files_changed.connect(populate)


func _add_items() -> void:
    add_commands([[ID_NEW, &"file_new"], [ID_NEW_FROM_CLIPBOARD, &"file_new_from_clipboard"], LINE, [ID_OPEN, &"file_open"]])
    _add_recent_submenu()
    # Its own entry rather than a second meaning for Open: Import puts a picture
    # into the document that is already open.
    var rows: Array = [
        [ID_IMPORT, &"file_import"],
        LINE,
        [ID_SAVE, &"file_save"],
        [ID_SAVE_AS, &"file_save_as"],
        [ID_SAVE_AS_JPEG_XL, &"file_save_as_jpeg_xl"],
        LINE,
        [ID_EXPORT, &"file_export"],
        [ID_EXPORT_TARGETS, &"file_export_targets"],
    ]
    # Shown rather than dimmed, and only while the document holds a simulation:
    # most documents never hold one, and a dim row would stand on every File.
    var frames := _descriptor(&"file_export_frames")
    if frames != null and frames.is_enabled():
        rows.append([ID_EXPORT_FRAMES, &"file_export_frames"])
    rows.append_array([LINE, [ID_CLOSE, &"file_close"], [ID_QUIT, &"ui_quit"]])
    add_commands(rows)


## The recent files, rebuilt with the menu because the list moves.
##
## **A heading and its rows, where it was a submenu.** `SaChoicePopup` has no
## second window to hang one off, and a submenu was never what these rows
## wanted: a painter opening File to reach the last file they had open had to
## find Open Recent, hover it, wait for the second list and then aim. The rows
## are in this list now, under a heading, and the list scrolls past its height
## cap. Each row still carries its full path as its own tip, which is the thing
## the submenu's rows carried and the reason they are not just filenames.
func _add_recent_submenu() -> void:
    _recent_paths = SaSettings.recent_files()
    add_heading(tr("Open Recent"))
    if _recent_paths.is_empty():
        add_item(tr("No recent files"), ID_RECENT_BASE, true)
        explain(ID_RECENT_BASE, "Nothing has been opened yet. A file opened from here or from Open File joins this list.")
        return
    for i in _recent_paths.size():
        var path: String = _recent_paths[i]
        add_item(path.get_file(), ID_RECENT_BASE + i)
        set_item_tooltip(ID_RECENT_BASE + i, path)


## The recent rows, the only ones here that run no command. Their ids arrive
## here because they are rows of this list, and the row is bounded here, which
## also makes the disabled "No recent files" row a no-op. Whether the file
## takes a tab of its own is the flow's to decide, so nothing is asked here.
func _pressed(id: int) -> void:
    var row := id - ID_RECENT_BASE
    if row >= 0 and row < _recent_paths.size() and files() != null:
        files().open_path(_recent_paths[row])


## The document flow the rows run, or null for a menu with no app around it.
## A seam a suite overrides to record what a row asked for, since the flow
## itself needs Sara's own main scene.
func files() -> SaDocumentFiles:
    return SaDocumentFiles.in_tree(popup.get_tree()) if in_tree() else null
