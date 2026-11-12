## The row of tabs above the canvas: one tab for each open document, in the
## owner's order, with the file name, a star while it has unsaved changes and a
## close button, the front one pressed. A button at the end lists the open
## documents in a menu.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It draws the documents `SaDocumentTabs` hands it, in the order the owner
## holds them, and sends what the painter asked for, [signal picked] and
## [signal close_asked], so `SaDocuments` stays the one writer of the list and
## `SaDocumentTabs` decides what a close does. Every size is
## in logical units (hard rule 7, only `SaUI` scales the window), and the list is a `PopupMenu`, a window of its
## own, so it is handed to `SaUI.apply_to_window` before it opens.
class_name SaDocumentTabBar
extends PanelContainer

## The painter clicked *surface*'s tab, or its row in the list.
signal picked(surface: SaSurface)

## The painter pressed *surface*'s close button.
signal close_asked(surface: SaSurface)

## The bar's height in logical pixels.
const HEIGHT: int = 28

## A tab's name is cut to this many characters, so a long file name leaves
## room for the others.
const NAME_CHARS: int = 32

## The open documents' surfaces in tab order, as last handed to [method show_documents].
var surfaces: Array[SaSurface] = []

## The surface in front, whose tab is pressed.
var front: SaSurface = null

## The row holding a tab for each document.
var tabs: HBoxContainer = null

## The button at the end that opens the list of open documents.
var list_button: Button = null

## The list it opens.
var list: PopupMenu = null

## The documents whose name and star the tabs show, connected while held so a
## save or a stroke redraws the tab, and let go when the tab goes.
var _heard: Array[SaDocument] = []


func _init() -> void:
    name = "DocumentTabBar"
    add_to_group(SaCanvasView.COVER_GROUP)
    anchor_left = 0.0
    anchor_right = 0.0
    anchor_top = 0.0
    anchor_bottom = 0.0
    custom_minimum_size = Vector2(0.0, float(SaUI.px(HEIGHT)))
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_primary", "border_color": "border_primary"})
    style.border_width_bottom = 1
    style.content_margin_left = float(SaUI.px(SaTheme.GAP))
    style.content_margin_right = float(SaUI.px(SaTheme.GAP))
    add_theme_stylebox_override("panel", style)
    var row := SaMake.row(self, "Row", 0)
    tabs = SaMake.row(row, "Tabs", SaUI.px(2))
    tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.clip_contents = true
    list_button = SaMake.button(row, "ListButton", "", tr("The open documents"))
    SaUI.set_button_icon(list_button, "chevron_down", "")
    list_button.flat = true
    list_button.custom_minimum_size = Vector2(float(SaUI.px(HEIGHT)), 0.0)
    list_button.pressed.connect(open_list)
    list = PopupMenu.new()
    list.name = "DocumentList"
    list.id_pressed.connect(_on_list_pressed)
    add_child(list)


func _ready() -> void:
    SaUI.apply_ui_theme(self)


func _exit_tree() -> void:
    _hear([])


## Builds a tab for each of *open*, in its order, with *in_front*'s pressed,
## and says each one's name.
func show_documents(open: Array[SaSurface], in_front: SaSurface) -> void:
    surfaces = open.duplicate()
    front = in_front
    for old: Node in tabs.get_children():
        tabs.remove_child(old)
        old.queue_free()
    var held: Array[SaDocument] = []
    for at in surfaces.size():
        var surface := surfaces[at]
        _tab(surface, at)
        if surface.get_document() != null:
            held.append(surface.get_document())
    _hear(held)
    refresh()


## Says every tab's name and star again, and presses the front one's.
func refresh(_value: Variant = null) -> void:
    for tab: Node in tabs.get_children():
        var surface := surfaces[tab.get_index()] if tab.get_index() < surfaces.size() else null
        var name_button := tab.get_node("Name") as Button
        name_button.text = tab_text(SaSurface.document_of(surface))
        name_button.tooltip_text = _full_name(SaSurface.document_of(surface))
        name_button.set_pressed_no_signal(surface != null and surface == front)
        (tab.get_node("Close") as Button).visible = surfaces.size() > 1


