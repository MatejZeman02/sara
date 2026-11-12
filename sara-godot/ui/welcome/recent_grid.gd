## The recent documents on the welcome window as cards: a thumbnail, the file's
## name, its folder and the day it was last written, and a small control that
## takes the path off the list.
##
## **The picture comes out of the file, never out of the document.** A preview is in
## every `.sad` the painter saves, and `SaSadFile.read_preview` seeks to it without
## building anything. Loading ten documents to draw ten thumbnails is the readback
## the rule against reading the canvas back exists to stop, so a file with no preview, which is every older `.sad`
## and every picture opened as a document, draws a placeholder rather than being
## opened to make one.
##
## **And out of the cache when the file has none**. The document was read back
## once while it was live, by `WelcomePreviewCache`, and a card draws that
## picture rather than a placeholder. The grid takes it at an open it sees, and
## the document flow at every close through `SaWelcomeWindow.keep_closing_picture`,
## since a grid that was never built sees no open. The grid is the only reader.
##
## **The cards stand under their folders**, as `welcome-window.md` asks: a header
## naming the folder over a grid of its cards, the folders in the order of the
## newest document in each. `WelcomeRecentFolders` in `recent/` does the grouping
## and this file draws it.
##
## **One reader and one writer of the list, and neither is here.** The cards are
## `SaSettings.recent_files()` as it stands, rebuilt on `recent_files_changed`,
## and the remove control calls `SaSettings.remove_recent_file` and touches
## nothing on disk. An open goes through the document flow's `confirm_discard`
## and `open_path`, the guard a recent row in the menu uses, so a click on the
## welcome window cannot lose unsaved work the menu would have asked about.
##
## **A grid built while Sara boots holds its cards until the boot is done**, since
## the welcome window is on screen before the document flow
## exists. The cards are dimmed, a press on one keeps its path rather than
## opening it, and the card chosen is drawn whole among the dimmed. On
## `EventBus.boot_finished` every card is whole again and the one chosen opens
## through the same guard a press takes.
@tool
class_name WelcomeRecentGrid
extends ScrollContainer

## A card's width, in logical units. Four of them, their gaps and a scroll bar
## fit the pane of a welcome window at its 720 wide, so a painter sees a row
## whole. The height is whatever the picture and three lines of words need.
const CARD_WIDTH := 164.0

## The space between a card's edge and what it holds, in logical units.
const PADDING := 6

## The box the thumbnail is fitted into, in logical units. A preview is 256 on
## its long side, so this is a little over half of it and never an enlargement.
const THUMB := Vector2(152.0, 84.0)

## The gap between two cards, in logical units.
const GAP := SaTheme.GAP

## How far a card that will not open is faded. Dimmed is disabled here, the way
## a menu row that cannot be chosen reads.
const MISSING_ALPHA := 0.45

## Frames between the moment the recent list moves and the readback that stores
## the picture of the document behind it. Two, because the list moves at the end
## of an open and the composite that draws the document just opened has not run
## yet: one frame is the composite's own frame, the second is the one after it.
##
## Counted in `SceneTree.process_frame` rather than in this node's own frames,
## because the grid sits inside the welcome window and that window is usually
## hidden by the time a document is opened. A node that draws no frame of its own
## still has to see the tree's.
const CAPTURE_DELAY := 2

## How many cards stand in one row of a folder's grid.
const COLUMNS := 4

## The column the folders stand in, each a header and a grid of its cards.
var folders: VBoxContainer

## One grid per folder, in the order the folders stand, four cards to a row.
var grids: Array[GridContainer] = []

## One entry per card, in card order, the facts a card was drawn from, for
## `row_report`.
var _rows: Array[Dictionary] = []

## The block an empty list shows in place of the cards, an action to open a
## file and a line saying what fills the list, so a first start opens on a way
## in rather than on a blank panel.
##
## The pane makes it and lays it beside this grid, which hides itself while the
## line shows. Inside the grid it was one cell, and it wrapped into a column a
## quarter of the pane wide. Null for a grid built alone.
var empty_line: Control

