## Base class for all floating docker panels.
## Handles window setup, drag handles, resizing, scaling, and backgrounds.
@tool
class_name DockerWindow
extends Window

const DockerResizerScript = preload("res://ui/dockers/docker_resizer.gd")
const DockerDragHandleScript = preload("res://ui/dockers/docker_drag_handle.gd")

## Geometry in logical units. Window.size is measured differently depending on
## whether the window is embedded, and that is not knowable in _init, so the
## logical values are kept and converted once the window is in the tree.
##
## **`logical_size` follows the window**. It is the constructor's number only
## until something else resizes the docker, and after that it is whatever that
## resize left, read back through [method _track_logical_size]. Kept as the
## constructor's number for the life of the run, it would have [method
## apply_window_scale] re-derive a size the docker has not had since startup,
## and a UI scale write would throw a restored layout away.
##
## `logical_min_size` does not follow, and that is not an oversight: it is the
## floor the docker declares for itself, while `min_size` is that floor raised
## to whatever the content column insists on. A tracked minimum would ratchet
## the declared one up every time the column grew.
var logical_size: Vector2i = Vector2i(320, 240)
var logical_min_size: Vector2i = Vector2i(80, 80)

## True only while this class is writing `size` itself, so the tracker does not
## read its own derivation back as if a painter had done it.
var _deriving_geometry: bool = false

## What [method content_height_cap] leaves for the top bar and whatever the
## desktop puts at the edges, in logical units. A docker floored to the whole
## usable height has its own title bar off the bottom of it. What share of the
## screen's usable height a docker will open at, at most. Half, because every
## shipped layout stacks two dockers down an edge.
const CONTENT_HEIGHT_SHARE: float = 0.5

## True once the painter has dragged or resized any docker, after which
## [method grow_to_content] leaves every docker's size alone.
##
## Static, and that is the decision rather than an accident: a workspace
## somebody has arranged is theirs, and growing the docker beside the one they
## just dragged is the same surprise as growing the one they dragged.
## Read from outside, written here only.
static var painter_sized: bool = false

var drag_handle: PanelContainer
var resizer: Control

## The button at the end of the drag bar that closes this docker. Built for
## every docker and shown only while the layout page's one switch is on, so a
## painter who does not remember the chord still has a way out.
var hide_button: Button

## The button beside it that fills the window with this docker and puts it back.
## Built for every docker and shown only while this docker's own maximise switch
## is on, which is the per-docker option `SaDockerMaximise` declares.
var maximise_button: Button

## The button that holds this docker out on a summon, before the two above it in
## the bar. Built for every docker and shown only while the docker is out, which
## is `SaDockerLock`'s to offer and to take away.
var lock_button: Button

## The button that keeps this docker shown when Tab hides the rest, `SaDockerPin`'s.
var pin_button: Button

## Whether this docker is out on a summon or on a right press's lend, written by
## [method show_lent]. While it is, the head is shown with its title and its
## close whatever the layout switches say, because a docker parked under the
## pointer with no head has no way home but the gesture that brought it.
var lent: bool = false
var _drag_handle_input: DockerDragHandle = null
var _control_node: Control

## The column the composed dockers' library draws what a painter placed in this
## docker into, after the docker's own elements, or null while nothing has been
## placed here. Written by [method place_column], and by a composed docker,
## whose whole content it is.
var placed_column: Control = null

## The window this docker was last held above, its transient parent, or null
## while the docker is hidden or has no window of its own to hold. Read by the suite that pins it across a hide and a show.
var held_by: Window = null

## Whether the display server gives a transient window an owner only when it is
## exclusive too. Godot 4.7 on Windows does: `window_set_transient` and
## `_create_window` set `GWLP_HWNDPARENT` only for an exclusive window, so a
## docker that is merely transient is a free top-level window. It then sinks
## under the main window whenever that is activated, and it has a taskbar entry
## of its own. Static so the suite can take the Windows path on any desktop.
static var owner_needs_exclusive: bool = OS.get_name() == "Windows"


