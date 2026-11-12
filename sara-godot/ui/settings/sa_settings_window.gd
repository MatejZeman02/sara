## The Preferences window: the page list on the left, the switching, the sidebar
## that draws it in three groups, the search over it, the eleven built-in pages it
## registers and the way back to every default at the sidebar's foot, one class
## again.
##
## Split three ways once, against a 300-line cap `test_settings_pages.gd` held
## the window to. The seventh rule of structure is what removed the cap: "Length
## is an alarm and not a rule... nothing is asked of a file under a thousand",
## and the second: "A class is never cut to fit a line count."
## `SaSettingsSidebar` and `SaSettingsPages` were statics taking this window as
## a parameter on every call, ten uses between them, and `SaSettingsScroll` and
## the section button beside it needed no file of their own. They come back
## here, and `SaSettingsSearch` keeps its own file because it owns state a
## window does not: the field, the index, the mark.
@tool
extends SaDialogWindow

class_name SaSettingsWindow

var split_container: HSplitContainer
var menu_list: VBoxContainer

## The pane `menu_list` scrolls inside. Kept because a category selected by the
## search has to be scrolled into view, and because a test asks how tall it is.
var category_scroll: SaSettingsScroll
var content_scroll: ScrollContainer
var content_container: VBoxContainer

## What the page area shows while the search matches nothing: "Nothing matches",
## where the page's title was, and under it what Sara says about a word it has
## no setting for. Without it the sidebar empties beside the page that was open,
## and nothing on screen says the search found nothing rather than broke.
var nothing_matches: VBoxContainer
var _nothing_why: Label

## The search over the category list: the field, the index and the mark on the
## first matching row. Built with the categories, the content scroll and a way
## to build a page, once both exist, so it owns what it works on rather than
## reaching back into this window for it.
var search: SaSettingsSearch

## The title bar's maximize and minimize, and the fit to the host.
var frame := SaSettingsFrame.new()

## Big enough for the whole category list and for a page that is not a list of
## every command: twenty-six rows of 32 and 40 for the margins and title bar
## make 872, which still opens whole on a laptop's 900 at an interface scale of
## 2, and `frame.fit_to_host()` brings it back down on a display that has less
## to give.
##
## It is not the list's ceiling. The list scrolls in a pane of its own, rather
## than growing the split past the window's bottom edge and taking the page on
## the right with it. This size is what opens without a scrollbar showing, not
## what the categories must fit in. 1440 wide, because a hint runs across the
## whole row and the width is what gives a paragraph fewer lines.
const DEFAULT_LOGICAL_SIZE := Vector2i(1440, 872)

## The first page Preferences opens, what a painter changes first, in the
## order `SaGeneralPage` gives the reason for.
const INTERFACE_PAGE := "Interface"

## The eleven pages, in the order the sidebar draws them, by what a painter is
## doing there rather than by the folder a class lives in. Sorted by source
## folder, half of thirteen pages were about where a class lives: Presets
## holding one button, Colour Spaces a browser with no setting on it, Colour
## Themes the one choice most painters make at the top of 47 rows of swatches.
## The three groups are `SaUIRegistry`'s, and [constant GROUP_TITLES] names
## them.
##
## **Interface** comes first, because the first page Preferences opens is the
## one a painter changes in their first sessions: the interface's size, its
## theme, the pen's door, the undo depth and what shows at start, and last in
## it the language Sara speaks, a choice made once. Then **Painting**, the
## brush slots and the Krita import, the pen and the canvas, and **Files and
## system**, where a module's page goes unless it names a group. A MIDI
## controller's page comes in through the door as a module's does, so it
## lists after the canvas in Painting.
## Modules closes Files and system, the list of what loads at the next start.
##
## The top bar has no page of its own: its window buttons and the way to its
## element list are a section of Layouts and dockers. A docker declared in
## `SaSettingsLayout` gets a line on Layouts and dockers for free rather than a
## page of its own.
const FIXED_PAGES := [
    INTERFACE_PAGE,
    SaDockersPage.TITLE,
    "Keyboard shortcuts",
    SaLanguagesPage.TITLE,
    "Brushes",
    "Pen and tablet",
    "Canvas and colour",
    "Files",
    "Performance",
    "Recorder",
    SaModulesPage.TITLE,
]

## The column a page made of parts is drawn in, which [SaBuiltinPages] builds.
## Kept under this name while a suite casts a page to it.
# gdlint:ignore=constant-name
const PageParts = SaBuiltinPages.PageParts

## The heading each of `SaUIRegistry.SETTINGS_GROUPS` is drawn under.
const GROUP_TITLES := {
    &"interface": "Interface",
    &"painting": "Painting",
    &"files_and_system": "Files and system",
}

## The title the colour theme's editor opens under, in the page area, with
## Interface marked in the sidebar. Not a page of the sidebar: Edit colours…
## on the Interface page is its door. Its two former titles still open it.
const COLOURS_TITLE := "Colour theme"

