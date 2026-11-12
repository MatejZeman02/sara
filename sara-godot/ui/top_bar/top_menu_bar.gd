## Single-row top menu bar combining main window menu bar and tool options.
##
## Highly configurable: sections can be toggled on/off (except main menu).
## Provides fixed top-right window controls (-, [], X).
##
## This file is the facade and the menus: the row of menu buttons with a list
## behind each, the order and visibility a profile gives them, and which sections
## show. The two rows and the placement of the tool option controls on them are
## `SaTopBarRows`, the window buttons `SaTopBarWindowButtons`, the rotation
## pair `SaTopBarRotation` and the last title, which holds the titles a narrow
## window has no room for, `SaTopBarMenuOverflow`, the right click menu and the
## Ctrl drag that arrange the bar on itself `SaTopBarArrange`, the ALT double
## click that opens the bar's line in Preferences `SaTopBarPageGesture`, and each
## owns what it holds.
##
## **The engine's `MenuBar` is gone and `menu_bar` is a plain `HBoxContainer` of `Button`s**. A `MenuBar` owns its
## `PopupMenu` children and opens them itself, so replacing the list meant replacing the bar as well. The member keeps
## its name because half a dozen files and as many tests ask the bar for it, and the two calls that were the engine's,
## `set_menu_hidden` and `set_menu_title`, are a button's `visible` and `text` now. `menus` holds one `SaChoicePopup`
## per menu, parented here rather than to the button, because a popup is a `Window` and a `Button` is not a place to
## keep one. What each menu holds lives in ui/menus/, one file per menu extending `SaMenu`, so a phase that fills the
## Layer menu edits layer_menu.gd and nothing here. The docker rows are the one exception, and they are not a menu of
## their own any more: `MainDockers` appends them into the Window menu, because the bar does not know the dockers.
extends PanelContainer

class_name TopMenuBar

signal section_visibility_changed(section_name: String, is_visible: bool)

var top_bar_style: StyleBoxFlat
## The two rows, which place the tool option controls, measure them and keep the
## second row when one would not hold them. The menus and the window buttons are
## this bar's, put on the first row around its slot.
var rows: SaTopBarRows
## The three window buttons, which sit at one end of the first row.
var window_buttons: SaTopBarWindowButtons
## The rotation slider and its reset button, which are row elements like every
## other and whose behaviour lives in `top_bar_rotation.gd`. Not `rotation`,
## which is a `Control` property this bar would be redefining.
var rotation_row := SaTopBarRotation.new()
## The Undo and Redo buttons, row elements as well, which run the Edit menu's
## commands through the registry `bind_commands` hands the menus.
var history_row := SaTopBarHistory.new()
## The Focus Mode button, a row element too, which runs the toggle Tab runs once
## main hands it over through [method bind_commands].
var focus_mode_row := SaTopBarFocusMode.new()

## The row of menu buttons, one per menu, in the profile's order. Named for what
## it replaced, because that is the name every caller already asks for.
var menu_bar: HBoxContainer
## Menu name -> the button that opens it.
var menu_buttons: Dictionary = {}
## The last title on the menu row, shown when a title does not fit, and the list
## it opens with the titles that did not.
var menu_overflow: SaTopBarMenuOverflow
## The bar arranged on itself: the right click menu on an element and the Ctrl
## drag that moves one, `arrange/top_bar_arrange.gd`.
var arrange: SaTopBarArrange
## ALT and a double click on the bar, which open its line in Preferences as the
## same gesture on a docker opens the docker's, `page_gesture/top_bar_page_gesture.gd`.
var page_gesture: SaTopBarPageGesture

## View-menu item id for the highlight tonemapper, kept here because a test
## reads it off the bar. `SaViewMenu` is where it is defined.
const VIEW_ID_TONEMAP: int = SaViewMenu.ID_TONEMAP

## The eleven, in the order the bar makes them. Preferences uses it to keep
## the menus reordering among themselves and never past the sentinel. The
## Display and Tablet pages are Help's rows rather than a Settings menu's, which
## would only take space on the bar.
const MENU_NAMES := ["File", "Edit", "View", "Window", "Image", "Layer", "Select", "Tools", "Filter", "Modules", "Help"]

## The key of the overflow switch among the bar's per-docker options, which
## Preferences > Layouts and dockers, the top bar section, writes.
const OVERFLOW_OPTION := SaTopBarOverflow.OPTION

