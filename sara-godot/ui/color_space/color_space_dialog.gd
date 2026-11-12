## Image > Colour Space: assign what the document's numbers mean, or convert them.
##
## Two operations, deliberately not one button. Assign relabels and touches no
## pixel, which is the honest repair for a file that recorded no colour space.
## Convert rewrites every colour-typed field through a Bradford-adapted matrix.
## Photoshop separates them for the same reason: choosing the wrong one silently
## produces a document that is either mislabelled or recoloured, and the user
## cannot tell afterwards which happened.
##
## The dialog holds no document. Main configures it with the current descriptor
## and the reason a conversion would refuse, and applies whichever signal fires,
## so a suite can exercise it without an easel.
##
## The Target is `SaColorSpacePicker`, so Assign and Convert take a preset, a
## saved space, an ICC profile file or any primaries, white and curve.
@tool
class_name ColorSpaceDialog
extends SaDialogWindow

## The margin round the column, the gap between its rows, the height held for
## the status line and the height the scrolling page counts for in the floor, in
## logical units.
##
## Named because [method fit_to_content] adds them back up: the floor this
## window may be dragged to is the column's own minimum plus the chrome round it,
## and a number written twice is a number that goes stale in one of the two.
## The page counts for `BODY_FLOOR` and no more, because what it wants is the
## whole drawing, a thousand units and more, and a window that could not be
## dragged shorter than that is no window on a laptop.
const MARGIN: int = SaTheme.PAD
const SEPARATION: int = 10
const STATUS_H: int = 48
const BODY_FLOOR: int = 200

## The size the constructor asks for, and the smallest it is willing to be
## however little the content needs, since the diagram reports almost no width.
const DEFAULT_SIZE: Vector2i = Vector2i(700, 500)
const FLOOR_SIZE: Vector2i = Vector2i(600, 430)
## The width it opens at where the host has the room, the rows and the drawing
## side by side. Taken after the fit and not asked of the constructor, because
## the fit reads the wrapped notes at the width the window has, and a width the
## host then took back left them a line short and the buttons under the edge.
const WIDE: int = 1100

## The user chose to reinterpret the existing numbers as *space*.
signal assign_requested(space: SaColorSpace)

## The user chose to rewrite the pixels into *space*.
signal convert_requested(space: SaColorSpace)

## The Target's rows and the space they add up to, bound through the page as
## `picker`.
var picker := SaColorSpacePicker.new()
## The Target's rows, realized into `TargetRows`.
var page: SaPage = null
var _current_label: Label = null
var _status_label: Label = null
var _note_label: Label = null
var cancel_button: Button = null
var assign_button: Button = null
var convert_button: Button = null

## The column the window is made of and the scroll the drawing goes in.
##
## Held because the floor this window may be dragged to is measured off the
## column rather than guessed (see [method fit_to_content]).
var _column: VBoxContainer = null
var _page_scroll: ScrollContainer = null

## What the target currently names, drawn rather than spelled. "What will this
## conversion do to my document" is the question this window exists to answer,
## and a gamut triangle answers it better than the word "ACEScg".
var browser: SaColorSpaceBrowser = null

## The document's current descriptor, for the "Current:" line.
var _current: SaColorSpace = null

## `func(target: SaColorSpace) -> String`, normally
## `SaColorConversion.blocked_reason`. Held as a callable rather than a
## precomputed string because the answer depends on the *target*, which the user
## changes with the dropdown while the window is open.
var _blocked_reason_for: Callable = Callable()


