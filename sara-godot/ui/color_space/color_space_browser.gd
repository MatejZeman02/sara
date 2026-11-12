## Shows what a colour space actually is: its gamut on the CIE 1931 diagram, its
## white point, its primaries and its transfer function.
##
## A colour space decides what every pixel in a document means, and until this
## existed the only way to see one was to read `core/api/color/sa_color_space.gd`.
##
## It appears three times: as the Preferences > Colour Spaces page, where it owns
## the dropdown, and as a preview beside the chooser in File > New and in
## Image > Colour Space, where the dialog owns the dropdown and this only draws.
## Krita's new-image dialog does the same, for the same reason: the name "ACEScg"
## says nothing about how much of the visible spectrum it holds, and a triangle
## over the horseshoe says it at a glance.
##
## The three drawings are their own classes: `SaChromaticityDiagram` owns the
## horseshoe and `SaGamutSolid` the volume under it. This owns the page they sit
## on, the two choosers over them and the legend under.
@tool
class_name SaColorSpaceBrowser
extends VBoxContainer

## Triangle areas this close count as equal, so a gamut is never its own
## "next larger" on a rounding error.
const COMPARE_AREA_EPSILON := 0.0001

## The chooser's last row, for a space no preset names. New Document's word for
## the same thing, `NewDocumentDialog.CUSTOM_LABEL`, so one space has one name.
const CUSTOM_LABEL := "Custom"


## The transfer curve: encoded value in, linear light out.
class TransferPlot:
    extends Control

    ## Where `report` samples the drawn curve, so two curves read as two numbers.
    const SAMPLES: Array[float] = [0.25, 0.5, 0.75]

    var space: SaColorSpace = null

    func _init() -> void:
        custom_minimum_size = Vector2(float(SaUI.px(240)), float(SaUI.px(240)))
        size_flags_horizontal = Control.SIZE_EXPAND_FILL

    ## The square the curve is drawn in, centred in the control.
    ##
    ## Both axes run from nought to one, so the curve only has its shape when
    ## they share a scale: Gamma 3.0 leaves the bottom late and climbs, sRGB has
    ## a toe. The row expands to the page's width, and drawn across all of it at
    ## 1,635 by 110 both were one flat line along the bottom edge. The same
    ## answer `SaChromaticityDiagram.plot_rect` gives the horseshoe above it.
    func plot_rect() -> Rect2:
        var side := minf(size.x, size.y)
        if side <= 0.0:
            return Rect2()
        return Rect2(Vector2((size.x - side) * 0.5, (size.y - side) * 0.5), Vector2(side, side))

    ## *t* encoded to the point it is drawn at, linear light up.
    func to_plot(t: float) -> Vector2:
        var rect := plot_rect()
        var light := space.transfer.decode(t) if space != null else t
        return Vector2(rect.position.x + t * rect.size.x, rect.end.y - light * rect.size.y)

    func _draw() -> void:
        var rect := plot_rect()
        draw_rect(rect, Color(0.08, 0.10, 0.09), true)
        for i in 5:
            var t := float(i) / 4.0
            var x := rect.position.x + t * rect.size.x
            var y := rect.position.y + t * rect.size.y
            draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(1, 1, 1, 0.06), 1.0)
            draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.06), 1.0)

        # y = x for reference, so a linear document's curve visibly lies on it.
        draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), Color(1, 1, 1, 0.18), 1.0)

        if space == null:
            return
        var curve := PackedVector2Array()
        for i in 65:
            curve.append(to_plot(float(i) / 64.0))
        draw_polyline(curve, Color(0.95, 0.55, 0.2), 2.0)

    ## The plot's shape and what it drew, for a capture.
    func report() -> Dictionary:
        var rect := plot_rect()
        var drawn: Array = []
        for t in SAMPLES:
            var at := to_plot(t)
            drawn.append(snappedf((rect.end.y - at.y) / rect.size.y if rect.size.y > 0.0 else 0.0, 0.001))
        return {
            "transfer": String(space.transfer.id) if space != null else "",
            "size": [snappedf(size.x, 0.1), snappedf(size.y, 0.1)],
            "plot":
            [
                snappedf(rect.position.x, 0.1),
                snappedf(rect.position.y, 0.1),
                snappedf(rect.size.x, 0.1),
                snappedf(rect.size.y, 0.1)
            ],
            "drawn_height_at": {"0.25": drawn[0], "0.5": drawn[1], "0.75": drawn[2]},
        }


