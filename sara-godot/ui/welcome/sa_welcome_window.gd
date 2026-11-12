## The window a painter meets before any brush: a painted picture across its
## top, then the recent documents under New and Open, the news, the tips and
## the quick settings, with the switch that keeps it from the start under them.
##
## This class is the window, the boot decision and what New and Open do,
## which the Recent pane lays out at its top. The four
## panes exist and are named, and what each of them holds belongs to the pane's
## own class, and the picture is `WelcomePicture`'s.
##
## **The window is taller by the band**: it opens at 720 wide and 480
## high under a band 240 tall, and its floor is 520 wide and 360 under a band 174
## tall, both measured at their widths, and the band's own height follows the
## window's width from there. A press on the band is a press on the window, so it
## leaves it up as a press on a pane does.
##
## **The three refusals the boot has to make live in `wanted_at_start`**, one
## static, because the committed scenarios photograph the main window at boot and
## a window over it would change every one of them. A document named on the
## command line is refused too: that painter asked for that document.
##
## **`SaBoot` builds this window before the rest of Sara exists**, so a
## window built with *booting* true draws New, Open and the recent documents
## disabled and dimmed until `EventBus.boot_finished`. A recent document chosen
## while dimmed is held by its grid and opened once the boot is done.
##
## **On Sara's very first launch it opens on Quick settings**,
## and on Recent at every launch after. The boot reads
## `SaSettings.first_launch_done` and builds the window with *first_launch*,
## and the window turns that true once it has been shown on the pane, so a
## launch that fails before the window is seen asks again.
##
## **A press outside it puts it away, as Blender's splash does**. While it
## is up it hears the main window and every docker, and a press on either
## closes it: on the canvas, on the bar, on a docker, and on the main window
## when subwindows are not embedded, which is where such a press lands. A press
## on the window itself, or on another window of Sara's that is not a docker,
## a dialog, a picker or a list, leaves it up, so Cancel in New Document or in
## the picker its own buttons opened comes back to it. A press on a title of
## the bar or on a docker goes on to what it landed on, so one press both closes
## this and opens a menu. A press on the canvas closes this and goes no further,
## its drag and its release with it, because a click out of a dialog or this
## window should not paint. The window names the press it went away on in `SaPutAway`, which is
## where the canvas asks.
@tool
class_name SaWelcomeWindow
extends SaDialogWindow

## The window without its band, at the width the band is measured at: the size it
## opens at and the floor it is dragged down to.
const PANES_SIZE := Vector2i(720, 540)
const PANES_MIN_SIZE := Vector2i(520, 360)

## The four panes in tab order and the switch, so a test or a scenario reads
## what the window built rather than walking it by name.
var tabs: TabContainer
var recent_pane: WelcomeRecentPane
var news_pane: WelcomeNewsPane
var tips_pane: WelcomeTipsPane
var quick_settings_pane: WelcomeQuickSettingsPane
var show_at_start: CheckButton

## The line for a painter who has never painted, between the panes and the
## switch at the foot, which only the first launch's window draws. Null in every other.
var beginner_line: WelcomeBeginnerLine

## The painted band across the top, above the light mode offer and the panes.
var band: WelcomePicture

## The offer of the light mode to a weak GPU, above the panes.
## It takes no height unless the offer is due, which it is once at most.
var light_mode_offer: SaLightModeOffer

## Hears the presses beside this window that put it away while it is up.
var _put_away := PressElsewhere.new()

## The main window's rectangle `open` last centred this window on, in the space
## its `position` is measured in, so a main window that changes size afterwards
## takes the window along unless the painter has moved it.
var _centred_on: Rect2i = Rect2i()

## Every word the window draws outside its panes, `[node, property, English]`
## apiece, so a change of language writes each again. A word with a context
## carries it as a fourth item.
var _words: Array[Array] = []