func _init() -> void:
    _init_dialog("ColorSpaceDialog", tr("Document Colour Space"), DEFAULT_SIZE, FLOOR_SIZE)

    var margin := SaMake.margin(content, "Margin", MARGIN)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    _column = SaMake.column(margin, "Column", SEPARATION)

    # A `Window` clips and does not scroll, and a `VBoxContainer` insists on the
    # sum of its children, so a column taller than the window would push its
    # own last row past the bottom edge with nothing to say so. Everything above
    # the buttons goes in here, and the buttons stay outside it: a row that can
    # be scrolled out of sight is still a row a painter has to search for.
    #
    # It is the window's `scrolling_body`, the one region that scrolls, so the
    # drawing goes in whole and the window opens as tall as the drawing wants or
    # as the host allows, rather than the browser sitting in a scroll of its
    # own inside this one, which cuts the diagram to a letterbox and leaves the
    # room under it empty.
    _page_scroll = SaMake.scroll(_column, "ColumnScroll")
    _page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = _page_scroll
    var page_column := SaMake.column(_page_scroll, "Page", SEPARATION)
    page_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _current_label = SaMake.label(page_column, "CurrentLabel", tr("Current: unknown"))
    # The rows and the drawing side by side, as in File > New, so the diagram
    # stays above the foot of a 1080 screen. A flow, so a narrow host puts the
    # drawing under the rows rather than the window past the screen's edge.
    var target_body := HFlowContainer.new()
    target_body.name = "TargetBody"
    target_body.add_theme_constant_override(&"h_separation", SaUI.px(SEPARATION))
    target_body.add_theme_constant_override(&"v_separation", SaUI.px(SEPARATION))
    target_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_column.add_child(target_body)
    var target_rows := SaMake.column(target_body, "TargetRows")
    target_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(target_rows)
    page.row_changed.connect(func(key: StringName, _value: Variant) -> void: picker.row_changed(key))
    # Re-evaluated on every move of the picker. Asking the document once when
    # the window opened left Convert greyed out for every target except the one
    # it was configured with, which is to say it left the feature unreachable.
    picker.moved.connect(_on_target_moved)

    browser = picker.make_browser()
    browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    target_body.add_child(browser)

    # What the two buttons do, under the page and above the row they are on, so
    # it is in sight whenever they are. The page scrolls and a line at its foot
    # would be the one a short host cut off.
    _note_label = SaMake.label(
        _column,
        "NoteLabel",
        tr("Assign keeps every pixel and reads it in the new space. Convert changes the pixels so they look the same.")
    )
    _note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _note_label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    SaTheme.bind_font(_note_label, "text_muted")

    # Reserved whether or not a reason is showing, so the buttons do not jump up
    # the moment the dropdown lands on a target the document can be converted to.
    # Outside the scroll for the same reason: the reason Convert is
    # greyed out has to be readable beside it. It does not expand, because an
    # expanding child would take half of the room `pinned_buttons` leaves to the
    # scroll.
    _status_label = SaMake.label(_column, "StatusLabel")
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.custom_minimum_size = Vector2(0, float(SaUI.px(STATUS_H)))

    # The way out first and the default last, in the one order every dialog's
    # row reads.
    var buttons := pinned_buttons(_column)
    cancel_button = SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)

    convert_button = SaMake.button(
        buttons, "ConvertButton", tr("Convert"), tr("Rewrite every colour field into this space, as one undo entry.")
    )
    convert_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    convert_button.pressed.connect(_on_convert)

    assign_button = SaMake.button(
        buttons,
        "AssignButton",
        tr("Assign"),
        tr("Declare that the existing pixels are already in this space. Nothing is recoloured.")
    )
    assign_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    assign_button.pressed.connect(_on_assign)
    # Assign rather than Convert: Enter takes the reversible one, because
    # Convert rewrites every chunk and a mistyped Enter should not.
    default_button = assign_button

    configure(null, Callable())


## The Target, with no depth row: Assign and Convert keep the document's depth.
func _declare(ui: SaPage) -> void:
    ui.section("")
    picker.declare_picked(ui, self, &"picker", "Target", false)
    picker.declare_details(ui, self, &"picker")


## Measures the content once the theme is on, and again whenever it changes.
##
## `minimum_size_changed` rather than a subscription to the two EventBus scale
## signals: a font change, a theme swap, a translation and a status line that
## appeared all move the column's minimum and all arrive here, and the base class
## already keeps the theme itself in step. Deferred because the signal fires
## mid-layout, and a window resized from inside a layout pass is a warning.
func _ready() -> void:
    super._ready()
    _column.minimum_size_changed.connect(_fit_later)
    _fit_later()


func _fit_later() -> void:
    fit_to_content.call_deferred()


