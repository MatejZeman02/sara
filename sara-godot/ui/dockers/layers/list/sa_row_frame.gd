## The box a layer row and a filter row are both made of: the eye, the picture
## slot with the mask's picture beside it, the name and its field, the note
## mark, the three locks and a group's two marks.
##
## A row is not a kind of another row. A layer row and a filter row are two
## things made of this frame, and neither inherits the other: a filter row that
## inherited every behaviour of a layer row answered
## none of them sensibly, because it carries no layer, no name to write and no
## three locks.
##
## The frame also carries the row's place and the picked set, so a row answers
## for itself what it looks like, what its dump says and which rows a press on
## it acts through.
class_name SaRowFrame
extends PanelContainer

## The three toggles at the right, in Krita's order: id, icon, tooltip. Each is
## drawn on every row whatever its state, so a painter can find a lock that is
## off and see where one came from. Off is an outline in the muted text colour
## and on is filled with the accent, both at full strength: an off lock drawn
## faint reads as one that cannot be pressed. On the
## selected row an off lock is outlined in the text colour instead.
const TOGGLES: Array = [
    [&"paint", "Lock", "Lock painting on this layer"],
    [&"alpha", "GuiMiniCheckerboard", "Paint only where this layer already has paint"],
    [&"clip", "Container", "Clip this layer to the one below"],
]

## The palette key an off lock is drawn in on a row that is not selected.
const LOCK_INK := "text_muted"
## And on the selected one, because the muted text all but vanishes against
## the selection's ground in most palettes, where the text colour stays above
## 4 to 1 in every shipped one. The on lock keeps its accent ground, which is
## what tells it from an off one on either row.
const LOCK_INK_LIT := "text_primary"

## The icon of the fold mark a group's row carries before its name, and the one
## it turns to when the group is closed. It is a button of its own rather than
## the first two characters of the label, because a group collapses and a mark
## nothing can press reads as a broken one. It is an icon rather than two
## triangles, because the default Inter and two of the other faces have
## neither and draw a box holding "25 BE".
const GROUP_MARK: String = "chevron_down"
const GROUP_MARK_CLOSED: String = "chevron_right"

## The eye's words on a layer's row, hidden first and shown second: the state,
## which a theme with no icon draws as the button's text, and what a press does,
## which is the tooltip. The state alone said nothing on hover, because the text
## is only drawn where the icon is missing.
const LAYER_EYE: Array = [
    ["Hidden", "Show this layer, or drag over the other eyes to show those too"],
    ["Visible", "Hide this layer, or drag over the other eyes to hide those too"],
]
## The same on a filter's row, whose eye turns the filter off and on rather than
## hiding a picture, and which no drag sweeps.
const FILTER_EYE: Array = [
    ["Filter is off", "Turn this filter on"],
    ["Filter is on", "Turn this filter off"],
]

## Taller than a button row, because the row now carries a picture.
const ROW_HEIGHT: int = 28

## How big a lock is, in logical units. Twenty inside the row's 28, because at
## 18 the icons inside measured 2.3 to 1 against the row and read as specks.
const TOGGLE_SIDE: int = 20

## What a group's row says where a layer's paint lock is. A group has no paint
## of its own, so it draws no lock there, and the empty slot keeps the locks
## below and above it in one column.
const GROUP_PAINT_TIP: String = "A group has no pixels of its own to paint on"

## What a ground's row says where a layer's paint lock and alpha lock are. A
## ground stores nothing, so neither lock has anything to hold, and the one slot
## spans both.
const GROUND_PAINT_TIP: String = "A ground holds no paint"

## What the note mark looks like when the layer holds no note.
const DIM_ALPHA: float = 0.3

## What a row looks like when a group above it is hidden. The layer's own eye is
## untouched: opening the group again shows it as it was.
const HIDDEN_BY_GROUP_ALPHA: float = 0.45

## The left edge of the active row when more than one is picked, in logical
## units. The selected style already draws two.
const ACTIVE_BORDER: int = 5

## The rim of the layer a filter's panel paints under, in logical units. The row
## keeps the unlit ground and takes the selection's colour round its edge, so it
## reads as where the brush goes and never as a second picked row.
const TARGET_BORDER: int = 1

## How thick the mark on the target row is, in logical units. Three rather than
## two because at two it was hard to see against the row below it in the
## capture, and a marker nobody can find is the thing that mark is fixing.
const DROP_BORDER: int = 3