## The cards themselves, in the same order as the report, so a test or a scenario
## presses the one it means. Each sits in a `RecentCardBox<index>` beside its
## column of words and its `RecentRemove<index>`.
var cards: Array[Button] = []

## The document flow a test hands in. A running app leaves it null and the grid
## asks the main scene for the flow at the moment of a press.
var _files: SaDocumentFiles = null

## The list moved while the window was hidden, so the next show rebuilds.
var _stale: bool = false

## Whether a deferred capture is on its way, so two moves of the list in the
## same frame take one picture rather than two.
var _capture_running: bool = false

## The recent list as it stood the last time it moved, so the path that arrived
## at the head can be told from a list that only got shorter.
var _known_recent: Array = []

## The path that just arrived at the head of the list, "" when none did. Taken
## by the next capture, which is the only reader of it.
var _arrived: String = ""

## Whether the boot this grid was built in is still running.
var _booting: bool = false

## The path chosen while the boot runs, "" when none was. Opened when it ends.
var _chosen: String = ""


## *booting* is true for the grid of a welcome window `SaBoot` built, whose
## cards wait for `EventBus.boot_finished`. *empty* is the line the pane laid
## beside this grid, shown while there is no card.
func _init(files: SaDocumentFiles = null, booting: bool = false, empty: Control = null) -> void:
    name = "RecentCards"
    _files = files
    _booting = booting
    empty_line = empty
    if _booting:
        EventBus.boot_finished.connect(_on_boot_finished, CONNECT_ONE_SHOT)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    folders = SaMake.column(self, "Folders", GAP)
    folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _known_recent = SaSettings.recent_files()
    SaSettings.recent_files_changed.connect(_on_recent_files_changed)
    # A document already live when this grid was built has had its own moment,
    # the open, and this is the only chance to take its picture: a launch that
    # opened a file on the command line builds the window after it. The
    # picture lands a few frames on, and the cards are built again then.
    _capture_live_document()
    rebuild()


func _notification(what: int) -> void:
    if what == NOTIFICATION_VISIBILITY_CHANGED and _stale and is_visible_in_tree():
        rebuild()


## One dictionary per card in card order, which is folder by folder: `path`,
## `name`, `folder`, `date`,
## `missing`, `preview`, true when the card drew a picture, `source`, which
## of the three places the picture came from: "file", "cache", "picture" for
## a PNG or EXR read out of the file itself, or "" for none,
## and `held`, true while the boot holds the card and it is not the one chosen.
##
## `source` is what a capture reads to tell a card with a picture out of the
## file from one that is drawn from the cache, which are the same card on screen
## and two different claims about where it came from.
func row_report() -> Array:
    var report: Array = []
    for row in _rows:
        var entry: Dictionary = row.duplicate()
        entry["held"] = _booting and entry["path"] != _chosen
        report.append(entry)
    return report


## Draws one card per recent path, from the list as it stands, under a header
## per folder.
##
## Old folders are taken out of the column at once and freed at the end of the
## frame, because the press that asked for this rebuild is still being handled
## by a button on one of them.
func rebuild() -> void:
    _stale = false
    for old in folders.get_children():
        folders.remove_child(old)
        old.queue_free()
    grids.clear()
    cards.clear()
    _rows.clear()

    var groups := WelcomeRecentFolders.group(WelcomeRecentFolders.of_recent_list(SaSettings.recent_files()))
    for group_index in groups.size():
        var group: Dictionary = groups[group_index]
        var header := SaMake.label(folders, "FolderHeader%d" % group_index, group["folder"])
        header.text_overrun_behavior = SaTheme.TEXT_CUT
        header.tooltip_text = group["folder"]
        var cards_grid := SaMake.grid(folders, "Cards%d" % group_index, COLUMNS, GAP)
        cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grids.append(cards_grid)
        for path: String in group["paths"]:
            var row := read_row(path)
            _rows.append(row)
            var built := _build_card(cards.size(), row)
            cards.append(built)
            cards_grid.add_child(built.get_parent())
    # The grid steps aside for the line while the list is empty, so the line
    # has the pane rather than a share of it.
    visible = not cards.is_empty()
    if empty_line != null:
        empty_line.visible = cards.is_empty()
    _show_held()