var option: SaChoiceButton = null
var compare_option: SaChoiceButton = null
var diagram: SaChromaticityDiagram = null
var transfer_plot: TransferPlot = null
var solid: SaGamutSolid = null
## Says which drawn shape is the selected space and which is the comparison,
## and says so in words when the two turn out to be one shape.
var legend: Label = null
var readout: Label = null
var presets: Array[SaColorSpace] = []
var _current_space: SaColorSpace = null
## The last space shown that matched no preset, which the Custom row puts back
## when it is picked. Null until one has been shown.
var _custom_space: SaColorSpace = null

## Hides the browser's own chooser, for embedding it beside one that already
## exists. The page in the info docker owns its dropdown, and the copies in File
## New and Image > Colour Space follow the dropdown the dialog already has: two
## choosers side by side for one choice is worse than none.
var preview_only: bool = false


## Wraps *page* in a scroll view sized so a dialog can always reach its buttons.
##
## The three drawings and the readout add up to several times a dialog's height,
## and a VBoxContainer's minimum is the sum of its children's. Put straight into a
## dialog column, that minimum is larger than the dialog, so the button row below
## it was pushed off the bottom edge: File > New had no way to confirm and
## Image > Colour Space no way to assign or convert. Nothing clips, so there was
## no visual sign of it either.
##
## A ScrollContainer does not propagate its child's minimum height, which is the
## whole fix: the column's minimum falls back to the rows plus the buttons, and
## the preview takes whatever is left.
static func scrolled(page: SaColorSpaceBrowser) -> ScrollContainer:
    var scroll := SaMake.scroll(null, "ColorSpaceScroll")
    # Off, so the child is held to the view's width and only the height scrolls.
    # A horizontal bar here would mean the diagrams had been left at their own
    # minimum width rather than filling.
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # Enough that the view never collapses to a sliver, small enough that it is
    # not the thing deciding how tall the dialog has to be.
    scroll.custom_minimum_size = Vector2(0.0, float(SaUI.px(200)))
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(page)
    return scroll


func _init(preview: bool = false) -> void:
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    preview_only = preview

    presets = SaColorSpace.presets()
    # Sara's own choice button rather than the engine's dropdown. Both choosers
    # key their rows on the position in the list they were built from, because
    # that is what `select_space` and `_on_compare_selected` have always taken
    # and what the `{"dropdown":...}` step still writes.
    var space_rows: Array = []
    for i in presets.size():
        space_rows.append({"id": i, "label": SaColorSpace.display_name(presets[i].id)})
    # The row after the presets, keyed on the list's length the way New
    # Document keys its own. Without it a space no preset names left the
    # button on whatever it showed first, sRGB over a readout of Oklab.
    space_rows.append({"id": presets.size(), "label": tr(CUSTOM_LABEL)})
    option = SaMake.choice(null, "GamutOption", space_rows)
    # Named, so a scenario can reach either chooser by `{"dropdown":...}`.
    # An unnamed control answers to `@Button@47`, which no scenario can write
    # down, and the compare chooser had no other door at all.
    # The node name is `GamutOption` and stays, because scenarios and
    # `test_colour_picker_ring_and_display.gd` reach the control by it, but
    # what it chooses is a colour space and the tooltip is where that is said. A
    # colour space here is primaries, a white point, a transfer curve and a
    # coordinate system together, and two of the seven are in Oklab coordinates,
    # which have no gamut of their own.
    option.tooltip_text = tr(
        "The colour space this page is describing: its gamut, its white point, its curve and its coordinates."
    )
    option.choice_picked.connect(func(row: Variant) -> void: select_space(int(row)))
    option.visible = not preview_only
    add_child(option)

    # This graph is useless with nothing to compare it to: a preview beside a
    # dialog's own chooser keeps the single-space view it always had, and only
    # the standalone Preferences page gets a second dropdown.
    if not preview_only:
        var gamut_rows: Array = []
        var gamut_presets := SaGamut.presets()
        for i in gamut_presets.size():
            gamut_rows.append({"id": i, "label": tr("Compare: %s") % gamut_presets[i].display_name})
        compare_option = SaMake.choice(self, "CompareGamutOption", gamut_rows)
        # This one really is a gamut list, `SaGamut.presets()`, which is why it
        # keeps the word the heading above it lost.
        compare_option.tooltip_text = tr("Compare with a bigger gamut.")
        compare_option.choice_picked.connect(func(row: Variant) -> void: _on_compare_selected(int(row)))

    diagram = SaChromaticityDiagram.new()
    add_child(diagram)

    var caption := SaMake.label(
        self,
        "DiagramCaption",
        tr("CIE 1931 xy. The horseshoe is everything the eye can see, the triangle is the gamut this space holds.")
    )
    caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaUI.size_text(caption, SaUI.fraction_of(10))
    SaTheme.bind_font(caption, "text_muted")

    transfer_plot = TransferPlot.new()
    add_child(transfer_plot)

    solid = SaGamutSolid.new()
    add_child(solid)

    # Which shape is which. The legend shows two shapes and the pair only
    # works if a reader can tell them apart, which a nested wireframe and a
    # nested triangle cannot do on their own.
    legend = SaMake.label(self, "GamutLegend")
    legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaUI.size_text(legend, SaUI.fraction_of(10))

    var solid_caption := SaMake.label(self, "SolidCaption")
    solid_caption.text = tr(
        "The same gamut as a volume, in Oklab. Drag to turn it, Ctrl+wheel to zoom. The diagram above is a slice through this."
    )
    solid_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaUI.size_text(solid_caption, SaUI.fraction_of(10))
    SaTheme.bind_font(solid_caption, "text_muted")

    readout = SaMake.label(self, "Readout")
    SaUI.size_text(readout, SaUI.fraction_of(11))

    select_space(0)