## The mark a row carries when its layer holds a note, and what the mark looks
## like when it does not. Drawn on every row whatever its state, the way the
## three locks are, so a painter who has seen one knows where to look for the
## next: dimmed is empty, lit is a note, and the text is on the row's tooltip
## either way.
const COMMENT_ICON: String = "VisualShaderNodeComment"

## How much of a group row's height, top and bottom, drops the layer beside the
## group rather than inside it. A whole-row target would be a group nothing can
## be moved above.
const GROUP_EDGE: float = 0.25

## What the row draws. The layer is what a layer's row carries and the record
## what a filter's, and exactly one of them is null: the row kind decides which,
## and the frame never needs both to draw.
var label: String = ""
var layer: SaLayer = null

## How many steps the row is indented. A row whose layer moved into or out of
## a group is kept and indented again by [method reindent].
var indent_depth: int = 0
var record: SaAttachedFilter = null
var is_group: bool = false

## Which way a group's fold mark points. The docker keeps the set of shut
## groups, so the row is told rather than asked.
var collapsed: bool = false

## The row's index and the set that picks it. A rebuild makes new rows, and a
## fold keeps the rows it leaves standing and numbers them again through
## [method renumber], which is what every press on the row reads.
var row_index: int = -1
var picked: SaLayerPick = null

## What the last `style` said, so a dump reports the look the row wears.
var lit: bool = false
## Whether the last `style` drew the row as the layer under a picked filter.
var target: bool = false

var hbox: HBoxContainer
var eye_btn: Button
## The row's colour behind its eye, as Photoshop draws it, transparent on a row
## with No Colour and on a filter's row. Drawn behind the button's icon and
## blind to the mouse, so the eye reads and presses as it did.
var color_tint: ColorRect
var thumb: SaLayerThumbnail

## The mask's picture, and null on a row with no mask. Built and dropped by
## `refresh` as the mask comes and goes, because adding one rebuilds no row.
var mask_thumb: SaLayerThumbnail = null
var lbl: Label
var edit: LineEdit
var comment_btn: Button

## A group's fold mark, and null on every other row.
var disclose: Button = null
## A group's mark that it composites into an intermediate of its own, null on a
## layer's row. Shown while `SaLayerStack.isolates` says so, whether the painter
## ticked Blend Group on Its Own or something the group carries isolates it,
## because the members' blend modes read differently either way and the flag
## alone does not say which way they read now.
var isolated_mark: IsolatedMark = null
## A layer's mark that its paint carries a height, null on a group's row and on
## a filter's. Shown while `SaLayer.carries_height` says so, which it does from
## the first height-writing dab on.
var height_mark: HeightMark = null
## A layer's mark that it is stored at other than the document's resolution,
## "2x" beside the name, null on a group's row and on a filter's. Shown while the layer's `resolution_scale` is not 1.0.
var scale_mark: Label = null
## A layer's words that it is an effect layer reading nothing, "No input" beside
## the name, null on a group's row and on a filter's. Shown while
## `SaEffectLayer.input_of` answers null for an effect layer, after its input was
## deleted or before one was picked, since the row's picture is then empty and
## an empty picture says nothing about why.
var input_mark: Label = null

## The three locks by id, `&"paint"`, `&"alpha"` and `&"clip"`.
var toggles: Dictionary = {}

## The key the locks are drawn in now, `LOCK_INK` or `LOCK_INK_LIT`, so `style` redraws
## them only when the row's selection changes and a dump says which it is.
var locks_ink: String = ""

## The empty slot a group's row keeps where the paint lock is, and a ground's
## where the paint lock and the alpha lock are, and null on every other row. The
## locks themselves are built and hidden, so `toggles` holds the same three on
## every row and the list connects them the same way.
var paint_slot: Control = null

## What [method show_eye] last drew the eye by, so the same eye is not drawn again.
var _eye_drawn := ""

## What [method set_collapsed] last drew the fold mark by.
var _fold_drawn := ""

## What [method style] last drew the panel by, so the same panel is not drawn
## again.
var _style_drawn: Array = []

## The blank before everything else that indents the row, null at depth 0.
var _indent: Control = null