## The page each former title of the sidebar lives on, so a door call or a
## scenario that names a page by an older title still lands. Colour Themes is
## the editor rather than a page, and [method show_page] opens it. Colour Spaces
## is not in Preferences at all: it is Help, Colour Spaces…, a window of its
## own.
const FORMER_TITLES := {
    "General": INTERFACE_PAGE,
    "Workspace": INTERFACE_PAGE,
    "Keyboard Shortcuts": "Keyboard shortcuts",
    "Presets": "Brushes",
    "Brush Slots": "Brushes",
    "Tablet": "Pen and tablet",
    "Display": "Canvas and colour",
    "Timelapse": "Recorder",
    "Top Menu Bar": SaDockersPage.TITLE,
}

## The row a former title lands on when the door names none: the top bar's
## section of Layouts and dockers, rather than the top of a page it is the
## fourth section of.
const FORMER_ROWS := {
    "Top Menu Bar": SaTopBarSection.FIRST_ROW,
}

## The gutter between the page column and the window's edges. Twice the column's
## own row gap, because less at this width reads as none and the row panels run
## into the frame.
const CONTENT_MARGIN := 20

## One category button, and the list's own gap between two of them.
const BUTTON_HEIGHT := 28
const LIST_SEPARATION := SaTheme.GAP_TIGHT

## The clear space over a group's heading, past the list's own gap, logical
## units. Five button gaps, so a group reads as a group and not as a wider gap
## between two buttons. The first heading in view has none.
const GROUP_GAP := 20

## The two answers to the question Reset all preferences asks. Cancel is the
## one Enter, Escape and the close button give, so a reset is never the answer
## a painter did not choose.
const RESET_CANCEL := 0
const RESET_CONFIRM := 1

## The question's size, tall enough for both of its paragraphs at the default
## font, so what stays is read without scrolling for it. `SaMessage` opens every
## question at the size of a one-line one, and at that size the second
## paragraph was under the buttons.
const RESET_QUESTION_SIZE := Vector2i(560, 330)

## Public with `build_page` because `SaSettingsSearch` walks all three, this
## file being the list and the switching and the search living beside it.
var categories: Array = []
var current: int = -1

## The group of each of `categories`, at the same index, and the button the
## sidebar draws it with. The list holds the group headings as well, so a
## button is found here rather than by its index among the list's children.
var category_groups: Array[StringName] = []
var category_buttons: Array[Button] = []

## The heading over each group the sidebar draws, by the group's id.
var group_headings: Dictionary[StringName, Label] = {}

## The tool registry, so the Keyboard Shortcuts page names a module's tool the
## way its own toolbox button does. Optional: the page falls back to the action
## name without it.
var tools_registry: SaToolRegistry = null

## The filter registry, so the same page names a module's filter the way its
## Filter menu row does. Optional like the tool registry.
var filters_registry: SaFilterRegistry = null

## The command registry, so the same page names a command by its title, the
## words the menus draw it with. Optional like the other two.
var commands_registry: SaCommandRegistry = null

## The translation registry, whose catalogues the Languages page lists and
## offers. Optional: the page offers English alone without it.
var translations_registry: SaTranslationRegistry = null

## Where the pages are registered: the host's, or one of this window's own when
## it is made with none, so the ten come through the door either way.
var _ui_registry: SaUIRegistry

## The sidebar's panel, the search field and the category list inside it, kept
## so a page registered or taken away can have it built again.
var _sidebar_panel: PanelContainer

## The request that drew the page on screen, a sidebar page, a docker's part or
## the colour theme's editor, so a change of catalogue draws the same page again.
var _reopen := Callable()

## Reset all preferences, at the foot of the sidebar under the list, and the
## question it asks while that question is up. Both public because a suite
## presses the button and answers the question through them.
var reset_button: Button
var reset_question: SaMessage

## The pages built once and kept, Keyboard shortcuts and Canvas and colour, and
## which column is on screen. Public so a suite counts the columns it made.
var kept_pages: SaSettingsKeptPages

## True while the window builds the page it is about to show, rather than one
## the search indexes off the tree. A page as big as Keyboard shortcuts reads it
## in its factory and builds its rows a slice a frame once on screen.
var building_to_show := false
## The search's field, which the window holds in its sidebar, read for whether
## a search is typed as a page opens.
var _search_field: LineEdit = null


