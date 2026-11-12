## The one row shape every Preferences page is built from.
##
## A row is a bold title with a dimmed, smaller explanation under it, and the
## control to the right, in a column that starts at the same x on every row of
## every page. A section is a heading over a rule. Pages built by hand each have
## their own idea of where a label goes, some labels the control's own text and
## some a Label beside it, and read badly side by side, so the shape is not
## optional: a page is sections, and a section is rows.
class_name SaSettingsRows
extends RefCounted

## The label column of a row in a dialog or a panel, logical units, one number
## so that the control column lines up down the whole dialog.
const LABEL_WIDTH := 210

## The widest a Preferences page's title column grows, logical units. A page
## measures its longest title, where 210 for every page cut the long ones, and
## past this a title wraps rather than squeeze the controls.
const COLUMN_MAX := 360

## Set on the column a Preferences page goes into, the title column `measure`
## found in pixels. A line under no such column is a dialog's row.
const COLUMN_META := &"sa_settings_column"

## The title a row gave its control, for anything that describes the control
## later. The note mode reads a control's tooltip when it has no text of its
## own, so the row also puts its explanation there.
const TITLE_META := &"sa_settings_title"

## Set on the HBoxContainer a row is, and on nothing else, so a test or a
## walker can tell a row from the box a slider row packs its readout into.
const ROW_META := &"sa_settings_row"

## Words a row is found by beside the ones it draws, set on the line by the
## declarative builder and read by the search's haystack.
const WORDS_META := &"sa_settings_words"

## Set on the column a section's rows go into, so the search can tell an
## element list a page placed bare in a section, whose items it finds one by
## one, from a box inside a row, which the row stands for.
const SECTION_META := &"sa_settings_section"

## The four text sizes of a page as fractions of the theme font's size: the
## page's title, a row's title, a section's heading, a row's explanation,
## largest first. Fractions rather than points, so the Font size preference
## moves all four together. The heading is below a row's title on purpose, since
## the rule under it and its Bold face already set it apart.
const PAGE_TITLE_SCALE := 1.3
const ROW_TITLE_SCALE := 1.0
const HEADING_SCALE := 0.9
const HINT_SCALE := 0.75

## An explanation on a Preferences page, across the whole row, where 0.75 read
## as too small. Dialogs and panels keep it.
const WIDE_HINT_SCALE := 0.85

## The fraction a label was sized with, so `refit` can size it again when the
## Font size preference moves. A dialog never runs the theme pass, which is why
## the label carries an override of its own and this.
const SIZE_META := &"sa_settings_size"


## The page itself: the spacing between sections.
static func setup_page(page: VBoxContainer) -> void:
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.add_theme_constant_override("separation", SaUI.px(16))


## The size a label at *fraction* of the theme font draws at, logical.
static func font_size(fraction: float) -> int:
    return maxi(1, int(roundf(SaUI.pxf(float(SaUI.BASE_FONT_SIZE) * SaUI.user_font_scale * fraction))))


## Sizes *label* at *fraction* of the theme font and remembers the fraction.
static func size_label(label: Control, fraction: float) -> void:
    label.set_meta(SIZE_META, fraction)
    label.add_theme_font_size_override("font_size", font_size(fraction))


## Sizes every label under *root* that `size_label` sized again, at the Font
## size preference as it stands now.
static func refit(root: Node) -> void:
    if root == null:
        return
    var control := root as Control
    if control != null and control.has_meta(SIZE_META):
        control.add_theme_font_size_override("font_size", font_size(float(control.get_meta(SIZE_META))))
    for child: Node in root.get_children():
        refit(child)


## A heading over a rule, and the container the section's rows go into. An
## empty *title* draws neither, so a dialog that wants the section's spacing
## without a name, which New Document asks for, gets no bare rule at its top.
static func section(page: Container, title: String) -> VBoxContainer:
    var block := SaMake.column(page, "Section", 6)
    block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if not title.is_empty():
        var heading := SaMake.label(block, "Heading", title)
        # Wrapped, so a heading longer than a page drawn in a docker goes onto
        # a second line rather than widening the docker past its edge.
        heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        size_label(heading, HEADING_SCALE)
        embolden(heading)
        SaMake.separator(block, "Rule")
    var rows := SaMake.column(block, "Rows", SaTheme.GAP)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rows.set_meta(SECTION_META, true)
    return rows


