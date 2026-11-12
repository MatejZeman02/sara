## The Reference docker: PureRef's board beside the painting, grown from one
## picture with its own zoom and pan.
##
## Several pictures on a board, each dragged where the painter wants it, a board
## per subject under a tab of its own, a normalise that brings every picture to
## one size in a row, and the sampling click the one picture had, asked of the
## picture under the cursor. The model is `SaReferenceBoard`, beside this file,
## the drawing and the input are `ReferencePictureView`, and what is left here is
## the boards, the tabs, where they are kept and what a sampled texel becomes.
##
## **The view is its own and touches nothing.** Zoom and pan are the board's
## two numbers, not `SaView`, so a reference held at 4x while the canvas sits
## at 100 per cent is the whole point rather than a state to keep in step.
## Nothing in here calls `request_composite`, and the document is reached for
## two things only: the board it carries when the painter keeps boards with the
## document, and what a sampled colour would be stored as, for the dump.
##
## **Where a board is kept is a Preferences choice**: with the document, which
## is the default and goes into the `.sad` as paths and rectangles under its
## own key, or in the settings file. Both are the same `to_header` and the same
## `from_header`, written to a different place, and a document with no board
## opens with an empty docker.
##
## **The canvas is an element on the board**, so it can be flipped, greyed and
## cropped as any picture can. The Canvas button puts the canvas on the board as a
## `Picture` whose pixels are the easel's, drawn by `ReferenceCanvasElement`.
## The four per-picture toggles, flip, greyscale, crop and always on top, are
## flags on the model reached from the hover bar `ReferencePictureView` carries,
## for the canvas as for every picture. `ReferencePictureView` carries the
## gesture too, so this file stays the boards, the tabs and where they are kept.
##
## **A sample is converted out of the picture's own space, not the document's.** A
## picture's texel already names a colour, so it is carried into the document's gamut
## and handed to the colour store as the picker's triple there: a PNG's red lands where
## sRGB's red sits in a P3 document, and an EXR's linear texel is encoded first, or a
## mid grey lands at 0.214 where it belongs at 0.5.
@tool
extends DockerWindow

class_name ReferenceDocker

## Logical size of the button row's buttons, so the row matches every other
## docker's.
const BUTTON_H: int = 22

## The two per-docker options on the Reference page of Preferences, declared on
## the row layer rather than drawn by hand.
const OPTION_STORE := "store"
const OPTION_NORMALISE := "normalise"
const STORES: Array[String] = ["document", "settings"]

## Where the settings file keeps the boards when the painter chose that.
const SETTINGS_SECTION := "reference"
const SETTINGS_KEY := "boards"

## The board's Control, and a public part of this docker: the buttons below,
## the capture and the tests ask it for what is under the pointer and for a
## fit, a zoom or a pan, rather than this file forwarding each of them.
var board_view: ReferencePictureView

var _tabs: ReferenceTabs

## Solo and Canvas, pressed while the board shows one picture alone or holds the canvas.
var _solo_button: Button
var _canvas_button: Button

## Fit, Normalize and Solo, which have nothing to act on until the board showing
## holds a picture and are dimmed until then, so an empty board offers only Open
## and Canvas.
var _needs_picture: Array[Button] = []

## Each button's own hover, button to words, which a dimmed one says with why.
var _hovers: Dictionary = {}

## One board per tab, and which tab is showing. Never empty once anything has
## been asked of the docker: `board()` makes the first on demand.
var _boards: Array[SaReferenceBoard] = []
var _current: int = 0

## The last colour taken off a picture, as three numbers a capture can read:
## the texel as stored, the display colour that went on the wheel, and where
## the click landed. Empty until something is sampled.
var _sampled_texel: Color = Color.TRANSPARENT
var _sampled_display: Color = Color.TRANSPARENT
var _sampled_at: Vector2i = Vector2i(-1, -1)