## Menu name -> the `SaChoicePopup` its button opens, one per name in `MENU_NAMES`.
var menus: Dictionary = {}

## Menu name -> the process frame its list last went away in, or nothing for a
## list that has never hidden one. Read by the next press on that menu's title
## and spent by it, see `_on_menu_button_pressed`.
var _hidden_frames: Dictionary = {}

## Menu name -> the `SaMenu` filling it. Built once in `_ready` and kept, so a
## second `_ready` repopulates through the same objects and the same handlers
## rather than connecting a second set.
var _menu_objects: Dictionary = {}

var _sections: Dictionary = {}


## A menu's name in the painter's language. The words are read out of
## `MENU_NAMES`, so the template holds every one, and a name the list lacks
## stays as it is.
static func menu_title(menu_name: String) -> String:
    var at := MENU_NAMES.find(menu_name)
    return String(TranslationServer.translate(MENU_NAMES[at])) if at >= 0 else menu_name


func _init() -> void:
    name = "TopMenuBar"
    set_anchors_preset(Control.PRESET_TOP_WIDE)
    mouse_filter = MOUSE_FILTER_IGNORE

    top_bar_style = StyleBoxFlat.new()
    SaTheme.bind(top_bar_style, {"bg_color": "bg_primary", "border_color": "border_primary"})
    top_bar_style.border_width_bottom = 1
    top_bar_style.content_margin_left = float(DockerUtils.px(6))
    top_bar_style.content_margin_right = float(DockerUtils.px(6))
    top_bar_style.content_margin_top = float(DockerUtils.px(1))
    top_bar_style.content_margin_bottom = float(DockerUtils.px(1))
    add_theme_stylebox_override("panel", top_bar_style)


func _enter_tree() -> void:
    var root := get_tree().root
    if not root.window_input.is_connected(_on_window_input):
        root.window_input.connect(_on_window_input)


func _exit_tree() -> void:
    var root := get_tree().root
    if root.window_input.is_connected(_on_window_input):
        root.window_input.disconnect(_on_window_input)


## Built here rather than in `_ready`, so a bar handed its tool options before
## it is in the tree has its rows to put them on.
func _build() -> void:
    rows = SaTopBarRows.new(top_bar_style.content_margin_left, top_bar_style.content_margin_right, top_bar_style.bg_color)
    add_child(rows)
    var main_row := rows.main_row

    var hbox_menu_bar := SaMake.row(main_row, "HBoxMenuBar")
    hbox_menu_bar.size_flags_horizontal = SIZE_SHRINK_BEGIN
    hbox_menu_bar.size_flags_vertical = SIZE_SHRINK_CENTER
    main_row.move_child(hbox_menu_bar, 0)

    menu_bar = SaMake.row(hbox_menu_bar, "MenuBar", 2)
    menu_bar.size_flags_horizontal = SIZE_SHRINK_BEGIN
    menu_bar.size_flags_vertical = SIZE_SHRINK_CENTER
    menu_bar.custom_minimum_size = Vector2(0, DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2))

    for m_name: String in MENU_NAMES:
        _make_menu(m_name)

    # After the row of titles and not on it, so the profile's order and its
    # visibility, which walk that row, never take it for a menu.
    menu_overflow = SaTopBarMenuOverflow.new(menu_bar, title_box(false))
    menu_overflow.menu_asked.connect(_on_menu_button_pressed)
    hbox_menu_bar.add_child(menu_overflow)
    # The search's loupe, after the overflow title and off the titles row for the
    # same reason, so it stays at the row's end wherever Help is moved to.
    hbox_menu_bar.add_child(SaSearchWindow.loupe(title_box(false)))

    var vsep := SaMake.separator(main_row, "MenuSeparator", true)
    vsep.size_flags_vertical = SIZE_EXPAND_FILL
    var vsep_style := StyleBoxFlat.new()
    SaTheme.bind(vsep_style, {"bg_color": "border_primary"})
    vsep_style.expand_margin_top = float(DockerUtils.px(3))
    vsep_style.expand_margin_bottom = float(DockerUtils.px(3))
    vsep.add_theme_stylebox_override("separator", vsep_style)
    vsep.add_theme_constant_override("separation", DockerUtils.px(SaTheme.GAP_TIGHT))
    main_row.move_child(vsep, 1)

    window_buttons = SaTopBarWindowButtons.new()
    window_buttons.close_pressed.connect(_on_close_pressed)
    main_row.add_child(window_buttons)

    var second_row := rows.second_row
    arrange = SaTopBarArrange.new(
        menu_bar, menu_buttons, main_row, second_row, rows.elements, rows.row_container, _a_menu_is_open
    )
    add_child(arrange)
    page_gesture = SaTopBarPageGesture.new(_hide_menus)
    add_child(page_gesture)

    _sections = {
        "main_menu": main_row,
        "window_controls": window_buttons,
        "second_row": second_row,
    }


