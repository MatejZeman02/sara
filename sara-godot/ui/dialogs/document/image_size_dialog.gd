## Image > Image Size: a new width and height, a lock that keeps the aspect
## ratio, and how to read between texels.
##
## Beside `ui/dialogs/document/canvas_size_dialog.gd` rather than inside it, which is the same cut
## the passes behind them take. Canvas Size keeps the pixels and changes the
## canvas around them, so it asks where the old picture sits and has no filter.
## Image Size keeps the picture and changes the pixels, so it asks how to read
## between them and has no anchor. One window with both would need a nine-cell
## grid that means nothing for half its own answers, which is the sentence
## `SaCanvasSizeDialog`'s header already carries from the other side.
##
## The lock is a `CheckButton` rather than a chain glyph between the two rows,
## because a chain is a picture nobody reads the first time and the row under it
## has to say what it does anyway.
@tool
class_name SaImageSizeDialog
extends SaDialogWindow

## The painter confirmed. *size* is the new document in pixels and *filter* is a
## `SaResampleKernel.Filter`.
signal resample_requested(size: Vector2i, filter: int)

## The same ceiling File > New, Canvas Size and the pass itself use.
const MAX_DIMENSION := SaResample.MAX_DIMENSION

## The filter rows, in the order the dropdown draws them, indexed by
## `SaResampleKernel.Filter`.
const FILTER_LABELS: Array[String] = ["Bilinear", "Nearest"]

## The line that says how the image is scaled, whole for each of
## [constant FILTER_LABELS] rather than the filter's name dropped into one
## sentence, so a language with cases can decline it. The two percentages stay
## placeholders.
const RESAMPLED_WITH: Dictionary = {
    "Bilinear": "%s%% × %s%%, resampled with Bilinear.",
    "Nearest": "%s%% × %s%%, resampled with Nearest.",
}

## The four rows the page binds, one property each. The spinboxes, the lock and
## the dropdown are the page's, and this window reads what they wrote.
var wanted_width: int = 1920
var wanted_height: int = 1080
var keep_aspect: bool = true
var filter: int = SaResampleKernel.Filter.BILINEAR

## The declared rows, realized once into `ImageSizePage`.
var page: SaPage = null

var _current_label: Label = null
var _scale_label: Label = null
var _document_size := Vector2i(1920, 1080)


func _init() -> void:
    _init_dialog("ImageSizeDialog", tr("Image Size"), Vector2i(460, 360), Vector2i(420, 340))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    # Everything above the buttons scrolls for the reason Canvas Size gives. In
    # the same room 335 tall this dialog's buttons ended at 340.
    var rows_view := SaMake.scroll(column, "RowsScroll")
    rows_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    rows_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = rows_view
    var rows := SaMake.column(rows_view, "Rows", SaTheme.GAP)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _current_label = SaMake.label(rows, "CurrentLabel")
    _current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(SaMake.column(rows, "ImageSizePage"))
    page.row_changed.connect(_on_row_changed)

    _scale_label = SaMake.label(rows, "ScaleLabel")
    _scale_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _scale_label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    _scale_label.modulate = Color(1.0, 1.0, 1.0, 0.7)

    var buttons := pinned_buttons(column)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size.x = float(SaUI.px(90))
    cancel_button.pressed.connect(hide)
    default_button = SaMake.button(buttons, "ScaleButton", tr("Scale", "scale the image"))
    default_button.custom_minimum_size.x = float(SaUI.px(90))
    default_button.pressed.connect(_confirm)
    configure(_document_size)


## The page: two numbers, the lock, the filter. The lock is a row of its own
## rather than a chain glyph between the two numbers, for the reason the header
## gives, and its explanation is the sentence that says what it does.
func _declare(ui: SaPage) -> void:
    var rows := ui.section("")
    rows.number("Width", 1, MAX_DIMENSION, self, ^"wanted_width").step(1).named(&"width").node("WidthSpin")
    rows.number("Height", 1, MAX_DIMENSION, self, ^"wanted_height").step(1).named(&"height").node("HeightSpin")
    rows.toggle("Keep aspect ratio", self, ^"keep_aspect").named(&"lock").node("LockCheck").explain(
        tr("Typing one number fills the other in.")
    )
    rows.choice("Filter", FILTER_LABELS, self, ^"filter").named(&"filter").node("FilterOption")