## *booting* is true for the window `SaBoot` shows while the boot goes on, and
## *first_launch* for the one shown on the profile's first launch, which opens
## on the Quick settings pane.
func _init(booting: bool = false, first_launch: bool = false) -> void:
    var opening := Vector2i(PANES_SIZE.x, PANES_SIZE.y + WelcomePicture.band_height(PANES_SIZE.x))
    var floor_size := Vector2i(PANES_MIN_SIZE.x, PANES_MIN_SIZE.y + WelcomePicture.band_height(PANES_MIN_SIZE.x))
    _init_dialog("WelcomeWindow", tr("Welcome to Sara"), opening, floor_size)
    SaPutAway.join(self)
    # A name of its own, because the base calls every dialog's close button
    # "CloseButton" and a scenario aims at a control by name.
    close_button.name = "WelcomeClose"
    # The shared theme before the panes are built rather than in the base's
    # `_ready`, so the window enters the tree in it and no control in it is
    # told the theme changed and measured again.
    adopt_shared_theme()

    # The band runs edge to edge, so it is above the margin the panes keep and
    # not in it.
    var frame := SaMake.column(content, "Frame", 0)
    frame.set_anchors_preset(Control.PRESET_FULL_RECT)
    band = WelcomePicture.new()
    frame.add_child(band)
    var margin := SaMake.margin(frame, "Margin", SaTheme.PAD)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var column := SaMake.column(margin, "Column", 10)

    light_mode_offer = SaLightModeOffer.new()
    column.add_child(light_mode_offer)

    tabs = TabContainer.new()
    tabs.name = "Panes"
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # The panes sit straight in the tab panel, and its box keeps no room between
    # its border and what it holds, so a pane's title stood on the border. The
    # panel keeps the margin the window keeps round its panes, and this window's
    # panel alone: the table's box stays the engine's margin for every other
    # tab container.
    tabs.add_theme_stylebox_override("panel", SaThemeFrames.frame("page", SaTheme.PAD))
    column.add_child(tabs)

    recent_pane = WelcomeRecentPane.new(booting)
    news_pane = WelcomeNewsPane.new(true)
    tips_pane = WelcomeTipsPane.new()
    quick_settings_pane = WelcomeQuickSettingsPane.new()
    # The band takes the room the rows under it leave, and a tab container
    # measures only the pane in front, so a band on top of panes of different
    # minimum heights was a different height on each and jumped at every change
    # of tab. Every pane but Recent scrolls inside its tab, Quick settings by
    # itself and News and Tips in a scroll the window puts them in, and each of
    # those tabs is held at Recent's minimum height, the one that keeps New and
    # Open on screen, so the panes measure alike whichever is in front. Not by
    # measuring the hidden tabs, because a container out of sight is not laid
    # out, its wrapping text read thousands of lines tall and Quick settings'
    # rows widened the window.
    tabs.add_child(recent_pane)
    tabs.add_child(_scrolled(news_pane))
    tabs.add_child(_scrolled(tips_pane))
    tabs.add_child(quick_settings_pane)
    recent_pane.minimum_size_changed.connect(_hold_the_panes_to_recent)
    _hold_the_panes_to_recent()
    # The tab title a painter reads is the child's node name, so it is said here
    # through `tr` rather than left as an internal name that only looks like a
    # word: "QuickSettings" is the node, "Quick settings" is the tab.
    tabs.set_tab_title(0, tr("Recent"))
    tabs.set_tab_title(1, tr("News"))
    tabs.set_tab_title(2, tr("Tips"))
    tabs.set_tab_title(3, tr("Quick settings"))
    # Through the tab bar, because a `TabContainer` out of the tree only notes
    # a `current_tab` for its ready and reads back the first tab until then,
    # where its bar takes the tab at once and the container follows it.
    if first_launch:
        tabs.get_tab_bar().current_tab = tabs.get_tab_idx_from_control(quick_settings_pane)

    if first_launch:
        beginner_line = WelcomeBeginnerLine.new()
        column.add_child(beginner_line)
        beginner_line.refresh()

    var buttons := SaMake.row(column, "Buttons", SaTheme.GAP)
    var new_button := recent_pane.new_button
    var open_button := recent_pane.open_button
    var open_a_file := recent_pane.open_a_file
    var new_tip := "A fresh document, at the size, depth and colour space you pick"
    var open_tip := "Open a Sara document (.sad) or a picture."
    (
        _words
        . append_array(
            [
                [new_button, &"text", "New"],
                [new_button, &"tooltip_text", new_tip],
                [open_button, &"text", "Open", "open a document"],
                [open_button, &"tooltip_text", open_tip],
                [open_a_file, &"text", "Open a file"],
                [open_a_file, &"tooltip_text", open_tip],
            ]
        )
    )
    # Straight down the bus, which is the door the File menu's own New row uses,
    # so the dialog behind it is the one there is rather than a second one.
    new_button.pressed.connect(func() -> void: EventBus.new_document_requested.emit())
    default_button = new_button
    first_focus = new_button
    open_button.pressed.connect(_on_open_pressed)
    open_a_file.pressed.connect(_on_open_pressed)
    # Nothing answers the three until `Main` has wired the File menu and
    # `MainDialogs`, so they wait for the boot rather than press into nothing.
    if booting:
        var held: Array[Button] = [new_button, open_button, open_a_file]
        for button in held:
            button.disabled = true
        # A method of this window rather than a lambda, so a window freed before
        # the boot ends lets go of the bus. A lambda would stay connected and
        # write to freed buttons.
        EventBus.boot_finished.connect(_release.bind(held), CONNECT_ONE_SHOT)
        EventBus.boot_finished.connect(come_forward, CONNECT_ONE_SHOT)

    var spacer := Control.new()
    spacer.name = "Spacer"
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(spacer)

    # A switch with its words on its left, the shape of every on or off row of a
    # page, rather than a check box whose own word sat in its box. Checked, that
    # box drew a bordered bar round the words.
    var at_start := SaMake.label(buttons, "ShowAtStartLabel", tr("Show this at start"))
    at_start.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    show_at_start = SaMake.switch(buttons, "ShowAtStart", "", SaSettings.welcome_at_start)
    show_at_start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    show_at_start.tooltip_text = tr("Open this window whenever Sara starts with no document.")
    (
        _words
        . append_array(
            [
                [at_start, &"text", "Show this at start"],
                [show_at_start, &"tooltip_text", "Open this window whenever Sara starts with no document."],
            ]
        )
    )
    show_at_start.toggled.connect(func(pressed: bool) -> void: SaSettings.welcome_at_start = pressed)
    # The window is built once and shown again, so the switch is read back on every
    # open rather than only at construction: a profile written while it was
    # hidden, by a scenario or by a later Preferences row, is what it shows.
    # Assigning `button_pressed` announces nothing, so this is not a write.
    visibility_changed.connect(_on_shown)
    # A `Window` joins the tree already visible, and a show that changes
    # nothing announces nothing, so the boot's window starts hearing here.
    tree_entered.connect(_on_shown)
    tree_exiting.connect(_put_away.stop_hearing)
    tree_entered.connect(_follow_the_main_window_from_here)
    tree_exiting.connect(_stop_following_the_main_window)


