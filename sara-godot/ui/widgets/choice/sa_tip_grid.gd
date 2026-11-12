## The Tip Image row as a grid of the tips' pictures under a filter of the
## folders they sit in, the control every surface builds for
## `SaOptionSpec.Kind.TIP_IMAGE`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A grid of pictures rather than a list of names, as the brush presets are
## chosen, and one control in `ui` that the stamp brush and the noise brush both
## build, because the pattern chooser and the presets grid that already draw
## pictures are the stamp module's and the presets', and the noise module sees
## the door only.
##
## **Each cell is the tip's mask**, its coverage as the alpha of the ink, read by
## the door's own readers, so a grey picture and a colour one and a GIMP brush
## and the first cell of a pipe each show the shape the brush paints rather than
## the file's colours. A picture is shrunk to the cell before the mask rule
## reads it: the rule is a loop over every texel in GDScript, and the shipped
## tips are two hundred texels across.
##
## **The filter's rows are folders**, [method SaTipChoices.folders], All first,
## so a folder is a tip's tag and nothing stores tags. The closed button says
## which folder it shows, "Folder: Sara", and the open list names the folders
## alone, the reading the presets' tag row has.
##
## **The cells stand in a frame of their own**, as tall as their rows up to
## [constant FRAME_ROWS] of them and scrolling past that, so the tips a painter
## adds over time stop pushing Load Tip and the rows under it down the docker,
## out of reach but by the docker's scroll bar. The frame's height is
## worked out from the rows rather than read from the flow, because a scroll asks
## for no height of its own and the flow only knows how it wraps once it has been
## laid out, and a wheel over the frame scrolls the tips before the docker.
##
## **A press writes the path** through the surface's write, the way a choice
## writes its id, and a picture that cannot be read is refused at the press with
## its reason. The grid follows the shown tool's `tip_loaded`, so a picture the
## Load Tip action reads joins the grid under its folder and the cell of what the
## row holds stays pressed.
class_name SaTipGrid
extends VBoxContainer

## A cell's side in logical pixels: six across the Tool Options docker at its
## default width, and a picture still large enough to read the shape in.
const CELL: int = 40

## How much of the cell the picture leaves for the frame the chosen cell wears.
const FRAME: int = 3

## How many rows of cells the frame shows before it scrolls, the greatest height
## it takes: four rows are twenty-four tips across the docker at its default
## width, which is the shipped folder's own, and leave Load Tip on screen.
const FRAME_ROWS: int = 4

## How many cells a row holds before the grid has been given a width, the six
## across the Tool Options docker at its default width.
const ACROSS: int = 6

## What the capture door's `stock` names the copies it writes with, and `tidy`
## removes by.
const STOCK_PREFIX: String = "stock-"

## What a cell whose picture cannot be read shows in place of one.
const UNREADABLE_MARK: String = "?"

## The filter of folders above the grid.
var filter: SaChoiceButton = null

## The scroll the cells stand in, as tall as their rows up to [constant
## FRAME_ROWS] and with a scroll bar when the shown folder holds more.
var frame: ScrollContainer = null

## The cells, one a tip, flowing to the width the row gives them.
var cells: HFlowContainer = null

## The folder the filter shows, empty for All. Written here only.
var folder: String = ""

## The path of the picture the row holds, empty for none. Written here only.
var chosen: String = ""

## How many times the cells were built, which a suite reads to say a sync that
## changed nothing built nothing.
var builds: int = 0

## The surface's door for a press, called with the path.
var _write: Callable = Callable()

## What the row holds on the tool it shows, handed over by [method follow].
var _read: Callable = Callable()

## The tips the grid lists while the row holds a path, handed the path and
## answering as [method SaTipChoices.listing] does.
var _listing: Callable = Callable()

## Whether the cell the row holds is still to be scrolled into the frame. Kept
## until the frame's scroll bar has had room for the scroll, which it has only
## once the frame has been laid out around the cells.
var _reveal_pending: bool = false

## The tool whose `tip_loaded` the grid hears, or null.
var _tool: Object = null

## The tips the cells were built from, as [method SaTipChoices.listing] gave
## them.
var _listed: Array[Dictionary] = []

## Path to its cell.
var _cells: Dictionary[String, Button] = {}

## Path to why its picture cannot be read, for the cells that cannot.
var _errors: Dictionary[String, String] = {}

## Path to its picture drawn at a side, as `{"stamp", "side", "size", "bytes",
## "error"}`. Bytes rather than a texture, so a run's end finds no object or
## card resource here.
static var _pictures: Dictionary[String, Dictionary] = {}


