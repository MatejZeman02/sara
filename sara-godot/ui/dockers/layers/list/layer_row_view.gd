## One layer's row in the layers docker, made of the frame every row is made of:
## the eye, the picture, the name and the three locks.
##
## A layer with a mask carries a second picture right after the first, the mask
## in grey, in the same box, so the row is no taller and a row with no mask is
## the picture it always was.
##
## What this file answers is the layer's own half: what the layer says on every
## frame, which group above it is closed, what a press aims the brush at, and
## where a drop over it lands. A filter's row is its peer, made of the same
## frame.
class_name SaLayerRowView
extends SaRowFrame

## How opaque a row's colour is behind its eye.
const TINT_ALPHA := 0.35

## What the row last drew its name, marks, eye and pictures from, as
## [method _drawn_for] reads it.
var _refresh_drawn: Array = []


func _init(label_text: String, depth: int, group: bool, idx: int, row_layer: SaLayer = null, pick: SaLayerPick = null) -> void:
    super(label_text, depth, group, idx, row_layer, null, pick)
    name = "LayerRow_%d" % idx


## Puts the layer's current state back on the row: its name, its three locks, its
## eye, and whether a group above it is closed.
func refresh(document: SaDocument) -> void:
    if not has_layer():
        return
    # The three locks are buttons a press turns before the layer is written,
    # so they are put back on every refresh, which costs a call each.
    var flags := {&"paint": layer.is_locked, &"alpha": layer.alpha_locked, &"clip": layer.clip_to_below}
    for which: StringName in toggles:
        (toggles[which] as Button).set_pressed_no_signal(flags[which])
    thumb.bind_layer(layer, document)
    # Everything else the row draws is read from what it is drawn for, and a
    # row whose reading has not moved since it was last drawn is left as it
    # stands. A step that changes a few rows of a deep stack refreshes every
    # row, and drawing each again was 15 ms of the 593 rows of a large test document.
    var drawn := _drawn_for(document)
    if drawn == _refresh_drawn:
        return
    _refresh_drawn = drawn

    # A rename writes the node's name and fires nothing, so the row that was
    # labelled when it was built shows the old one until the list is rebuilt.
    # The capture caught it: a layer added and renamed in one step read "Layer 5"
    # in the first shot and "Hidden" in the second. The fold mark is a button of
    # its own, so the label is the name alone.
    if not layer.shown_name().is_empty():
        var wanted := layer.shown_name()
        if lbl.text != wanted:
            lbl.text = wanted
            label = wanted
    _fit_name()

    # The note, and where it is read. The mark is lit when there is one and
    # dimmed when there is not, and the tooltip goes on the row's box rather
    # than on the mark alone, because the note is about the layer and a painter
    # hovering the name is asking the same question as one hovering the mark.
    # An empty mark says what its press does instead, since a press on it opens
    # the note to be written and a mark with no words read as a dead button.
    var note := layer.comment
    comment_btn.modulate.a = 1.0 if not note.is_empty() else DIM_ALPHA
    comment_btn.tooltip_text = note if not note.is_empty() else String(TranslationServer.translate("Add a note to this layer"))
    tooltip_text = note

    if isolated_mark != null:
        isolated_mark.visible = SaLayerStack.isolates(layer)
        isolated_mark.tooltip_text = TranslationServer.translate(
            (
                "Blends on its own while it carries a mask or a filter: its layers blend with each other first"
                if SaLayerStack.held_isolated(layer)
                else "Blends on its own: its layers blend with each other first"
            )
        )

    if scale_mark != null:
        var density := layer.resolution_scale
        var words := str(int(density)) if density == floorf(density) else str(density)
        scale_mark.visible = density != 1.0
        scale_mark.text = TranslationServer.translate("%sx") % words
        scale_mark.tooltip_text = (
            TranslationServer.translate(
                "Stored at %sx the document's resolution: finer detail zoomed in, more memory where it has paint."
            )
            % words
        )

    # An effect layer that reads nothing draws nothing, and its picture is as
    # empty as a fresh paint layer's, so the row says why in words. Asked on
    # every refresh rather than kept, because the input's delete and its undo
    # each rebuild the rows, and a rebuilt row asks again.
    # A frame layer's row says so in the same place, since its picture alone
    # reads as paint and the next frame writes over any paint put on it.
    if input_mark != null:
        input_mark.visible = layer.is_effect() and SaEffectLayer.input_of(layer) == null
        input_mark.text = TranslationServer.translate("No input")
        input_mark.tooltip_text = TranslationServer.translate(
            "Reads no layer, so it shows nothing. Right-click the row and choose one under Input."
        )
        if SaFrameLayer.holds(layer):
            input_mark.visible = true
            input_mark.text = TranslationServer.translate("Frame")
            input_mark.tooltip_text = TranslationServer.translate(
                "Holds the last frame another program sent it, such as Blender's camera view. Paint on a layer above it."
            )

    # A ground stores no height and still stands in relief by its tooth, so it is
    # marked by the tooth ("if a layer has a impasto, it should show it as the
    # mountains symbol").
    if height_mark != null:
        var tooth := SaGeneratedLayer.tooth_of(layer)
        height_mark.visible = layer.carries_height() or tooth > 0.0
        var tip := String(
            TranslationServer.translate(
                "Carries paint height: its thick strokes stand in relief, and it costs a quarter more memory where it has some"
            )
        )
        if tooth > 0.0:
            tip = String(TranslationServer.translate("Its tooth stands in relief, %.2f mm high")) % tooth
        height_mark.tooltip_text = tip

    show_eye(layer.visible)
    color_tint.color = tint_of(layer.color_tag)

    # A layer inside a hidden group is not on the canvas, and its own eye still
    # says what it will be when the group comes back. The row says both: the eye
    # is the layer's, the dimming is the group's.
    hbox.modulate.a = 1.0 if shown_by_its_groups(layer) else HIDDEN_BY_GROUP_ALPHA

    _sync_mask_thumb()
    var into := picked_picture(document)
    # The layer's rim is lit only on a row that has a second picture to tell
    # it from, so a row with no mask is the picture it always was.
    thumb.show_picked(into == &"layer" and mask_thumb != null)
    if mask_thumb != null:
        mask_thumb.show_mask(_mask(), document, into == &"mask")