## Dims every card the boot holds and draws the chosen one whole. Set on the
## card's box rather than on the grid, because a child cannot be brighter than
## the parent it is drawn in.
func _show_held() -> void:
    for index in cards.size():
        var held: bool = _booting and _rows[index]["path"] != _chosen
        var box := cards[index].get_parent() as Control
        box.modulate = Color(1.0, 1.0, 1.0, MISSING_ALPHA if held else 1.0)


## Forgets the card chosen while the boot runs, so it does not open once the
## boot is done. The welcome window asks when a press outside puts it away,
## because nothing should open behind a window the painter dismissed.
func drop_held_choice() -> void:
    if _chosen.is_empty():
        return
    _chosen = ""
    _show_held()


## The boot is done: every card is whole, and the one chosen while it ran opens.
func _on_boot_finished() -> void:
    _booting = false
    _show_held()
    var path := _chosen
    _chosen = ""
    if not path.is_empty():
        _on_card_pressed(path)


## What a card shows for *path*, read without opening the document.
##
## Static so a test asks it of a path alone. `preview` and `source` start empty
## and the card fills both once it has read the picture, which is the one read
## of the file's blob a card makes, and the second read of the cache when that
## found nothing.
static func read_row(path: String) -> Dictionary:
    var missing := not FileAccess.file_exists(path)
    return {
        "path": path,
        "name": path.get_file(),
        "folder": path.get_base_dir(),
        "date": "" if missing else date_text(FileAccess.get_modified_time(path)),
        "missing": missing,
        "preview": false,
        "source": "",
    }


## The day a file was last written as the painter's own calendar reads it,
## `2026-09-15`, the shape `SaNoteFile.now` gives a note's `date`. The day and
## not the minute, because the minute does not fit a card at the theme's font
## and a painter looking for last week's file reads the day.
##
## `FileAccess.get_modified_time` is seconds since the epoch in UTC, so the
## system's time zone bias is added before the dictionary is taken.
static func date_text(unix_seconds: int) -> String:
    var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
    var t := Time.get_datetime_dict_from_unix_time(unix_seconds + bias_minutes * 60)
    return "%04d-%02d-%02d" % [t.year, t.month, t.day]


func _on_recent_files_changed() -> void:
    # The list moves at the end of an open and at the end of a save, and the
    # document behind its newest path is the one worth a picture. Deferred,
    # because an open has not composited yet on this frame.
    var now := SaSettings.recent_files()
    _arrived = _arrived_path(now)
    _known_recent = now
    _capture_soon()
    _draw_cards()


## Draws the cards from the list as it stands.
##
## A hidden window reads ten file headers for nothing, so it waits to be shown.
## Detached, which is a suite, it rebuilds at once so the report is current.
## So does a grid hidden by its own empty list, since the show of its window
## never reaches a child that is hidden itself, and it would wait for good.
func _draw_cards() -> void:
    if is_inside_tree() and visible and not is_visible_in_tree():
        _stale = true
        return
    rebuild()


## The path that has just arrived at the head of the list, or "" when the list
## moved for another reason.
##
## `add_recent_file` erases a path and pushes it to the front, so the list is no
## shorter than it was and its head is a different path. `remove_recent_file`
## takes a path away, so the list is shorter: that is the whole of the test, and
## it is what keeps a card whose remove control was just pressed from being
## handed the picture of whatever document happens to be open.
##
## A path put at the head of a list that was already that long, without being
## opened, has no such witness and is read as an open. Nothing in the app moves
## the list that way: only a settings file written by hand does.
func _arrived_path(now: Array) -> String:
    if now.is_empty() or now.size() < _known_recent.size():
        return ""
    if not _known_recent.is_empty() and str(now[0]) == str(_known_recent[0]):
        return ""
    return str(now[0])