## The window's own words read again in the language set now: its title, the
## tab titles, New, Open, Open a file and the switch. The engine sends this on every
## change of locale, and `SaTranslationRegistry` when a catalogue of it comes
## or goes. The panes follow on the same notification, each by itself.
func _notification(what: int) -> void:
    if what != NOTIFICATION_TRANSLATION_CHANGED or tabs == null:
        return
    title = tr("Welcome to Sara")
    var words := drag_handle.find_child("TitleLabel", true, false) as Label if drag_handle != null else null
    if words != null:
        words.text = title
    var titles := ["Recent", "News", "Tips", "Quick settings"]
    for index in titles.size():
        tabs.set_tab_title(index, tr(titles[index]))
    # A fourth item is the word's context, which "Open" carries, so the word
    # is read again under the entry it was first read under.
    for said: Array in _words:
        var context := StringName(said[3]) if said.size() > 3 else &""
        (said[0] as Object).set(said[1], tr(String(said[2]), context))


## The tab that holds *pane*, which is *pane* itself or the scroll the window
## put it in, for a pane that brings itself to the front.
static func tab_of(pane: Control) -> Control:
    var wrapper := pane.get_parent() as ScrollContainer
    if wrapper != null and wrapper.get_parent() is TabContainer:
        return wrapper
    return pane