## Tells the dialog what it is looking at.
##
## *reason_for* is `func(target: SaColorSpace) -> String`, normally
## `SaColorConversion.blocked_reason`, so the window explains why Convert is
## unavailable instead of leaving a dead button. An undescribed document is the
## case that matters: Convert is wrong for it and Assign is right, and the text
## says so in those words.
func configure(current: SaColorSpace, reason_for: Callable) -> void:
    _current = current
    _blocked_reason_for = reason_for

    if current == null:
        _current_label.text = tr("Current: no document")
    elif not current.is_specified:
        _current_label.text = tr("Current: unspecified (the file never said)")
    else:
        # A preset's name, a saved space's, a profile's, or Custom, as the rows read.
        _current_label.text = tr("Current: %s") % picker.name_of(current)
    # sRGB is what a document that never said is read as.
    picker.show_space(current if current != null and current.is_specified else SaColorSpace.srgb())
    _refresh_status()


## The picker moved, so its rows show it and Convert is asked about it again.
func _on_target_moved() -> void:
    if page != null:
        page.refresh()
    _refresh_status()


## Asks the document about the target the dropdown currently names.
func _refresh_status() -> void:
    var reason := ""
    if _blocked_reason_for.is_valid():
        reason = str(_blocked_reason_for.call(selected_space()))
    if convert_button == null:
        return
    convert_button.disabled = not reason.is_empty()
    var said := [picker.profile_problem, tr("Convert is unavailable: %s") % reason if not reason.is_empty() else ""]
    _status_label.text = "\n".join(said.filter(func(line: String) -> bool: return not line.is_empty()))


## The descriptor the Target's rows add up to, at the document's depth.
func selected_space() -> SaColorSpace:
    return picker.selected_space()


func _on_assign() -> void:
    assign_requested.emit(selected_space())
    hide()


func _on_convert() -> void:
    convert_requested.emit(selected_space())
    hide()


## The base class's fit, then this window's own floor.
##
## The base fit raises the floor to the whole drawing's height, which a painter
## could not drag below, so the floor goes back to the measured one at once.
## Last, `WIDE` where the host has it.
func fit_opening_size() -> void:
    super.fit_opening_size()
    fit_to_content()
    if host_room().x < WIDE or logical_size.x >= WIDE or not visible:
        return
    var before := size.x
    logical_size.x = WIDE
    size.x = maxi(size.x, SaUI.window_size_for(self, logical_size).x)
    @warning_ignore("integer_division")
    position.x -= (size.x - before) / 2
    _keep_inside_host()


## Measures the content and lifts the window's floor to it.
##
## Public because the test drives it: a deferred call needs a frame the suite
## does not have, and this is a method rather than a member, so the privates rule
## has nothing to say about it.
##
## A guessed floor cut the Cancel, Assign and Convert row off the foot of the
## window whenever the column grew, as it does under a larger Font size, which
## `SaUI.scale()` leaves out (`sa_ui.gd`), and when dragged to the floor.
##
## Asking the column is the only number that follows a font the painter chose.
## Deferred through `minimum_size_changed`, so a font change, a theme swap and a
## status line that appeared all reach it by the same door, and guarded by the
## early return so a resize that re-lays out the column cannot loop.
func fit_to_content() -> void:
    # A hidden window sorts none of its children, so a wrapping label in it
    # answers its whole text one character wide, a floor that cannot shrink.
    # The base fit asks again on the frame the window is shown.
    if not is_inside_tree() or not visible:
        return
    var wanted := _yielding_to_host(content_minimum())
    if wanted == logical_min_size:
        return
    logical_min_size = wanted
    logical_size = Vector2i(maxi(logical_size.x, wanted.x), maxi(logical_size.y, wanted.y))
    min_size = SaUI.window_size_for(self, logical_min_size)
    size = Vector2i(maxi(size.x, min_size.x), maxi(size.y, min_size.y))


## *floor* held to what the host can give, by the rule `fit_opening_size` holds
## every dialog's floor to: the declared floor yields to the room, and what the
## content needs may take the margin as well, up to the whole host.
##
## Without it the floor measured here put the window back at 430 tall on a host
## 335 tall, the one that `FLOOR_SIZE` was a guess for, and the buttons went
## under the screen's edge although the page above them could have scrolled.
func _yielding_to_host(floor_size: Vector2i) -> Vector2i:
    var room := host_room()
    if room.x <= 0 or room.y <= 0:
        return floor_size
    return floor_size.min(room.max(content_minimum_size().min(host_room(0))))