## Asks for the readback a couple of frames from now, once, however many times
## the list moves before it runs.
func _capture_soon() -> void:
    if _capture_running or not is_inside_tree():
        return
    _capture_running = true
    var tree := get_tree()
    for _frame in CAPTURE_DELAY:
        await tree.process_frame
    _capture_running = false
    if not is_inside_tree():
        return
    # The cards are built again once the picture lands, not here.
    _capture_live_document()


## Takes the live document's picture into the cache the cards read, and says
## whether one was stored.
##
## Nothing to do without a canvas, without a file this document came out of, or
## when that file carries a picture of its own: the grid reads that one, and a
## second copy of the same picture under `user://` would answer a question
## nobody asked. That last test is also what keeps a save from costing a
## readback, since the save is what writes the file's own preview.
##
## The file is the document's own path, or, for a picture opened as a document,
## the path that just arrived at the head of the recent list. See the two
## branches below for why those are the same question asked twice.
##
## The readback is export's, through `SaExport.take_preview`, so a cached
## picture is exactly what `File > Save` puts in the file and not a second kind
## of picture. It happens outside a stroke, at the one moment the pixels are
## already in VRAM, which is a readback the rule against reading the canvas back leaves open. The picture
## is taken on the card and read over the frames after, so
## true here says a picture is on its way. The cards are built again once it
## is stored, even on a grid out of sight, as the build of the window built
## them with the picture in.
func _capture_live_document() -> bool:
    var canvas_node := _live_canvas()
    if canvas_node == null:
        return false
    var document := canvas_node.document
    if document == null:
        return false
    var arrived := _arrived
    _arrived = ""
    var path := document.file_path
    if path.is_empty():
        # A picture opened as a document is nameless on purpose: there is no
        # `.sad` behind it, so `File > Open` puts the picture in the recent list
        # and leaves the document modified and without a path. The file it came
        # out of is the path that just arrived at the head of that list, and it
        # is a picture rather than a document, which is what tells this apart
        # from the move a save makes.
        if not SaImageImport.is_image_path(arrived):
            return false
        path = arrived
    if SaSadFile.read_preview(path) != null:
        return false
    if WelcomePreviewCache.read(path) != null:
        return false
    return WelcomePreviewCache.take(path, canvas_node.easel, rebuild)


## The canvas the cards are about: the front document's, never the info
## docker's scratchpad, whose document is a scratchpad and reaches no card.
func _live_canvas() -> SaCanvas:
    var live := SaCanvasView.front_canvas()
    return live if live != null and live.document != null else null


## What every card is showing and the folder headers in order, for the state
## dump.
##
## A shot shows a card with a picture in it and cannot say where the picture came
## from. Empty when no grid is on screen, which is every dump of a run that never
## opened the welcome window.
static func capture_state(root: Window) -> Dictionary:
    var cards_grid := root.find_child("RecentCards", true, false) as WelcomeRecentGrid
    if cards_grid == null:
        return {}
    var headers: Array = []
    for header: Node in cards_grid.folders.get_children():
        if header is Label:
            headers.append((header as Label).text)
    return {"rows": cards_grid.row_report(), "folders": headers}