## Draws whatever space it is handed, whether or not a preset happens to match.
##
## A gamut and a curve are chosen separately, so most combinations are not
## presets, and a page that drew only presets would draw nothing for them. The
## dropdown still follows along when there is a match, so the
## page answers "what am I painting in" before "what else is there".
##
## The match ignores storage depth. `SaColorSpace.matches` compares it, a
## document opens at F16 and every preset is F32, so the dropdown never followed
## a real document and the page would read "sRGB" over a drawing of Display P3.
## Nothing on this page depends on depth, and the readout underneath names
## it, so the chooser is about the gamut and the curve.
##
## **A space no preset names puts the chooser on Custom**. The easel's
## default is Oklab over P3 or the display's gamut, which is no preset, and a
## button left on its first row would read "sRGB" over a readout of Gamma 3.0
## and Oklab.
func show_space(space: SaColorSpace) -> void:
    if space == null:
        return
    var matched := presets.size()
    for i in presets.size():
        if presets[i].with_depth(space.depth).matches(space):
            matched = i
            break
    if matched == presets.size():
        _custom_space = space
    option.select_value(matched)
    _render(space)


## Shows preset *index*, or on the Custom row the last space that matched none,
## the easel's default before any has been shown.
func select_space(index: int) -> void:
    if index == presets.size():
        show_space(_custom_space if _custom_space != null else SaEasel.default_space())
        return
    if index < 0 or index > presets.size():
        return
    option.select_value(index)
    _render(presets[index])


func _render(space: SaColorSpace) -> void:
    _current_space = space
    diagram.space = space
    transfer_plot.space = space
    solid.space = space

    if compare_option != null:
        _apply_compare(compare_gamut_for(space))

    diagram.queue_redraw()
    transfer_plot.queue_redraw()
    solid.queue_redraw()
    _refresh_legend()

    var text := tr("Gamut: %s\n") % space.gamut().display_name
    text += tr("Transfer: %s\n") % space.transfer.display_name
    # Said out loud, because everything else on this page describes the RGB view
    # and a reader has no other way to tell that the chunks hold something else.
    text += tr("Coordinates: %s\n") % SaColorSpace.coordinates_name(space.coordinates)
    # The name and the pair from the call the Info docker's white row makes. The
    # pair alone left "D65" in the docker with nothing on this page to say which
    # light that is, and this is the page that describes the spaces.
    text += tr("White: %s\n") % SaColorNames.white_point_text(space.white)
    text += tr("Red:   %.4f, %.4f\n") % [space.primaries[0].x, space.primaries[0].y]
    text += tr("Green: %.4f, %.4f\n") % [space.primaries[1].x, space.primaries[1].y]
    text += tr("Blue:  %.4f, %.4f\n") % [space.primaries[2].x, space.primaries[2].y]
    var to_xyz := space.rgb_to_xyz()
    text += tr("RGB to XYZ, by column:\n")
    for axis: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
        var column: Vector3 = to_xyz * axis
        text += "  %.5f  %.5f  %.5f\n" % [column.x, column.y, column.z]
    readout.text = text


