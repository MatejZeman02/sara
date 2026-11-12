## The painter's manual, in a window of Sara's own.
##
## Help > Manual opens it. The pages are the markdown files in `res://manual/`,
## one per page, in the order of their file names, and their pictures sit in
## `res://manual/pictures/`. Both export presets carry the folder, so a painter
## with no network, no browser and no checkout beside the build still has the
## manual. Documentation stays in Help and keeps opening the developers' pages
## on the web.
##
## The page list is on the left and the page on the right. A page is rendered
## from a small markdown subset into one `RichTextLabel` in the shared theme:
## headings, paragraphs, lists, bold, italic, code, links between pages and
## pictures. Anything outside the subset stays as its markdown on screen, which
## is what the suite looks for. `render()` is the whole of the conversion and
## static, so the suite reads every page without building a window. The
## renderer itself is `SaMarkdown`, which the Modules window draws a module's
## README with as well.
@tool
class_name SaManualWindow
extends SaDialogWindow

const FOLDER := "res://manual"

## The least the window is made, in logical units: the page list and a column of
## page beside it. Low, because the page and the list both scroll already, so a
## shorter window costs lines and never a control. A floor of 560 by 360 would
## not fit below the top bar of a 1280 by 800 screen at an interface scale of 2.
const FLOOR := Vector2i(420, 240)

## The page list down the left, one row per page, titled by its first heading.
var page_list: ItemList = null
## The page itself.
var page_view: RichTextLabel = null
## The page files, in the order the list shows them.
var pages: PackedStringArray = PackedStringArray()
## The row showing, or -1 before the first page is turned to.
var current: int = -1


func _init() -> void:
    _init_dialog("ManualWindow", tr("Manual"), Vector2i(960, 680), FLOOR)
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    var row := SaMake.row(column, "Row", SaTheme.GAP)
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL

    page_list = ItemList.new()
    page_list.name = "Pages"
    # As wide as its longest title in its own font, with the item padding, the
    # panel's margins and the scroll bar when it shows. The list measures it on
    # every reshape, which a theme or font change is, so a title is never cut.
    # A fixed width would cut a long title, "Selections and the transform tool".
    page_list.auto_width = true
    page_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page_list.item_selected.connect(show_page)
    row.add_child(page_list)

    page_view = RichTextLabel.new()
    page_view.name = "Page"
    page_view.bbcode_enabled = true
    page_view.scroll_active = true
    page_view.selection_enabled = true
    page_view.focus_mode = Control.FOCUS_CLICK
    page_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page_view.meta_clicked.connect(_on_link)
    # The pictures are drawn as wide as the page, so a page drawn at one width
    # is drawn again at the next.
    page_view.resized.connect(_draw_page)
    row.add_child(page_view)
    SaMarkdown.set_faces(page_view)

    # A way out in the row as well as the cross, and the button Enter presses. Not called `CloseButton`,
    # which is the cross's name, so a scenario names the one it means.
    var buttons := pinned_buttons(column)
    default_button = SaMake.button(buttons, "CloseManualButton", tr("Close"))
    default_button.custom_minimum_size.x = float(SaUI.px(90))
    default_button.pressed.connect(hide)

    pages = page_files()
    for path: String in pages:
        page_list.add_item(title_of(path))


## Shows the manual held under *parent*, built there on first ask and turned
## to page 1, and kept, so a painter who shuts it on page 4 opens it on page 4.
## `MainDialogs` asks this when Help, Manual is pressed.
static func open_in(parent: Node) -> SaManualWindow:
    var window := parent.get_node_or_null("ManualWindow") as SaManualWindow
    if window == null:
        window = SaManualWindow.new()
        parent.add_child(window)
        window.show_page(0)
    window.popup_centered()
    return window


## Turns to page *index*, counted from nought in the list's order.
func show_page(index: int) -> void:
    if index < 0 or index >= pages.size():
        return
    current = index
    if not page_list.is_selected(index):
        page_list.select(index)
    _draw_page()
    page_view.scroll_to_line(0)


## The facts a capture's dump carries, or an empty dictionary before the
## window was first opened: the pages, the one showing, what the painter reads
## on it, anything on it that did not resolve, and the page list's width beside
## the width its longest title takes in the list's font.
static func capture_state(root: Window) -> Dictionary:
    var window := root.find_child("ManualWindow", true, false) as SaManualWindow
    if window == null:
        return {}
    var showing := window.pages[window.current] if window.current >= 0 else ""
    return {
        "visible": window.visible,
        "pages": Array(window.pages),
        "current": showing.get_file(),
        "text": window.page_view.get_parsed_text(),
        "problems": Array(render(showing)["problems"]) if not showing.is_empty() else [],
        "list_width": window.page_list.size.x,
        "widest_title": window.widest_title(),
    }


## The width the longest title in the page list takes in the list's own font.
func widest_title() -> float:
    var font := page_list.get_theme_font("font")
    var font_size := page_list.get_theme_font_size("font_size")
    var widest := 0.0
    for row: int in page_list.item_count:
        widest = maxf(widest, font.get_string_size(page_list.get_item_text(row), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    return widest


## The page carries its sizes in its own markup, which no theme reaches, so a
## change of the Font size while the manual is open draws the page again.
func _on_ui_font_scale_changed(font_scale: float) -> void:
    super(font_scale)
    _draw_page()


func _draw_page() -> void:
    if current < 0 or page_view == null:
        return
    SaMarkdown.set_faces(page_view)
    # The scroll bar takes its width off the page whether it shows or not.
    var width := int(page_view.size.x) - SaUI.px(24)
    page_view.text = String(render(pages[current], width)["bbcode"])


## A link to another page turns to it, and a link to the web opens the browser,
## which a painter with no network gets nothing from, so the pages keep those few.
## A browser that does not answer is said in the corner, with the address.
func _on_link(meta: Variant) -> void:
    var target := str(meta)
    if SaMarkdown.is_web(target):
        SaMenuCommands.open_url(target)
        return
    var index := Array(pages).find(FOLDER.path_join(target))
    if index >= 0:
        show_page(index)


## Every page in the folder, sorted by file name, which is the order the
## manual is read in.
static func page_files() -> PackedStringArray:
    var found := PackedStringArray()
    for file_name: String in DirAccess.get_files_at(FOLDER):
        if file_name.get_extension() == "md":
            found.append(FOLDER.path_join(file_name))
    found.sort()
    return found


## The page's first heading, or its file name when it has none.
static func title_of(path: String) -> String:
    for line: String in FileAccess.get_file_as_string(path).split("\n"):
        if line.begins_with("# "):
            return line.substr(2).strip_edges()
    return path.get_file().get_basename()


## The page at *path* as BBCode, with pictures no wider than *picture_width*
## (none when it is nought or less, which draws each at its own width).
## Returns `bbcode`, `title`, `links` and `pictures` as the page names them, and
## `problems`, one sentence for each link or picture that does not resolve.
static func render(path: String, picture_width: int = 0) -> Dictionary:
    var markdown := SaMarkdown.new(path.get_base_dir(), picture_width)
    var bbcode := markdown.to_bbcode(FileAccess.get_file_as_string(path))
    return {
        "bbcode": bbcode,
        "title": markdown.title,
        "links": markdown.links,
        "pictures": markdown.pictures,
        "problems": markdown.problems,
    }