func _init() -> void:
    _init_docker(SaDockerIds.REFERENCE, "Reference", Vector2i(280, 300), Vector2i(140, 120))
    position = Vector2i(2, 960)
    _register_options()
    # Delete and Backspace are the board's while the docker has the focus or
    # the pointer, which take a picture off it, and not Clear Layer's.
    set_meta(ShortcutRouter.KEEPS_ERASE_KEYS_META, true)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Reference")
    vbox.add_child(drag_handle)

    # The board stands straight under the tabs' row with no gap, the way a tab
    # sits on its page, so the docker's height is the board's but for the drag
    # bar and that one row.
    var body := SaMake.column(vbox, "Body", 0)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var tabs := ReferenceTabs.new()
    tabs.board_selected.connect(select_board)
    tabs.board_closed.connect(close_board)
    tabs.board_renamed.connect(rename_board)
    tabs.board_added.connect(_on_add_board_pressed)
    tabs.pictures_wanted.connect(open_dialog)
    body.add_child(tabs)
    _tabs = tabs

    # The buttons share the tabs' row as icons, each hover the word the button
    # said over what it does. Fit calls the view, which is made below the row,
    # so a lambda: the button is built before the part it calls.
    var row := tabs.buttons
    _make_button(row, "OpenButton", "folder_open", "Open...", "Add reference images to this board", open_dialog)
    var fit := func() -> void: board_view.fit()
    _needs_picture.append(_make_button(row, "FitButton", "fit_view", "Fit", "Show the whole board", fit))
    _needs_picture.append(
        _make_button(row, "NormaliseButton", "normalize", "Normalize", "Every picture at one size, in a grid", normalise)
    )
    _solo_button = _make_button(
        row, "SoloButton", "solo", "Solo", "Show the selected picture alone, or the whole board again", solo
    )
    _solo_button.toggle_mode = true
    SaTheme.make_toggle(_solo_button)
    _needs_picture.append(_solo_button)
    var canvas_hint := "Put the canvas on this board, to flip, grey and crop like a picture, or take it off again"
    _canvas_button = _make_button(row, "CanvasButton", "easel", "Canvas", canvas_hint, toggle_canvas)
    _canvas_button.toggle_mode = true
    SaTheme.make_toggle(_canvas_button)

    board_view = ReferencePictureView.new()
    board_view.name = "Picture"
    board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    board_view.mouse_filter = Control.MOUSE_FILTER_STOP
    # A board drawn at 8x is larger than the docker, and Godot clips nothing by
    # default, so without this it runs over the drag bar and out of the window.
    board_view.clip_contents = true
    board_view.resized.connect(_on_picture_resized)
    board_view.sampled.connect(sample_at)
    board_view.changed.connect(_changed)
    board_view.toggled.connect(_on_picture_toggled)
    board_view.paste_wanted.connect(paste_at)
    # `board()` auto-creates and calls `_sync_tabs()`, which sets `board` on
    # `board_view` before this emit returns, so the draw that asked for one has
    # it by the time the emit call is done.
    board_view.canvas_wanted.connect(board)
    body.add_child(board_view)
    _sync_tabs()
    _sync_status()


## The two rows of the Reference page, once. Idempotent, because the option
## store refuses a key it already holds, and a docker is built once per window.
func _register_options() -> void:
    (
        SaSettings
        . register_docker_option(
            SaDockerIds.REFERENCE,
            OPTION_STORE,
            {
                "title": "Keep boards",
                "hint": "With the document, saved into the file as paths, or in the settings for every document.",
                "kind": SaSettingsLayout.OPTION_CHOICE,
                "values": STORES,
                "labels": ["With the document", "In the settings"],
                "default": STORES[0],
            }
        )
    )
    (
        SaSettings
        . register_docker_option(
            SaDockerIds.REFERENCE,
            OPTION_NORMALISE,
            {
                "title": "Normalize to",
                "hint": "What Normalize makes the same for every picture on the board.",
                "kind": SaSettingsLayout.OPTION_CHOICE,
                "values": SaReferenceBoard.NORMALISE_MODES,
                "labels": ["The same height", "The same width", "The same area"],
                "default": SaReferenceBoard.NORMALISE_MODES[0],
            }
        )
    )


