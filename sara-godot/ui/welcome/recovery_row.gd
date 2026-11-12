## The autosave's recovery offer as the top of the welcome window's Recent pane:
## one row per copy, above the grid, with the three choices the chain of windows
## asks, rather than a window of its own per copy.
##
## **What a copy is worth offering is `SaAutosave.find_recoveries`' business**,
## and this row is a second caller of it rather than a second copy of its rules
## about staleness. Nor does it load a copy to draw a row: the name, the path and
## the file's time are all it needs, and a load is a readback of every chunk.
##
## The boot opens this row or the chain, never both, and `SaBoot` is where that
## is decided (`SaWelcomeWindow.wanted_at_start`, then
## `SaAutosave.surface_at_start` in `Main`).
##
## A row built while Sara boots offers its copies before the autosave exists,
## so Open waits for `EventBus.boot_finished` and is drawn disabled until then.
## Delete and Later touch nothing the boot builds and work at once.
@tool
class_name WelcomeRecoveryRow
extends VBoxContainer

## The copies drawn now, each `{"copy", "original"}` as `find_recoveries` gave
## them, in that order.
var entries: Array = []

## Copies the painter put off with Later while the window was open, which come
## back the next time it opens because the file was never touched.
var _put_off: Array[String] = []

## Whether the boot this row was built in is still running.
var _booting: bool = false


## *booting* is true for the row of a welcome window `SaBoot` built.
func _init(booting: bool = false) -> void:
    name = "Recoveries"
    add_theme_constant_override("separation", SaUI.px(6))
    _booting = booting
    if _booting:
        EventBus.boot_finished.connect(_on_boot_finished, CONNECT_ONE_SHOT)


## The boot is done, so the autosave is there to open a copy and to record the
## offer, and the rows are drawn again with Open live. Copies put off during the
## boot stay put off.
func _on_boot_finished() -> void:
    _booting = false
    var window := get_window() if is_inside_tree() else null
    var autosave := _autosave()
    if window != null and window.visible and autosave != null:
        refresh(autosave.recoveries_for_pane(SaSettings.recent_files()))
    else:
        refresh(entries)


func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_TREE:
        var window := get_window()
        if window != null and not window.visibility_changed.is_connected(_on_window_visibility_changed):
            window.visibility_changed.connect(_on_window_visibility_changed)
        # The first open announces nothing: a `Window` is visible from its
        # constructor, so the one `popup_centered` after the window joins the
        # tree does not change `visible`. Asked once the frame's building is done.
        _show_or_collapse()
        _on_window_visibility_changed.call_deferred()


## Asks again every time the welcome window opens, because a copy can be written
## or retired between two opens of a window that is built once and kept.
func _on_window_visibility_changed() -> void:
    var window := get_window()
    if window == null or not window.visible:
        return
    _put_off.clear()
    var recent := SaSettings.recent_files()
    var autosave := _autosave()
    refresh(autosave.recoveries_for_pane(recent) if autosave != null else SaAutosave.find_recoveries(recent))


## Draws one row per entry of *found*, which is what `find_recoveries` returned.
func refresh(found: Array) -> void:
    entries = found.duplicate()
    for child in get_children():
        remove_child(child)
        child.queue_free()
    var index := 0
    for entry: Dictionary in entries:
        if not _put_off.has(String(entry["copy"])):
            add_child(_build_row(entry, index))
        index += 1
    _show_or_collapse()


## What the row draws, one dictionary per copy in `entries` order, for a test
## and for the dump: the name a painter reads, the copy's path and time, and
## whether Later put it off.
func row_report() -> Array:
    var report: Array = []
    for entry: Dictionary in entries:
        var copy := String(entry["copy"])
        var entry_report := {
            "name": name_for(String(entry["original"])),
            "copy": copy,
            "original": String(entry["original"]),
            "modified": modified_text(copy),
            "put_off": _put_off.has(copy),
        }
        report.append(entry_report)
    return report