func _init(ui_registry: SaUIRegistry = null) -> void:
    _ui_registry = register_builtins(ui_registry)
    _init_dialog("SaSettingsWindow", tr("Preferences"), DEFAULT_LOGICAL_SIZE, Vector2i(400, 300))

    # **Never modal**, so a painter paints beside Preferences whether it is
    # open, rolled up to its title strip or minimized.
    #
    # `Window.exclusive` blocks the parent for as long as the window is visible
    # rather than only under what it covers, so an open Preferences took every
    # press meant for the canvas beside it. `transient` is what `_init_dialog`
    # already sets and what keeps the page above the window it is about, which
    # is all the "in front of the canvas" a Preferences page ever needed.
    #
    # **Preferences alone.** New Document, Colour Space and the rest stay modal,
    # because each asks a question and waits for the answer, so the flag is
    # written here rather than in `sa_dialog_window.gd`.
    #
    # The focus_entered and tree_exited disconnect spam an exported build with
    # embedded subwindows prints is godotengine/godot#87626, an engine bug fixed
    # upstream for 4.8, and not this flag.
    exclusive = false

    # A Window is visible the moment it joins the tree, and this one is built on
    # the first request rather than at boot. A toggle asks whether the window is
    # open before it decides, so a window nobody has opened yet has to answer
    # no, or the first Ctrl+comma hides a window that was never on screen.
    visible = false

    # Anchored full-rect inside `content`, not stacked in a container. The
    # split's panes are sized from its own width, and putting it in a
    # VBoxContainer changed that width enough to push the right-hand toggles off
    # the edge.
    split_container = HSplitContainer.new()
    split_container.name = "SplitContainer"
    split_container.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.add_child(split_container)

    # The list scrolls rather than growing the pane. A VBoxContainer of buttons
    # has the height of all of them as its minimum, and an HSplitContainer takes
    # its own minimum from its tallest child, so once this list outgrew the
    # window the split was laid out 81 logical pixels taller than the window
    # shows and the last row of the page on the right could not be clicked. The
    # list was sixteen categories when the window's size was chosen and is more
    # now, and the next module to declare a docker adds another.
    content_scroll = SaSettingsScroll.new()
    # No sideways scrolling: a page is as wide as its pane, and one that asks for
    # more wraps. The Keyboard Shortcuts page grew a horizontal bar and pushed
    # its profile and search fields past the right edge.
    content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var margin := SaMake.margin(content_scroll, "ContentMargin", CONTENT_MARGIN)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content_container = SaMake.column(margin, "Content", 10)
    content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var registries := func() -> Array: return [tools_registry, filters_registry, commands_registry]
    kept_pages = SaSettingsKeptPages.new(margin, content_container, registries)

    # Beside the page rather than in it, the margin drawing whichever of the two
    # is showing: `_on_category_selected` empties `content_container` on every
    # switch, and this stands in for whichever page is open.
    nothing_matches = SaMake.column(margin, "NothingMatches", 10)
    nothing_matches.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    nothing_matches.visible = false
    var nothing_title := SaMake.label(nothing_matches, "NothingMatchesTitle", tr("Nothing matches"))
    SaSettingsRows.size_label(nothing_title, SaSettingsRows.PAGE_TITLE_SCALE)
    _nothing_why = SaSettingsRows.hint_label("")
    _nothing_why.name = "NothingMatchesWhy"
    nothing_matches.add_child(_nothing_why)

    _take_categories()
    _make_search()

    _build_sidebar(split_container)
    split_container.add_child(content_scroll)

    _on_category_selected(0)


## The registry is heard only while the window is in the tree, so a window a
## suite builds and drops is not kept alive by a registry that outlives it. A
## page registered or taken away while it was out is caught up on the way in.
func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_TREE:
        if not _ui_registry.settings_pages_changed.is_connected(_on_settings_pages_changed):
            _ui_registry.settings_pages_changed.connect(_on_settings_pages_changed)
        if categories != _sidebar_titles(_ui_registry):
            _on_settings_pages_changed()
    elif what == NOTIFICATION_EXIT_TREE:
        if _ui_registry.settings_pages_changed.is_connected(_on_settings_pages_changed):
            _ui_registry.settings_pages_changed.disconnect(_on_settings_pages_changed)
    elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _follow_the_catalogues()


## Every word the window draws read again in the catalogues in use. The engine
## sends this on a change of locale, and `SaTranslationRegistry` when a
## catalogue of the locale comes or goes, which Modules > Reload Modules does.
## The window is built once and kept, and it writes its words translated, so the
## engine's own translation of a button's text took the old translation for a
## key and found nothing: a window first opened in Czech kept the page list's
## and the open page's old words after a reload brought a catalogue with new ones.
##
## The open page is drawn again by the request that drew it, then the sidebar
## and the search are built again the way a page coming or going builds them,
## which writes the list, the group headings, Reset all preferences and the
## search field in the new words and drops the search's index of the old ones.
func _follow_the_catalogues() -> void:
    title = tr("Preferences")
    (drag_handle.find_child("TitleLabel", true, false) as Label).text = title
    (nothing_matches.get_node(^"NothingMatchesTitle") as Label).text = tr("Nothing matches")
    content_container = kept_pages.drop_all()
    _reopen.call()
    _on_settings_pages_changed()