## Points the dialog at the document it is about to scale, on every open rather
## than once, for the reason Canvas Size gives: the numbers start at what the
## document is now and it has moved on since the last open.
func configure(document_size: Vector2i) -> void:
    _document_size = document_size
    wanted_width = document_size.x
    wanted_height = document_size.y
    page.refresh()
    _current_label.text = tr("The image is %s × %s px.") % [document_size.x, document_size.y]
    _show_scale()


## The line under the rows, which is the only place the consequence of the two
## numbers is written down. "3840 × 2160" is a size and "200%" is what it does
## to the picture, and a painter who typed one wants to read the other.
func _show_scale() -> void:
    var wanted := requested_size()
    if wanted == _document_size:
        _scale_label.text = tr("The image does not change.")
        return
    var across := 100.0 * float(wanted.x) / float(maxi(1, _document_size.x))
    var down := 100.0 * float(wanted.y) / float(maxi(1, _document_size.y))
    _scale_label.text = (tr(RESAMPLED_WITH[FILTER_LABELS[selected_filter()]]) % [percent_text(across), percent_text(down)])


## *percent* as the scale line writes it, "200" for a whole number and "66.7"
## for any other, so a doubling does not read as 200.0.
static func percent_text(percent: float) -> String:
    var tenths := snappedf(percent, 0.1)
    return str(roundi(tenths)) if is_equal_approx(tenths, roundf(tenths)) else "%.1f" % tenths


## One number moved the other while the lock is on. The other row is written
## through its property and the page pushes it back into the spinbox silently,
## so the two never chase each other's rounding and need no guard of their own.
func _on_row_changed(key: StringName, _value: Variant) -> void:
    if keep_aspect and key == &"width":
        wanted_height = SaResample.locked_height(_document_size, wanted_width)
        page.refresh()
    elif keep_aspect and key == &"height":
        wanted_width = SaResample.locked_width(_document_size, wanted_height)
        page.refresh()
    _show_scale()


## What the two spinboxes currently ask for.
func requested_size() -> Vector2i:
    return Vector2i(wanted_width, wanted_height)


## Which filter is chosen, as a `SaResampleKernel.Filter`.
func selected_filter() -> int:
    return clampi(filter, 0, FILTER_LABELS.size() - 1)


## Whether the aspect ratio lock is on.
func aspect_locked() -> bool:
    return keep_aspect


func _confirm() -> void:
    var wanted := requested_size()
    var chosen := selected_filter()
    hide()
    if wanted != _document_size:
        resample_requested.emit(wanted, chosen)


## Scales by the Image Size dialog: its rows moved and Scale pressed, with it
## open, `{"image_size": {"width": 3840, "lock": true, "filter": "nearest"}}`.
##
## The rows are driven the way a hand moves them, so the lock's own handler runs
## and the other number is filled in by the code a painter's typing reaches:
## `width` alone with the lock on is what proves the height follows. What stays
## here is the order, the filter by name and the press, which is not a row. A
## scenario may move one row alone with `page_row` on `ImageSizePage`.
static func capture_image_size(tree: SceneTree, spec: Dictionary) -> String:
    var dialog := tree.root.find_child("ImageSizeDialog", true, false) as SaImageSizeDialog
    if dialog == null:
        return "SaCapture: no Image Size dialog open to scale in"
    if spec.has("lock"):
        dialog.page.row(&"lock").drive(spec["lock"])
    var lowered := FILTER_LABELS.map(func(label: String) -> String: return label.to_lower())
    var filter_row := lowered.find(String(spec.get("filter", "")).to_lower())
    if filter_row >= 0:
        dialog.page.row(&"filter").drive(filter_row)
    for key: String in ["width", "height"]:
        if spec.has(key):
            dialog.page.row(StringName(key)).drive(spec[key])
    var before := dialog._document_size
    var wanted_size := dialog.requested_size()
    var named := FILTER_LABELS[dialog.selected_filter()]
    if bool(spec.get("cancel", false)):
        dialog.hide()
        return "SaCapture: image_size cancelled at %d x %d" % [wanted_size.x, wanted_size.y]
    dialog._confirm()
    return (
        "SaCapture: image_size %d x %d -> %d x %d, %s, lock %s"
        % [before.x, before.y, wanted_size.x, wanted_size.y, named, dialog.aspect_locked()]
    )