func add_tool_options(bar: ToolOptionsBar) -> void:
    if rows == null:
        _build()
    # The rotation pair belongs to this bar rather than to the tool options
    # builder, so it is parented here and ordered by the profile like the rest.
    rotation_row.attach(bar)
    SaToolOptionViews.register_controls(bar, rotation_row.elements(), rotation_row.view)
    # A tool registered after the bar was laid out brings new children, and
    # the stored order has to be applied to them too.
    if not bar.controls_changed.is_connected(apply_layout_settings):
        bar.controls_changed.connect(apply_layout_settings)
    var elements := rotation_row.elements().merged(SaTopBarEnvironment.home(bar))
    elements.merge(SaTopBarPageEdges.home(bar))
    elements.merge(SaTopBarDoubleResolution.home(bar))
    elements.merge(history_row.home(bar))
    elements.merge(focus_mode_row.home(bar))
    var groups := rotation_row.groups().merged(SaTopBarEnvironment.groups())
    groups.merge(SaTopBarPageEdges.groups())
    groups.merge(SaTopBarDoubleResolution.groups())
    groups.merge(SaTopBarHistory.groups())
    groups.merge(SaTopBarFocusMode.groups())
    rows.attach(bar, elements, groups)


func set_section_visible(section_name: String, vis: bool) -> void:
    if section_name == "main_menu":
        # Only the menu with the settings cannot be toggled off
        return
    if section_name == "tool_options":
        if rows.show_options(vis):
            section_visibility_changed.emit(section_name, vis)
        return
    if _sections.has(section_name):
        var node: Control = _sections[section_name]
        if node != null and node.visible != vis:
            node.visible = vis
            section_visibility_changed.emit(section_name, vis)


func is_section_visible(section_name: String) -> bool:
    if section_name == "tool_options":
        return rows.options_shown
    if _sections.has(section_name):
        var node: Control = _sections[section_name]
        if node != null:
            return node.visible
    return false


func _ready() -> void:
    if rows == null:
        _build()
    _populate_menus()
    # Each menu a view another docker can hold, through the door a module uses.
    SaMenuViews.register(MENU_NAMES, _on_menu_button_pressed)

    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    # The width a row has changes with the window, so the rows are laid out
    # again: the sliders grow into what is spare and the second row comes back
    # when the first cannot hold what the switch asked for. `fit_sliders` alone
    # would leave a bar widened past its one-row spend and narrowed back with no
    # overrun reported and the first row scrolling. Only
    # when the width moved, since the rows' own second row changes the height.
    var refit := rows.refit_if_moved
    if not resized.is_connected(refit):
        resized.connect(refit)
    apply_layout_settings()


## The titles in the locale set now. A title is the menu's English name
## through `tr()`, written when the bar is built and when a profile is applied,
## so a run begun in Czech kept Czech titles after a switch to English. The engine sends this on every change of locale, and
## `SaTranslationRegistry` when a catalogue of the locale comes or goes.
## Applying the layout writes them again and fits the rows to their new widths.
## The rows under a title need nothing, being built again before every open.
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        apply_layout_settings()


## Hands every popup to the class that knows what goes in it.
##
## Every menu the bar makes is in the table. A name missing from it would be
## left empty, and the docker rows are the Window menu's. A local rather than a const, because a
## dictionary of class references is not a constant expression to GDScript.
func _populate_menus() -> void:
    var menu_classes := {
        "File": SaFileMenu,
        "Edit": SaEditMenu,
        "View": SaViewMenu,
        "Window": SaWindowMenu,
        "Image": SaImageMenu,
        "Layer": SaLayerMenu,
        "Select": SaSelectMenu,
        "Tools": SaToolsMenu,
        "Filter": SaFilterMenu,
        "Modules": SaModulesMenu,
        "Help": SaHelpMenu,
    }
    for menu_name: String in menu_classes:
        var popup: SaChoicePopup = menus.get(menu_name)
        if popup == null:
            continue
        if not _menu_objects.has(menu_name):
            _menu_objects[menu_name] = _build_menu(menu_classes[menu_name], popup)
        _menu_objects[menu_name].populate()