## Every page the sidebar lists now, and the group of each, from the registry.
## A docker's list is reached from its line on Layouts and dockers, and the
## sidebar lists no docker at all.
func _take_categories() -> void:
    categories = []
    category_groups.clear()
    for entry: Dictionary in _sidebar_entries(_ui_registry):
        categories.append(entry["title"])
        category_groups.append(StringName(entry["group"]))


## A new search over `categories`, with a fresh index, because the index is
## built once for the search's life and a page that came or went is not in it.
func _make_search() -> void:
    search = SaSettingsSearch.new(categories, content_scroll, build_page)
    search.narrowed.connect(_on_search_narrowed)
    search.page_wanted.connect(show_page)


## A module that brings a Preferences page was enabled or disabled after the
## window was built: the sidebar is built
## again from the registry, and so are the search and its index.
##
## The page on screen stays when it still exists, and is not built again, so
## a value the painter is part way through editing on it is not thrown away.
## Its row is found at its new index and marked the way a click would mark it.
## When it is the page that went, the first page opens instead. What the
## painter had typed into the search is typed into the new one, so the list
## stays narrowed to the same words.
func _on_settings_pages_changed() -> void:
    var open_title := String(categories[current]) if current >= 0 and current < categories.size() else ""
    var needle := _search_field.text
    search.clear_highlight()
    kept_pages.drop_hidden()

    _take_categories()
    _make_search()

    # Out of the split at once, so the new panel takes the old one's place, and
    # freed a frame later, the way a page is, in case the signal came from a
    # press inside it.
    split_container.remove_child(_sidebar_panel)
    _sidebar_panel.call_deferred("free")
    _build_sidebar(split_container)
    split_container.move_child(_sidebar_panel, 0)

    var at := categories.find(open_title)
    if at == -1:
        _on_category_selected(0)
    else:
        _mark_selected(at)
        search.mark_page_open(open_title)
    if not needle.is_empty():
        search.apply(needle)


## The chrome goes on after the base has built the bar, the resizer and the
## overlay, because the frame moves its two buttons in beside the close button
## and hides the resizer while the window is rolled up.
func _ready() -> void:
    super()
    frame.attach(self)
    frame.fit_to_host()
    visibility_changed.connect(_on_shown)
    add_child(SaSettingsTypeAhead.new(self))


## Preferences comes back as a window, at a size that fits wherever it is now.
##
## A window left rolled up would otherwise reopen as a title bar with nothing
## under it, where a Preferences that comes back should be bigger, not smaller.
func _on_shown() -> void:
    if not visible:
        return
    if frame.mode == SaSettingsFrame.Mode.COLLAPSED:
        frame.set_mode(SaSettingsFrame.Mode.NORMAL)
    frame.fit_to_host()


## The page's four text sizes follow the Font size preference while the page is
## open, because the Font size row is on one of these pages and a drag of it
## that moves only the theme's text leaves the title, the headings and the
## explanations where they are.
func _on_ui_font_scale_changed(font_scale: float) -> void:
    super(font_scale)
    SaSettingsRows.refit(menu_list)
    SaSettingsRows.refit(content_container)
    SaSettingsRows.refit(nothing_matches)
    SaSettingsRows.measure(content_container)


## A scale change re-derives the geometry from the logical size, which is
## neither of the geometries the two buttons set, so both states end with it.
func apply_window_scale() -> void:
    kept_pages.drop_hidden()
    frame.set_mode(SaSettingsFrame.Mode.NORMAL)
    super()
    frame.fit_to_host()


## The panel, the search field, the category list, one button per category
## in the order the window put them in under a heading per group, and Reset all
## preferences at its foot.
##
## Through `show_page` rather than a private handler, because a button here is
## the same request the menu and a scenario make.
func _build_sidebar(split: HSplitContainer) -> void:
    var left_panel := PanelContainer.new()
    var left_style := StyleBoxFlat.new()
    SaTheme.bind(left_style, {"bg_color": "bg_sidebar"})
    left_style.content_margin_left = float(SaUI.px(8))
    left_style.content_margin_right = float(SaUI.px(8))
    left_style.content_margin_top = float(SaUI.px(8))
    left_style.content_margin_bottom = float(SaUI.px(8))
    left_panel.add_theme_stylebox_override("panel", left_style)
    left_panel.custom_minimum_size = Vector2(SaUI.px(160), 0)
    split.add_child(left_panel)
    _sidebar_panel = left_panel

    var left_box := SaMake.column(left_panel, "Sidebar", SaTheme.GAP)
    _search_field = search.field
    left_box.add_child(_search_field)

    category_scroll = SaSettingsScroll.new()
    category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    category_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_box.add_child(category_scroll)

    menu_list = SaMake.column(category_scroll, "Categories", LIST_SEPARATION)
    menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    category_buttons.clear()
    group_headings.clear()
    for i in categories.size():
        var group := category_groups[i]
        if not group_headings.has(group):
            group_headings[group] = _group_heading(group)
        var page_title := String(categories[i])
        var btn := Button.new()
        btn.text = tr(page_title)
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        btn.custom_minimum_size = Vector2(0, SaUI.px(BUTTON_HEIGHT))
        btn.pressed.connect(func() -> void: show_page(page_title))
        menu_list.add_child(btn)
        category_buttons.append(btn)
    _refresh_headings()

    # Under the list rather than in it, so the search, which hides every page
    # whose words it does not match, never hides it.
    reset_button = SaMake.button(
        left_box,
        "ResetAllPreferences",
        tr("Reset all preferences..."),
        tr("Asks first, then puts every setting back to its default")
    )
    reset_button.custom_minimum_size = Vector2(0, SaUI.px(BUTTON_HEIGHT))
    reset_button.pressed.connect(ask_to_reset)