## Builds the frame. *depth* indents it one step per group it sits inside, and a
## group's row carries a folder mark before its name. Nothing is connected here
## and nothing is added to a parent: both are the list's, so a private handler
## stays private to the file that holds it.
func _init(
    label_text: String,
    depth: int,
    group: bool,
    idx: int,
    row_layer: SaLayer = null,
    row_record: SaAttachedFilter = null,
    pick: SaLayerPick = null
) -> void:
    label = label_text
    is_group = group
    layer = row_layer
    record = row_record
    row_index = idx
    indent_depth = depth
    picked = pick
    # PASS, so a press the row has no use for keeps travelling up to the docker
    # and reaches `LayersDocker._on_control_gui_input`, which is what opens the
    # actions menu on the row under the pointer. A mouse event stops at the
    # first STOP control it meets on the way up, and a `PanelContainer` is born
    # STOP, so the row ate every right press that landed on it: the menu opened
    # from the empty space under the rows and never from a row, which is exactly
    # the row the menu is about. A left press still selects, because the list's
    # handler is on this row's own `gui_input`, and the controls that answer a
    # press of their own, the eye, the note mark and the three locks, are
    # buttons and stay STOP.
    mouse_filter = Control.MOUSE_FILTER_PASS
    # A press here picks the row and its drag reorders the stack, so a press and
    # drag never scrolls the list from a row.
    set_meta(SaDragScroll.OWN_DRAG_META, true)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    custom_minimum_size = Vector2(0, SaUI.px(ROW_HEIGHT))

    hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", SaUI.px(6))
    add_child(hbox)

    reindent(depth)

    # Before the eye, where the label's first character would be, so the row
    # is the same picture while the group is open.
    if is_group:
        disclose = SaMake.button(hbox, "DiscloseBtn", "", TranslationServer.translate("Collapse this group"))
        SaUI.set_button_icon(disclose, GROUP_MARK)
        disclose.flat = true
        disclose.focus_mode = Control.FOCUS_NONE
        # The icon fills what the margins leave, so 22 wide leaves it 14, where
        # 16 left a speck. The two triangles as text were 24.
        disclose.custom_minimum_size = Vector2(SaUI.px(22), SaUI.px(20))

    eye_btn = Button.new()
    # Named, so a scenario can hover the top row's eye by name.
    eye_btn.name = "EyeBtn"
    eye_btn.flat = true
    eye_btn.custom_minimum_size = Vector2(SaUI.px(20), SaUI.px(20))
    show_eye(true)
    hbox.add_child(eye_btn)
    color_tint = ColorRect.new()
    color_tint.name = "ColourTint"
    color_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    color_tint.color = Color(0, 0, 0, 0)
    color_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # The whole row is tinted, as Photoshop does. A tint only the eye's size
    # sat under the selection's own fill and the eye's icon and read as nothing.
    add_child(color_tint)
    move_child(color_tint, 0)

    # Krita's order: eye, thumbnail, name, then the locks pushed
    # to the right by the name filling what is left.
    thumb = SaLayerThumbnail.new()
    thumb.name = "Thumbnail"
    hbox.add_child(thumb)

    lbl = Label.new()
    lbl.text = label
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    # A Label's own minimum is the width of its text, so without this the longest
    # layer name set the whole docker's minimum width: the list asked for 266
    # logical units on a default document, six more than the docker's own default
    # width, and every row below it hung off the right edge.
    lbl.text_overrun_behavior = SaTheme.TEXT_CUT
    hbox.add_child(lbl)

    if is_group:
        isolated_mark = IsolatedMark.new()
        isolated_mark.name = "IsolatedMark"
        isolated_mark.custom_minimum_size = Vector2(SaUI.px(14), SaUI.px(18))
        isolated_mark.visible = false
        hbox.add_child(isolated_mark)
    elif record == null:
        scale_mark = Label.new()
        scale_mark.name = "ScaleMark"
        scale_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        scale_mark.mouse_filter = Control.MOUSE_FILTER_PASS
        scale_mark.visible = false
        hbox.add_child(scale_mark)
        input_mark = Label.new()
        input_mark.name = "InputMark"
        input_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        input_mark.mouse_filter = Control.MOUSE_FILTER_PASS
        input_mark.visible = false
        hbox.add_child(input_mark)
        height_mark = HeightMark.new()
        height_mark.name = "HeightMark"
        height_mark.custom_minimum_size = Vector2(SaUI.px(14), SaUI.px(18))
        height_mark.visible = false
        hbox.add_child(height_mark)

    # The rename field, built with the row and hidden until something asks for
    # it. It takes the label's slot rather than sitting beside it, so opening
    # one does not push the three locks along the row and out of reach. Built
    # here rather than on demand because the theme pass runs once, over the row
    # the list has just added, and a control made after it keeps the default
    # font.
    edit = SaMake.line_edit(hbox, "NameEdit")
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    edit.visible = false

    # The note mark, between the name and the three locks. A Button rather than
    # a TextureRect because that is what every other mark on this row is, and
    # because a tooltip on a Control that takes no mouse input never shows. Its
    # press is the list's to connect, like the eye's, and opens the note.
    comment_btn = SaMake.button(hbox, "CommentMark")
    comment_btn.flat = true
    comment_btn.focus_mode = Control.FOCUS_NONE
    comment_btn.custom_minimum_size = Vector2(SaUI.px(18), SaUI.px(18))
    SaUI.set_button_icon(comment_btn, COMMENT_ICON, "")

    for entry: Array in TOGGLES:
        var btn := SaMake.button(
            hbox, "%sToggle" % String(entry[0]).capitalize(), "", TranslationServer.translate(String(entry[2]))
        )
        btn.toggle_mode = true
        # The theme pass writes `flat` off, which is why it is not set here any
        # more: a flat button draws no stylebox, so these three read as
        # unpressed always.
        SaTheme.make_toggle(btn)
        _lock_look(btn, LOCK_INK)
        btn.focus_mode = Control.FOCUS_NONE
        btn.custom_minimum_size = Vector2(SaUI.px(TOGGLE_SIDE), SaUI.px(TOGGLE_SIDE))
        SaUI.set_button_icon(btn, String(entry[1]), "")
        toggles[entry[0]] = btn
    locks_ink = LOCK_INK

    if is_group:
        _empty_paint_slot([&"paint"], GROUP_PAINT_TIP)
    elif layer != null and layer.is_generated():
        _empty_paint_slot([&"paint", &"alpha"], GROUND_PAINT_TIP)

    if _mask() != null:
        _add_mask_thumb()