## What the row draws is read from, beside the locks: the name, the note,
## each mark's question, the eye, the colour, the group's eye above it, the
## mask and the picture the brush paints, and the language and scale the words
## and icons are drawn in. Equal to the last means the row already shows it.
func _drawn_for(document: SaDocument) -> Array:
    var mask := _mask()
    return [
        layer.shown_name(),
        layer.comment,
        SaLayerStack.isolates(layer) if isolated_mark != null else false,
        SaLayerStack.held_isolated(layer) if isolated_mark != null else false,
        layer.resolution_scale,
        layer.is_effect() and SaEffectLayer.input_of(layer) == null if input_mark != null else false,
        SaFrameLayer.holds(layer),
        layer.carries_height() if height_mark != null else false,
        SaGeneratedLayer.tooth_of(layer) if height_mark != null else 0.0,
        layer.visible,
        layer.color_tag,
        shown_by_its_groups(layer),
        document,
        mask,
        mask.enabled if mask != null else false,
        picked_picture(document),
        TranslationServer.get_locale(),
        SaUI.px(SaUI.BASE_ICON_SIZE),
    ]


## The tint behind the eye of a row coloured *id*: its hue thinned to
## `TINT_ALPHA`, strong enough to tell seven colours apart and thin enough that
## the eye's icon reads over it in the light and the dark themes alike.
static func tint_of(id: StringName) -> Color:
    var hue := SaLayerColorTag.hue(id)
    return Color(hue, TINT_ALPHA) if hue.a > 0.0 else Color(0, 0, 0, 0)