## A menu is handed its popup, and View the two calls behind its section rows,
## which are the only thing a menu asks of the bar that the tree does not
## answer.
func _build_menu(menu_class: GDScript, popup: SaChoicePopup) -> SaMenu:
    if menu_class == SaViewMenu:
        return SaViewMenu.new(popup, is_section_visible, set_section_visible)
    return menu_class.new(popup)


## The object filling the named menu, or null for a menu nothing fills.
func menu(menu_name: String) -> SaMenu:
    return _menu_objects.get(menu_name)


func apply_layout_settings() -> void:
    if not menu_bar:
        return
    window_buttons.apply_settings()
    var order := SaSettings.get_layout_order("TopMenuBar")

    # 1. The buttons, in the profile's relative order
    var current_menu_idx := 0
    for element: String in order:
        var button: Button = menu_buttons.get(element)
        if button != null:
            menu_bar.move_child(button, current_menu_idx)
            current_menu_idx += 1

    # Visibility, and the title. The button's node name is the key a stored
    # profile holds and stays English, and its text is what the bar draws, so
    # the two part here.
    for i in menu_bar.get_child_count():
        var child := menu_bar.get_child(i) as Button
        if child == null:
            continue
        var m_name := String(child.name)
        child.visible = SaSettings.get_element_visible("TopMenuBar", m_name)
        child.text = menu_title(m_name)

    # 2. The tool option elements: which row, in what order, and whether shown.
    #   Everything after the sentinel goes to the second row when it is on, and
    #   to the middle of the first row when it is off. The controls keep their
    #   owner and their signals, only their parent moves.
    rows.refit()


## The bar in *root*'s tree, or null before there is one. What the three
## capture functions below report from.
static func _find(root: Window) -> TopMenuBar:
    for node in root.find_children("*", "PanelContainer", true, false):
        if node is TopMenuBar:
            return node as TopMenuBar
    return null


## What each row holds and where each of its children landed, for a capture.
## Static and taking the root, the shape every other block in the dump uses, so
## `sa_state_report.gd` needs one line rather than a lookup of its own.
static func capture_rows(root: Window) -> Dictionary:
    var bar := _find(root)
    if bar == null or bar.rows == null:
        return {}
    return {
        "row_1": bar.rows.row_report(1),
        "row_2": bar.rows.row_report(2),
        "second_row_setting": SaSettings.second_row,
        "second_row_shown": bar.rows.second_row.visible,
        "second_row_forced_by": bar.rows._second_row_forced_by,
        # The menu titles on the row and the ones behind its last title, with
        # the room the row had for them.
        "menus": bar.menu_overflow.report().merged({"room": bar.rows.menu_room()}),
        # How many layout passes the rows have made, so two captures either side
        # of a switch say how many it cost.
        "refits": bar.rows._refits,
        # An element lifted off the bar and the two the gap stands between.
        "arrange": bar.arrange.report(),
    }


## The rotation pair and what it costs the row it is on, for a capture.
static func capture_rotation(root: Window) -> Dictionary:
    var bar := _find(root)
    var out: Dictionary = bar.rotation_row.report() if bar != null and bar.rows != null else {}
    if out.is_empty():
        return out
    var bar_rows := bar.rows
    (
        out
        . merge(
            {
                "row": 2 if bar.rotation_row.slider.get_parent() == bar_rows.second_options_row else 1,
                "row_spent": bar_rows.row_spent(1),
                "row_budget": bar_rows.row_budget(1),
                "row_budget_2560": bar_rows.row_budget(1, 2560.0),
                # The second row's own, since that row is on for a fresh profile and
                # what row one does not spend, row two does.
                "row_spent_2": bar_rows.row_spent(2),
                "row_budget_2": bar_rows.row_budget(2),
            }
        )
    )
    return out


## The edge the window buttons sit at under *setting* on *os_name*, "left" or
## "right". A page that names what Automatic picks asks here rather than the
## buttons' own file, which is this package's inside.
static func window_button_side(setting: String, os_name: String) -> String:
    return SaTopBarWindowButtons.side_for(setting, os_name)


## The look the window buttons take under *setting* on *os_name*, "lights" or
## "icons", asked the same way.
static func window_button_style(setting: String, os_name: String) -> String:
    return SaTopBarWindowButtons.style_for(setting, os_name)