## Redraws a lock's off states as an outline in the palette's *ink* on no
## ground, over the toggle boxes `SaTheme.make_toggle` set, whose pressed box is
## the accent. Hover keeps its ground, which is the feedback a press is coming.
## Its icon is in the ink too while it is off. Bound to the palette, so a
## theme switch moves both. The margins are thinned in every state, so the icon
## takes the room the larger box gave it rather than the box's padding.
static func _lock_look(btn: Button, ink: String) -> void:
    for state: String in SaTheme.TOGGLE_STATES:
        var box := btn.get_theme_stylebox(state) as StyleBoxFlat
        if box == null:
            continue
        box.set_content_margin_all(float(SaUI.px(2)))
        if state in ["normal", "focus"]:
            SaTheme.bind(box, {"border_color": ink})
            box.draw_center = false
    SaTheme.bind_font(btn, ink, "icon_normal_color")
    SaTheme.bind_font(btn, ink, "icon_hover_color")


## Draws the three locks in the ink the row's selection asks for. The first
## ink is drawn on fresh boxes, and a later one is bound again on the boxes
## the locks already wear, whose binding of the edge's colour it replaces,
## because fifteen new boxes a row were half of the millisecond a row took to
## light on a large test document.
func _ink_locks() -> void:
    var ink := LOCK_INK_LIT if lit else LOCK_INK
    if ink == locks_ink:
        return
    for which: StringName in toggles:
        var btn: Button = toggles[which]
        if locks_ink.is_empty():
            SaTheme.make_toggle(btn)
            _lock_look(btn, ink)
        else:
            _reink(btn, ink)
    locks_ink = ink


## Binds *ink* again on the edge and the glyph of *btn*, a lock that wears
## the boxes [method _lock_look] drew.
static func _reink(btn: Button, ink: String) -> void:
    for state: String in ["normal", "focus"]:
        var box := btn.get_theme_stylebox(state) as StyleBoxFlat
        if box != null:
            SaTheme.bind(box, {"border_color": ink})
    SaTheme.bind_font(btn, ink, "icon_normal_color")
    SaTheme.bind_font(btn, ink, "icon_hover_color")


## Hides the locks *locks* names, which stand side by side, and puts one empty
## slot as wide as all of them and the gaps between in their place, carrying
## *tip*, the sentence that says why. A group hides its paint lock and a ground
## its paint and alpha locks, and the clip lock keeps its column either way.
func _empty_paint_slot(locks: Array[StringName], tip: String) -> void:
    var first: Button = toggles[locks[0]]
    var wide := float(hbox.get_theme_constant("separation")) * (locks.size() - 1)
    for which: StringName in locks:
        var lock: Button = toggles[which]
        lock.visible = false
        wide += lock.custom_minimum_size.x
    paint_slot = Control.new()
    paint_slot.name = "PaintSlot"
    paint_slot.custom_minimum_size = Vector2(wide, first.custom_minimum_size.y)
    # PASS rather than IGNORE, because a tooltip only shows on a control that
    # takes the mouse, and PASS hands the press on to the row so it still picks.
    paint_slot.mouse_filter = Control.MOUSE_FILTER_PASS
    paint_slot.tooltip_text = TranslationServer.translate(tip)
    hbox.add_child(paint_slot)
    hbox.move_child(paint_slot, first.get_index())


