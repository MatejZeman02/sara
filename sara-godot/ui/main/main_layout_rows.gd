## The Window menu's Layouts section, under the dockers they arrange: a row for
## each named layout, the current one marked, and the press that loads one.
## Switching only: saving one and deleting one are on the Workspace page,
## because a delete behind a hover is a delete nobody meant.
##
## **A heading and its rows rather than a submenu.** `SaChoicePopup` has no
## second window to hang one off, and the list is read from disk every time
## [method add_to] runs, which is before every open: the Window menu has an
## `SaMenu` behind it, so the bar's own rebuild is what keeps this current, and
## the store's `presets_changed` rebuilds it too: a layout saved in Preferences
## while the app is running is in the list the next time the menu is pulled
## down.
##
## **A layout's UI scale is kept between opens.** The row's hover names the
## scale a layout sets, and reading it is parsing the layout's whole file. Read
## for every row before every open, it took a few milliseconds of the Window
## menu's frame on a large document, so each file's scale is kept until
## the file changes on disk.
##
## Its own class, cut out of `MainDockers` by what each part owns:
## the docker rows are that node's, and these rows are the layout store's.
class_name MainLayoutRows
extends RefCounted

## What a row id starts with, before the layout's index in the store's list.
const PREFIX := "layout_"

## The row a store with no layouts shows, which takes no press.
const NONE := &"layout_none"

## The store whose layouts these are.
var _store: DockerLayoutStore

## Each layout file's UI scale, by the path it is read from, as
## `[time on disk, scale]`.
var _scales: Dictionary = {}


func _init(store: DockerLayoutStore) -> void:
    _store = store


## Appends the section to *menu*, the list the Window menu's own rebuild has
## just filled with the docker rows.
func add_to(menu: SaChoicePopup) -> void:
    if menu == null:
        return
    menu.add_gap()
    menu.add_section(tr("Layouts"))
    var presets: Array[String] = _store.list_presets()
    if presets.is_empty():
        menu.add_row(NONE, tr("No saved layouts"), false, false, "", "", true)
        return
    var current: String = _store.current_preset()
    var chosen := &""
    for i in presets.size():
        var row_id := StringName(PREFIX + str(i))
        menu.add_row(row_id, _store.presets().title(presets[i]))
        var button := menu.label_button(row_id)
        if button != null:
            button.tooltip_text = _sentence(presets[i])
        if presets[i] == current:
            chosen = row_id
    menu.set_current(chosen)


## Whether *row_id* is a layout's row that a press loads.
func is_layout(row_id: StringName) -> bool:
    return String(row_id).begins_with(PREFIX) and row_id != NONE


## Loads the layout whose row is *row_id*, if the store still lists it.
func load_at(row_id: StringName) -> void:
    var at := int(String(row_id).trim_prefix(PREFIX))
    var presets: Array[String] = _store.list_presets()
    if at >= 0 and at < presets.size():
        _store.load_preset(presets[at])


## What a layout's row says on hover: the UI scale it sets when that is not 1,
## and nothing otherwise. No shipped layout sets one, so the row that says one
## is a painter's own layout.
func _sentence(preset_name: String) -> String:
    var scale := _scale_of(preset_name)
    if is_equal_approx(scale, 1.0):
        return ""
    # A per cent is a figure with its sign and governs no word, so it needs no plural form.
    return tr("Places its dockers and sets the UI scale to %s.") % ("%d%%" % roundi(scale * 100.0))


## The UI scale *preset_name* sets, read from its file only when the file is
## new to this or its time on disk has moved. A layout saved again within the
## second of the last read is the one change this misses, and only in a hover
## sentence, until the next save or the next start.
func _scale_of(preset_name: String) -> float:
    var presets := _store.presets()
    var path := presets.read_path(preset_name)
    var stamp: int = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1
    var kept: Array = _scales.get(path, [])
    if kept.size() != 2 or kept[0] != stamp:
        kept = [stamp, presets.ui_scale_of(preset_name)]
        _scales[path] = kept
    return float(kept[1])