## A group's heading, in the list above the group's first button: the group's
## name, small, bold and muted, the way a section's heading on a page is, so it
## reads as a title over buttons and not as one of them. Text the pointer
## passes through, so it is never pressed.
func _group_heading(group: StringName) -> Label:
    var heading := SaMake.label(menu_list, "Group" + String(group).to_pascal_case(), tr(String(GROUP_TITLES.get(group, group))))
    SaSettingsRows.size_label(heading, SaSettingsRows.HEADING_SCALE)
    SaSettingsRows.embolden(heading)
    SaTheme.bind_font(heading, "text_muted")
    heading.uppercase = true
    heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return heading


## Shows each group's heading while a button of its group is showing, with the
## clear space over it unless it is the first heading in view, so a search that
## leaves one group draws no gap over the top of the list and no heading over
## nothing.
##
## The heading's text starts where a button's label does, read off the theme's
## button face rather than written down, so a theme with a wider margin moves
## both together.
func _refresh_headings() -> void:
    var face := category_buttons[0].get_theme_stylebox("normal") if not category_buttons.is_empty() else null
    var indent := face.get_margin(SIDE_LEFT) if face != null else 0.0
    var first := true
    for group: StringName in group_headings:
        var shown := false
        for i in categories.size():
            if category_groups[i] == group and category_buttons[i].visible:
                shown = true
                break
        var heading := group_headings[group]
        heading.visible = shown
        var gap := 0 if first else SaUI.px(GROUP_GAP)
        heading.custom_minimum_size = Vector2(0, SaUI.px(BUTTON_HEIGHT) + gap)
        var box := StyleBoxEmpty.new()
        box.content_margin_left = indent
        heading.add_theme_stylebox_override("normal", box)
        if shown:
            first = false


## The search narrowed the list to *titles*: every other button hides, and a
## group's heading with the last of its buttons. A list narrowed to nothing
## puts "Nothing matches" over the page, and *why* under it, since the field is
## never empty then: an empty one narrows to every category.
func _on_search_narrowed(titles: PackedStringArray, why: String) -> void:
    for i in category_buttons.size():
        category_buttons[i].visible = titles.has(String(categories[i]))
    _refresh_headings()
    _show_nothing_matches(titles.is_empty(), why)


## "Nothing matches" in the page area in place of the page, with *why* under it
## when there is one, or the page back.
func _show_nothing_matches(on: bool, why: String = "") -> void:
    nothing_matches.visible = on
    content_container.visible = not on
    _nothing_why.text = why if on else ""
    _nothing_why.visible = not _nothing_why.text.is_empty()


func _on_category_selected(idx: int, row: StringName = &"") -> void:
    var cat_name: String = categories[idx]
    _reopen = show_page.bind(cat_name)
    var kept := kept_pages.column_of(cat_name)
    if kept != null:
        _open(idx, cat_name, null, row, kept)
    else:
        building_to_show = true
        var pg := build_page(cat_name)
        building_to_show = false
        _open(idx, cat_name, pg, row)