## Whether the row still carries a layer that has not been freed. A row can
## outlive its layer, and `is` against a freed instance raises.
## Draws the eye for *shown*: the open or the shut icon, the state as the text a
## theme with no icon draws, and what a press does as the tooltip, in the words
## of the row's kind.
## An eye drawn as it already is is left alone, 14 ms of a 308-row refresh.
func show_eye(shown: bool) -> void:
    var drawn := "%d %d %s" % [int(shown), SaUI.px(SaUI.BASE_ICON_SIZE), TranslationServer.get_locale()]
    if drawn == _eye_drawn:
        return
    _eye_drawn = drawn
    var words: Array = (FILTER_EYE if record != null else LAYER_EYE)[int(shown)]
    var icon := "GuiVisibilityVisible" if shown else "GuiVisibilityHidden"
    SaUI.set_button_icon(eye_btn, icon, TranslationServer.translate(words[0]))
    eye_btn.tooltip_text = TranslationServer.translate(words[1])


func has_layer() -> bool:
    return is_instance_valid(layer)


## The mask the picture beside the row's own draws, the layer's or the record's.
func _mask() -> SaMask:
    if record != null:
        return record.mask
    return layer.mask if has_layer() else null


## What the row puts back when the document changed, which each kind answers.
func refresh(_document: SaDocument) -> void:
    pass


## Moves the row to *idx*, its index and the name a scenario finds it by, for a
## fold that kept it. The name's prefix is the row kind's own, so a layer's row
## stays `LayerRow_` and a filter's `FilterRow_`.
func renumber(idx: int) -> void:
    row_index = idx
    name = "%s_%d" % [String(name).get_slice("_", 0), idx]


## Indents the row *depth* steps, for a layer moved into or out of a group. A
## group moved out of its parent took its every member's row with it, and
## building each again was 2.5 ms a row, a fifth of a second for the twenty
## rows of a group.
func reindent(depth: int) -> void:
    indent_depth = depth
    if depth <= 0:
        if _indent != null:
            hbox.remove_child(_indent)
            _indent.queue_free()
            _indent = null
        return
    if _indent == null:
        _indent = Control.new()
        _indent.name = "Indent"
        _indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hbox.add_child(_indent)
        hbox.move_child(_indent, 0)
    _indent.custom_minimum_size = Vector2(SaUI.px(14 * depth), 0)


## The mask's picture, right after the row's own.
func _add_mask_thumb() -> void:
    mask_thumb = SaLayerThumbnail.for_mask()
    hbox.add_child(mask_thumb)
    hbox.move_child(mask_thumb, thumb.get_index() + 1)


## Builds or drops the mask's picture as the mask comes and goes.
func _sync_mask_thumb() -> void:
    var wanted: bool = _mask() != null
    if wanted and mask_thumb == null:
        _add_mask_thumb()
    elif not wanted and mask_thumb != null:
        hbox.remove_child(mask_thumb)
        mask_thumb.queue_free()
        mask_thumb = null


## Whether the mask's picture no longer matches the mask: one added or taken
## away, or switched on or off, since the row last refreshed. Cheap, so the list
## asks it on every stroke, where a whole refresh would be a dozen icon writes
## per dab.
func mask_is_stale() -> bool:
    var mask := _mask()
    if (mask != null) != (mask_thumb != null):
        return true
    return mask_thumb != null and mask_thumb.is_dimmed() == mask.enabled


## Says the pictures may have moved. A mask added or switched off announces its
## chunks and nothing else, so the row puts itself right here rather than waiting
## for a rebuild.
func mark_dirty(document: SaDocument) -> void:
    if mask_is_stale():
        refresh(document)
    if is_instance_valid(thumb):
        thumb.mark_dirty()
    if mask_thumb != null:
        mask_thumb.mark_dirty()


## Wakes the pictures that wait out of sight, which the list asks after a scroll.
func wake() -> void:
    if is_instance_valid(thumb):
        thumb.wake()
    if mask_thumb != null:
        mask_thumb.wake()