## A manual pick from the "Compare with" dropdown, overriding the default
## `compare_gamut_for` chose.
func _on_compare_selected(index: int) -> void:
    var gamuts := SaGamut.presets()
    if index < 0 or index >= gamuts.size() or _current_space == null:
        return
    _apply_compare(gamuts[index])
    diagram.queue_redraw()
    solid.queue_redraw()
    _refresh_legend()


## Selects *gamut* on the dropdown and hands both drawings a shape to compare
## against: the raw gamut for the flat diagram, and a full colour space sharing
## the selected one's transfer for the volume, so the pair differs only by
## gamut.
func _apply_compare(gamut: SaGamut) -> void:
    if gamut == null:
        # No row is marked and the button says so, and it holds no value, so a
        # press on the gamut it last compared is a pick again.
        compare_option.clear_choice(tr("Compare: nothing larger"))
        diagram.compare = null
        solid.compare = null
        return
    var gamuts := SaGamut.presets()
    for i in gamuts.size():
        if gamuts[i].matches(gamut):
            compare_option.select_value(i)
            break
    diagram.compare = gamut
    solid.compare = SaColorSpace.create(gamut.id, gamut.primaries, gamut.default_white(), _current_space.transfer)


## Names the two shapes, or says there is only one.
##
## A comparison against the gamut already selected draws the same triangle and
## the same wireframe twice, which reads as a rendering fault rather than as an
## answer. The browser says it in words instead, because the graph is useless with nothing to compare against.
func _refresh_legend() -> void:
    if legend == null or _current_space == null:
        return
    var selected := _current_space.gamut()
    var against: SaGamut = diagram.compare
    if against == null and preview_only:
        # A preview has no second dropdown by design, so it draws one shape
        # whatever the gamut is. Saying the widest-on-offer line here is a claim
        # about the gamut, and it is false for three of the four Sara ships:
        # sixteen dumps of a colour space scenario read it over Display P3.
        legend.text = tr("One gamut at a time here. Help > Colour Spaces compares two.")
    elif against == null:
        legend.text = (
            tr("%s is the widest gamut on offer, so there is nothing larger to draw against it.") % selected.display_name
        )
    elif against.matches(selected):
        legend.text = (tr("%s is drawn against itself, so there is one shape here rather than two.") % selected.display_name)
    elif _triangle_area(against.primaries) > _triangle_area(selected.primaries):
        legend.text = (
            tr("Bright and outermost: %s, the wider gamut. Dimmed and inside it: %s, the one selected.")
            % [against.display_name, selected.display_name]
        )
    else:
        legend.text = (
            tr("Bright: %s, narrower than the selection. Dimmed: %s, the one selected, which reaches further out.")
            % [against.display_name, selected.display_name]
        )


## What the two drawings are showing, for a capture.
##
## The node reports itself, the way the minimap and the Display page do, and
## carries the pair each drawing holds rather than a screenshot's worth of
## nested outlines nobody can count.
func capture_state() -> Dictionary:
    return {
        # Which of the two browsers this is. The dialog's preview and the
        # Preferences page answer the same shape, and a dump that does not say
        # which reads an absent comparison as a comparison that found nothing.
        "preview": preview_only,
        "space": String(_current_space.id) if _current_space != null else "",
        "gamut": String(_current_space.gamut().id) if _current_space != null else "",
        "coordinates": SaColorSpace.coordinates_name(_current_space.coordinates) if _current_space != null else "",
        # The readout's white as printed, so a dump can hold it beside the Info
        # docker's row and say the two are one string.
        "white": SaColorNames.white_point_text(_current_space.white) if _current_space != null else "",
        "chooser": option.text if option != null else "",
        "compare_chooser": compare_option.text if compare_option != null else "",
        "legend": legend.text if legend != null else "",
        "diagram": diagram.report(),
        "transfer": transfer_plot.report(),
        "solid": solid.report(),
    }