## *docker_title* is the title in English, kept as the window's `title`, which
## the engine translates wherever it draws one and the capture harness finds a
## docker by in any language. The drag bar shows it translated.
func _init_docker(
    docker_name: String, docker_title: String, default_size: Vector2i, min_docker_size: Vector2i = Vector2i(80, 80)
) -> void:
    name = docker_name
    title = docker_title
    visible = false
    initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE

    logical_size = default_size
    logical_min_size = min_docker_size
    size = default_size
    min_size = min_docker_size
    wrap_controls = true
    transient = true
    borderless = true
    transparent = true
    transparent_bg = true

    _control_node = Control.new()
    _control_node.name = "Control"
    _control_node.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_control_node)
    _control_node.unique_name_in_owner = true
    _control_node.owner = self
    DockerUtils.create_docker_background(_control_node)
    # Every show builds a new OS window, so the owner is asked for after each
    # one. `tree_entered` covers a docker that joins the tree already visible.
    visibility_changed.connect(_hold_above_transient_parent)
    tree_entered.connect(_hold_above_transient_parent)


## The drag bar's title read again in the locale set now. A docker is built
## once and lives for the whole run, so a title written once in `_init` stayed
## in whatever language the run began in. The engine sends this on every
## change of locale and on entering the tree, and `SaTranslationRegistry` sends
## it when a catalogue of the locale comes or goes.
func _notification(what: int) -> void:
    if what != NOTIFICATION_TRANSLATION_CHANGED or drag_handle == null or title.is_empty():
        return
    var said := tr(title)
    var words := drag_handle.find_child("TitleLabel", true, false) as Label
    if words != null:
        words.text = said
        _hold_the_english_width(words)
    else:
        drag_handle.tooltip_text = said


## A horizontal title keeps its English width and wraps a longer translation,
## which had widened the Undo docker past the window's edge. A change of
## scale or font changes the label's theme, which measures it again.
func _hold_the_english_width(words: Label) -> void:
    if drag_handle.custom_minimum_size.y == 0.0:
        return
    var translating := words.auto_translate_mode
    words.autowrap_mode = TextServer.AUTOWRAP_OFF
    words.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    var shown := words.text
    words.text = title
    var english := words.get_minimum_size().x
    words.text = shown
    words.auto_translate_mode = translating
    words.custom_minimum_size.x = english
    words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    if not words.has_meta(&"holds_english_width"):
        words.set_meta(&"holds_english_width", true)
        words.theme_changed.connect(_hold_the_english_width.bind(words), CONNECT_DEFERRED)


func _setup_docker_ready() -> void:
    assert(drag_handle != null, "drag_handle must be initialized before calling _setup_docker_ready")
    # is_embedded() is only meaningful once the window is in the tree, and it
    # decides both the scale factor and the units the geometry is measured in.
    apply_window_scale()
    SaUI.apply_ui_theme(self)
    resizer = DockerResizerScript.new(self)
    resizer.name = "Resizer"
    _control_node.add_child(resizer)
    _adopt_shared_theme()
    # A test that calls `_ready` on a detached docker has no tree to follow.
    if is_inside_tree():
        follow_root_theme(get_tree().root)
    # Built here rather than in _init, so a docker that never reaches _ready (the
    # layout tests build one detached) does not leave an orphaned Node behind.
    # Parented to the Control, not to the window: add_child() on a node that is
    # itself mid-_ready is rejected, and a rejected add leaves the node orphaned.
    _drag_handle_input = DockerDragHandleScript.new()
    _drag_handle_input.name = "DragHandleInput"
    _control_node.add_child(_drag_handle_input)
    _drag_handle_input.bind(self, drag_handle)
    _build_hide_button()
    # After the resizer exists, which `apply_window_scale` above it did not have.
    reserve_grip_corner()
    # Deferred, because a column's minimum is only its own until its children
    # have been laid out once, and every docker builds its content in _init.
    # The corner reservation reads that same minimum in its own axis, so it goes
    # round again after the layout for the same reason.
    enforce_column_minimum.call_deferred()
    reserve_grip_corner.call_deferred()
    # After both, because the content height it reads is the column's and the
    # grip's reservation is part of what it adds.
    grow_to_content.call_deferred()
    if not EventBus.docker_layout_changed.is_connected(_onpainter_sized_a_docker):
        EventBus.docker_layout_changed.connect(_onpainter_sized_a_docker)
    if not SaSettings.profile_changed.is_connected(_on_profile_changed):
        SaSettings.profile_changed.connect(_on_profile_changed)
    if not SaSettings.changed.is_connected(_on_maximise_switch_moved):
        SaSettings.changed.connect(_on_maximise_switch_moved)
    # A Control can only draw inside its own viewport, so each Window needs its own.
    CursorOverlay.attach_to(self)
    if not EventBus.ui_scale_changed.is_connected(_on_ui_scale_changed):
        EventBus.ui_scale_changed.connect(_on_ui_scale_changed)
    if not EventBus.ui_font_scale_changed.is_connected(_on_ui_font_scale_changed):
        EventBus.ui_font_scale_changed.connect(_on_ui_font_scale_changed)
    # After `apply_window_scale` above, so the docker's own opening size is the
    # first thing the tracker sees rather than the raw constructor number.
    if not size_changed.is_connected(_track_logical_size):
        size_changed.connect(_track_logical_size)