## Holds every tab but Recent's at Recent's minimum height, so the band over
## them is one height whichever is in front.
func _hold_the_panes_to_recent() -> void:
    var floor_height := recent_pane.get_combined_minimum_size().y
    for tab: Node in tabs.get_children():
        var held := tab as Control
        if held != null and held != recent_pane and not is_equal_approx(held.custom_minimum_size.y, floor_height):
            held.custom_minimum_size.y = floor_height


## *pane* in a scroll of its own, so its minimum height is not the tab's.
func _scrolled(pane: Control) -> ScrollContainer:
    var wrapper := ScrollContainer.new()
    wrapper.name = "%sScroll" % pane.name
    wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
    wrapper.add_child(pane)
    return wrapper


## Lists *registry*'s languages in the Quick settings pane, and reads its
## modules' notes in the News pane, from now on. `MainDialogs` hands it in,
## since the boot builds this window first.
func follow_catalogues(registry: SaTranslationRegistry) -> void:
    quick_settings_pane.follow_catalogues(registry)
    news_pane.follow_catalogues(registry)


## Notes that the first launch's window has been seen, once *shown* and the
## Quick settings pane is in front, and never before: a launch that fails
## before the window is up asks again. Written once in a profile's life, so a
## window shown on the pane later writes nothing.
func remember_first_launch(shown: bool) -> void:
    if shown and not SaSettings.first_launch_done and tabs.current_tab == tabs.get_tab_idx_from_control(quick_settings_pane):
        SaSettings.first_launch_done = true


## The boot is done, and New, Open and Open a file have something to open into.
func _release(held: Array) -> void:
    for button: Button in held:
        button.disabled = false


## In front of every docker, when this window is up.
##
## The boot shows this window first and the dockers after it, so an embedded
## docker stacked above it: on a 1280 by 1024 screen the Tool Options covered
## its left edge, part of the recovery row and the Open button. Focus is what
## raises an embedded window to the top of its host's stack.
func come_forward() -> void:
    if visible and is_inside_tree():
        grab_focus()


## Shows this window centred on the main window, which is the one way the boot
## and Help > Welcome open it.
##
## `popup_centered` alone was not enough, twice. A window that is its own OS
## window is centred on the screen rather than on the main window, and on every
## show after the first it is a new OS window whose position is read back as
## (0, 0), so the second open stood in the host's top-left corner. The boot's
## copy is centred on a main window that has not taken its final size yet, and
## stayed where that smaller or larger window had its middle. The show is still
## `popup_centered`'s, for the focus and the stacking it does, and the position
## is written after it.
func open() -> void:
    popup_centered()
    centre_on_main()


## Puts this window in the middle of the main window as it is now.
func centre_on_main() -> void:
    _centred_on = main_rect()
    position = centred_in(_centred_on, size)


## The main window's rectangle in the space this window's `position` is
## measured in: the visible rectangle of the viewport it is embedded in, which
## is what `popup_centered` centres on, and the main window on the screen when
## not. The engine keeps `get_embedder` from scripts, and the embedder is the
## viewport the parent stands in.
func main_rect() -> Rect2i:
    if is_embedded():
        return Rect2i(get_parent().get_viewport().get_visible_rect())
    var main := get_tree().root
    return Rect2i(main.position, main.size)