## An icon button on the tabs' row. Its hover is *word*, the button's name,
## over *sentence*, both given in English and translated here, and
## `_sync_status` adds why it is dimmed.
func _make_button(
    row: HBoxContainer, node_name: String, icon: String, word: String, sentence: String, action: Callable
) -> Button:
    var button := SaMake.button(row, node_name, "", "")
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(SaUI.px(BUTTON_H), SaUI.px(BUTTON_H))
    SaUI.set_button_icon(button, icon, tr(word))
    # The hover is written again at each change of language, since the docker
    # is built before a language module's catalogue arrives.
    var write := func() -> void:
        _hovers[button] = "%s\n%s" % [tr(word), tr(sentence)]
        button.tooltip_text = _hovers[button]
        _sync_status()
    SaOnLanguage.watch(button, write)
    button.pressed.connect(action)
    return button


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    _setup_docker_ready()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()
    if not EventBus.document_loaded.is_connected(_on_document_loaded):
        EventBus.document_loaded.connect(_on_document_loaded)
    if not EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.connect(_on_front_changed)
    # A docker that is its own OS window hears a drop itself. An embedded one
    # hears it through the File menu's handler on the root window, which hands
    # the drop over through `take_drop`.
    if not files_dropped.is_connected(open_paths):
        files_dropped.connect(open_paths)
    if _store() == "settings":
        restore(SaSettings.config.get_value(SETTINGS_SECTION, SETTINGS_KEY, []))


## The drag bar and the resize grip follow the Preferences page every registered
## docker gets, which is what makes this one no different from the others
## rather than a window with its own rules.
func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.REFERENCE)


# --- Boards and tabs ---------------------------------------------------------


## The board showing, made if there is none yet, with its tab and its hover.
func board() -> SaReferenceBoard:
    if _boards.is_empty():
        _boards.append(SaReferenceBoard.new(tr("Board")))
        _current = 0
        _sync_tabs()
        _sync_status()
    return _boards[clampi(_current, 0, _boards.size() - 1)]


## A new board under a new tab, showing, and its index.
func add_board(board_name: String) -> int:
    _boards.append(SaReferenceBoard.new(board_name if not board_name.is_empty() else tr("Board")))
    _current = _boards.size() - 1
    _sync_tabs()
    _changed(true)
    return _current


func select_board(index: int) -> void:
    if index < 0 or index >= _boards.size() or index == _current:
        return
    _current = index
    board_view.deselect()
    _sync_tabs()
    board_view.queue_redraw()
    _sync_status()


func rename_board(index: int, board_name: String) -> void:
    if index < 0 or index >= _boards.size() or board_name.is_empty():
        return
    _boards[index].name = board_name
    _sync_tabs()
    _changed(true)


## The rename dialog a double click on the tab at *index* opens, for a scenario.
func open_rename(index: int) -> AcceptDialog:
    return _tabs.open_rename(index)


## Closes a tab. The last board is not closed but emptied, so there is always
## one to drop a picture on.
func close_board(index: int) -> void:
    if index < 0 or index >= _boards.size():
        return
    if _boards.size() == 1:
        _boards[0] = SaReferenceBoard.new(_boards[0].name)
    else:
        _boards.remove_at(index)
        _current = clampi(_current if _current < index else _current - 1, 0, _boards.size() - 1)
    board_view.deselect()
    _sync_tabs()
    _changed(true)


## The picture view's board follows the tab showing, so it never asks the docker
## for it.
func _sync_tabs() -> void:
    if _tabs != null:
        var names := PackedStringArray()
        for entry in _boards:
            names.append(entry.name)
        _tabs.sync(names, _current)
    if board_view != null:
        board_view.board = _boards[clampi(_current, 0, _boards.size() - 1)] if not _boards.is_empty() else null


func _on_add_board_pressed() -> void:
    var number := _boards.size() + 1
    add_board(tr_n("Board %d", "Board %d", number) % number)


# --- Loading ------------------------------------------------------------------


## Puts a file picker up, the way the File menu does, and it takes several
## files at once. The picker is the platform's own where it has one, and the
## summon holds the docker out while it is up.
func open_dialog() -> void:
    var filters := PackedStringArray([SaImageImport.dialog_filter()])
    SaFilePicker.open(self, SaFilePicker.Mode.OPEN_FILES, filters, open_paths)


## Adds every image in *paths* to the board showing, and fits the board so the
## new arrivals are on screen. Answers how many were placed.
func open_paths(paths: PackedStringArray) -> int:
    var placed := 0
    for path in paths:
        if not SaImageImport.is_image_path(path) and not path.begins_with("res://"):
            continue
        var picture := board().add_path(path)
        if picture == null:
            continue
        board_view.select_picture(picture)
        placed += 1
    if placed > 0:
        board().fit_all(board_view.size)
        _changed(true)
    return placed