## What the row says on hover. A name that fits its label needs no help, so the
## row says what it always has, the note. One cut short by the label's ellipsis
## is read whole here, with the note below it when there is one, because the
## three locks keep their place on every row and the name gives way to them. The
## label is measured rather than asked, since a `Label` does not say whether it
## trimmed, and a row being renamed has no label on show, so its name is not cut.
func _get_tooltip(_at_position: Vector2) -> String:
    if not has_layer() or not _name_is_cut():
        return tooltip_text
    var note := layer.comment
    return lbl.text if note.is_empty() else "%s\n%s" % [lbl.text, note]


## A change of language reaches a row that is not refreshed for it, so the name
## is fitted again then, as the catalogue may now make it Sara's or longer.
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and lbl != null:
        _fit_name()


## Lets a name Sara wrote wrap onto a second line of the row, and keeps a
## painter's own on one line under its ellipsis. Sara's words are the ones the
## catalogue turns into something else, "Background" among them, so in English
## nothing wraps and no row moves, while a translation longer than English shows
## the name whole on two lines. A name the painter typed is in no catalogue, and
## a long one is still read whole on hover. Smart wrapping breaks inside a word
## too, because a translated Background is one word wider than its column. A
## wrapping label trims nothing, because Godot gives a label that wraps and trims
## a minimum height of one pixel, and the row would never grow to the second line.
func _fit_name() -> void:
    var sara_wrote_it := lbl.atr(lbl.text) != lbl.text
    var wrapping := TextServer.AUTOWRAP_WORD_SMART if sara_wrote_it else TextServer.AUTOWRAP_OFF
    var cut := TextServer.OVERRUN_NO_TRIMMING if sara_wrote_it else SaTheme.TEXT_CUT
    if lbl.autowrap_mode != wrapping:
        lbl.autowrap_mode = wrapping
    if lbl.text_overrun_behavior != cut:
        lbl.text_overrun_behavior = cut


## True while the name is wider than the room the label has been given, or, on
## a name that wraps, has more lines than the label shows.
func _name_is_cut() -> bool:
    if not lbl.is_visible_in_tree():
        return false
    if lbl.autowrap_mode != TextServer.AUTOWRAP_OFF:
        return lbl.get_line_count() > lbl.get_visible_line_count()
    var font := lbl.get_theme_font(&"font")
    var wide := font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl.get_theme_font_size(&"font_size")).x
    return wide > lbl.size.x


## What a plain press on a row aims the brush at. The mask's picture makes the
## mask the document's `mask_target`, the layer's picture gives the brush back
## to the paint, and a press anywhere else on the row keeps the mask only when
## it is this layer's own, because a brush painting one layer's mask while
## another layer is active is a mode nobody asked for. Static, because the press
## that asks has usually rebuilt the rows and freed this one, so it is called
## after the selection with the layer the press was on.
static func aim_brush(document: SaDocument, of: SaLayer, picture: StringName) -> void:
    if document == null or of == null:
        return
    var mask := of.mask
    var wanted: SaMask = document.mask_target
    if picture == &"mask" and mask != null:
        wanted = mask
    elif picture == &"layer" or (wanted != null and wanted != mask):
        wanted = null
    if wanted != document.mask_target:
        document.mask_target = wanted


## What a drop at *global_point* over this row means. A row that is not a group
## takes the layer above or below itself, by which half of it the pointer is in.
## A group takes it inside, unless the pointer is in the quarter at either end.
func drop_mode_at(global_point: Vector2) -> SaLayerList.Drop:
    var rect := get_global_rect()
    if rect.size.y <= 0.0:
        return SaLayerList.Drop.NONE
    var down := (global_point.y - rect.position.y) / rect.size.y
    if is_group and down > GROUP_EDGE and down < 1.0 - GROUP_EDGE:
        return SaLayerList.Drop.INTO
    return SaLayerList.Drop.ABOVE if down < 0.5 else SaLayerList.Drop.BELOW


## True when every group above *layer* is visible. The layer's own eye is not
## part of the answer, because a hidden layer inside a shown group is dimmed by
## its own icon rather than by the row.
static func shown_by_its_groups(of: SaLayer) -> bool:
    var group := SaLayerStack.parent_of(of)
    var guard := 0
    while group != null and guard < 64:
        if not group.visible:
            return false
        group = SaLayerStack.parent_of(group)
        guard += 1
    return true