## *write* is the surface's door for a press. *listing* is where the tips come
## from, which a suite hands a list of its own and which is
## [method SaTipChoices.listing] otherwise.
func _init(write: Callable = Callable(), listing: Callable = Callable()) -> void:
    name = "TipGrid"
    _write = write
    _listing = listing if listing.is_valid() else SaTipChoices.listing
    # Asked of the theme pass rather than set, which would replace it.
    set_meta(SaUI.SEPARATION_SCALE_META, 0.4)
    var choice := SaMake.choice(self, "FolderFilter")
    choice.text_overrun_behavior = SaTheme.TEXT_CUT
    choice.focus_mode = Control.FOCUS_NONE
    choice.tooltip_text = tr("The folder whose tips the grid shows. A tip's folder is its tag.")
    choice.choice_picked.connect(_on_folder_picked)
    filter = choice
    frame = SaMake.scroll(self, "Frame")
    frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # The bar tells the frame it has room for the scroll a cell is waiting on.
    frame.get_v_scroll_bar().changed.connect(_reveal)
    cells = HFlowContainer.new()
    cells.name = "Cells"
    cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cells.add_theme_constant_override("h_separation", SaUI.px(4))
    cells.add_theme_constant_override("v_separation", SaUI.px(4))
    frame.add_child(cells)


func _notification(what: int) -> void:
    # A file dropped into a tip folder while Sara runs is a cell the next time
    # the row is shown, the way the pattern list reads its folders at each open.
    if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
        relist()
    elif what == NOTIFICATION_RESIZED and frame != null:
        _fit_frame()


## Points the grid at *tool*, whose row value *read* answers, and shows what
## it holds. The surface calls it on every sync, so a second call for the same
## tool hears nothing new.
func follow(tool: Object, read: Callable) -> void:
    _read = read
    if tool != _tool:
        if _tool != null and is_instance_valid(_tool) and _tool.is_connected(&"tip_loaded", _on_tip_loaded):
            _tool.disconnect(&"tip_loaded", _on_tip_loaded)
        _tool = tool
        if tool != null and tool.has_signal(&"tip_loaded"):
            tool.connect(&"tip_loaded", _on_tip_loaded)
    relist()


## Shows *path* as the row's value, its cell pressed. A path the cells do not
## hold has them listed again, which is how a preset's picture from outside the
## folders comes in.
func show_tip(path: String) -> void:
    _reveal_pending = _reveal_pending or path != chosen
    chosen = path
    if not path.is_empty() and not _cells.has(path):
        relist()
        return
    for listed_path: String in _cells:
        _cells[listed_path].set_pressed_no_signal(listed_path == chosen)
    _reveal()


## Lists the tips again and builds the cells when the list moved, then shows
## what the row holds.
func relist() -> void:
    var held := String(_read.call()) if _read.is_valid() else chosen
    var listed: Array[Dictionary] = []
    listed.assign(_listing.call(held))
    if listed != _listed:
        _build(listed)
    _reveal_pending = _reveal_pending or held != chosen
    chosen = held
    for listed_path: String in _cells:
        _cells[listed_path].set_pressed_no_signal(listed_path == chosen)
    _reveal()


## Shows only the tips of *shown*, a folder, or every tip for an empty one, the
## way a row of the filter does. A folder no tip sits in shows them all.
func choose_folder(shown: String) -> void:
    folder = shown if shown.is_empty() or _folder_rows().any(func(row: Dictionary) -> bool: return row["id"] == shown) else ""
    filter.select_value(folder)
    _name_filter()
    for listed: Dictionary in _listed:
        var cell := _cells.get(listed["path"]) as Button
        if cell != null:
            cell.visible = folder.is_empty() or listed["folder"] == folder
    _reveal_pending = true
    _fit_frame()


## Presses *path*'s cell the way a hand does. False when no cell shown holds it.
func pick(path: String) -> bool:
    var cell := _cells.get(path) as Button
    if cell == null or not cell.visible:
        return false
    cell.pressed.emit()
    return true


## The paths of the cells shown, in the order the grid draws them.
func shown_paths() -> Array[String]:
    var out: Array[String] = []
    for listed: Dictionary in _listed:
        var cell := _cells.get(listed["path"]) as Button
        if cell != null and cell.visible:
            out.append(listed["path"])
    return out