## One row: the bold title, the dimmed explanation under it, and `control` at
## the right, or on a Preferences page the shape `Line` gives it. A slider, a
## text box and a dropdown fill the column, anything else
## sits at its left edge so that switches and spin boxes line up. `control` may
## be null for a row that is only text.
##
## **A dropdown fills because it has no width of its own**. A `SaChoiceButton`
## clips its text rather than widening the row it sits in, which is right in a
## docker, and a clipping button's minimum is its arrow and nothing else. Left at
## its left edge it was drawn at that minimum, an arrow in a box with the chosen
## label clipped to nothing, on every Preferences page at once. A switch and a
## spin box carry a real minimum, so they still line up at the edge. The Tool
## Options docker's dropdowns never showed this because that builder hands each
## one a width, which is the other way to answer it.
static func row(rows: Container, title: String, hint: String, control: Control) -> HBoxContainer:
    var line := Line.new()
    line.name = "Row"
    line.set_meta(SaMake.KIND_META, SaMake.Kind.ROW)
    line.add_theme_constant_override("separation", SaUI.px(SaTheme.PAD))
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.set_meta(ROW_META, true)
    line.set_meta(TITLE_META, title)
    rows.add_child(line)

    var labels := SaMake.column(line, "Labels", 2)
    labels.custom_minimum_size = Vector2(SaUI.px(LABEL_WIDTH), 0)
    labels.size_flags_horizontal = Control.SIZE_FILL
    var title_lbl := SaMake.label(labels, "Title", title)
    title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    size_label(title_lbl, ROW_TITLE_SCALE)
    embolden(title_lbl)

    if not hint.is_empty():
        labels.add_child(hint_label(hint))

    if control != null:
        control.set_meta(TITLE_META, title)
        if control.tooltip_text.is_empty():
            control.tooltip_text = title
        var fills := control is Slider or control is LineEdit or control is SaChoiceButton
        control.size_flags_horizontal = Control.SIZE_EXPAND_FILL if fills else Control.SIZE_SHRINK_BEGIN
        # A choice that fills the column wraps a label longer than it, so a
        # sentence in a longer language reads whole on two lines.
        if control is SaChoiceButton:
            (control as SaChoiceButton).wrap_its_words()
        control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        line.add_child(control)
    return line


## Writes a new title and hint on a line `row` drew, and the title the search
## and the row report read off it. Here rather than in the page that asks,
## because this is the class that knows the line's shape, and a page that
## reached into it by child index is how the Workspace page's scale row came to
## say one scale on screen and another in its dump. A control
## whose tooltip was its title keeps it that way. A line drawn without a hint
## changes only its title.
static func retitle(line: Control, title: String, hint: String) -> void:
    var was := String(line.get_meta(TITLE_META, ""))
    line.set_meta(TITLE_META, title)
    for child: Node in line.get_children():
        if child.has_meta(TITLE_META):
            child.set_meta(TITLE_META, title)
            var shown := child as Control
            if shown.tooltip_text == was:
                shown.tooltip_text = title
    var title_lbl := line.get_node_or_null(^"Labels/Title") as Label
    if title_lbl != null:
        title_lbl.text = title
    var hint_lbl := line.get_node_or_null(^"Labels/Hint") as Label
    if hint_lbl != null:
        hint_lbl.text = hint


## A slider row with its value read out beside the slider, so the number is
## never carried in the title.
static func slider_row(
    rows: Container,
    title: String,
    hint: String,
    min_value: float,
    max_value: float,
    step: float,
    initial: float,
    on_changed: Callable
) -> HSlider:
    var box := SaMake.row(null, "SliderBox", SaTheme.GAP)
    var slider := HSlider.new()
    # The wheel belongs to the page that scrolls, which has no undo for a
    # value moved by a notch passing over the track.
    slider.scrollable = false
    slider.min_value = min_value
    slider.max_value = max_value
    slider.step = step
    slider.value = initial
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    box.add_child(slider)

    var value_lbl := SaMake.label(box, "Value", "%.2f" % initial)
    value_lbl.custom_minimum_size = Vector2(SaUI.px(44), 0)
    value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

    slider.value_changed.connect(
        func(val: float) -> void:
            value_lbl.text = "%.2f" % val
            on_changed.call(val)
    )
    slider.tooltip_text = title
    row(rows, title, hint, box)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return slider


## A dimmed paragraph across the whole row, for text that belongs to no one
## control: a restart notice, a readout.
static func note(rows: Container, text: String) -> Label:
    var lbl := hint_label(text)
    rows.add_child(lbl)
    return lbl


## The dimmed, smaller explanation under a title.
static func hint_label(text: String) -> Label:
    var lbl := SaMake.label(null, "Hint", text)
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_label(lbl, HINT_SCALE)
    SaTheme.bind_font(lbl, "text_muted")
    return lbl


## The interface font's Bold face, rather than the theme's font emboldened by a
## variation, which smears.
static func embolden(label: Label) -> void:
    label.add_theme_font_override("font", SaFonts.bold())


## Measures the title column of the Preferences page under *root*, its longest
## title up to `COLUMN_MAX`, once it is built and when the Font size moves, and
## sizes every explanation and note under it at `WIDE_HINT_SCALE`.
static func measure(root: Control) -> void:
    var widest := 0.0
    for node: Node in root.find_children("*", "Label", true, false):
        _enlarge(node)
        if node.name == &"Title" and node.get_parent().get_parent() is Line:
            widest = maxf(widest, text_width(node as Label))
    root.set_meta(COLUMN_META, mini(ceili(widest), SaUI.px(COLUMN_MAX)))
    for node: Node in root.find_children("*", "HBoxContainer", true, false):
        if node is Line:
            (node as Line).queue_sort()