## Frees the row's controls with it while [SaLayerRowSleep] holds them out of
## the tree, where the row's own free would not reach them.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and is_instance_valid(hbox) and hbox.get_parent() == null:
        hbox.free()


## Which of the two pictures *local_point*, in the row's own coordinates, is
## over: `&"layer"`, `&"mask"`, or nothing. Read off the pictures' rectangles
## inside the row, because both sit inside the row's one press and only the
## rectangle says which was meant. Local rather than global, because a press the
## row's `gui_input` hands on is already in the row's space, and a row that is
## not in a tree has no global transform to ask.
func picture_at(local_point: Vector2) -> StringName:
    var inside := local_point - hbox.position
    if mask_thumb != null and mask_thumb.get_rect().has_point(inside):
        return &"mask"
    if thumb.get_rect().has_point(inside):
        return &"layer"
    return &""


## A press with Shift and nothing else on the mask's picture switches the mask
## off or on, as Photoshop and Krita do, one undo step through `SaMaskOps`.
## Answers whether the press was that one, and then the list goes no further:
## the picked rows and the brush's target stay as they were, so a mask being
## painted is still the target once it is switched back on.
func switch_mask(press: InputEventMouseButton, document: SaDocument) -> bool:
    if document == null or not press.shift_pressed or press.ctrl_pressed or press.alt_pressed:
        return false
    if picture_at(press.position) != &"mask" or _mask() == null:
        return false
    var holder: Object = layer
    if record != null:
        holder = record
    return SaMaskOps.new(document).set_enabled(holder, not _mask().enabled)


## Which picture the brush paints into, when it is one of this row's: `&"mask"`
## when the document's mask target is this row's mask, `&"layer"` when the layer
## is the active one and no mask is the target, and nothing otherwise. A record
## has no paint of its own to pick, so its mask is the whole answer.
func picked_picture(document: SaDocument) -> StringName:
    if document == null:
        return &""
    var mask := _mask()
    if mask != null and document.mask_target == mask:
        return &"mask"
    if record != null:
        return &""
    if document.mask_target == null and document.active_layer == layer:
        return &"layer"
    return &""


## The name of the icon the fold mark draws, read off the button by its file,
## and "" on a row with no mark.
func _disclose_icon() -> String:
    if disclose == null or disclose.icon == null:
        return ""
    return disclose.icon.resource_path.get_file().get_basename()


## Turns a group's fold mark round. The row stays where it is: what a collapse
## hides is the rows under it, which is the list's rebuild to make.
func set_collapsed(shut: bool) -> void:
    collapsed = shut
    if disclose == null:
        return
    # Every sync tells every group's row, so a mark drawn as it already is
    # is left alone.
    var drawn := "%d %d %s" % [int(shut), SaUI.px(SaUI.BASE_ICON_SIZE), TranslationServer.get_locale()]
    if drawn == _fold_drawn:
        return
    _fold_drawn = drawn
    SaUI.set_button_icon(disclose, GROUP_MARK_CLOSED if shut else GROUP_MARK)
    disclose.tooltip_text = TranslationServer.translate("Expand this group" if shut else "Collapse this group")


## The rows an eye or a lock pressed on this row acts on: every picked row when
## this one is among them, and this row alone otherwise. The two sweeps run it.
func acted_on() -> Array[int]:
    return picked.acted_on(row_index) if picked != null else [row_index]


## Whether this row is the one the pick is on, which is what the dump reports as
## the active row and what a rename with no row named means. The thicker edge is
## another question: it marks that row only when several are picked.
func on_the_pick() -> bool:
    return picked != null and row_index == picked.selected_idx


## Draws the row's panel: lit when it is picked, a thicker left edge when it is
## the active one of several, and the drop mark when a drag is over it.
func style(mode: SaLayerList.Drop) -> void:
    lit = picked != null and picked.is_lit(row_index, record)
    target = picked != null and picked.is_target(row_index)
    var leads := picked != null and picked.leads(row_index)
    # A panel drawn for the same pick, drop and scale is left as it stands,
    # because a step that changes a few rows restyles them all, and a new box
    # a row was 8 ms of a large test document's 593. A theme recolours the boxes it
    # bound in place, so the palette is not asked.
    var drawn := [lit, target, leads, mode, SaUI.px(ACTIVE_BORDER)]
    if drawn == _style_drawn:
        return
    _style_drawn = drawn
    var box := SaTheme.make_row_style(lit)
    if target:
        _mark_target(box)
    # Every picked row is lit, and the active one carries a thicker edge, so a
    # set of three still says which of them the blend mode and the opacity
    # slider are describing.
    if leads:
        box.border_width_left = SaUI.px(ACTIVE_BORDER)
    if mode != SaLayerList.Drop.NONE:
        _mark_drop(box, mode)
    add_theme_stylebox_override("panel", box)
    _ink_locks()