## What a dump and a suite read: the tips shown, how many carry a picture, the
## folder shown and the filter's rows, the tip the row holds and the cells that
## cannot be read, with why, and the frame's height and how far it is scrolled.
func tip_grid_report() -> Dictionary:
    var shown := shown_paths()
    var pictured := 0
    for path: String in shown:
        if _cells[path].icon != null:
            pictured += 1
    var pressed: Array[String] = []
    for path: String in _cells:
        if _cells[path].button_pressed:
            pressed.append(path)
    return {
        "tips": shown,
        "pictures": pictured,
        "folder": folder,
        "filter": filter.text,
        "folders": filter.choice_labels(),
        "chosen": chosen,
        "pressed": pressed,
        "unreadable": _errors.duplicate(),
        "frame_height": int(frame.custom_minimum_size.y),
        "scrolled": frame.scroll_vertical,
    }


## The brush editor's dump door for a row it did not build.
func capture_option_report() -> Dictionary:
    return tip_grid_report()


## The capture door: `{"folder": "Sara"}` chooses a folder by its name or its
## path, `{"pick": "res://tips/tree.png"}` presses a cell, `{"load_tip": path}`
## loads a picture through the shown tool's `load_tip`, the Load Tip action's
## door past the file dialog nobody can drive, and `{}` answers the report.
## `{"stock": 120}` writes that many copies of the shipped tips into the
## painter's folder, so the grid can be shot over a folder that has grown, and
## `{"tidy": true}` removes them again. The Tool Options docker's `option` step
## reaches it by the row's key, and the brush editor's `widget` step as it
## reaches any row's control.
func capture_option_edit(spec: Dictionary) -> String:
    _scroll_into_view()
    var said := PackedStringArray()
    if spec.has("stock"):
        said.append("stock %d" % _stock(int(spec["stock"])))
    if bool(spec.get("tidy", false)):
        said.append("tidy %d" % _tidy())
    if spec.has("folder"):
        var asked := String(spec["folder"])
        var found := ""
        for row: Dictionary in _folder_rows():
            if row["id"] == asked or row["label"] == asked:
                found = row["id"]
        choose_folder(found)
        said.append("folder %s" % (found if not found.is_empty() else "All"))
    if spec.has("load_tip"):
        var path := String(spec["load_tip"])
        if _tool == null or not _tool.has_method("load_tip"):
            return "SaCapture: the tip grid follows no tool that loads a tip"
        said.append("load_tip %s %s" % [path, "loaded" if bool(_tool.call("load_tip", path)) else "refused"])
    if spec.has("pick"):
        var path := String(spec["pick"])
        said.append("pick %s %s" % [path, "pressed" if pick(path) else "is no cell shown"])
    return "SaCapture: tip grid %s %s" % [", ".join(said), JSON.stringify(tip_grid_report())]


## Scrolls the row this grid sits in into view with its label, and the row under
## it, Load Tip, so the shot after a step shows the grid it drove and what a
## painter reaches for beside it, which with the advanced rows on sits a page
## down the docker.
func _scroll_into_view() -> void:
    var row := get_parent() as Control if get_parent() is Control else self
    var scroll := row.get_parent()
    while scroll != null and not scroll is ScrollContainer:
        scroll = scroll.get_parent()
    if scroll == null:
        return
    (scroll as ScrollContainer).ensure_control_visible(row)
    var siblings := row.get_parent()
    var next := row.get_index() + 1
    if next < siblings.get_child_count() and siblings.get_child(next) is Control:
        var below := siblings.get_child(next) as Control
        if below.visible:
            (scroll as ScrollContainer).ensure_control_visible(below)


## Gives the painter's folder *count* copies of the shipped PNG tips, each as
## `stock-<tip>-<number>.png`, lists again and answers how many were written.
func _stock(count: int) -> int:
    var shipped: Array[String] = []
    for path: String in SaBrushTipMask.available():
        if path.get_base_dir() == SaBrushTipMask.SHIPPED_DIR and path.get_extension() == "png":
            shipped.append(path)
    if shipped.is_empty():
        return 0
    var written := 0
    for index in count:
        var source := shipped[index % shipped.size()]
        var file_name := "%s%s-%03d.png" % [STOCK_PREFIX, source.get_file().get_basename(), index]
        if not SaBrushTipMask.save(file_name, FileAccess.get_file_as_bytes(source)).is_empty():
            written += 1
    relist()
    return written


## Removes what [method _stock] wrote, lists again and answers how many files
## went.
func _tidy() -> int:
    var saved := SaBrushTipMask.saved_dir()
    var removed := 0
    for file_name: String in DirAccess.get_files_at(saved):
        if file_name.begins_with(STOCK_PREFIX) and DirAccess.remove_absolute(saved.path_join(file_name)) == OK:
            removed += 1
    relist()
    return removed