## Keeps a shown docker above its transient parent and off the taskbar.
##
## Only the display server's exclusive flag is set, never `Window.exclusive`.
## On Windows the display server's flag does nothing but set the owner, while
## the modal behaviour, the parent refusing input, is `Window.exclusive`'s own
## scene-side bookkeeping. The docker is owned and the canvas under it still
## takes the pen.
func _hold_above_transient_parent() -> void:
    held_by = hold_above_transient_parent(self)


## Asks the display server to hold *window* above the window it is transient
## to, and answers that window, or null while *window* is hidden or transient
## to nothing. Shared with `SaDialogWindow`, whose dialogs sank and had taskbar
## entries of their own for the same reason the dockers did.
static func hold_above_transient_parent(window: Window) -> Window:
    if not window.visible or not window.transient or not window.is_inside_tree() or Engine.is_editor_hint():
        return null
    var parent := transient_parent_window(window)
    if parent == null or not owner_needs_exclusive or window.is_embedded():
        return parent
    var id := window.get_window_id()
    if id != DisplayServer.INVALID_WINDOW_ID:
        DisplayServer.window_set_exclusive(id, true)
    return parent


## The window Godot makes *window* transient to: the nearest Window above its
## parent, the same walk `Window._make_transient` does.
static func transient_parent_window(window: Window) -> Window:
    var parent := window.get_parent()
    if parent == null:
        return null
    var viewport := parent.get_viewport()
    while viewport != null:
        if viewport is Window:
            return viewport as Window
        if viewport.get_parent() == null:
            return null
        viewport = viewport.get_parent().get_viewport()
    return null


## The SaSettings category this docker's Preferences page lives under. The node
## name is right for every docker whose settings key matches it, ColorDocker
## overrides, because its elements were registered under "ColorPicker".
func settings_category() -> String:
    return String(name)


## Elements a runtime-registered docker offers for reorder and visibility.
## This is the chrome every DockerWindow has. Subclasses append their own.
func layout_elements() -> Array:
    return ["Drag Handle", "Resizer"]


func apply_docker_base_layout(category: String) -> void:
    if drag_handle:
        drag_handle.visible = lent or SaSettings.get_element_visible(category, "Drag Handle")
    if resizer:
        resizer.visible = SaSettings.get_element_visible(category, "Resizer")
    # After the visibility, because a grip switched off reserves nothing.
    reserve_grip_corner()


## Re-derive geometry from the logical size for however this window is hosted.
##
## Recomputing from the stored logical values rather than multiplying the current
## size means repeated calls cannot compound, and toggling embedded subwindows at
## runtime moves the docker between the two measurement schemes cleanly.
##
## **Both floors are re-asserted deferred as well**, for the reason
## `_setup_docker_ready` already defers them: this writes `min_size` from the
## logical minimum, which drops whatever the column had raised it to, and the
## synchronous raise below then reads a combined minimum the engine has not
## recomputed since the theme was re-applied in this same frame. A width read
## there can fall short of the column's, be saved, and be clamped up by the
## next run's restore through `SaDockerStoredEntry.floored`, which does read
## the column. That is a docker narrower on the first run after a fresh
## settings directory than on every run after it, and a capture before and
## after any change is then two different pictures.
func apply_window_scale() -> void:
    _deriving_geometry = true
    SaUI.apply_to_window(self)
    size = SaUI.window_size_for(self, logical_size)
    min_size = SaUI.window_size_for(self, logical_min_size)
    _deriving_geometry = false
    enforce_column_minimum()
    reserve_grip_corner()
    if is_inside_tree():
        enforce_column_minimum.call_deferred()
        reserve_grip_corner.call_deferred()