## Stands the bar across *room*, a rectangle in the window's logical pixels whose
## height is ignored, and shows it when *shown*.
func place_in(room: Rect2, shown: bool) -> void:
    visible = shown
    position = room.position
    size = Vector2(maxf(room.size.x, 0.0), float(SaUI.px(HEIGHT)))


## What *document*'s tab reads: its file name, or Untitled, with the star the
## title and the Info docker show while it has unsaved changes, cut to
## [constant NAME_CHARS].
static func tab_text(document: SaDocument) -> String:
    if document == null:
        return ""
    var file_name := SaDocumentLabel.file_name_of(document)
    if file_name.length() > NAME_CHARS:
        file_name = file_name.left(NAME_CHARS - 1) + "…"
    return SaDocumentLabel.text_for(file_name, document.modified, false)


## What each tab's name button reads now, in tab order.
func tab_texts() -> Array[String]:
    var texts: Array[String] = []
    for tab: Node in tabs.get_children():
        texts.append((tab.get_node("Name") as Button).text)
    return texts


## The surface whose tab is under *global_point*, a point in the bar's own
## viewport, or null off every tab and while the bar is hidden.
func surface_at(global_point: Vector2) -> SaSurface:
    if not is_visible_in_tree():
        return null
    for tab: Node in tabs.get_children():
        var at := tab.get_index()
        if at < surfaces.size() and (tab as Control).get_global_rect().has_point(global_point):
            return surfaces[at]
    return null


## Opens the list of open documents under its button, the front one highlighted
## rather than dotted, as every one-of list in Sara is.
func open_list() -> void:
    list.clear()
    for at in surfaces.size():
        var surface := surfaces[at]
        list.add_item(_full_name(surface.get_document()), at)
    SaUI.apply_to_window(list)
    var under := list_button.get_global_rect()
    list.reset_size()
    list.position = Vector2i(Vector2(under.end.x - float(list.size.x), under.end.y))
    list.popup()
    list.set_focused_item(surfaces.find(front))


func _tab(surface: SaSurface, at: int) -> void:
    var tab := SaMake.row(tabs, "Tab%d" % at, 0)
    var name_button := SaMake.button(tab, "Name")
    name_button.toggle_mode = true
    name_button.focus_mode = Control.FOCUS_NONE
    name_button.pressed.connect(_on_tab_pressed.bind(surface))
    var close := SaMake.button(tab, "Close", "×", tr("Close this document"))
    close.flat = true
    close.focus_mode = Control.FOCUS_NONE
    close.custom_minimum_size = Vector2(float(SaUI.px(20)), 0.0)
    close.pressed.connect(func() -> void: close_asked.emit(surface))


func _on_tab_pressed(surface: SaSurface) -> void:
    # A toggle button lets go of itself on a second click, and the front tab
    # stays pressed whatever the click, so the state is said again either way.
    picked.emit(surface)
    refresh()


func _on_list_pressed(id: int) -> void:
    if id >= 0 and id < surfaces.size():
        picked.emit(surfaces[id])


func _full_name(document: SaDocument) -> String:
    if document == null:
        return ""
    var shown := SaDocumentFiles.display_name(document)
    return "%s*" % shown if document.modified else shown


## Connects the name and the star of each document in *held*, and lets go of
## the ones no tab shows any more.
func _hear(held: Array[SaDocument]) -> void:
    for document: SaDocument in _heard:
        if is_instance_valid(document) and not held.has(document):
            if document.modified_changed.is_connected(refresh):
                document.modified_changed.disconnect(refresh)
            if document.path_changed.is_connected(refresh):
                document.path_changed.disconnect(refresh)
    for document: SaDocument in held:
        if not document.modified_changed.is_connected(refresh):
            document.modified_changed.connect(refresh)
        if not document.path_changed.is_connected(refresh):
            document.path_changed.connect(refresh)
    _heard = held