## How many cells a row of the frame holds at the width the grid has now.
func _across() -> int:
    var side := SaUI.px(CELL)
    var gap := cells.get_theme_constant("h_separation")
    if size.x <= 0.0:
        return ACROSS
    return maxi(1, floori((size.x + gap) / float(side + gap)))


## How many rows *count* cells fill, as the flow lays them.
func _rows(count: int) -> int:
    return ceili(float(count) / float(_across()))


## Gives the frame the height of the rows shown, to [constant FRAME_ROWS] of
## them. More rows than that scroll, and the bar shows once the frame is laid
## out around them.
func _fit_frame() -> void:
    var rows := mini(_rows(shown_paths().size()), FRAME_ROWS)
    var side := SaUI.px(CELL)
    var gap := cells.get_theme_constant("v_separation")
    var height := rows * side + maxi(0, rows - 1) * gap
    if int(frame.custom_minimum_size.y) != height:
        frame.custom_minimum_size = Vector2(0.0, height)
    _reveal()


## Scrolls the frame to the row of the cell the row holds, by the least that
## shows it, or to the top when that cell is not shown. It runs when something
## asked for the scroll and again each time the scroll bar's range moves,
## because the bar holds the range of the cells it was laid out around and a
## value past it is cut to it, which is what a frame not laid out yet does to
## every value. A wheel or a drag later is the painter's and is left alone.
func _reveal() -> void:
    if not _reveal_pending:
        return
    var index := shown_paths().find(chosen)
    var wanted := 0
    if index >= 0:
        var side := SaUI.px(CELL)
        var top := floori(float(index) / float(_across())) * (side + cells.get_theme_constant("v_separation"))
        var page := int(frame.custom_minimum_size.y)
        wanted = clampi(frame.scroll_vertical, top + side - page, top)
    frame.scroll_vertical = wanted
    _reveal_pending = frame.scroll_vertical != wanted


## Builds a cell for each tip of *listed* and the filter's rows over them,
## keeping the folder shown when a tip still sits in it.
func _build(listed: Array[Dictionary]) -> void:
    for child in cells.get_children():
        cells.remove_child(child)
        child.queue_free()
    _cells.clear()
    _errors.clear()
    _listed = listed
    builds += 1
    var side := SaUI.px(CELL)
    for entry: Dictionary in listed:
        _cells[entry["path"]] = _cell(entry, side)
    var rows := _folder_rows()
    filter.set_choices(rows)
    for row: Dictionary in rows:
        var line := filter.popup.label_button(SaChoiceButton.row_id_of(row["id"]))
        if line != null and not String(row["id"]).is_empty():
            line.tooltip_text = String(row["id"])
    choose_folder(folder)


## The filter's rows over the tips listed now.
func _folder_rows() -> Array[Dictionary]:
    return SaTipChoices.folders(_listed)


## The closed filter says what it filters by, and the open list the folders
## alone.
func _name_filter() -> void:
    var rows := _folder_rows()
    var label := TranslationServer.translate("All")
    for row: Dictionary in rows:
        if row["id"] == folder:
            label = row["label"]
    filter.text = tr("Folder: %s") % label


func _cell(entry: Dictionary, side: int) -> Button:
    var path := String(entry["path"])
    var cell := Button.new()
    cell.name = "Cell_" + path.get_file().validate_node_name()
    cell.toggle_mode = true
    cell.focus_mode = Control.FOCUS_NONE
    cell.custom_minimum_size = Vector2(side, side)
    cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cell.expand_icon = true
    # The theme caps a button's icon at the toolbar's, a third of a cell.
    cell.add_theme_constant_override("icon_max_width", side - 2 * SaUI.px(FRAME))
    # The chosen cell wears a frame in the accent colour, the pattern chooser's
    # mark, since the theme's pressed shade is lost on a face that is a picture.
    var pressed := StyleBoxFlat.new()
    SaTheme.bind(pressed, {"bg_color": "bg_primary", "border_color": "accent_primary"})
    pressed.set_border_width_all(SaUI.px(2))
    cell.add_theme_stylebox_override("pressed", pressed)
    var folder_label := SaTipChoices.folder_name(String(entry["folder"]))
    var picture := _picture(path, side - 2 * SaUI.px(FRAME))
    if String(picture["error"]).is_empty():
        var drawn: Vector2i = picture["size"]
        var image := Image.create_from_data(drawn.x, drawn.y, false, Image.FORMAT_LA8, picture["bytes"] as PackedByteArray)
        cell.icon = ImageTexture.create_from_image(image)
        cell.tooltip_text = "%s\n%s" % [entry["label"], folder_label]
    else:
        _errors[path] = String(picture["error"])
        cell.text = UNREADABLE_MARK
        cell.modulate = Color(1.0, 1.0, 1.0, SaOptionSpec.DIMMED_ALPHA)
        cell.tooltip_text = "%s\n%s\n%s" % [tr("%s (unreadable)") % entry["label"], folder_label, picture["error"]]
    cell.pressed.connect(_on_cell_pressed.bind(path))
    cells.add_child(cell)
    return cell