func _build_card(index: int, row: Dictionary) -> Button:
    var path: String = row["path"]
    var missing: bool = row["missing"]

    # The card is three layers in one container, so its height is what its words
    # and picture need at the font the theme gives them: the button behind, the
    # column over it, and the remove control over both. A `Button` is not a
    # container, so words put inside one spill out of it at a larger font.
    var box := MarginContainer.new()
    box.name = "RecentCardBox%d" % index
    box.custom_minimum_size = Vector2(SaUI.pxf(CARD_WIDTH), 0.0)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var built := SaMake.button(box, "RecentCard%d" % index, "", path)
    # Disabled rather than only faded, so a press and Enter both do nothing and
    # the theme draws it the way every control that cannot act is drawn.
    built.disabled = missing
    built.pressed.connect(_on_card_pressed.bind(path))

    var margin := SaMake.margin(box, "Padding", PADDING)
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var column := SaMake.column(margin, "Column", 2)
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if missing:
        column.modulate = Color(1.0, 1.0, 1.0, MISSING_ALPHA)

    var picture: Image = null
    var source := ""
    if not missing:
        # The file's own preview first, the cache second and a picture file's
        # own pixels third: a `.sad` this build saved carries a preview, and
        # everything older and every picture opened as a document carries none.
        picture = SaSadFile.read_preview(path)
        if picture != null:
            source = "file"
        else:
            picture = WelcomePreviewCache.read(path)
            if picture != null:
                source = "cache"
            elif WelcomePreviewCache.after(path, rebuild):
                # A close took it a frame or two ago and it is still coming
                # back from the card, so the cards are built again when it lands.
                pass
            else:
                # A PNG or EXR on the list is a picture already, so a card with
                # nothing cached reads the file itself.
                picture = WelcomePreviewCache.of_picture_file(path)
                if picture != null:
                    source = "picture"
    row["preview"] = picture != null
    row["source"] = source
    column.add_child(_thumbnail(picture))

    _line(column, "FileName", row["name"], false)
    _line(column, "Folder", row["folder"], true)
    var date_words: String = tr("missing") if missing else str(row["date"])
    _line(column, "Date", date_words, true)

    # Last, so it is drawn over the picture and takes the press before the card
    # does. It stays live on a card that will not open, because a path whose
    # file is gone is the one a painter most wants off the list.
    var corner := SaMake.row(box, "Corner")
    corner.alignment = BoxContainer.ALIGNMENT_END
    corner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var remove := SaMake.button(
        corner, "RecentRemove%d" % index, "×", tr("Take this file off the recent list. Nothing on disk is touched.")
    )
    remove.flat = true
    remove.pressed.connect(_on_remove_pressed.bind(path))
    return built


## One line of a card's words, cut with an ellipsis rather than widening the card.
func _line(parent: Container, node_name: String, text: String, muted: bool) -> void:
    var line := SaMake.label(parent, node_name, text)
    line.text_overrun_behavior = SaTheme.TEXT_CUT
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if muted:
        SaTheme.bind_font(line, "text_muted")


## The picture in its box, or a plain placeholder when the file carries none.
func _thumbnail(picture: Image) -> Control:
    var box := Vector2(SaUI.pxf(THUMB.x), SaUI.pxf(THUMB.y))
    if picture != null:
        var shown := TextureRect.new()
        shown.name = "Thumbnail"
        shown.custom_minimum_size = box
        shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        shown.texture = ImageTexture.create_from_image(picture)
        shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return shown

    var placeholder := PanelContainer.new()
    placeholder.name = "Placeholder"
    placeholder.custom_minimum_size = box
    placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = SaTheme.palette.bg_input
    placeholder.add_theme_stylebox_override("panel", style)
    var words := SaMake.label(placeholder, "PlaceholderText", tr("No preview"))
    words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    words.mouse_filter = Control.MOUSE_FILTER_IGNORE
    SaTheme.bind_font(words, "text_muted")
    return placeholder


func _on_card_pressed(path: String) -> void:
    if _booting:
        _chosen = path
        _show_held()
        return
    var files := _flow()
    if files == null:
        return
    files.confirm_discard(tr("opening another file"), _open_and_close.bind(files, path))


## Opens *path* and puts the welcome window away, run only once the guard has
## said nothing unsaved is in the way.
func _open_and_close(files: SaDocumentFiles, path: String) -> void:
    files.open_path(path)
    if not is_inside_tree():
        return
    var window := get_window()
    if window != null and window != get_tree().root:
        window.hide()


func _on_remove_pressed(path: String) -> void:
    SaSettings.remove_recent_file(path)


## The document flow the open goes through: the one a test handed in, or the
## main scene's.
func _flow() -> SaDocumentFiles:
    if _files != null:
        return _files
    return SaDocumentFiles.in_tree(get_tree()) if is_inside_tree() else null