## The layer under a picked filter: an outline in the selection's colour on the
## unlit ground, with the left edge as thick as a lit row's, so the eye finds it
## in the same place and still tells it from a picked row.
static func _mark_target(box: StyleBoxFlat) -> void:
    SaTheme.bind(box, {"border_color": "border_selected"})
    var thin := SaUI.px(TARGET_BORDER)
    box.border_width_top = thin
    box.border_width_bottom = thin
    box.border_width_right = thin
    box.border_width_left = SaUI.px(2)


## The drop mark, on the style the row was about to take. A line along the edge
## the layer will land on, and a box around a group it will land inside, which
## is the whole difference between the two drops said in one glance.
static func _mark_drop(box: StyleBoxFlat, mode: SaLayerList.Drop) -> void:
    # The accent rather than the selection green, because the row being dropped
    # on is often the selected one and the two marks then said the same thing.
    SaTheme.bind(box, {"border_color": "accent_primary"})
    var thick := SaUI.px(DROP_BORDER)
    match mode:
        SaLayerList.Drop.ABOVE:
            box.border_width_top = thick
        SaLayerList.Drop.BELOW:
            box.border_width_bottom = thick
        SaLayerList.Drop.INTO:
            box.border_width_top = thick
            box.border_width_bottom = thick
            box.border_width_left = thick
            box.border_width_right = thick
        SaLayerList.Drop.REFUSED:
            # A dragged mask this row will not take: the box of INTO in the dim
            # border and the ground of a disabled button, so the eye that looks
            # for the accent box finds none here.
            SaTheme.bind(box, {"border_color": "border_secondary", "bg_color": "button_disabled"})
            box.border_width_top = thick
            box.border_width_bottom = thick
            box.border_width_left = thick
            box.border_width_right = thick
        _:
            pass


## What the row is and where its press targets are, for a capture that presses
## one with the mouse instead of calling into the list.
##
## The rects are in the docker window's own coordinates, and a press routed
## through the root has the window's position added to it, which is the sum
## `drag_window` already makes. Both halves have to be readable: a row that
## never took the press and an eye that never toggled are the same picture.
func report() -> Dictionary:
    var shown: SaLayer = layer if has_layer() else null
    var group: SaLayer = SaLayerStack.parent_of(shown) if shown != null else null
    return {
        "label": label,
        "name": shown.shown_name() if shown != null else "",
        "selected": lit,
        "target": target,
        "active": on_the_pick(),
        "visible": shown.visible if shown != null else true,
        "renaming": edit.visible,
        "edit_text": edit.text,
        "rect": _rect(get_global_rect()),
        "eye_rect": _rect(eye_btn.get_global_rect()),
        # The row's colour and the tint drawn for it, which a shot shows and a
        # suite reads here.
        "color_tag": str(shown.color_tag) if shown != null else "",
        "tint": color_tint.color.to_html(),
        # The rim around the picture, which a photograph of an empty row cannot
        # tell apart from the row behind it.
        "thumb_rim": thumb.rim_report(),
        # The note itself, and whether the mark is lit. A note is text on a
        # tooltip nothing photographs, and a lit mark and a dimmed one are a few
        # pixels apart, so a scenario asserts both here rather than in a shot.
        "comment": shown.comment if shown != null else "",
        "comment_lit": comment_btn.modulate.a >= 1.0,
        # Where to press the mark, which opens the note, and what its hover says.
        "comment_rect": _rect(comment_btn.get_global_rect()),
        "comment_tip": comment_btn.tooltip_text,
        # Which way the fold mark points, and where to press it. A row whose
        # children are hidden and a group with no children are the same picture.
        "is_group": is_group,
        # Which locks are on and which are drawn, and where a group's empty
        # slot is. On and off differ by the box rather than by brightness, so a
        # shot shows the look and this says which state it means.
        "locks": _locks_report(),
        # The palette key the off locks are drawn in, which the selected row
        # changes.
        "locks_ink": locks_ink,
        "paint_slot_rect": _rect(paint_slot.get_global_rect()) if paint_slot != null else {},
        "paint_slot_tip": paint_slot.tooltip_text if paint_slot != null else "",
        "collapsed": collapsed,
        "disclose_rect": _rect(disclose.get_global_rect()) if disclose != null else {},
        # The icon the fold mark draws, by its file's name, and its text, which
        # stays empty: a glyph there is a box in a face that lacks it.
        "disclose_icon": _disclose_icon(),
        "disclose_text": disclose.text if disclose != null else "",
        # Whether the group's row says it is isolated, which is a mark fourteen
        # units wide in a picture.
        "isolated_mark": isolated_mark != null and isolated_mark.visible,
        # Whether the layer's row says its paint has a height, the same width.
        "height_mark": height_mark != null and height_mark.visible,
        "scale_mark": scale_mark.text if scale_mark != null and scale_mark.visible else "",
        # What an effect row says when it reads nothing, empty when it reads a
        # node or is no effect layer.
        "input_mark": input_mark.text if input_mark != null and input_mark.visible else "",
        # Where those words are drawn, so a shot can be cut to them and a label
        # squeezed to nothing by the name beside it is told from one on show.
        "input_mark_rect": _rect(input_mark.get_global_rect()) if input_mark != null and input_mark.visible else {},
        # The group the layer sits in, or nothing. A row dropped into a group
        # and a row dropped beside it draw at the same x, so this is what puts
        # the membership a drag changed in the dump.
        "group": str(group.name) if group != null else "",
        # The mask's picture and where to press it, whether it is dimmed, and
        # which of the two pictures the brush paints into. A picked rim is two
        # pixels of accent, so a scenario reads the pick here.
        "has_mask": mask_thumb != null,
        "mask_rect": _rect(mask_thumb.get_global_rect()) if mask_thumb != null else {},
        "thumb_rect": _rect(thumb.get_global_rect()),
        "mask_enabled": _mask().enabled if _mask() != null else false,
        "mask_dimmed": mask_thumb != null and mask_thumb.is_dimmed(),
        "picked": String(picked_picture(_document_of(shown))),
    }