## A cell was pressed: the surface writes its path, and a picture that cannot
## be read is refused with its reason where refusals go, the cell of what the
## row holds pressed again.
func _on_cell_pressed(path: String) -> void:
    if _errors.has(path):
        EventBus.paint_refused.emit(_errors[path])
        show_tip(chosen)
        return
    show_tip(path)
    if _write.is_valid():
        _write.call(path)


func _on_folder_picked(value: Variant) -> void:
    choose_folder(String(value))


## A tip landed on the tool, so the grid lists again around it. A grid drawn
## again queues its cells for freeing, and one that is going still hears the
## tool until the frame ends, so it stays quiet.
func _on_tip_loaded(_path: String) -> void:
    if is_queued_for_deletion():
        return
    relist()


## The mask of the tip at *path* drawn at most *side* texels across, kept
## while the file's modified time and the side stay as they were.
static func _picture(path: String, side: int) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"error": TranslationServer.translate("%s is not on disk.") % path.get_file()}
    var stamp := FileAccess.get_modified_time(path)
    var kept: Dictionary = _pictures.get(path, {})
    if not kept.is_empty() and kept["stamp"] == stamp and kept["side"] == side:
        return kept
    var drawn := _drawn(_mask_of(path, side), side)
    drawn["stamp"] = stamp
    drawn["side"] = side
    _pictures[path] = drawn
    return drawn


## The tip at *path* read by the door's own readers: a pipe's first cell, and a
## PNG shrunk to *side* before the mask rule reads it.
static func _mask_of(path: String, side: int) -> SaTipImage.Tip:
    if SaBrushTipMask.is_pipe_path(path):
        var bytes := FileAccess.get_file_as_bytes(path)
        var pipe := SaGihPipe.read_head(bytes, path.get_file())
        if not pipe.error.is_empty():
            var refused := SaTipImage.Tip.new()
            refused.error = pipe.error
            return refused
        return SaGihPipe.read_cell(bytes, pipe, 0, path.get_file())
    if path.to_lower().ends_with(".png"):
        var image := Image.new()
        var bytes := FileAccess.get_file_as_bytes(path)
        if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
            return SaTipImage.load_bytes(bytes, path.get_file())
        var fitted := _fitted(Vector2i(image.get_width(), image.get_height()), side)
        if fitted.x < image.get_width():
            image.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
        return SaTipImage.load_bytes(image.save_png_to_buffer(), path.get_file())
    return SaTipImage.load_from(path)


## *tip*'s coverage at most *side* across as white whose alpha is the coverage,
## `{"size", "bytes", "error"}`, the bytes an `FORMAT_LA8` picture's.
static func _drawn(tip: SaTipImage.Tip, side: int) -> Dictionary:
    if not tip.ok():
        var reason := tip.error if not tip.error.is_empty() else String(TranslationServer.translate("The tip holds no picture."))
        return {"error": reason}
    var mask := Image.create_from_data(tip.size.x, tip.size.y, false, Image.FORMAT_RF, tip.mask.to_byte_array())
    var fitted := _fitted(tip.size, side)
    mask.resize(fitted.x, fitted.y, Image.INTERPOLATE_BILINEAR)
    mask.convert(Image.FORMAT_L8)
    var coverage := mask.get_data()
    var bytes := PackedByteArray()
    bytes.resize(coverage.size() * 2)
    for index in coverage.size():
        bytes[2 * index] = 255
        bytes[2 * index + 1] = coverage[index]
    return {"size": fitted, "bytes": bytes, "error": ""}


## *extent* scaled to fit a square of *side*, its proportions kept.
static func _fitted(extent: Vector2i, side: int) -> Vector2i:
    var ratio := float(side) / float(maxi(1, maxi(extent.x, extent.y)))
    return Vector2i(maxi(1, roundi(extent.x * ratio)), maxi(1, roundi(extent.y * ratio)))