## Remember, in logical units, whatever size something other than this class
## just gave the window.
##
## A restored layout, a `docker` capture step and a dragged corner all write
## `size` and none of them writes `logical_size`, so without this the two
## disagree from the first restore onwards. With
## the logical size honest, re-deriving from it is a no-op at an unchanged scale
## and the right multiplication at a changed one.
##
## **The divisor is the scale last applied to this window, not the current one.**
## `SaUI.apply_to_window` stamps `APPLIED_SCALE_META` with the factor the
## window's geometry is measured in, and turning embedded subwindows on or off
## changes what `SaUI.window_scale` answers a frame before the geometry is
## re-derived. Dividing by the current answer there would read a host-logical
## size as if it were physical and shrink the docker by the scale factor.
func _track_logical_size() -> void:
    if _deriving_geometry:
        return
    var applied: float = get_meta(SaUI.APPLIED_SCALE_META, 0.0)
    if applied <= 0.0:
        return
    logical_size = Vector2i(roundi(size.x / applied), roundi(size.y / applied))


## The drag bar's hide button, built into the bar the docker already has.
##
## `DockerUtils.make_drag_bar` puts the title straight into a PanelContainer,
## which lays every child over the whole panel, so a title and a button cannot
## both be children of it. The bar's own content moves into a row and the button
## goes at the end of that row. `SaDialogWindow` builds its close button the
## same way and says so, which is where the shape comes from.
func _build_hide_button() -> void:
    if drag_handle == null or drag_handle.get_child_count() != 1:
        return
    var content := drag_handle.get_child(0) as Control
    if content == null:
        return

    drag_handle.remove_child(content)
    var row := SaMake.row(drag_handle, "DragBarRow", SaTheme.GAP_TIGHT)
    row.add_child(content)

    # Ahead of the close, so the maximise stands next to it, because the close
    # is what sits at the end of the bar.
    maximise_button = SaDockerMaximise.build_button(row, self)
    hide_button = SaMake.button(row, "HideButton", "", tr("Hide this docker."))
    hide_button.flat = true
    hide_button.focus_mode = Control.FOCUS_NONE
    hide_button.custom_minimum_size = Vector2(float(SaUI.px(24)), 0.0)
    SaUI.set_button_icon(hide_button, "window_close", "X")
    # The window's own signal rather than `hide()`. MainDockers listens on it and
    # is what keeps the Dockers menu's tick and the saved layout honest, so
    # hiding the window here would leave both saying the docker is still open.
    hide_button.pressed.connect(func() -> void: close_requested.emit())
    pin_button = SaDockerPin.build_button(row, self)
    # Built last and placed at the head of the row, which its own builder does,
    # so the lock reads beside the title and the close stays the last button.
    lock_button = SaDockerLock.build_button(row, self)

    apply_hide_button()
    apply_maximise_button()
    apply_pin_button()


## Show or hide the button from the one setting that governs every docker.
##
## The button lives inside the drag bar, so a painter who has switched the Drag
## Handle row off has hidden it too. That is the same trade the resize grip
## already makes, and the chord is still there.
func apply_hide_button() -> void:
    if hide_button != null:
        hide_button.visible = lent or SaSettings.docker_hide_button
        hide_button.tooltip_text = tr("Send this docker back where it was.") if lent else tr("Hide this docker.")


## Marks this docker out on a lend, or home again, and draws its head to match:
## the drag bar with the title and the close stay shown while it is out, and
## the close says it sends the docker back. Home again, the head follows the
## layout's switches as before. The summon is the one caller, on a borrow and
## on its return, so the head and the borrow cannot drift apart.
func show_lent(out: bool) -> void:
    lent = out
    if drag_handle != null:
        drag_handle.visible = out or SaSettings.get_element_visible(settings_category(), "Drag Handle")
    apply_hide_button()


## Show or hide the pin from its switch, which the Toolbox overrides.
func apply_pin_button() -> void:
    SaDockerPin.apply_button(pin_button)


## Show or hide the maximise button from the one switch every docker shares.
func apply_maximise_button() -> void:
    SaDockerMaximise.apply_button(maximise_button)