## The three window buttons as numbers, for a capture.
static func capture_window_buttons(root: Window) -> Dictionary:
    var bar := _find(root)
    return bar.window_buttons.report() if bar != null and bar.window_buttons != null else {}


## The frame a borderless main window lacks, laid under *bar*, see
## `SaTopBarWindowFrame`. A *live* one acts on the window Sara runs in.
static func window_frame(bar: Control, live: bool) -> CanvasLayer:
    return SaTopBarWindowFrame.new(bar, live)


## The main window's mode, place, size and kept state, for a capture.
static func capture_main_window(root: Window) -> Dictionary:
    return SaTopBarWindowFrame.capture_state(root)


## One menu: the button on the bar and the list it opens.
##
## The list is parented to this bar rather than to the button, so it is in the
## tree from the start and takes the window's scale through
## `SaChoicePopup.open_under`, which is `SaUI.apply_to_window` and therefore
## hard rule 7's one writer of the window scale.
func _make_menu(m_name: String) -> void:
    if menus.has(m_name):
        return
    # Searched whatever its length, so every menu on the bar carries the field
    # and a painter never has to know which ones are long, and keeps its rows.
    var popup := SaChoicePopup.new(true, false, true, true)
    popup.name = m_name + "Menu"
    add_child(popup)
    # The frame the list went away in, which the next press on the title has to
    # read against its own. See `_on_menu_button_pressed`.
    popup.popup_hide.connect(_on_menu_hidden.bind(m_name))
    # A press outside the list puts it away and goes no further, see
    # `_put_away_on`, and the canvas asks this group while the list is up.
    SaPutAway.join(popup)
    menus[m_name] = popup

    var button: Button = menu_buttons.get(m_name)
    if button == null:
        button = SaMake.button(menu_bar, m_name)
        # Not flat: a flat button never draws its normal box, and the normal box
        # is where the divider that parts one title from the next is drawn.
        button.focus_mode = Control.FOCUS_NONE
        # A title answers on the press, the way an `OptionButton` answers and
        # `SaDropdownButton` answers, because a popup closes on the press that
        # lands outside it: a title answering on the release answered after its
        # own menu had already gone, and opened it again.
        button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
        # No font scale meta, so the title is drawn at the interface's font size
        # like every other button on the bar. A scale of 11 / 20 would put File
        # and Edit at 55 percent of the preset dropdown beside them, since the
        # engine theme's 11 is its own smaller base and not a menu title being
        # half a label. The engine's MenuBar draws its titles with
        # almost no padding, and a `Button` draws its own box, so the three
        # states are given one with the same margins the bar had, drawing only
        # the divider, and the hover box is what says the pointer is on a menu.
        var compact := title_box(m_name != MENU_NAMES[MENU_NAMES.size() - 1])
        for state: String in ["normal", "pressed", "focus"]:
            button.add_theme_stylebox_override(state, compact)
        menu_buttons[m_name] = button
    button.text = tr(m_name)
    if not button.pressed.is_connected(_on_menu_button_pressed):
        button.pressed.connect(_on_menu_button_pressed.bind(m_name))


## The box a menu title is drawn in, the margins the engine's `MenuBar` gave its
## titles, so the hover box is what says the pointer is on one.
##
## *divided* draws a 1 pixel line in `border_primary` down the title's right
## edge, which is what says at rest where one title ends and the next begins.
## The line sits inside the 4 units of right margin the title already had, so
## the box is exactly as wide as before and no title is folded for it. The
## last title and the overflow title take none, and read as the row's end.
static func title_box(divided: bool = true) -> StyleBox:
    if not divided:
        var compact := StyleBoxEmpty.new()
        _margin(compact)
        return compact
    var line := StyleBoxFlat.new()
    line.draw_center = false
    line.border_width_right = maxi(1, DockerUtils.px(1))
    # Pulled in from the title's top and bottom, so the line is a tick between
    # two words and not a wall the height of the bar.
    line.expand_margin_top = -float(DockerUtils.px(5))
    line.expand_margin_bottom = -float(DockerUtils.px(5))
    SaTheme.bind(line, {"border_color": "border_primary"})
    _margin(line)
    return line