## Draws *page* in the page area under *page_title*, with the sidebar's button
## at *idx* marked, and marks *row* on it when one is named. What a click on a
## category does, and what a docker's two buttons on Layouts and dockers do with
## a part of that docker's page, which is the sidebar's Layouts and dockers
## still.
##
## *kept* is the column a kept page was built in on an earlier open, shown again
## as it stands. A kept page opening for the first time is built in a column of
## its own, and every other page in the window's plain one.
func _open(idx: int, page_title: String, page: Control, row: StringName, kept: VBoxContainer = null) -> void:
    # The page about to be freed holds the marked row.
    search.forget_highlight()
    _mark_selected(idx)
    # Opening a page is the painter's act, through a door or a click, and the
    # page is what they asked to see, whatever the search last said.
    _show_nothing_matches(false)

    # Clear content. `queue_free` on a node outside the tree is never collected,
    # which left every page the suite had shown still a child of
    # `content_container` and answering `SaSettingsRowReport.report` for every
    # category after the first declared one. Removed synchronously either way,
    # so a report taken this same frame never finds it, and freed through
    # `call_deferred` rather than by hand: the Workspace page's
    # `rebuild_requested` reaches here while the page holding the row that
    # moved is still emitting it, and freeing it there is freeing a locked
    # object.
    var column := kept
    if column == null:
        column = kept_pages.column_for(page_title, page != null)
    content_container = kept_pages.bring_forward(column)
    if kept == null:
        for child in content_container.get_children():
            content_container.remove_child(child)
            child.call_deferred("free")

        # First on the page, and a Label: the note mode reads the open page's
        # name from it.
        var title_lbl := SaMake.label(content_container, "PageTitle", tr(page_title))
        SaSettingsRows.size_label(title_lbl, SaSettingsRows.PAGE_TITLE_SCALE)

        if page != null:
            page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            kept_pages.arrive(page)
    # A page still arriving a slice a frame brings what it has not reached now
    # when a door names a row, or a search is typed, whose mark lands on the
    # first row that matches.
    var searching := _search_field != null and not _search_field.text.strip_edges().is_empty()
    var brought := kept_pages.land(row, searching)

    # A kept page shown again was measured when it was built, at the font and
    # the scale it shows at still, since a change of either drops it, unless a
    # landing brought sections in just now.
    if kept == null or brought:
        SaSettingsRows.measure(content_container)

    # A page opens at its top. The pane is one scroll for every page, so without
    # this the next page opens as far down as the last one was read. A row the
    # search asked for still scrolls into view, a couple of frames after this,
    # in `mark_page_open`.
    content_scroll.scroll_vertical = 0

    # Opening is the painter's act, so the mark goes on here, on the row a door
    # named when it named one.
    search.mark_page_open(page_title, row)


## One part of a docker's page, its element list or its options, in the page
## area under the docker's title, with Layouts and dockers marked in the
## sidebar. What a docker's Elements… and Options… buttons ask for, and false
## for a category with no line there.
##
## *row* names a row of the part to land on, the way a door names one on any
## page.
func show_docker(category: String, part: StringName = SaLayoutPage.ELEMENTS, row: StringName = &"") -> bool:
    var docker_title := SaDockersPage.docker_title(category)
    var at := categories.find(SaDockersPage.TITLE)
    if category == SaDockersPage.TOP_BAR and at != -1:
        _reopen = show_docker.bind(category, part)
        _open(at, internal_title_for(category), SaTopBarPage.new(_back_to_line.bind(category)), row)
        return true
    if docker_title.is_empty() or at == -1:
        return false
    _reopen = show_docker.bind(category, part)
    _open(at, docker_title, SaLayoutPage.new(category, part, _back_to_line.bind(category)), row)
    return true


## The Back row of a docker's part: Layouts and dockers again, scrolled to the
## docker's line and marked, so the painter is where they left it.
func _back_to_line(category: String) -> void:
    show_page(SaDockersPage.TITLE, SaDockersPage.line_key(category))


## A docker's page by the title it had in the sidebar, for a door or a scenario
## written while it had one: the options when *row* names one of them, and the
## element list otherwise, which is what Elements… opens.
func _show_docker_titled(docker_title: String, row: StringName) -> bool:
    var category := internal_category_for(docker_title)
    if SaDockersPage.docker_title(category).is_empty() and category != SaDockersPage.TOP_BAR:
        return false
    for spec: Dictionary in SaSettings.docker_options(category):
        if StringName(spec.get("key", "")) == row and not row.is_empty():
            return show_docker(category, SaLayoutPage.OPTIONS, row)
    return show_docker(category, SaLayoutPage.ELEMENTS, row)


## The page at *idx* becomes the current one and its button the one drawn
## pressed, without the page on the right being built again.
##
## **That button is where the keyboard lands when Preferences opens.**
## Left to `focus_first_control`, the first control Tab reaches is the search
## box, and a text box holding the keyboard keeps the first Escape for itself,
## so one Escape would leave Preferences open under every profile, the Krita
## one included, where a painter expects Escape to close it. A search the
## painter clicked into still lets go first, because Escape in a text box
## leaves the box before it closes anything.
func _mark_selected(idx: int) -> void:
    current = idx
    if idx >= 0 and idx < category_buttons.size():
        first_focus = category_buttons[idx]
    for i in category_buttons.size():
        var btn := category_buttons[i]
        btn.flat = (i != idx)
        # The sidebar scrolls, so a category reached by `show_page` or by
        # the search rather than by a click can be off the top or the bottom
        # of it. A click on one is already in view and this moves nothing.
        if i == idx and category_scroll != null and category_scroll.is_inside_tree():
            category_scroll.ensure_control_visible(btn)