## One path, and whether a picture came of it. The door the tests use.
func load_image(path: String) -> bool:
    return open_paths(PackedStringArray([path])) == 1


## Puts the picture on the desktop clipboard on the board showing, its centre
## at *at* in the view's own coordinates, selected, and answers it. *held* is
## the picture the right click's menu read when it opened, so the row pastes
## what it offered, and null reads the clipboard now, which the key does.
##
## The picture is kept by a file, `ReferencePaste.keep`, and added through
## `add_path`, so it is saved with the boards and comes back like a picture
## opened from a file. Nothing is put on the canvas or into a layer. An empty
## clipboard says so in the corner and adds nothing.
##
## A picture larger than the view at the board's zoom is shown whole by
## `fit_one`, which never zooms above 1.0. One that fits leaves the zoom alone
## and stays where it was aimed.
func paste_at(at: Vector2, held: SaDesktopPicture = null) -> SaReferenceBoard.Picture:
    var picture := held if held != null else ReferencePaste.read()
    if picture == null:
        SaMessage.notice(tr(ReferencePaste.NOTHING))
        return null
    var path := ReferencePaste.keep(picture)
    var placed := board().add_path(path) if not path.is_empty() else null
    if placed == null:
        return null
    board().move(placed, board().to_board(at) - placed.rect.get_center())
    var room := board_view.size
    var drawn := placed.rect.size * board().zoom
    if drawn.x > room.x or drawn.y > room.y:
        board().fit_one(placed, room)
    board_view.select_picture(placed)
    _changed(true)
    return placed


## Whether a Paste belongs to this docker rather than to the canvas: it is on
## screen and holds the keyboard's focus, which `DockerFocus` moves to the
## docker the pointer is over, or the pointer is inside it.
func wants_paste() -> bool:
    if not visible or not is_inside_tree():
        return false
    if has_focus():
        return true
    if is_embedded():
        return wants_drop(get_tree().root.get_mouse_position())
    return Rect2(Vector2.ZERO, Vector2(size)).has_point(get_mouse_position())


## The Paste command's first ask, whatever chord the profile in force gives
## it: a Reference docker that wants the paste takes it at the centre of its
## view, and answers true, whether or not the clipboard held a picture, so the
## canvas never gets a paste aimed at the board. False sends it to the canvas.
static func take_paste(tree: SceneTree) -> bool:
    var docker := tree.root.find_child(SaDockerIds.REFERENCE, true, false) as ReferenceDocker if tree != null else null
    if docker == null or not docker.wants_paste():
        return false
    docker.paste_at(docker.board_view.size / 2.0)
    return true


## A drop on the root window at *at* while the pointer is over an embedded
## Reference docker is the docker's, not a layer import. Called by the document
## flow's drop handler first, and answers whether it took the files.
##
## **The point is handed in rather than read here**. The caller is the one that
## knows when the reading is worth trusting, `SaDocumentFiles.drop_point` says what
## that reading costs on Wayland, and a test can drive this at a point inside the
## docker and a point outside it without an OS window to drop on.
##
## A docker that is its own OS window is not this: the compositor hands the
## drop to that surface, `_ready` connects `files_dropped` straight to
## `open_paths`, and the root window never hears it. `is_embedded()` is the
## test for exactly that.
static func take_drop(tree: SceneTree, files: PackedStringArray, at: Vector2) -> bool:
    var docker := tree.root.find_child(SaDockerIds.REFERENCE, true, false) as ReferenceDocker
    if docker == null or not docker.wants_drop(at):
        return false
    return docker.open_paths(files) > 0


## Whether a drop at *at*, in the root viewport's units, belongs to this docker.
##
## Split off `take_drop` so the geometry is a question a test can ask of a
## docker it built, rather than one only a real drop can reach. A subwindow's
## own position and size are already in those units, so there is nothing to
## convert.
func wants_drop(at: Vector2) -> bool:
    return visible and is_embedded() and Rect2(Vector2(position), Vector2(size)).has_point(at)


## Forgets every board, so a docker left open on files that have moved is not
## a docker showing something that is not there any more.
func clear() -> void:
    _boards.clear()
    _current = 0
    board_view.deselect()
    _sampled_at = Vector2i(-1, -1)
    _sync_tabs()
    _changed(true)