## The margins every title box has, which are what the row's width is made of.
static func _margin(box: StyleBox) -> void:
    box.content_margin_left = float(DockerUtils.px(4))
    box.content_margin_right = float(DockerUtils.px(4))
    box.content_margin_top = float(DockerUtils.px(1))
    box.content_margin_bottom = float(DockerUtils.px(1))


## Opens one menu under its own button, built from scratch first.
##
## Rebuilt on every open rather than kept and patched by `about_to_popup`
## handlers: a row carries its state as an argument, so the state is right
## exactly when the list is made.
##
## **A press that arrives just after its own list hid is the close, not an
## open.** A popup closes itself on the press that lands outside it, so the same
## press that reaches the title has already hidden the menu behind it, and
## `popup.visible` alone read false every time and reopened the list. The frame
## the list went away in is what carries the close across the two: a press that
## finds its menu closed in that frame is that same close. It is the rule
## `SaDropdownButton` holds for every dropdown in Sara, kept apart rather than
## shared because a dropdown remembers one list on one button where the bar
## remembers twelve, and because the record here is spent by the press that
## reads it. Spending it is what leaves the next press a press: a menu closed
## this frame still opens on the press after the one that closed it.
##
## *beside* is a view of the menu placed in another docker, which the list opens
## beside rather than under the title. `SaMenuViews` is handed this function as
## the one way a view opens it.
func _on_menu_button_pressed(m_name: String, beside: Control = null) -> void:
    var popup := menus.get(m_name) as SaChoicePopup
    if popup == null or menu_buttons.get(m_name) == null:
        return
    var was_open := popup.visible
    _hide_menus()
    if was_open:
        # This press is the close. The hide it just asked for is its own, so
        # nothing is left for a press later in the frame to answer.
        _hidden_frames.erase(m_name)
        return
    if _take_hidden_frame(m_name):
        return
    _show_menu(m_name, beside)


## Every menu and the last title's list go away. A `MenuBar` closed the one that
## was up when the pointer reached another title, and a `PopupPanel` opened
## beside its sibling instead: the first run of the menu scenario photographed
## four menus on screen at once.
func _hide_menus() -> void:
    for other_name: String in menus:
        var other := menus[other_name] as SaChoicePopup
        if other != null and other.visible:
            other.hide()
    menu_overflow.list.hide()


## Fills *m_name*'s list and opens it under its title, or beside *beside*, a
## view of it in a docker. A title a narrow window folded has no place on the
## row, so its menu opens under the last title, which is where the painter
## pressed for it.
func _show_menu(m_name: String, beside: Control = null) -> void:
    var filler := _menu_objects.get(m_name) as SaMenu
    if filler != null:
        filler.populate()
    var button: Control = menu_overflow if menu_overflow.folded.has(m_name) else menu_buttons[m_name]
    (menus[m_name] as SaChoicePopup).open_under(beside if beside != null else button)


## Whether a menu is open, which is the one time the pointer on a title means
## anything: a list of the last title's counts as a menu.
func _a_menu_is_open() -> bool:
    if menu_overflow.list.visible:
        return true
    for popup: SaChoicePopup in menus.values():
        if popup.visible:
            return true
    return false


## A menu bar hands the open menu to the title the pointer moves onto, and closes
## it on a press anywhere else, and Sara's bar of buttons does both here, on the
## root window's input.
##
## **Heard at the window and not on the titles.** An open list is a focused
## embedded window, so every motion goes to it and a title never sees the
## pointer arrive, the reason `MainCanvas._on_window_input` listens here as well.
## The window emits `window_input` before it forwards the event, and the point
## it carries is the window's own, so it is taken to the logical space the rects
## are measured in. With no menu open nothing is done, so a pointer crossing the
## bar opens nothing.
func _on_window_input(raw: InputEvent) -> void:
    var is_motion := raw is InputEventMouseMotion
    if not (is_motion or SaPutAway.is_press(raw)) or not _a_menu_is_open():
        return
    var root := get_tree().root
    var moved := raw.xformed_by(root.get_final_transform().affine_inverse())
    if is_motion:
        _hand_over_to((moved as InputEventMouseMotion).position)
        return
    var mouse := moved as InputEventMouse
    _put_away_on(raw, mouse.position if mouse != null else (moved as InputEventScreenTouch).position)