## The next larger of the registered gamuts by CIE 1931 triangle area (P3
## round sRGB), or the display profile's when that one is larger, or nothing.
##
## AP1 needs its own area rather than `SaGamut.presets()`'s own order: that list
## puts Rec. 2020 after AP1 for the chooser's sake, but AP1 is the larger
## triangle of the two.
static func compare_gamut_for(space: SaColorSpace) -> SaGamut:
    var current_area := _triangle_area(space.gamut().primaries)
    var larger: Array[SaGamut] = []
    for candidate in SaGamut.presets():
        if _triangle_area(candidate.primaries) > current_area + COMPARE_AREA_EPSILON:
            larger.append(candidate)
    if larger.is_empty():
        # Null rather than the display profile whatever its size. A document in
        # ACEScg was drawn against sRGB with sRGB in the bright outer role: the
        # smaller triangle drawn as the larger, which is the opposite of what
        # wanted. The legend says there is nothing larger instead,
        # and a painter who wants a narrower gamut on the same picture can still
        # pick one from the dropdown.
        var display := SaSettings.display_profile_space().gamut()
        return display if _triangle_area(display.primaries) > current_area + COMPARE_AREA_EPSILON else null
    larger.sort_custom(func(a: SaGamut, b: SaGamut) -> bool: return _triangle_area(a.primaries) < _triangle_area(b.primaries))
    return larger[0]


## The shoelace formula over three points, which is all a gamut triangle is.
static func _triangle_area(xy: PackedVector2Array) -> float:
    if xy.size() < 3:
        return 0.0
    var a := xy[0]
    var b := xy[1]
    var c := xy[2]
    return absf(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2.0


## The gamut browser a dump is about, with `window` naming the one it is in and
## `focused` saying whether that window was in front, or nothing while no window
## showing a browser is open. A longer name than the one form, because
## `capture_state` is already this node's own answer, which the dump asks of
## whichever browser this walk picks.
##
## Three controls answer this shape: the Colour Spaces page in Preferences, the
## preview in the Colour Space dialog and a second preview in the New Document
## dialog. The front one is chosen rather than the first the tree holds,
## because Preferences hides on escape rather than freeing, and once a run had
## opened it every later dump would be its browser however many dialogs stood
## in front. The block names the window that answered.
static func capture_front_state(root: Window) -> Dictionary:
    var rows: Array = []
    for window: Window in _visible_windows(root):
        var browser := _browser_in(window)
        if browser == null:
            continue
        rows.append({"title": window.title, "focused": window.has_focus(), "browser": browser})
    var front := _front_browser_row(rows)
    if front.is_empty():
        return {}
    var state: Dictionary = front["browser"].capture_state()
    state["window"] = String(front["title"])
    state["focused"] = bool(front["focused"])
    return state


## Which of *rows* a dump is about: the last one whose window holds the focus,
## and the last one of all when no window does.
##
## Last rather than first, because the walk is in tree order and tree order is
## build order, so the later of two windows is the one opened more recently. That
## alone is not enough, which is the whole of the bug: both windows outlive their
## first opening, so build order stops saying which is in front the moment either
## is reopened. `Window.has_focus` is what does say, and it is asked first.
##
## Split out of the walk above so a suite can drive it. A `Window` outside the
## scene tree cannot be given the focus, so the choice is a function over rows
## rather than over nodes, and the running app proves the wiring.
static func _front_browser_row(rows: Array) -> Dictionary:
    var answer: Dictionary = {}
    for row: Dictionary in rows:
        if answer.is_empty() or bool(row["focused"]) or not bool(answer["focused"]):
            answer = row
    return answer


## Every visible window at or under *node*, outermost first, in tree order.
##
## A hidden window's children are not walked, which is the point of the walk: a
## window Godot has hidden is not on screen, and Preferences hides rather than
## frees, so the browser under it is not what a dump is about.
static func _visible_windows(node: Node) -> Array:
    var found: Array = []
    if node is Window:
        var window := node as Window
        if not window.visible:
            return found
        found.append(window)
    for child in node.get_children():
        found.append_array(_visible_windows(child))
    return found


## The gamut browser *node*'s own window draws, or null. Nested windows are not
## descended into, so a browser belongs to the window that shows it rather than
## to every ancestor of it.
##
## Found by method rather than by class, because a cast to this file's own
## `class_name` inside a static function leaks the script, which only the
## leak report at exit shows. `VBoxContainer` is part of the test rather than
## decoration: a window can answer both method names and not be a browser.
static func _browser_in(node: Node) -> Node:
    for child in node.get_children():
        if child is Window:
            continue
        # Validity first. A page switch frees the previous page in the same
        # frame a dump may be taken in, and `is` against a freed instance is a
        # script error rather than false.
        if not is_instance_valid(child) or child.is_queued_for_deletion():
            continue
        if child is VBoxContainer and child.has_method("capture_state") and child.has_method("show_space"):
            return child
        var found := _browser_in(child)
        if found != null:
            return found
    return null