## The column the Preferences page above *node* measured, or -1. The walk
## stops at a window, so a dialog Preferences opens keeps its rows.
static func column_for(node: Node) -> int:
    var walk := node.get_parent()
    while walk != null and not walk is Window:
        if walk.has_meta(COLUMN_META):
            return int(walk.get_meta(COLUMN_META))
        walk = walk.get_parent()
    return -1


## How wide *label* draws its text on one line, its box's margins counted.
static func text_width(label: Label) -> float:
    var font := label.get_theme_font(&"font")
    var drawn := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size"))
    return drawn.x + label.get_theme_stylebox(&"normal").get_minimum_size().x


## Whether *line* draws a rule under it: a Preferences row whose hint runs past
## one line, with a row next. A note next belongs to the row above it.
static func ruled(line: Control) -> bool:
    var hint := line.get_node_or_null(^"Labels/Hint") as Label
    if hint == null or not hint.visible or hint.get_line_count() < 2 or column_for(line) < 0:
        return false
    var rows := line.get_parent()
    for at in range(line.get_index() + 1, rows.get_child_count()):
        var next := rows.get_child(at) as Control
        if next != null and next.visible:
            return next.has_meta(ROW_META)
    return false


static func _enlarge(node: Node) -> void:
    if node is Control and float(node.get_meta(SIZE_META, 0.0)) == HINT_SCALE:
        size_label(node as Control, WIDE_HINT_SCALE)


## A row's line, the plain box in a dialog or a panel. On a Preferences page
## the title and the control share the first line, the title in the page's
## column, and the hint runs under both across the row, so a wider window gives
## a paragraph fewer lines. Laid out after the box's own pass rather than by a
## container of its own, so `Labels/Title`, `Labels/Hint` and the order, labels
## first and control last, stay what a dozen readers walk. The title is held
## as tall as the control, which keeps the hint below it.
class Line:
    extends HBoxContainer

    func _notification(what: int) -> void:
        if what != NOTIFICATION_SORT_CHILDREN or not has_meta(ROW_META):
            return
        var column := SaSettingsRows.column_for(self)
        if column < 0:
            return
        var labels := get_child(0) as VBoxContainer
        var tall := 0.0
        for at in range(1, get_child_count()):
            var control := get_child(at) as Control
            if control == null or not control.visible:
                continue
            tall = maxf(tall, control.get_combined_minimum_size().y)
            if control is CheckButton and not control.has_node(^"State"):
                SwitchWord.new(control as CheckButton)
        for label: Node in labels.get_children():
            SaSettingsRows._enlarge(label)
        var title := labels.get_node(^"Title") as Label
        labels.custom_minimum_size.x = column
        title.custom_minimum_size = Vector2(column, tall)
        title.size_flags_horizontal = SIZE_SHRINK_BEGIN
        fit_child_in_rect(labels, Rect2(0.0, 0.0, size.x, labels.size.y))
        queue_redraw()

    func _draw() -> void:
        if not SaSettingsRows.ruled(self):
            return
        var rule := get_theme_stylebox(&"separator", &"HSeparator")
        var thick := rule.get_minimum_size().y
        var gap := float((get_parent() as Control).get_theme_constant(&"separation"))
        draw_style_box(rule, Rect2(0.0, size.y + (gap - thick) * 0.5, size.x, thick))


## The On or Off a Preferences switch says, since a knob alone leaves its
## colour to tell on from off. Inside the switch's rect, so a press on the
## word flips it, and read on a press and on every draw, which a page's re-read
## causes with no signal.
class SwitchWord:
    extends Label

    var _switch: CheckButton

    func _init(switch: CheckButton) -> void:
        _switch = switch
        name = "State"
        mouse_filter = MOUSE_FILTER_IGNORE
        vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        SaSettingsRows.size_label(self, SaSettingsRows.ROW_TITLE_SCALE)
        switch.add_child(self)
        set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
        switch.toggled.connect(_read.unbind(1))
        switch.draw.connect(_read)
        _read()

    func _read() -> void:
        text = tr("On") if _switch.button_pressed else tr("Off")
        var points := get_theme_font_size(&"font_size")
        var on := get_theme_font(&"font").get_string_size(tr("On"), HORIZONTAL_ALIGNMENT_LEFT, -1, points).x
        var off := get_theme_font(&"font").get_string_size(tr("Off"), HORIZONTAL_ALIGNMENT_LEFT, -1, points).x
        offset_left = _switch.get_theme_stylebox(&"normal").get_margin(SIDE_LEFT)
        var wide := _switch.get_minimum_size().x + offset_left + SaUI.px(SaTheme.GAP) + maxf(on, off)
        _switch.custom_minimum_size = Vector2(ceilf(wide), get_combined_minimum_size().y)