# --- Where the boards are kept --------------------------------------------------


func _store() -> String:
    return String(SaSettings.get_docker_option(SaDockerIds.REFERENCE, OPTION_STORE))


## Every board as the header the file or the settings hold, the one showing
## marked, so a painting reopens on the tab it was saved on.
func to_header() -> Array:
    var out: Array = []
    for i in range(_boards.size()):
        var header := _boards[i].to_header()
        if i == _current:
            header["showing"] = true
        out.append(header)
    return out


## Every board back from *raw*, which is what `to_header` wrote. An empty or
## foreign value is an empty docker, which is what a document with no board
## means.
func restore(raw: Variant) -> void:
    _boards.clear()
    board_view.deselect()
    _current = 0
    if raw is Array:
        for entry: Variant in raw:
            if entry is Dictionary and bool(entry.get("showing", false)):
                _current = _boards.size()
            _boards.append(SaReferenceBoard.from_header(entry))
    _sync_tabs()
    board_view.queue_redraw()
    _sync_status()


## After the model moved: the drawing, the buttons and their hovers, and the
## place the boards are kept. *content* is true for a change to what is on a
## board rather than to the view over it, and only that marks the document
## modified.
func _changed(content: bool) -> void:
    board_view.queue_redraw()
    _sync_status()
    var header := to_header()
    if _store() == "settings":
        # The file is written for a change to a board, not for every pan: the
        # view goes into the config in memory and lands with the next save.
        SaSettings.config.set_value(SETTINGS_SECTION, SETTINGS_KEY, header)
        if content:
            SaSettings.save_settings()
        return
    var document := _document()
    if document == null:
        return
    document.reference_boards = header
    if content:
        document.modified = true


func _on_document_loaded(document: SaDocument) -> void:
    if _store() == "document":
        restore(document.reference_boards)


## Boards kept in the document follow the document in front, so a second one
## brought forward shows its own boards and not the first's.
func _on_front_changed(surface: SaSurface) -> void:
    var document := SaSurface.document_of(surface)
    if document != null:
        _on_document_loaded(document)


## The Solo button's state, which buttons a picture is needed for, and what the
## showing tab says on hover: the chosen picture's path, or how many pictures
## the board holds.
func _sync_status() -> void:
    if _tabs == null or board_view == null:
        return
    _solo_button.set_pressed_no_signal(not _boards.is_empty() and board().soloed() != null)
    _canvas_button.set_pressed_no_signal(not _boards.is_empty() and board().canvas_picture() != null)
    var count := board().pictures.size() if not _boards.is_empty() else 0
    for button in _needs_picture:
        button.disabled = count == 0
        var own: String = _hovers.get(button, "")
        button.tooltip_text = own if count > 0 else "%s\n%s" % [own, tr("Open or drop a picture on the board first.")]
    for i in _boards.size():
        _tabs.describe(i, _counted(_boards[i].pictures.size()))
    var chosen := board_view.selected()
    if chosen != null:
        _tabs.describe(_current, chosen.path + (tr(" (missing)") if chosen.is_missing() else ""))


## How many pictures a board holds, in the words a tab says on hover.
func _counted(count: int) -> String:
    if count == 0:
        return tr("No reference")
    return tr_n("%d picture", "%d pictures", count) % count


# --- The view and the colour a sample becomes ---------------------------------
##
## The board's Control is `board_view`, a part of this docker that is public:
## the buttons here, the capture and the tests ask it for what is under the
## pointer, and for a fit, a zoom or a pan, so this file carries no door that
## is only a call on it. What stays here is the docker's own: which board is
## showing, where the boards are kept, and what a sampled texel becomes.


## Every picture at one size in a row, the size the Preferences row says. The
## row is this docker's own option and not the view's to read, so the mode is
## read here and the view is told what to bring every picture to.
func normalise() -> void:
    board_view.normalise(String(SaSettings.get_docker_option(SaDockerIds.REFERENCE, OPTION_NORMALISE)))