## The page for a title, or null for a title that is no page: a registered
## page's factory called with this window. A docker's title is no page, and
## [method show_docker] draws its parts.
func build_page(cat_name: String) -> Control:
    var entry := _ui_registry.settings_page_titled(cat_name)
    if not entry.is_empty():
        return SaSettingsSearch.tagged((entry["factory"] as Callable).call(self) as Control, cat_name)
    return null


## The colour theme's editor, every colour of the palette in use, in the page
## area under [constant COLOURS_TITLE] with Interface marked in the sidebar, the
## way a docker's part is drawn under Layouts and dockers. What Edit colours… on
## the Interface page asks for. Its Back row lands on the theme's row there.
func show_colours(row: StringName = &"") -> bool:
    var at := categories.find(INTERFACE_PAGE)
    if at == -1:
        return false
    _reopen = show_colours
    _open(at, COLOURS_TITLE, SaColorThemesPage.new(show_page.bind(INTERFACE_PAGE, SaColorThemesPage.THEME_ROW)), row)
    return true


## After a reset the page on screen shows values the reset changed, so it is
## built again, the page on screen rather than the first.
func rebuild_current_page() -> void:
    content_container = kept_pages.drop_all()
    if current != -1:
        _on_category_selected(current)


## The question Reset all preferences asks, naming what goes back and what
## stays. A painter wants to know whether a layout, a shortcut profile or a
## palette of their own survives. They do, each being a file the reset leaves
## alone, and the question says so in those words.
func reset_question_text() -> String:
    return (
        tr("Every setting on every page goes back to its default: the theme, the interface size and the font,")
        + " "
        + tr("the shortcut profile in use, the brush slots, the menu and docker rows you moved or hid,")
        + " "
        + tr("the switches every docker shares and the recent files.")
        + "\n\n"
        + tr("Your own layouts, shortcut profiles, palettes and pressure curves stay, ready to pick again.")
    )


## Asks before anything goes back. A second press while the question is up
## leaves that one up rather than stacking another on it.
func ask_to_reset() -> void:
    if reset_question != null and is_instance_valid(reset_question) and reset_question.visible:
        return
    reset_question = SaMessage.confirm(
        self,
        tr("Reset all preferences"),
        reset_question_text(),
        PackedStringArray([tr("Cancel"), tr("Reset")]),
        _on_reset_answered,
        RESET_CANCEL,
        RESET_CANCEL
    )
    # The fit `SaDialogWindow` runs on the frame after a window is shown grows
    # it to this and keeps it centred.
    reset_question.logical_size = RESET_QUESTION_SIZE


## The answer: Reset puts every setting back, Cancel and every other way out
## leave them as they were.
##
## The keymap is applied at once, because `SaShortcutStore.apply_active` runs
## only at boot, and without it Preferences says Sara Default while the old
## chords answer until the next launch. The page on screen is drawn again
## because it shows values the reset changed.
func _on_reset_answered(answer: int) -> void:
    reset_question = null
    if answer != RESET_CONFIRM:
        return
    SaSettings.reset_to_defaults()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    EventBus.shortcuts_changed.emit()
    rebuild_current_page()


## Opens the page with this title, and says whether there was one to open.
##
## The left-hand menu cannot be clicked from a capture scenario: Wayland will not
## let a client place the pointer, and an injected click does not route into an
## embedded subwindow, which is where this window lives. Without a way in that is
## not the mouse, every page but the first is unphotographable, and a page nobody
## has looked at is how File > New shipped with its Create button off the bottom.
##
## *row* names a row of that page by its key, for `toggle` below.
##
## A former title of the sidebar opens the page it went to, and Colour Themes
## the editor, because older scenarios name them by those titles. A docker's
## title opens that docker's part, for the same reason. A title the sidebar
## carries now comes first, so a module's page called Tablet opens rather than
## Pen and tablet.
func show_page(page_title: String, row: StringName = &"") -> bool:
    var at := categories.find(page_title)
    if at == -1 and (page_title in ["Colour Themes", "Theme colours"] or page_title == COLOURS_TITLE):
        return show_colours(row)
    if at == -1:
        at = categories.find(FORMER_TITLES.get(page_title, ""))
        if row.is_empty():
            row = FORMER_ROWS.get(page_title, &"")
    if at == -1:
        return _show_docker_titled(page_title, row)
    _on_category_selected(at, row)
    return true


## Whether Preferences counts as open.
##
## A window rolled up to its title bar by the frame's minimize button counts as
## open. That state is a smaller Preferences and not as a closed one, so a
## toggle that read it as closed would open a window that is already on screen
## and leave the painter pressing the chord twice to be rid of it.
##
## A window the OS has minimized counts as closed, for the mirror of the same
## reason: it is off the screen entirely, `visible` is still true because
## Godot's visibility and the window mode are different questions, and a toggle
## that read it as open would hide it and need a second press to bring it back.
func is_open() -> bool:
    return visible and not frame.is_os_minimized()