## The dump's two lines about the offer, merged into its autosave block: which
## surfaces *autosave* offered copies on, the chain or this row, and what the live
## row under *root* draws, empty when no welcome window has been built.
static func capture_state(root: Node, autosave: SaAutosave) -> Dictionary:
    var row := root.find_child("Recoveries", true, false) as WelcomeRecoveryRow
    return {"offer_surfaces": autosave.offer_surfaces, "recovery_rows": row.row_report() if row != null else []}


## The name a painter knows the copy by, the chain's own words for one that
## belongs to no file.
static func name_for(original: String) -> String:
    return original.get_file() if not original.is_empty() else String(TranslationServer.translate("an unsaved document"))


## When the copy was written, in local time, from the file's own time rather than
## from anything inside it.
static func modified_text(copy: String) -> String:
    if not FileAccess.file_exists(copy):
        return ""
    var bias_seconds: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
    return Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(copy) + bias_seconds, true)


func _build_row(entry: Dictionary, index: int) -> Control:
    var copy := String(entry["copy"])
    var original := String(entry["original"])

    var row := SaMake.row(null, "Recovery%d" % index, SaTheme.GAP)
    var text := SaMake.column(row, "Text")
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaMake.label(text, "Name", tr("Recovered work: %s") % name_for(original))
    var detail := SaMake.label(text, "Detail", tr("Kept %s, at %s") % [modified_text(copy), copy])
    detail.text_overrun_behavior = SaTheme.TEXT_CUT
    detail.tooltip_text = copy
    SaTheme.bind_font(detail, "text_muted")

    var open_tip := tr("Open this recovered copy as the original file, with unsaved changes.")
    var open := SaMake.button(row, "RecoveryOpen%d" % index, tr("Open", "open a document"), open_tip)
    open.pressed.connect(_on_open_pressed.bind(entry))
    open.disabled = _booting
    var delete := SaMake.button(row, "RecoveryDelete%d" % index, tr("Delete"), tr("Remove the recovery copy from the disk"))
    delete.pressed.connect(_on_delete_pressed.bind(entry))
    var later_tip := tr("Keep the copy and ask again the next time this window opens")
    SaMake.button(row, "RecoveryLater%d" % index, tr("Later"), later_tip).pressed.connect(_on_later_pressed.bind(entry))
    return row


## Open goes through the document flow's unsaved-changes prompt, the guard every other
## door that replaces the document uses, because this window can be opened from
## Help over a painting.
func _on_open_pressed(entry: Dictionary) -> void:
    var main_node := _main()
    var autosave := _autosave()
    if main_node == null or autosave == null:
        return
    var canvas := SaCanvasView.front_canvas()
    var proceed := _open_and_forget.bind(autosave, canvas, entry)
    var files := SaDocumentFiles.in_tree(get_tree())
    if files != null:
        files.confirm_discard(tr("opening the recovery copy"), proceed)
    else:
        proceed.call()


func _open_and_forget(autosave: SaAutosave, canvas: SaCanvas, entry: Dictionary) -> void:
    autosave.open_recovery(canvas, String(entry["copy"]), String(entry["original"]))
    _forget(entry)


func _on_delete_pressed(entry: Dictionary) -> void:
    SaAutosave.delete_recovery(String(entry["copy"]))
    _forget(entry)


func _on_later_pressed(entry: Dictionary) -> void:
    _put_off.append(String(entry["copy"]))
    refresh(entries)


## Takes an answered entry off the row. The rebuild only queues the pressed
## button for freeing, so it is safe from inside its own `pressed`.
func _forget(entry: Dictionary) -> void:
    var rest := entries.duplicate()
    rest.erase(entry)
    refresh(rest)


## With no copy to offer the row, and the container it sits in, take no height,
## so the grid starts right under the pane's title.
func _show_or_collapse() -> void:
    var shown := get_child_count() > 0
    visible = shown
    var holder := get_parent() as Control
    if holder != null:
        holder.visible = shown


func _main() -> Node:
    if not is_inside_tree():
        return null
    var main_node := get_tree().current_scene
    return main_node if main_node != null and main_node.has_method("get_canvas") else null


func _autosave() -> SaAutosave:
    var main_node := _main()
    if main_node == null or not ("autosave" in main_node):
        return null
    return main_node.autosave