## The smallest this window can be and still show every control, in logical units.
##
## The column's rows plus the chrome round them: the margin twice, and the drag
## bar, whose own height follows the title font and so is read back rather than
## taken from `DockerUtils.BASE_DRAG_H`. The scrolling page counts for
## `BODY_FLOOR` however tall the drawing in it is, because the scroll is what
## makes a short window possible, so the column's minimum with the page taken
## out is what the rows above and below it need. Never below `FLOOR_SIZE`, which
## is what keeps the width readable.
##
## Public because `capture_state` reports it and a test asserts it, and neither
## is this class. Nothing outside writes it, so it is a method rather than a
## member the privates rule would have to talk about.
func content_minimum() -> Vector2i:
    if _column == null or _page_scroll == null or drag_handle == null:
        return FLOOR_SIZE
    var column_min := _column.get_combined_minimum_size()
    var rows_height := column_min.y - _page_scroll.get_combined_minimum_size().y
    var bar := maxf(drag_handle.size.y, drag_handle.get_combined_minimum_size().y)
    var chrome := float(SaUI.px(MARGIN) * 2)
    var width := column_min.x + chrome
    var height := rows_height + float(SaUI.px(BODY_FLOOR)) + chrome + bar
    return Vector2i(maxi(int(ceil(width)), FLOOR_SIZE.x), maxi(int(ceil(height)), FLOOR_SIZE.y))


## The three buttons and the drawing, and where they sit, for the dump.
##
## A screenshot of a dialog whose bottom row is half off the edge and one whose
## bottom row is whole differ by a few dozen texels, and the whole question is
## which of the two it is. So the rectangle is a number here: each button in the
## window's own logical space, and whether it is inside the window's rect. The
## diagram is the same kind of fact, its rectangle and whether it lies inside the
## visible part of the page, because the dialog once cut it to a letterbox.
static func capture_state(root: Window) -> Dictionary:
    var dialog := root.find_child("ColorSpaceDialog", true, false) as ColorSpaceDialog
    if dialog == null or not dialog.visible:
        return {}
    var scale := SaUI.window_scale(dialog)
    var inner := Rect2(Vector2.ZERO, Vector2(dialog.size) / (scale if scale > 0.0 else 1.0))
    var buttons: Dictionary = {}
    var all_inside := true
    for button: Button in [dialog.cancel_button, dialog.assign_button, dialog.convert_button]:
        var rect := Rect2(button.global_position, button.size)
        var inside := inner.encloses(rect)
        all_inside = all_inside and inside
        buttons[String(button.name)] = {"rect": SaReportShapes.rect(rect), "inside": inside}
    var page_rect := Rect2(dialog._page_scroll.global_position, dialog._page_scroll.size)
    var diagram_rect := Rect2(dialog.browser.diagram.global_position, dialog.browser.diagram.size)
    return {
        "window": SaReportShapes.rect(inner),
        "size": SaReportShapes.vec(Vector2(dialog.size)),
        "min_size": SaReportShapes.vec(Vector2(dialog.min_size)),
        "logical_min_size": SaReportShapes.vec(Vector2(dialog.logical_min_size)),
        "content_minimum": SaReportShapes.vec(Vector2(dialog.content_minimum())),
        "buttons": buttons,
        "buttons_inside": all_inside,
        "button_labels": [dialog.cancel_button.text, dialog.convert_button.text, dialog.assign_button.text],
        "default_button": String(dialog.default_button.name),
        "page": SaReportShapes.rect(page_rect),
        "page_scrolls": dialog._page_scroll.get_v_scroll_bar().max_value > dialog._page_scroll.get_v_scroll_bar().page + 0.5,
        "diagram": SaReportShapes.rect(diagram_rect),
        "diagram_inside_page": page_rect.encloses(diagram_rect),
        "note": dialog._note_label.text,
        "target": dialog.picker.capture_state(),
        "current": dialog._current_label.text,
    }