## Fill the window with this docker, or put it back where the layout had it.
##
## `_deriving_geometry` is held over the resize for the reason it is held over
## `apply_window_scale`: the maximised size is this class's own derivation and
## not a size a painter gave the docker, so `_track_logical_size` must not read
## it back as the logical size. Without the flag a maximise and a restore left
## the docker believing it was the size of the whole window, and the next UI
## scale write re-derived from that.
func toggle_maximised() -> String:
    _deriving_geometry = true
    var said := SaDockerMaximise.toggle(self)
    _deriving_geometry = false
    return said


## Preferences changed under the docker, and the hide switch is one of the
## things that can have changed. Cheap enough to re-read on any of them. The
## painter dragged or resized a docker, so Sara stops sizing them.
func _onpainter_sized_a_docker() -> void:
    painter_sized = true


## Sara sizes the dockers again, as at a fresh start. The latch is static, so
## it outlives the suite whose drag set it, and a suite asking for the grow
## calls this first.
static func forget_painter_sizing() -> void:
    painter_sized = false


func _on_profile_changed() -> void:
    apply_hide_button()
    apply_maximise_button()
    SaDockerPin.redraw(self)


## The maximise and pin switches are preferences of the skeleton's own, so they
## are announced on `changed` and never on `profile_changed`. Named for them, as
## `PaletteDocker` has an `_on_setting_changed` that a method of that name here
## replaced without a word, leaving the palette's button unheard.
func _on_maximise_switch_moved(property: StringName) -> void:
    if SaDockerPin.names_the_switch(property):
        apply_pin_button()
    if not SaDockerMaximise.names_the_switch(property):
        return
    apply_maximise_button()
    # The button widens the drag bar, and the Toolbox, sixty units wide, drew its
    # hide button past its own right edge until the next start floored it.
    # Deferred: the column's minimum is recomputed once laid out with the button.
    if is_inside_tree():
        enforce_column_minimum.call_deferred()


## The window scale really has moved, so the geometry is re-derived from the
## logical size the docker is actually at. At the same scale that lands on the
## size it already has, because `SaSettings` emits this for a write of the scale
## it already holds and a painter's layout may not depend on which write it was.
func _on_ui_scale_changed(_new_scale: float) -> void:
    apply_window_scale()
    _adopt_shared_theme()
    SaUI.apply_ui_theme(self)


## The theme is read again and the docker grows with its text, as far as
## `SaDockerFontGrowth` says. `apply_window_scale` is not called, because the
## font scale is not the window scale and there is nothing for it to re-derive.
func _on_ui_font_scale_changed(_font_scale: float) -> void:
    _adopt_shared_theme()
    SaUI.apply_ui_theme(self)
    SaDockerFontGrowth.follow(self)


## Adopts the shared theme each time *root* takes a theme.
##
## A docker built at boot is ready before `Main`'s boot builds the shared
## theme, so the adoption in `_setup_docker_ready` finds nothing, and with the
## chain above it cut at `MainRoot` its tooltips were drawn in the engine's
## panel. Deferred, because the root takes the theme before `SaUI` stores it.
func follow_root_theme(root: Window) -> void:
    if not root.theme_changed.is_connected(_adopt_shared_theme):
        root.theme_changed.connect(_adopt_shared_theme, CONNECT_DEFERRED)


## A Window is a Viewport, so a theme set on the root does not reach into it.
func _adopt_shared_theme() -> void:
    var shared := SaUI.shared_theme
    if shared != null and theme != shared:
        theme = shared


## The column a docker stacks its drag bar and its content in, or null before
## the docker has built one.
##
## Every docker parents `drag_handle` to that column, which is the one thing
## they all agree on, so this is where the window's own width meets the width
## its contents insist on.
func content_column() -> Container:
    if drag_handle == null:
        return null
    return drag_handle.get_parent() as Container


## The hook an element is placed into a docker through: *column* goes at the
## end of the content column, under the docker's own elements, the first time
## the library places something here. The library fills it, and this window
## knows it only as a control, so a module's docker takes a placed element the
## way a built-in does and names nothing of `ui/dockers/composed`.
##
## At the end of the column rather than inside a docker's own scroll, because
## each docker builds that scroll its own way and the column is the one thing
## they all share. False, and nothing added, when there is no column yet or a
## column is placed already.
func place_column(column: Control) -> bool:
    var content := content_column()
    if content == null or placed_column != null:
        return false
    content.add_child(column)
    placed_column = column
    # The views widen the column, and a docker narrower than its column draws it
    # past its own edge, so the floor is read again once they are laid out.
    if is_inside_tree():
        enforce_column_minimum.call_deferred()
    return true