## Takes the colour under *at* and makes it the foreground, and answers whether
## there was one there to take. Out through `EventBus.color_picked`, which is
## the one door the colour store and every tool already listen at, so the
## reference is not a second writer of the foreground.
##
## The view's `sampled(at)` reaches this, on a real click and on a scenario's
## own `sample` step alike: a texel carried into the document's own space is
## the colour a sample becomes, which is this file's and not the board's.
func sample_at(at: Vector2) -> bool:
    var point := board().to_board(at)
    var picture := board().picture_at(point)
    if picture == null:
        return false
    # The canvas element answers no colour: its pixels are on the GPU and a
    # sample would be a readback for one texel, which is what hard rule 1 (no CPU-GPU ping-pong) is
    # there to stop. The eyedropper on the canvas itself is the same colour.
    if picture.live:
        return false
    var texel := picture.texel_at(point)
    if texel.x < 0:
        return false
    _sampled_at = texel
    _sampled_texel = picture.image.get_pixelv(texel)
    _sampled_display = SaColorSpace.picked_across(picture.source_space, _document_space(), _sampled_texel)
    EventBus.color_picked.emit(SaColorStore.opaque(_sampled_display))
    return true


## The picture view told us one of its flags flipped: the change is content,
## which the toggle already committed itself.
func _on_picture_toggled(_picture_arg: SaReferenceBoard.Picture, _id: String) -> void:
    _changed(true)


# --- The canvas element on the board -------------------------------------------


## The Canvas button's press and the scenario's: the canvas off the board showing
## through the view's delete when it is there, and null, or else on it, selected.
func toggle_canvas() -> SaReferenceBoard.Picture:
    if board_view.remove_picture(board().canvas_picture()):
        return null
    var picture := board().add_canvas(board_view.canvas_element.canvas_size())
    board_view.select_picture(picture)
    board().fit_all(board_view.size)
    _changed(true)
    return picture


## Keeps a board's canvas element in step with the canvas: its size, its bound
## output and its redraw on a new composite.
##
## Polled, for the reason the minimap polls: nothing announces a composite, a
## resize or a File New swapping the easel. Only while the docker is on screen
## and the board showing has an element, so a board of photographs costs nothing
## at all, and a redraw is asked for only when one of those three moved.
func _process(_delta: float) -> void:
    if board_view == null or not board_view.is_visible_in_tree() or _boards.is_empty():
        return
    var live := board().canvas_picture()
    if live == null:
        return
    var element := board_view.canvas_element
    var size_now := element.canvas_size()
    if size_now != live.live_size and size_now.x > 0 and size_now.y > 0:
        live.live_size = size_now
        board_view.queue_redraw()
    if element.refresh():
        board_view.queue_redraw()


## A docker resized while nothing has been panned or zoomed shows the whole
## board again, so a reference does not sit half off the edge after a drag of
## the corner. Once the view has been moved it is the painter's, and a resize
## leaves it alone.
func _on_picture_resized() -> void:
    if not _boards.is_empty() and _sampled_at.x < 0 and not board_view.busy():
        board().fit_all(board_view.size)
        board_view.queue_redraw()


# --- The dump ------------------------------------------------------------------


## What a capture reads: every board with its pictures, rectangles and flags,
## the view over the one showing, the canvas element and the last colour taken
## off a picture. None of that is in a screenshot. Built here, so every read is
## of the docker's own members and the harness reads the dictionary rather than
## the docker.
func report() -> Dictionary:
    var boards: Array = []
    for entry in _boards:
        var pictures: Array = []
        for picture in entry.pictures:
            pictures.append(_picture_report(picture))
        boards.append({"name": entry.name, "pictures": pictures})
    var shown := board() if not _boards.is_empty() else null
    var out := {
        "store": _store(),
        "boards": boards,
        "current": _current,
        "loaded": shown != null and not shown.pictures.is_empty(),
        "zoom": shown.zoom if shown != null else 1.0,
        "offset": {"x": shown.offset.x, "y": shown.offset.y} if shown != null else {"x": 0.0, "y": 0.0},
        "picture_size": {"w": board_view.size.x, "h": board_view.size.y},
        "sampled_at": [_sampled_at.x, _sampled_at.y],
        "sampled_texel": [_sampled_texel.r, _sampled_texel.g, _sampled_texel.b, _sampled_texel.a],
        "sampled_display": [_sampled_display.r, _sampled_display.g, _sampled_display.b, _sampled_display.a],
        "crop_mode": board_view.crop_mode,
        "solo": shown.pictures.find(shown.soloed()) if shown != null and shown.soloed() != null else -1,
        "hover_bar": board_view.bar_report(),
        # The selection's box while a left drag on the empty board draws it.
        "selection_box": board_view.selection.box_report(),
        "canvas_element": board_view.canvas_element.report(),
    }
    var space := _document_space()
    if space != null:
        var stored := space.from_display(_sampled_display)
        out["sampled_in_document"] = [stored.r, stored.g, stored.b, stored.a]
        out["document_space"] = String(space.id)
    return out