## Closes every menu on *press*, a press at *at* on no title and in no open
## list, and names it in `SaPutAway`, so the canvas it landed on takes none of
## it and the press that closes a menu paints no stroke.
##
## **Here and not left to the engine**, which closes an embedded list on a left
## press outside it and on no other button, and a frame later. A desktop menu bar
## closes on any press, and a list that stayed up under a right press on the
## canvas had the Brush Presets docker open beside it. A press on a title is the
## title's own, which closes or swaps the menu as `_on_menu_button_pressed`
## says, and a press in a list, a child list included, is the list's.
func _put_away_on(press: InputEvent, at: Vector2) -> void:
    if _title_under(at) != null or _list_at(at):
        return
    _hide_menus()
    SaPutAway.put_away(press)


## The title of the row under *at*, the last one included, or null.
func _title_under(at: Vector2) -> Button:
    var titles: Array = [menu_overflow]
    titles.append_array(menu_buttons.values())
    for title: Button in titles:
        if title.is_visible_in_tree() and title.get_global_rect().has_point(at):
            return title
    return null


## Whether an open list embedded in the main window is under *at*, a list
## opened beside one included. A list that is a window of its own never is,
## since a press on it is not the main window's.
##
## **A child list is asked for by name**, because the walk from the root stops
## at a window and a filter section's list is a child of the Filter menu's.
## Judged outside every list, a press on a filter's row would close both lists
## before the row heard it.
func _list_at(at: Vector2) -> bool:
    for window in SaCursorPolicy.embedded_subwindows(get_tree().root):
        if window is Popup and _list_or_child_covers(window, at):
            return true
    return false


## Whether *list* or a list open beside it, and beside that one in turn, covers
## *at*. A child list is embedded in the same viewport as the list it hangs
## from, so its place is measured in the same space.
static func _list_or_child_covers(list: Window, at: Vector2) -> bool:
    var shown: Window = list
    while shown != null:
        if shown.visible and Rect2(Vector2(shown.position), Vector2(shown.size)).has_point(at):
            return true
        var choice := shown as SaChoicePopup
        shown = choice.child_list if choice != null and choice.has_open_child() else null
    return false


## Opens the menu of the title at *at*, as a press on it would, unless that
## title's menu is the one open. The close a press may be reading, see
## `_on_menu_button_pressed`, is not a hover's to read: a title the pointer
## returns to in the frame its menu went away in opens it again.
func _hand_over_to(at: Vector2) -> void:
    var title := _title_under(at)
    if title == null:
        return
    if title == menu_overflow:
        if not menu_overflow.list.visible:
            _hide_menus()
            menu_overflow.open_list()
        return
    var m_name := menu_buttons.find_key(title) as String
    if not (menus[m_name] as SaChoicePopup).visible:
        _hide_menus()
        _show_menu(m_name)


## Whether *m_name*'s list went away in the frame that is running now, which is
## the one question a press has to ask before it opens the list again.
##
## The answer is spent by the asking, because the press that reads it is the
## close it is about: a record that outlived its press would hold a menu shut
## for the rest of the frame it closed in.
func _take_hidden_frame(m_name: String) -> bool:
    var at: int = _hidden_frames.get(m_name, -1)
    _hidden_frames.erase(m_name)
    return at == Engine.get_process_frames()


## The frame a menu's list went away in, for the guard above.
func _on_menu_hidden(m_name: String) -> void:
    _hidden_frames[m_name] = Engine.get_process_frames()


func _on_close_pressed() -> void:
    # The same request the window manager's own close button sends, so main can
    # ask about unsaved work before it quits.
    get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)


## Points every menu at the command registry, so a command entry's chord comes
## from the registry rather than a string the menu wrote by hand, and a module's
## own actions reach the Modules menu specifically. The Undo and Redo buttons
## take it as well, to run the menu's commands, and the Focus Mode button takes
## *focus_toggle*, the toggle Tab runs. Called by main once the registries
## exist, which is after _ready.
func bind_commands(registry: SaCommandRegistry, focus_toggle: Callable = Callable()) -> void:
    history_row.bind(registry)
    focus_mode_row.bind(focus_toggle)
    for menu_name: String in _menu_objects:
        (_menu_objects[menu_name] as SaMenu).bind_commands(registry)


## The two handlers `ui/top_bar/tests/test_top_menu_bar.gd` reaches through the bar. They
## forward to the menu that owns the item, and exist only so the suite that
## predates the split passes unchanged.
func _on_view_menu_id_pressed(id: int) -> void:
    menu("View").on_id_pressed(id)


func _on_modules_menu_id_pressed(id: int) -> void:
    menu("Modules").on_id_pressed(id)