## The narrowest the content column will lay out at, and -1 before there is one.
static func column_min_width(window: Window) -> int:
    if not window.has_method("content_column"):
        return -1
    var column: Container = window.call("content_column")
    return int(column.get_combined_minimum_size().x) if column != null else -1


## The shortest the content column will lay out at, and -1 before there is one.
##
## The other axis of `column_min_width`, and it exists for the same reason: a
## column shorter than its own minimum overflows past the window's bottom edge,
## where the grip is, and everything below the edge is clipped away.
static func column_min_height(window: Window) -> int:
    if not window.has_method("content_column"):
        return -1
    var column: Container = window.call("content_column")
    return int(column.get_combined_minimum_size().y) if column != null else -1


## A docker is never narrower than the column inside it.
##
## A window can be dragged down to `min_size`, but a container cannot go below
## its own combined minimum, so a docker whose declared minimum is under its
## column's draws that column overhanging its own right edge. Everything past
## the edge is clipped away and gone: the hide button is only the visible half
## of it, and the Colour Picker's six sliders and hex box went the same way.
##
## The Colour Picker shows why. Its declared minimum and its default are both
## narrower than its column, so without this its hide button would sit past
## the edge at the default and not move at all when the docker is dragged in,
## because the column is never narrower than its own minimum.
##
## Raising the window rather than shrinking the column is the choice, and the
## reason is that the column's width is text. Three numeric sliders in a row
## carry "R: 0.000" each and `FactorSlider` already floors itself at its own
## text, so a column squeezed under its minimum is numbers a painter cannot
## read, in the rows that exist to show numbers. A width is cheaper than a
## legibility, and the docker still ends where a painter drags it in the axis
## nothing demands. Holds the resize grip's corner clear of the content, for
## every docker.
##
## The grip is pinned to the window's bottom right corner and draws on top of
## whatever the content put there, so a press in that square resizes the window
## instead of doing what the control under it says. A hidden spacer at the
## right end of the last row would answer that for one docker and leave every
## other docker with the same trap.
##
## **The inset rather than a spacer.** With no reservation at all, most
## dockers put something pressable under the grip at their default size or at
## their smallest, and several put a `ScrollContainer`'s own vertical scroll bar
## there. A scroll bar runs the full height of the area it scrolls and is pinned
## to its right edge, so no amount of reserving at the end of the last row
## moves it. The rest put a button in the bottom row, which a spacer would
## answer.
##
## So the column's bottom is inset by the grip's height instead. It costs every
## docker one grip of height, it
## needs no docker to know the grip exists, and it clears the corner for a
## scroll bar and a button alike. The window's minimum height carries the same
## reservation, or a docker dragged to its floor squeezes the column under its
## own minimum and the bottom row is clipped away, which is the width floor's
## bug in the other axis.
func reserve_grip_corner() -> void:
    var column := content_column()
    if column == null:
        return
    var reserved := 0.0
    if resizer != null and resizer.visible:
        reserved = resizer.custom_minimum_size.y
    column.offset_bottom = -reserved
    # From the declared floor rather than from whatever `min_size` holds, so a
    # second call cannot stack a second grip's worth on top of the first.
    #
    # The floor is raised to the column's own minimum height only where
    # `column_height_floor` says so. Doing it for every docker would make the
    # Recorder far taller than it opens, because its column wants more than
    # the window shows, and `column_wants` in the dump block below carries the
    # number.
    var floor_size := SaUI.window_size_for(self, logical_min_size)
    min_size = Vector2i(min_size.x, maxi(floor_size.y + int(reserved), column_height_floor()))
    size = Vector2i(size.x, maxi(size.y, min_size.y))