# --- Solo ----------------------------------------------------------------------


## The bar's Solo and the shortcut's: the selected picture alone, or the one
## under the pointer when nothing is selected, and the whole board again when
## one is already alone. The button's pressed state follows the board, so a
## press that found nothing to solo leaves it up.
func solo() -> bool:
    var picture := board_view.selected() if board_view.selected() != null else board_view.hover_target()
    var done := board_view.toggle_solo(picture)
    _sync_status()
    return done


## The solo as a command the shortcut profile binds, Ctrl+Alt+S for solo,
## under the dockers on the Keyboard Shortcuts page, which is why its id starts
## `docker_`. Not Ctrl+Shift+F, which `test_fullscreen_is_f11_alone.gd` keeps
## free. Registered from
## `SaAppCommands.register_all` beside the docker toggles, and answered by the
## Reference docker in the tree.
##
## It names its docker, so with the docker hidden the command registry runs
## nothing and says in the corner what the chord does and how to show the
## docker, rather than a handler that checks the docker's visibility itself and
## declines in silence.
static func register_solo(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(
        ReferencePictureView.SOLO_COMMAND, "Reference: show one picture alone", _solo_in_tree
    )
    var key := InputEventKey.new()
    key.keycode = KEY_S
    key.ctrl_pressed = true
    key.alt_pressed = true
    command.default_events = [key]
    command.category = &"docker"
    command.docker = SaDockerIds.REFERENCE
    command.sentence = "Show the Reference docker's selected picture alone, or the whole board again."
    ctx.register_command(command)


## A press that finds no picture to solo says so and declines, so the chord
## travels on. The docker's bar button is dimmed on an empty board and never
## gets here.
static func _solo_in_tree() -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return false
    var docker := tree.root.find_child(SaDockerIds.REFERENCE, true, false) as ReferenceDocker
    if docker == null:
        return false
    if docker.solo():
        return true
    EventBus.corner_notice.emit(
        TranslationServer.translate("Select a picture on the Reference board, or hold the pointer over one, to show it alone.")
    )
    return false


## `{"reference": {...}}` in the state dump. Empty when the docker is not built,
## the way the Minimap's block is.
static func capture_state(root: Window) -> Dictionary:
    var docker := root.find_child(SaDockerIds.REFERENCE, true, false) as ReferenceDocker
    if docker == null:
        return {}
    var out := {"origin": {"x": float(docker.position.x), "y": float(docker.position.y)}}
    out.merge(docker.report())
    return out


## One picture of a board as the dump reads it: its file, rectangle, crop and
## four flags, and for the canvas element the size it shows, since it has no
## path to say what it is.
func _picture_report(picture: SaReferenceBoard.Picture) -> Dictionary:
    return {
        "path": picture.path,
        "rect": [picture.rect.position.x, picture.rect.position.y, picture.rect.size.x, picture.rect.size.y],
        "missing": picture.is_missing(),
        # The view's set and not its `selected()`, which answers null on a tab
        # not showing and with several selected.
        "selected": board_view.selection.has(picture),
        "flip": picture.flip_h,
        "greyscale": picture.greyscale,
        "on_top": picture.on_top,
        "crop": [picture.crop.position.x, picture.crop.position.y, picture.crop.size.x, picture.crop.size.y],
        "canvas": picture.live,
        "live_size": [picture.live_size.x, picture.live_size.y],
    }


## The open document, looked up rather than injected, the way the File menu
## reaches the canvas, because a reference that owned a document reference
## would be a second thing to keep in step with a document that closes.
func _document() -> SaDocument:
    var canvas := SaCanvasView.front_canvas() if is_inside_tree() else null
    return canvas.document if canvas != null else null


func _document_space() -> SaColorSpace:
    var document := _document()
    return document.color_space if document != null else null