## Ctrl+comma and Edit > Preferences: opens the window, or closes it again when
## it is already open, the way a docker's chord has worked.
##
## *page* names a page to land on, and a request that names one always opens.
## Help > Keyboard Shortcuts is a request for that page rather than a request to
## flip the window, and answering it by closing Preferences would be absurd.
##
## *row* names a row on that page by its key, and the page opens scrolled to it
## with the row marked, the way a search marks one. A page opened at its top
## left the monitor's profile row 13 of 18 and below the fold, and the first
## chord of Keyboard Shortcuts at y 762 of 976.
func toggle(page: String = "", row: StringName = &"") -> void:
    if page.is_empty() and is_open():
        hide()
        return
    if not page.is_empty():
        show_page(page, row)
    # A minimized window is still `visible` to Godot, and both `hide` and
    # `popup_centered` carry `Window.mode` across the OS window they destroy and
    # build, so a reopen without this comes back minimized.
    frame.clear_os_minimize()
    popup_centered()


## Registers the ten through the public door and hands the registry back,
## making one when it is given none. [SaBuiltinPages] does it: this stays as
## the line a window, a door and a suite already call.
static func register_builtins(registry: SaUIRegistry) -> SaUIRegistry:
    return SaBuiltinPages.register_builtins(registry)


## The sidebar's pages in the order it draws them: group by group in
## `SaUIRegistry.SETTINGS_GROUPS`'s order, and in each the skeleton's own, then
## a module's, each in registration order. A module registers at boot and the
## ten on the first request for Preferences, so registration order alone would
## put a module's page above Interface.
static func _sidebar_entries(registry: SaUIRegistry) -> Array[Dictionary]:
    var entries: Array[Dictionary] = []
    for group: StringName in SaUIRegistry.SETTINGS_GROUPS:
        for own: bool in [true, false]:
            for entry: Dictionary in registry.list_settings_pages():
                if StringName(entry["group"]) == group and String(entry["module"]).is_empty() == own:
                    entries.append(entry)
    return entries


## The titles of [method _sidebar_entries], what `categories` holds.
static func _sidebar_titles(registry: SaUIRegistry) -> Array:
    return _sidebar_entries(registry).map(func(entry: Dictionary) -> String: return String(entry["title"]))


## The title the layout list of *category* is drawn under, or "" for a key
## nobody registered.
static func internal_title_for(category: String) -> String:
    for entry: Dictionary in SaSettings.reorderable_categories():
        if String(entry["id"]) == category:
            return String(entry["title"])
    return ""


## The SaSettings key behind a page title, or "" when the page is not one of the
## reorderable element lists. A docker's title answers its key too, so a door
## written while it had a page still finds its parts.
static func internal_category_for(page_title: String) -> String:
    for entry: Dictionary in SaSettings.reorderable_categories():
        if entry["title"] == page_title:
            return String(entry["id"])
    return ""


## The scroll container every Preferences page and the category list are drawn
## inside, with a wheel step that does not depend on how tall the window is.
##
## Godot's own `ScrollContainer` moves an eighth of a visible page per notch, so
## a few notches take a page from its first row to its last. An eighth of a page
## also means a wheel notch travels further the larger the window is, which is
## backwards: a bigger window should show more per notch, not move more per
## notch.
##
## A subclass rather than a property, because the rate is `page / 8` inside the
## engine's own handler and `ScrollBar.custom_step` does not reach it. The
## script's `_gui_input` runs before the C++ one and `accept_event()` stops it,
## which is what keeps the two rates from adding up.
class SaSettingsScroll:
    extends ScrollContainer

    ## Logical pixels per wheel notch, about three rows of the page's own text.
    const WHEEL_STEP: int = 48

    ## A touchpad's pan moves the page as far as the fingers moved, a logical
    ## pixel for every pixel of its delta, as [SaScrollPace] moves every other
    ## dialog's. A sideways notch is left to the engine.
    ##
    ## [SaScrollPace] leaves this container to this method, because the method
    ## is the script's own `_gui_input`.
    func _gui_input(event: InputEvent) -> void:
        var pan := event as InputEventPanGesture
        var moved := pan.delta.y if pan != null else SaStep.notches(event).y
        if moved == 0.0:
            return
        var bar := get_v_scroll_bar()
        if bar == null or not bar.is_visible_in_tree():
            return
        if pan != null:
            # A slow finger sends a fraction of a pixel, which is kept on the
            # bar, whose value is a float, rather than rounded away on every one
            # of a hundred events.
            bar.value += moved
        else:
            # A fraction of a notch stays a fraction instead of becoming a whole one.
            scroll_vertical += int(round(float(SaUI.px(WHEEL_STEP)) * moved))
        accept_event()