## Where a window of *window_size* stands to have its middle on *host*'s.
static func centred_in(host: Rect2i, window_size: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return host.position + Vector2i((host.size.x - window_size.x) / 2, (host.size.y - window_size.y) / 2)


func _follow_the_main_window_from_here() -> void:
    var main := get_tree().root
    if not main.size_changed.is_connected(follow_the_main_window):
        main.size_changed.connect(follow_the_main_window)


func _stop_following_the_main_window() -> void:
    var main := get_tree().root
    if main.size_changed.is_connected(follow_the_main_window):
        main.size_changed.disconnect(follow_the_main_window)


## Centres this window again on a main window that changed size while it was
## up, when it still stands where `open` put it. One pixel is allowed either
## way, because the fit after a show grows it by half of an odd number at
## times. The place the engine pushes an embedded window to, inside a host that
## shrank under it, counts as where `open` put it too. A window the painter
## dragged elsewhere stays where it was put.
##
## Public because a suite calls it: the signal is the main window's, and a
## suite's main window is the test runner's.
func follow_the_main_window() -> void:
    if not visible or not is_inside_tree() or _centred_on.size == Vector2i.ZERO:
        return
    var placed := centred_in(_centred_on, size)
    var main := main_rect()
    var pushed := placed.clamp(main.position, main.position.max(main.end - size))
    if _near(position, placed) or _near(position, pushed):
        centre_on_main()


static func _near(a: Vector2i, b: Vector2i) -> bool:
    var apart := (a - b).abs()
    return apart.x <= 1 and apart.y <= 1


## Re-read the preference a painter changed while this window was hidden, and
## start or stop hearing the presses that put it away.
func _on_shown() -> void:
    if visible and show_at_start != null:
        show_at_start.button_pressed = SaSettings.welcome_at_start
    if visible and is_inside_tree():
        remember_first_launch(true)
        _put_away.hear(self)
        return
    _put_away.stop_hearing()
    # A window put away while the boot runs takes the card chosen in it along.
    if not visible and recent_pane != null:
        recent_pane.drop_held_choice()


## Whether a press at *at* on the main window, in the logical space its
## embedded subwindows are placed in, falls outside every one of *embedded*
## that is not a docker. This window is among them when it is embedded, and so
## is a dialog, a picker or a list, and none of those is outside. Static and
## handed the windows, so a suite asks it without a display server.
static func press_closes(at: Vector2, embedded: Array[Window]) -> bool:
    for window in embedded:
        if window is DockerWindow or not window.visible:
            continue
        var rect := Rect2(Vector2(window.position), Vector2(window.size))
        # Godot draws the title bar of a bordered embedded window above its
        # position. Sara's own windows are borderless and have none.
        if not window.borderless:
            var bar := float(window.get_theme_constant("title_height"))
            rect = rect.grow_side(SIDE_TOP, bar)
        if rect.has_point(at):
            return false
    return true


## Every docker under *node*, shown or not. The engine walks the tree for the
## windows, because a walk of every node in script took 3.7 ms of each opening.
static func dockers_under(node: Node) -> Array[Window]:
    var found: Array[Window] = []
    for child in node.find_children("*", "Window", true, false):
        if child is DockerWindow:
            found.append(child)
    return found


## The Open button, run through the document flow's own picker rather than a
## second one: the call File > Open makes, so the unsaved-changes prompt, the
## file filter and the import all come with it. A picker built here would be a
## second place the prompt could be forgotten.
##
## The window goes away once a file has landed, and not before, so a
## cancelled picker, a cancelled prompt or a file that would not load leaves it
## up. Heard on the flow rather than on the picker, because a picture asks for
## its depth after the picker has closed. Once heard, a drop or a recent card
## puts it away too, as a document opened puts Blender's splash away.
func _on_open_pressed() -> void:
    var files := SaDocumentFiles.in_tree(get_tree()) if is_inside_tree() else null
    if files == null:
        return
    if not files.document_opened.is_connected(_on_document_opened):
        files.document_opened.connect(_on_document_opened)
    files.open_with_dialog()


func _on_document_opened(_path: String) -> void:
    hide()


## Whether the boot opens this window, and the one place its refusals live.
##
## Static and handed its four facts rather than reading them, so a test asks
## every answer without a display server, a document or a `Main`. *setting* is
## `SaSettings.welcome_at_start`, *document_path* is what `SaBoot.document_path` found
## on the command line, and the other two are the runs a window may not cover.
static func wanted_at_start(setting: bool, document_path: String, is_capture: bool, is_test_environment: bool) -> bool:
    if not setting or is_capture or is_test_environment:
        return false
    return document_path.is_empty()


## Reads ahead the parts of the picture the window's next opening may show, a
## frame at a time once Sara has settled, so the first opening of a window
## built on Help's ask only blends them. `MainDialogs` calls it when it wires
## the window's door.
static func read_ahead() -> void:
    WelcomePicture.read_ahead()


## Keeps a picture of the document on *easel* for its card, as it closes. The
## flows that put another document in its place call this just before they do,
## and `WelcomePreviewCache.keep_closing` says when a picture is taken. Here
## rather than there because the cache is private to this window's folder,
## and a close happens whether or not the window was ever built.
static func keep_closing_picture(easel: SaEasel) -> bool:
    return WelcomePreviewCache.keep_closing(easel)


## The window's layout for the state dump: its logical size, the band's height,
## the feedback request block's and the News scroll's, all in logical units. A shot shows the
## change log is short and cannot say by how much, nor where the room went.
## Empty when no welcome window is up.
static func layout_state(root: Window) -> Dictionary:
    var window := root.find_child("WelcomeWindow", true, false) as SaWelcomeWindow
    if window == null or not window.visible:
        return {}
    var scroll := window.news_pane.find_child("NewsScroll", true, false) as Control
    var ask := window.news_pane.find_child(WelcomeNewsPane.ASK_BLOCK, true, false) as Control
    return {
        "window": SaReportShapes.vec(window.get_visible_rect().size),
        "band": window.band.size.y,
        "ask": ask.size.y,
        "news_scroll": scroll.size.y if scroll.is_visible_in_tree() else 0.0,
        "three_notes": three_notes_tall(scroll),
        "maximised": SaDockerMaximise.is_maximised(window),
    }


## How far down the scroll's column the newest section's third note ends, which
## is what the opening size is measured against. Zero for a section of fewer.
static func three_notes_tall(scroll: Control) -> float:
    var rows := scroll.find_child("Rows", true, false) as Container
    if rows == null or rows.get_child_count() < 3:
        return 0.0
    var third := rows.get_child(2) as Control
    return third.get_global_rect().end.y - scroll.find_child("NewsSections", true, false).get_global_rect().position.y


## A dialog put away on a press elsewhere, as this window and [SaLocalServerDialog]
## are. It hears the main window and every docker built before the show, hidden
## ones included, since a docker is shown and hidden rather than built again.
class PressElsewhere:
    extends RefCounted

    ## Each window heard with its callable, so a hide lets go of exactly those.
    var _heard: Dictionary = {}

    func hear(dialog: Window) -> void:
        # A window joining the tree shown is told twice in one frame, and the
        # walk for the dockers took 2.7 ms of each.
        if not _heard.is_empty():
            return
        var root := dialog.get_tree().root
        var windows: Array[Window] = [root]
        windows.append_array(SaWelcomeWindow.dockers_under(root))
        for window in windows:
            if not _heard.has(window):
                _heard[window] = _on_press.bind(window, dialog)
                window.window_input.connect(_heard[window])

    func stop_hearing() -> void:
        for window: Window in _heard:
            if is_instance_valid(window) and window.window_input.is_connected(_heard[window]):
                window.window_input.disconnect(_heard[window])
        _heard.clear()

    ## A window emits `window_input` before an embedded subwindow of it, so the
    ## main window hears a press on the dialog and on any dialog beside it too,
    ## which [method SaWelcomeWindow.press_closes] tells from a press elsewhere,
    ## in the space the embedded windows are placed in. `SaPutAway` names it.
    func _on_press(event: InputEvent, heard: Window, dialog: Window) -> void:
        if not dialog.visible or not SaPutAway.is_press(event):
            return
        if heard == dialog.get_tree().root:
            var moved := event.xformed_by(heard.get_final_transform().affine_inverse())
            var mouse := moved as InputEventMouse
            var at := mouse.position if mouse != null else (moved as InputEventScreenTouch).position
            if not SaWelcomeWindow.press_closes(at, SaCursorPolicy.embedded_subwindows(heard)):
                return
        dialog.hide()
        SaPutAway.put_away(event)