## Each lock's state for `report`: whether it is pressed, whether it is drawn,
## and where it is.
func _locks_report() -> Dictionary:
    var out := {}
    for which: StringName in toggles:
        var btn: Button = toggles[which]
        out[String(which)] = {
            "on": btn.button_pressed,
            "drawn": btn.visible,
            "alpha": btn.modulate.a,
            "rect": _rect(btn.get_global_rect()),
        }
    return out


## The document a row's layer belongs to, found up the tree, because a report is
## asked for with no document in hand.
static func _document_of(of: SaLayer) -> SaDocument:
    var node: Node = of
    while node != null:
        if node is SaDocument:
            return node
        node = node.get_parent()
    return null


static func _rect(r: Rect2) -> Dictionary:
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


## The mark itself: a frame with a filled square inside it, a composite held
## apart from what is around it. Drawn rather than an icon or a glyph, because
## the icon that reads as a box is the clip toggle's and a glyph is only as good
## as the font's coverage. It passes the mouse on, so a press still picks the row.
class IsolatedMark:
    extends Control

    func _init() -> void:
        mouse_filter = Control.MOUSE_FILTER_PASS

    func _draw() -> void:
        var side := minf(size.x, size.y)
        var frame := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)).grow(-side * 0.12)
        var ink := get_theme_color(&"font_color", &"Label")
        draw_rect(frame, ink, false, maxf(1.0, side * 0.08))
        draw_rect(frame.grow(-side * 0.22), ink, true)


## The height mark: a ridge of paint standing on a line, the profile a thick
## stroke has from the side. Drawn for `IsolatedMark`'s reasons, and it passes
## the mouse on as that one does, so a press still picks the row.
class HeightMark:
    extends Control

    func _init() -> void:
        mouse_filter = Control.MOUSE_FILTER_PASS

    func _draw() -> void:
        var side := minf(size.x, size.y)
        var box := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)).grow(-side * 0.12)
        var ink := get_theme_color(&"font_color", &"Label")
        var ground := box.position.y + box.size.y * 0.8
        var ridge := PackedVector2Array()
        var steps := 12
        for i in steps + 1:
            var t := float(i) / float(steps)
            var lift := sin(t * PI) * (0.55 + 0.25 * sin(t * PI * 3.0))
            ridge.append(Vector2(box.position.x + box.size.x * t, ground - box.size.y * 0.7 * lift))
        draw_colored_polygon(ridge, ink)
        draw_line(Vector2(box.position.x, ground), Vector2(box.end.x, ground), ink, maxf(1.0, side * 0.08))