## The height the column needs to show every row it holds, reaching through any
## scroll that hides one.
##
## **`column_min_height` is not this number and cannot be.** A `ScrollContainer`
## reports its own minimum and not its content's, which is the whole reason one
## could be put in without making a window taller. For the Tool Options docker
## `column_min_height` answers the drag bar and nothing else, because its rows
## are inside the scroll and invisible to it. So this walks the column's
## children, takes the content's minimum wherever one is a scroll, and adds the
## separation the box lays them out with.
##
## -1 before there is a column, the same as its two neighbours.
static func column_content_height(window: Window) -> int:
    if not window.has_method("content_column"):
        return -1
    var column: Container = window.call("content_column")
    if column == null:
        return -1

    var total := 0.0
    var counted := 0
    for child in column.get_children():
        var control := child as Control
        if control == null or not control.visible:
            continue
        counted += 1
        var scroll := control as ScrollContainer
        if scroll == null:
            total += control.get_combined_minimum_size().y
            continue
        # The tallest thing inside the scroll, which is what the scroll would
        # have to be to show it whole. A scroll holds its content plus its own
        # scrollbar node, so this is a maximum rather than a sum.
        var inside := 0.0
        for held in scroll.get_children():
            var content := held as Control
            if content != null and content.visible:
                inside = maxf(inside, content.get_combined_minimum_size().y)
        total += inside
    if counted > 1 and column is BoxContainer:
        total += float(column.get_theme_constant(&"separation") * (counted - 1))
    return int(ceil(total))


## The tallest a docker will be opened at, which is half the screen it is on.
##
## A docker taller than the screen shows fewer of its items rather than more, so
## opening at all its items stops being the answer somewhere, and the
## measurement says where. The Tool Options docker with a brush selected wants
## 1449 logical units of rows, which is more than a 1080 tall screen has: opened
## at its content it would be the screen. Half is the line, because two dockers
## side by side is the arrangement every shipped layout uses and a docker that
## takes the whole edge leaves no room for the one under it.
##
## The column scroll carries whatever is past the cap, so the content is
## reachable by scrolling rather than cropped away.
static func content_height_cap(window: Window) -> int:
    var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
    var scale := maxf(SaUI.window_scale(window), 0.01)
    return int(float(usable.size.y) / scale * CONTENT_HEIGHT_SHARE)


## Whether the column puts its content inside a scroll.
##
## A scroll is the docker's own statement that its content need not all be on
## screen at once, as `tool_options_docker.gd`'s does. A docker without one
## has no way to reach what it cannot fit, so its content is its floor and a
## docker with one keeps the floor it declared.
static func column_has_scroll(window: Window) -> bool:
    if not window.has_method("content_column"):
        return false
    var column: Container = window.call("content_column")
    if column == null:
        return false
    for child in column.get_children():
        if child is ScrollContainer:
            return true
    return false


## Opens this docker at the height its content needs, up to [method
## content_height_cap].
##
## **A size and not a minimum.** The width floor raises the *floor* to the
## column's width because a column narrower than its minimum draws numbers a
## painter cannot read, and there is no scroll in that axis. Height has a
## scroll, so the floor stays where each docker declared it and a painter can
## still drag a docker small. What changes is what it opens at, which is all
## its items where the screen has room for them.
##
## **It stops the moment the painter arranges anything.** `docker_layout_changed`
## is emitted by the drag handle and the resizer and by nothing else, so it is
## the one signal that means a person moved a window. After that Sara does not
## resize dockers for them, in any docker: a workspace somebody has arranged is
## theirs, and growing the docker beside the one they just dragged is the same
## surprise as growing the one they dragged.
func grow_to_content() -> void:
    if painter_sized:
        return
    var wanted := column_content_height(self)
    if wanted <= 0:
        return
    var reserved := 0
    if resizer != null and resizer.visible:
        reserved = int(resizer.custom_minimum_size.y)
    var opened := mini(wanted + reserved, content_height_cap(self))
    size = Vector2i(size.x, maxi(size.y, opened))

    # **A docker that cannot scroll cannot crop**, so its content is its floor
    # as well as its opening height. One that can keeps the floor it declared,
    # because a scroll is its own answer to not fitting and flooring it as well
    # would trap a painter behind a window they cannot make small. This is the
    # half of the rule that survives a stored layout: `restore_all` writes a
    # size over whatever this set, and it cannot write one under `min_size`.
    if not column_has_scroll(self):
        min_size = Vector2i(min_size.x, maxi(min_size.y, opened))
        size = Vector2i(size.x, maxi(size.y, min_size.y))


func enforce_column_minimum() -> void:
    var wanted := column_min_width(self)
    if wanted <= 0:
        return
    min_size = Vector2i(maxi(min_size.x, wanted), maxi(min_size.y, column_height_floor()))
    size = size.max(min_size)


## The height under which this docker's column is clipped, in window units with
## the grip's corner in, or 0 for a docker that keeps the floor it declared,
## which is every docker but Brush Presets.
func column_height_floor() -> int:
    return 0
