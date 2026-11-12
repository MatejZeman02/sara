## How a picture that is not the canvas's size should be placed.
##
## A paste and a drop are imports, and an import of the wrong size has to
## decide something. Three choices, the one that loses nothing preselected, and
## a "Do not ask again" that writes the answer to `SaSettings.import_fit` so a
## painter dropping a folder of references is asked once.
##
## The policy lives here too, in `place`, because the File menu and the Edit
## menu both need it and neither should own the other's copy: a drop asks when
## the sizes differ and the setting says ask, a paste puts the picture down at
## once with the preselected fit, Paste Special always asks, and a stored fit
## puts the picture down with that fit.
##
## The input colour space is in the same window, because the picture's size is
## not the only thing an import has to guess. `SaImageImport.space_for` answers
## the gamut the file names itself where it can: a PNG's `cICP` and a TIFF's
## profile, when it is one Sara writes. Everywhere else it is a rule about the
## format's convention and not about the file, sRGB for a PNG or a JPEG and
## linear sRGB for an EXR, since measured against Godot 4.7 a PNG's `iCCP` and
## `cHRM`, a JPEG's ICC profile and an EXR's `chromaticities` are all read and
## discarded. A PNG's `gAMA` is applied by the loader. So the dropdown is
## offered for every import rather than for a subset, preselected to what the
## file names or to the convention, and the line under it says which of the two
## it is. What the dropdown changes is the space `place` converts *from*.
##
## Opening a picture as a document is the window's second job and second
## shape. A picture opened as a document of its own is not fitted to anything,
## the canvas becomes its size, so the fit row means nothing there. What it does
## have to answer is the depth the document is stored at, which an eight-bit file cannot answer for itself. So the window
## has two modes, one row swapped for the other: `place` asks how a picture
## lands in the document that is open, `choose_depth` asks what a picture
## becoming a document costs. The colour space row is in both, because a file's
## gamut is a guess either way.
@tool
class_name SaImportFitDialog
extends SaDialogWindow

## The painter chose. The id is one of `SaImageImport.Fit`, and *source* is the
## space the picture is to be read as, which is the dropdown's answer rather
## than the caller's guess.
signal fit_chosen(fit: SaImageImport.Fit, source: SaColorSpace)

## The painter chose a depth for a picture that is becoming a document. *source*
## carries both answers: the gamut the space row is on, at the depth the depth
## row is on, which is what the new document is built with.
signal depth_chosen(source: SaColorSpace)

## The four the dialog offers, as `[fit, label, hint]`, in the order shown.
const CHOICES: Array = [
    [
        SaImageImport.Fit.STRETCH,
        "Stretch to the canvas",
        "The picture is stretched to fill the document, even where that changes its proportions.",
    ],
    [
        SaImageImport.Fit.ACTUAL,
        "Place at actual size",
        "Its own pixels, centred. Anything past the edge is kept and not shown.",
    ],
    [
        SaImageImport.Fit.INSIDE,
        "Fit inside the canvas",
        "The largest that fits with the ratio kept, centred.",
    ],
    [
        SaImageImport.Fit.GROW,
        "Grow the canvas to fit",
        "The canvas grows about its middle until the picture fits at its own pixels, centred.",
    ],
]

## When `place` opens the window, which its caller says: a drop under "ask", a
## paste never, Paste Special always.
enum Asks { UNDER_ASK, NEVER, ALWAYS }

## The setting's word for each fit, and the other way round.
const SETTING_NAMES: Dictionary = {
    SaImageImport.Fit.STRETCH: "stretch",
    SaImageImport.Fit.ACTUAL: "actual",
    SaImageImport.Fit.INSIDE: "inside",
    SaImageImport.Fit.GROW: "grow",
}

## The window when it asks about the fit, and when it asks about the depth.
##
## The numbers are measured against the Place and Open buttons' own rects in the
## scenario's dump rather than reasoned about, because a size reasoned about
## puts a button below the bottom edge as soon as the font grows.
##
## As a page, the fit question's Place button ends at 410 and the open
## question's Open button at 433. The first was measured by the scenario named
## after the Place button staying put, with each wrapped line held at its
## tallest sentence, in a window of 422 where the content set the height, and
## the second by the scenario named after the "Show this next time" row, in a
## window of 445. The fit size is its button
## plus 70, rather than 64, because a distro build wraps a line further, and its
## minimum the 422 the content needs. The open size is its button plus 37 and
## its minimum the 445 the content needs, since the window grows to what its
## rows ask for whatever a constant says.
const FIT_SIZE: Vector2i = Vector2i(440, 480)
const FIT_MIN_SIZE: Vector2i = Vector2i(400, 422)
const OPEN_SIZE: Vector2i = Vector2i(440, 470)
const OPEN_MIN_SIZE: Vector2i = Vector2i(400, 445)

## The first line of each question, the sizes in pixels. The fit question names
## a picture or a copy out of Sara's clipboard, the open question a float width
## the file names or the eight bits it holds. They are constants because the
## line's reserve reads them as well as the line does.
const PICTURE_LINE: String = "The picture is %s × %s px and the canvas is %s × %s px."
const COPY_LINE: String = "The copy is %s × %s px and the canvas is %s × %s px."
const OPENS_NAMED_LINE: String = "The picture opens as a new document of %s × %s px. The file is %s."
const OPENS_BYTES_LINE: String = (
    "The picture opens as a new document of %s × %s px. "
    + "It holds 8 bits a channel, so choose below the depth the document keeps it in."
)

## The size a line's reserve fills a sentence's numbers with, five of the widest
## digit, since no picture Sara opens is wider than 16384 pixels.
const RESERVED_NUMBER: String = "88888"

## The setting's word for each depth, and the other way round.
const DEPTH_SETTING_NAMES: Dictionary = {
    SaColorSpace.Depth.F32: "f32",
    SaColorSpace.Depth.F16: "f16",
}

## The four rows the page binds, one property each. The three dropdowns and the
## check are the page's, and this window reads what they wrote. *space_id* is
## the id of one of `_space_choices`, as a string because the row's ids are.
var space_id: String = ""
var wanted_fit: int = SaImageImport.Fit.INSIDE
var wanted_depth: int = SaColorSpace.Depth.F16
var remember: bool = false
## The open question's switch, "Show this next time", which the page binds. On
## it leaves `SaSettings.ask_when_opening` as it was, and off with Open writes it.
var show_next_time: bool = true

## The declared rows, realized once into `ImportFitPage`.
var page: SaPage = null

var _size_label: Label = null
## The rows a question shows or hides, and the one whose list is refilled, kept
## by `_declare` as it declares them.
var _space_row: SaPageRow = null
var _fit_row: SaPageRow = null
var _depth_row: SaPageRow = null
var _remember_row: SaPageRow = null
var _show_row: SaPageRow = null
## The fit row's own sentence, which follows the fit it is on.
var _fit_hint: Label = null
## What the file said of the gamut the space row opened on, which the row's
## sentence, tooltip and names follow.
var _said: SaImportSpaceWords = SaImportSpaceWords.new()
var _place_button: Button = null
## The presets and the file's space the dropdown opens with, in its order.
var _space_choices: Array[SaColorSpace] = []
## Those with the saved spaces and Custom..., which opens the colour space picker.
var _spaces := SaColorSpaceRow.new()
## Which question the window is up to answer, `place`'s or `choose_depth`'s.
var _asks_depth: bool = false
## The float width the open file named, or -1 when it named none. What the
## depth row opened on, and what decides whether confirming writes the habit
## back.
var _depth_from_file: int = -1
## The first line's, the fit row's and the space row's reserves, which hold each
## at the height of the tallest sentence it may carry, so the buttons below them
## stay where they are.
var _reserves: Array[SaLineReserve] = []
## The questions asked while the window was up, oldest first, each the call
## that asked it, run again once the window closes.
var _waiting: Array[Callable] = []
## A waiting question is being run, and asks rather than waits again.
var _taking_next: bool = false


func _init() -> void:
    # The slack over the measured Place button is for a shaping engine that
    # wraps a line further, which a distro Godot build does. The scenario
    # measures the button's own rect against the window rather than trusting a
    # number here.
    _init_dialog("ImportFitDialog", tr("Fit the picture"), FIT_SIZE, FIT_MIN_SIZE)
    visibility_changed.connect(_on_question_closed)
    _spaces.answered.connect(func(id: String) -> void: select_space(StringName(id)))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    # Everything above the buttons scrolls, for the reason Image Size gives. Each
    # wrapped line holds the height of its tallest sentence, and in the room 335
    # tall that a scale of 2 leaves on a 1280 by 800 screen the buttons then
    # ended below the window.
    var rows_view := SaMake.scroll(column, "RowsScroll")
    rows_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    rows_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = rows_view
    var rows := SaMake.column(rows_view, "Rows", SaTheme.GAP)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _size_label = SaMake.label(rows, "SizeLabel")
    _size_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    # One page for both questions, so the dropdowns share a left edge and each
    # sentence sits under the title of the row it explains.
    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(SaMake.column(rows, "ImportFitPage"))
    page.row_changed.connect(_on_row_changed)
    _depth_row.control.tooltip_text = tr("Both are floating point. 16-bit uses half the memory, 32-bit keeps the most precision.")
    _remember_row.control.tooltip_text = tr("You can turn this question back on in Preferences > Files.")
    _show_row.control.tooltip_text = tr(
        "When off, pictures open straight away with these settings. You can turn this question back on in Preferences > Files."
    )
    _fit_hint = _fit_row.line.find_child("Hint", true, false) as Label
    _fit_hint.name = "FitHint"
    var fit_option := _fit_row.control as SaChoiceButton
    fit_option.theme_changed.connect(_show_every_fit_whole.bind(fit_option))
    var space_hint := _space_row.line.find_child("Hint", true, false) as Label
    _reserves = [
        SaLineReserve.new(_size_label, _size_sentences),
        SaLineReserve.new(_fit_hint, _fit_sentences),
        SaLineReserve.new(space_hint, _space_sentences),
    ]

    var buttons := SaMake.row(column, "Buttons", SaTheme.GAP)
    buttons.alignment = BoxContainer.ALIGNMENT_END
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size.x = float(SaUI.px(90))
    cancel_button.pressed.connect(hide)
    _place_button = SaMake.button(buttons, "PlaceButton", tr("Place"))
    _place_button.custom_minimum_size.x = float(SaUI.px(90))
    _place_button.pressed.connect(_confirm)
    default_button = _place_button
    # Named rather than left to the Tab walk, which skips every dropdown here
    # because an `SaDropdownButton` takes no focus. In the open question the fit
    # row and the "Do not ask again" box are hidden, so the walk reached Cancel
    # first, its outline went there and Enter cancelled the open. In the fit
    # question it reached the box, and Enter ticked it rather than placing.
    first_focus = _place_button

    _fill_spaces(SaColorSpace.srgb())
    _show_fit_hint()
    # The fit question is what this window was, so it is what it is built as.
    # Both `configure` and `configure_open` say which one they want, and this is
    # only here so a window shown by neither is not both at once.
    _show_depth_question(false)


## The page, four rows and two of them per question.
##
## **Read the picture as**, the RGB presets. Oklab is left out on purpose. It
## is a storage choice a Sara document may make and not a space a PNG, a JPEG
## or an EXR is ever written in, so offering it here would be an option nobody
## can honestly pick. The filter asks the preset for its coordinate system
## rather than naming Oklab, so a later non-RGB preset drops out of this list by
## itself. Its sentence is `_show_space_hint`'s, one of two according to whether
## the file named its gamut, and both stay true when the dropdown is moved off
## where it opened: they say where it started and why.
##
## **Place the picture**, the four fits, as one dropdown rather than four
## toggle buttons with a paragraph under each, which is six rows that alternate
## and reads as confusing. Its sentence is the chosen fit's own, because
## the choice is made once per import and the sentence that describes what is
## about to happen is the one worth the room.
##
## **Bit depth**, the two float depths, named by `depth_name`, which is the New
## Document dialog's own row and copied on purpose rather than reworded: the two
## windows ask the same question about the same document. Hard rule 5 is not in
## question here, because both of them are float. Its sentence is the trade
## rather than a description of one side of it, and the file cannot answer it:
## an eight-bit picture has no float width to report.
##
## **Do not ask again**, which writes the fit to `SaSettings.import_fit`.
##
## **Show this next time**, the open question's own switch, which writes
## `SaSettings.ask_when_opening` when Open is pressed with it off.
func _declare(ui: SaPage) -> void:
    var fits: Array = CHOICES.map(func(choice: Array) -> Dictionary: return {"id": int(choice[0]), "label": choice[1]})
    var depths: Array = SaColorSpace.storage_depths().map(
        func(each: int) -> Dictionary: return {"id": each, "label": SaColorSpace.depth_name(each)}
    )
    var rows := ui.section("")
    # Declared with the convention's sentence, which is what the row opens on
    # before any file has been looked at. `_show_space_hint` rewrites it.
    _space_row = rows.choice("Read the picture as", [], self, ^"space_id").named(&"space").node("InputSpaceOption").explain(
        SaImportSpaceWords.UNNAMED_LINE
    )
    _spaces.attach(_space_row)
    # Declared with the sentence of the fit it opens on, so the row draws the
    # line `_show_fit_hint` rewrites.
    var opening_hint: String = CHOICES[_fit_index()][2]
    _fit_row = rows.choice("Place the picture", fits, self, ^"wanted_fit").named(&"fit").node("FitOption").explain(opening_hint)
    _depth_row = rows.choice("Bit depth", depths, self, ^"wanted_depth").named(&"depth").node("DepthOption").explain(
        tr("16-bit halves what the canvas costs in memory. 32-bit keeps every value a filter or an EXR can put in it.")
    )
    _remember_row = rows.toggle("Do not ask again", self, ^"remember").named(&"remember").node("RememberCheck")
    _show_row = rows.toggle("Show this next time", self, ^"show_next_time").named(&"show_next_time").node("ShowNextTimeCheck")


## Widens the Place the picture choice to its longest fit, so the button never
## cuts the one it is on.
##
## A `SaChoiceButton` clips its text rather than widening its row, and the
## column the dialog's 440 leaves it is narrower than the longest fit, which
## would read "Fit inside the ca…". The width is the button's own minimum, which
## is its frame and its arrow with the clipped text at nothing, plus the widest
## of the four labels in its own font. The window opens at what its content
## needs (`SaDialogWindow.fit_opening_size`), so it grows with the button. On
## `theme_changed`, because the interface scale and the Font size preference
## both reach the button that way and both move the label's width.
func _show_every_fit_whole(option: SaChoiceButton) -> void:
    var font := option.get_theme_font(&"font")
    var points := option.get_theme_font_size(&"font_size")
    var widest := 0.0
    for label: String in option.choice_labels():
        widest = maxf(widest, font.get_string_size(tr(label), HORIZONTAL_ALIGNMENT_LEFT, -1, points).x)
    var arrow := option.get_theme_icon(&"arrow", &"OptionButton")
    var frame := option.get_theme_stylebox(&"normal").get_minimum_size().x
    var beside := float(option.get_theme_constant(&"h_separation")) + (float(arrow.get_width()) if arrow != null else 0.0)
    option.custom_minimum_size.x = ceilf(widest + frame + beside)


## The fit row moved, so its sentence follows. The other rows wrote their
## property and nothing else hangs on them.
func _on_row_changed(key: StringName, _value: Variant) -> void:
    if key == &"fit":
        _show_fit_hint()
    elif key == &"space" and space_id != _spaces.take(space_id):
        # Custom... opened the picker, and the row goes back until it answers.
        space_id = _spaces.chosen
        page.refresh.call_deferred()


## Puts the chosen fit's sentence under the row's title.
func _show_fit_hint() -> void:
    var at := _fit_index()
    _fit_hint.text = tr(String(CHOICES[at][2])) if at >= 0 else ""


## Which row of `CHOICES` the fit is, and -1 for a fit the dialog does not offer.
func _fit_index() -> int:
    for i in CHOICES.size():
        if int(CHOICES[i][0]) == wanted_fit:
            return i
    return -1


## Refills the space row around *source*, which is preselected, and says in the
## row's sentence whether the file *named* it. A space the presets do not carry,
## a custom one out of a `.sad`, is appended rather than dropped, or the caller's
## own answer would vanish the moment this window opened over it. The list is
## the row's as well as the button's, so the page marks the row it is on. A
## custom space read off a *profile* is listed by the profile's name.
func _fill_spaces(source: SaColorSpace, named: bool = false, profile: SaIccProfile = null) -> void:
    _space_choices.clear()
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.coordinates == SaColorSpace.Coordinates.RGB:
            _space_choices.append(preset)
    if not _space_choices.any(func(space: SaColorSpace) -> bool: return space.id == source.id):
        _space_choices.append(source)
    _said = SaImportSpaceWords.new(named, profile)
    _spaces.fill(_space_choices, _space_choices.map(func(space: SaColorSpace) -> String: return _said.name_of(space.id)))
    space_id = _spaces.take(String(source.id))
    page.refresh()
    _show_space_hint()
    _reserve_lines()


## Puts the space row's sentence and its tooltip on the case it opened in, the
## gamut the file named or the convention for want of one.
func _show_space_hint() -> void:
    # Through the row, so its `explanation` and the dump read the words on screen.
    _space_row.retitle(_space_row.label, _said.line(StringName(space_id)))
    _space_row.control.tooltip_text = _said.tip(StringName(space_id))


## Puts the space row on the preset called *wanted*, and answers whether there
## was one. The capture harness's door: the dropdown's popup is a Window, so an
## injected click cannot reach a row of it.
func select_space(wanted: StringName) -> bool:
    if not _spaces.has(String(wanted)) or String(wanted) == SaColorSpaceRow.ASK_ID:
        return false
    space_id = _spaces.take(String(wanted))
    page.refresh()
    return true


## The space the row is on, which is what the picture is converted from.
func chosen_space() -> SaColorSpace:
    return _spaces.space_of(space_id)


## Puts the depth row on *wanted*, and answers whether storage offers it. The
## door the space row's `select_space` is, and for the same reason: the list is
## a Window that no injected click reaches.
func select_depth(wanted: int) -> bool:
    if not SaColorSpace.storage_depths().has(wanted):
        return false
    wanted_depth = wanted
    page.refresh()
    return true


## The depth the row is on, which is what the new document is stored at.
func chosen_depth() -> int:
    return wanted_depth


## The depth the painter last chose, which is what the dropdown opens on.
static func remembered_depth() -> int:
    return depth_from_setting(SaSettings.import_depth)


## The depth a stored setting names, and F16 for anything else, which is the
## fallback `SaSettingsValues.import_depth` already applies on its way in.
static func depth_from_setting(name_in_settings: String) -> int:
    for depth: int in DEPTH_SETTING_NAMES:
        if DEPTH_SETTING_NAMES[depth] == name_in_settings:
            return depth
    return SaColorSpace.Depth.F16


## The word the settings file keeps *depth* under.
static func setting_for_depth(depth: int) -> String:
    return String(DEPTH_SETTING_NAMES.get(depth, "f16"))


## Shows what is about to be placed, and preselects the choice that loses
## nothing, `preselected_fit`. *source* is the convention the
## caller read the file as, which the colour space row preselects, and *named*
## says the file itself named it rather than the format's convention supplying it.
## *profile* is the ICC profile the file carries, `SaImageImport.profile_for`,
## which the line names, or says why it was not used.
func configure(
    image_size: Vector2i, canvas_size: Vector2i, source: SaColorSpace = null, named: bool = false, profile: SaIccProfile = null
) -> void:
    _show_depth_question(false)
    _size_label.text = tr(PICTURE_LINE) % [image_size.x, image_size.y, canvas_size.x, canvas_size.y]
    remember = false
    _space_row.line.visible = true
    _fill_spaces(source if source != null else SaColorSpace.srgb(), named, profile)
    select(preselected_fit(image_size, canvas_size))


## The fit a picture lands with when nobody chose one: Place at actual size when
## it is no larger than the canvas on either side, and Fit inside when it is
## larger on either. Stretch only ever by the painter's own choice.
##
## Preselecting Fit inside whenever the ratios differ would bring a 240 by 160
## picture onto a 1920 by 1080 canvas at 1620 by 1080, and a picture blown up
## six times over is not the picture the painter copied. The same ratio earns
## no Stretch either: a picture the shape of the canvas and smaller than it is
## still one the painter meant at its own size.
static func preselected_fit(image_size: Vector2i, canvas_size: Vector2i) -> SaImageImport.Fit:
    if image_size.x <= canvas_size.x and image_size.y <= canvas_size.y:
        return SaImageImport.Fit.ACTUAL
    return SaImageImport.Fit.INSIDE


## `configure` for a copy out of Sara's clipboard, `place_held`'s question: the
## size line names a copy, the fit opens on its own pixels, Photoshop's answer
## and the one that keeps every texel, and the space row is hidden because the
## copy's *space* is known rather than guessed.
func configure_held(copy_size: Vector2i, canvas_size: Vector2i, space: SaColorSpace) -> void:
    configure(copy_size, canvas_size, space, true)
    _size_label.text = tr(COPY_LINE) % [copy_size.x, copy_size.y, canvas_size.x, canvas_size.y]
    _space_row.line.visible = false
    select(SaImageImport.Fit.ACTUAL)


## Shows what is about to become a document, and preselects a depth for it.
##
## *named_depth* is the float width the file carries, or -1 when it carries
## none, and it is the first answer whenever there is one: a file that says how
## wide its floats are has answered better than any habit could. The painter's
## last choice is what fills the row in when the file is silent, and a silent
## file is one of bytes, so its sentence says so. It is asked about only
## when Preferences asks every time, `SaOpenDepth.asks_for`.
##
## There is no fit to preselect: the canvas becomes the picture, so the row is
## not shown at all rather than shown with an answer nothing acts on. There is
## no "Do not ask again" either, since that one is the fit's habit. The habit
## this window has is its own switch, "Show this next time", which opens on and
## which `SaSettings.ask_when_opening` keeps once it is turned off. A depth is
## still one document's cost, so what the depth row is left on is
## `import_depth`'s and not the switch's.
func configure_open(
    image_size: Vector2i, source: SaColorSpace = null, named_depth: int = -1, named: bool = false, profile: SaIccProfile = null
) -> void:
    _show_depth_question(true)
    _space_row.line.visible = true
    show_next_time = true
    page.refresh()
    _depth_from_file = named_depth
    if named_depth >= 0:
        _size_label.text = tr(OPENS_NAMED_LINE) % [image_size.x, image_size.y, tr(SaColorSpace.depth_name(named_depth))]
    else:
        _size_label.text = tr(OPENS_BYTES_LINE) % [image_size.x, image_size.y]
    _fill_spaces(source if source != null else SaColorSpace.srgb(), named, profile)
    select_depth(named_depth if named_depth >= 0 else remembered_depth())


## Puts the window into one of its two questions: the fit row and the "do not
## ask again" box for an import, the depth row for an open.
##
## The title and the button move with the rows, because a window that says "Fit
## the picture" over a control that fits nothing is worse than no title. The
## drag bar carries its own copy of the title, so both are written.
func _show_depth_question(asks: bool) -> void:
    _asks_depth = asks
    _fit_row.line.visible = not asks
    _remember_row.line.visible = not asks
    _show_row.line.visible = asks
    _depth_row.line.visible = asks
    _place_button.text = tr("Open", "open a document") if asks else tr("Place")
    var bar_title := tr("Open the picture") if asks else tr("Fit the picture")
    title = bar_title
    var label := find_child("TitleLabel", true, false) as Label
    if label != null:
        label.text = bar_title
    # Through `logical_size` and `apply_window_scale` rather than by writing
    # `size`, because that is the one that survives an interface scale change:
    # a number written straight into `size` is undone the next time the scale
    # is applied, which is how a dialog ends up at another window's height.
    logical_size = OPEN_SIZE if asks else FIT_SIZE
    logical_min_size = OPEN_MIN_SIZE if asks else FIT_MIN_SIZE
    # Not before the window is in the tree, where there is no host to ask how
    # this one is scaled. The constructor's own call is the fit size, which is
    # what `_init_dialog` set anyway, and `_ready` applies it.
    #
    # `min_size` first, and this is not a tidiness. `apply_window_scale` writes
    # `size` before `min_size`, so a window coming back from the taller mode
    # would be clamped up to the height it is leaving and stay there, and the
    # dump would read the old minimum rather than either mode's size.
    if is_inside_tree():
        min_size = SaUI.window_size_for(self, logical_min_size)
        apply_window_scale()
    _reserve_lines()


## Measures every reserved line again, for a question or a list of spaces that
## has just changed what the lines may say.
func _reserve_lines() -> void:
    for reserve: SaLineReserve in _reserves:
        reserve.measure()


## Every first line the question in hand can open with, its numbers the widest
## a picture has.
func _size_sentences() -> Array:
    var n := RESERVED_NUMBER
    if _asks_depth:
        var said: Array = [tr(OPENS_BYTES_LINE) % [n, n]]
        for depth: int in SaColorSpace.storage_depths():
            said.append(tr(OPENS_NAMED_LINE) % [n, n, tr(SaColorSpace.depth_name(depth))])
        return said
    return [tr(PICTURE_LINE) % [n, n, n, n], tr(COPY_LINE) % [n, n, n, n]]


## Every fit's sentence, `CHOICES`'s third column.
func _fit_sentences() -> Array:
    var said: Array = []
    for i in CHOICES.size():
        said.append(tr(String(CHOICES[i][2])))
    return said


## The space row's sentence for a file that names nothing, and for one that names
## each space the row lists.
func _space_sentences() -> Array:
    return _said.sentences(_space_choices)


## Within half a percent, so a 1600 by 900 picture on a 1920 by 1080 canvas
## counts as the same shape and an off-by-one rounding does not decide this.
static func same_ratio(image_size: Vector2i, canvas_size: Vector2i) -> bool:
    if image_size.y <= 0 or canvas_size.y <= 0:
        return false
    var one := float(image_size.x) / float(image_size.y)
    var other := float(canvas_size.x) / float(canvas_size.y)
    return absf(one - other) <= 0.005 * other


## Puts the fit row on *wanted*, when the dialog offers it, and its sentence
## under the row's title.
func select(wanted: SaImageImport.Fit) -> void:
    if CHOICES.any(func(choice: Array) -> bool: return int(choice[0]) == int(wanted)):
        wanted_fit = wanted
        page.refresh()
        _show_fit_hint()


func chosen_fit() -> SaImageImport.Fit:
    return wanted_fit as SaImageImport.Fit


## What the dialog is offering and what it is on, for a capture that has to show
## the four choices are one control and that they line up with the row
## above. A picture cannot say whether two rows share a left edge to the pixel.
static func capture_state(root: Window) -> Dictionary:
    var dialog := root.find_child("ImportFitDialog", true, false) as SaImportFitDialog
    if dialog == null or not dialog.visible:
        return {}
    var rows: Array = []
    for row: SaPageRow in [dialog._space_row, dialog._fit_row, dialog._depth_row]:
        var option := row.control as SaChoiceButton
        (
            rows
            . append(
                {
                    "row": String(row.key),
                    "text": option.text,
                    "items": option.choice_labels().size(),
                    # The depth question swaps one row for the other, and a
                    # hidden button still answers what it is on. Without this
                    # the dump reads the same whichever question is up, which is
                    # the one thing the shot beside it cannot argue with.
                    "shown": row.line.visible,
                    "rect": _rect_of(option),
                    # Whether the label it is on is wider than the room the
                    # button gives it, which ends a long name in an ellipsis.
                    "cut": _cuts(option),
                    # Whether the sentence under the title is a step smaller
                    # than the title.
                    "title_font_size": _font_size_of(row.line.find_child("Title", true, false) as Control),
                    "hint_font_size": _font_size_of(row.line.find_child("*Hint", true, false) as Control),
                }
            )
        )
    return {
        "size": {"x": dialog.size.x, "y": dialog.size.y},
        # Where the window stands in the one it is embedded in, so the rects
        # below, which are the window's own, can be found in a shot.
        "position": {"x": dialog.position.x, "y": dialog.position.y},
        "asks": "depth" if dialog._asks_depth else "fit",
        "options": rows,
        # The sentence over the rows, which names every size in pixels and,
        # on the open question, says the picture opens as a new document.
        "size_text": dialog._size_label.text,
        "size_rect": _rect_of(dialog._size_label),
        "fit_hint": dialog._fit_hint.text,
        # The sentence under the space row, which says whether the file named
        # the gamut the row opened on or the convention supplied it.
        "space_hint": dialog._space_row.explanation,
        "gamut_named": dialog._said.named,
        # The open question's switch, which a picture cannot say the state of.
        "show_next_time": dialog.show_next_time,
        "show_next_time_shown": dialog._show_row.line.visible,
        "space_tip": dialog._space_row.control.tooltip_text,
        # The bottom of this against the window's height is what says the two
        # wrapped hints did not push the buttons off the edge.
        "place_button": _rect_of(dialog.find_child("PlaceButton", true, false) as Control),
        # Zero says the three toggle buttons are gone rather than merely
        # restyled, which is the half a screenshot argues about.
        "fit_toggle_buttons": dialog.find_children("Fit*Radio", "Button", true, false).size(),
    }


## Whether *option* draws its label cut: the text in its own font against the
## button's width less its frame, its arrow and the gap beside it.
static func _cuts(option: SaChoiceButton) -> bool:
    var font := option.get_theme_font(&"font")
    var text_width := font.get_string_size(option.text, HORIZONTAL_ALIGNMENT_LEFT, -1, option.get_theme_font_size(&"font_size")).x
    var arrow: float = float(option.icon.get_width()) if option.icon != null else 0.0
    var room: float = option.size.x - option.get_theme_stylebox(&"normal").get_minimum_size().x - arrow
    return text_width > room - float(option.get_theme_constant(&"h_separation"))


static func _font_size_of(control: Control) -> int:
    return control.get_theme_font_size("font_size") if control != null else 0


static func _rect_of(control: Control) -> Dictionary:
    if control == null:
        return {}
    var r := control.get_global_rect()
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


func remembers() -> bool:
    return remember


func _confirm() -> void:
    if _asks_depth:
        var depth := chosen_depth()
        # Written on confirming rather than behind a checkbox, which is what
        # "the painter's last choice" means: the next picture that cannot answer
        # for itself is offered this one's answer first.
        #
        # Not when the file filled the row in and the painter left it there. An
        # Enter over a half-float EXR is agreement with the file, and taking it
        # for a preference would flip the habit of a painter who never touched
        # the dropdown. Moving it off the file's answer is a choice, and that
        # one is kept, because the row is read back rather than the flag.
        if depth != _depth_from_file:
            SaSettings.import_depth = setting_for_depth(depth)
        # Open is the answer that keeps the switch, and Cancel never reaches
        # here, so a window shut with the switch off asked nothing of it.
        if not show_next_time:
            SaSettings.ask_when_opening = false
        hide()
        depth_chosen.emit(chosen_space().with_depth(depth as SaColorSpace.Depth))
        return
    var fit := chosen_fit()
    if remembers():
        SaSettings.import_fit = String(SETTING_NAMES.get(fit, "ask"))
    hide()
    # "Do not ask again" remembers the fit and never the space, because a fit is
    # a habit and a space is a fact about one file. A painter who drops a folder
    # of EXRs and a folder of phone screenshots wants the second question asked.
    fit_chosen.emit(fit, chosen_space())


## The fit a stored setting names, and ORIGIN for "ask", which no caller
## should reach: `place` asks instead.
static func fit_from_setting(name_in_settings: String) -> SaImageImport.Fit:
    for fit: SaImageImport.Fit in SETTING_NAMES:
        if SETTING_NAMES[fit] == name_in_settings:
            return fit
    return SaImageImport.Fit.ORIGIN


## Puts *image* into *document*, asking first when its size differs from the
## canvas and the setting still says ask, and handing the layer to *done*.
##
## *asks* is the caller's say in what "ask" means. `Asks.UNDER_ASK` is a drop's,
## which asks when the setting says so. `Asks.NEVER` is a paste's: under "ask"
## it places at once with the fit `preselected_fit` gives and says so in the
## message bar, the way Photoshop pastes at once, centred at its size. A stored
## fit still wins over that, so the Files page answers for a paste as well as a
## drop. `Asks.ALWAYS` is Paste Special's, which opens the window whatever the
## setting holds, so the painter can be asked on purpose.
##
## The one entry both menus use, so a paste and a drop cannot drift. *host* is
## a node in the window the dialog opens over, and a host outside the tree
## places without asking rather than building a `Window` nothing can show,
## which is what a headless test has.
##
## *named* is whether the file said *source* itself, the `SaImageImport` answer
## `named_space_for` is not null, and it only changes what the window's line
## says: a space read off the file or the one its format is usually in.
## *profile* is the ICC profile the file carries, which the line names.
static func place(
    host: Node,
    document: SaDocument,
    image: Image,
    layer_name: String,
    source: SaColorSpace,
    done: Callable = Callable(),
    named: bool = false,
    asks: Asks = Asks.UNDER_ASK,
    profile: SaIccProfile = null
) -> void:
    if document == null or image == null or image.is_empty():
        return
    var stored := SaSettings.import_fit
    var step := "Place Picture" if asks == Asks.UNDER_ASK else "Paste"
    var sizes_differ := image.get_size() != document.canvas_size
    if asks == Asks.NEVER and stored == "ask" and sizes_differ:
        var chosen := preselected_fit(image.get_size(), document.canvas_size)
        _place_and_report(document, image, layer_name, source, chosen, done, step)
        SaMessage.notice(placed_line(chosen))
        return
    var opens := asks == Asks.ALWAYS or (asks == Asks.UNDER_ASK and stored == "ask" and sizes_differ)
    if not opens or host == null or not host.is_inside_tree():
        var fit := fit_from_setting(stored)
        _place_and_report(document, image, layer_name, source, fit, done, step)
        return

    var dialog := for_host(host)
    var again := func() -> void:
        if is_instance_valid(document):
            place(host, document, image, layer_name, source, done, named, asks, profile)
    if dialog._waits(again):
        return
    # Every call rebinds: the payload of the last drop is not this one's.
    for connection: Dictionary in dialog.fit_chosen.get_connections():
        dialog.fit_chosen.disconnect(connection["callable"])
    dialog.fit_chosen.connect(
        func(fit: SaImageImport.Fit, chosen: SaColorSpace) -> void:
            _place_and_report(document, image, layer_name, chosen, fit, done, step)
    )
    dialog.configure(image.get_size(), document.canvas_size, source, named, profile)
    dialog.popup_centered()


## Pastes Sara's own *held* clipboard into *document*, asking first how it
## lands when the copy is wider or taller than the canvas and the setting still
## says ask, and handing the layer to *done*.
##
## `place`'s policy for a copy rather than a picture, so "Do not ask again"
## answers both. A copy that fits is put down at its own size without asking,
## in place on a canvas the size of its own and centred on any other,
## `SaClipboard.offset_in`, because that loses nothing. The colour space row is hidden: the clipboard knows the space it
## was painted in, and offering to read it as another would be a guess where
## there is a fact. A remembered fit is used only where the copy overhangs, the
## one case the question is about.
static func place_held(host: Node, document: SaDocument, held: SaClipboard, done: Callable = Callable()) -> void:
    if document == null or held == null or held.is_empty():
        return
    var stored := SaSettings.import_fit
    if not held.overhangs(document):
        _report(held.paste(document), done)
        return
    if stored != "ask" or host == null or not host.is_inside_tree():
        var remembered := fit_from_setting(stored)
        _report(held.paste(document, "Pasted Layer", remembered), done)
        return
    var dialog := for_host(host)
    var again := func() -> void:
        if is_instance_valid(document):
            place_held(host, document, held, done)
    if dialog._waits(again):
        return
    for connection: Dictionary in dialog.fit_chosen.get_connections():
        dialog.fit_chosen.disconnect(connection["callable"])
    dialog.fit_chosen.connect(
        func(fit: SaImageImport.Fit, _chosen: SaColorSpace) -> void: _report(held.paste(document, "Pasted Layer", fit), done)
    )
    dialog.configure_held(held.bounds.size, document.canvas_size, held.space)
    dialog.popup_centered()


static func _report(layer: SaLayer, done: Callable) -> void:
    if done.is_valid():
        done.call(layer)


## Asks which float depth a picture that is becoming a document should be stored
## at, and hands the answer to *done* as the space to build it with.
##
## The other half of `place`: that one asks how a picture lands in the document
## that is already open, this one asks what a picture that *is* the document
## costs. Both go through the one window, so a painter meets the colour space
## row in the same place either way.
##
## The window opens for every picture rather than only for the silent ones, until
## the painter turns "Show this next time" off. A file that names its own float
## width fills the row in and Enter agrees with it, so a float width is never
## taken without the painter seeing it, and the window has one behaviour: what
## changes with the file is the preselection, not whether the painter is shown
## the choice. The same window is where the gamut an open guesses is shown.
##
## A host outside the tree cannot show a window, and a painter who turned the
## switch off does not want one, so both answer the way the row would have
## opened: the file's width when it names one, and the remembered choice when it
## does not. That is the shape `place` already has, and the reason a headless
## test can walk this path at all.
##
## *named* and *profile* are `place`'s, whether the file said *source* itself
## and the ICC profile it carries.
static func choose_depth(
    host: Node, image: Image, source: SaColorSpace, done: Callable, named: bool = false, profile: SaIccProfile = null
) -> void:
    if not done.is_valid():
        return
    var guessed := source if source != null else SaColorSpace.srgb()
    var depth_named := SaImageImport.depth_for(image)
    if host == null or not host.is_inside_tree() or image == null or not SaSettings.ask_when_opening:
        var depth: int = depth_named if depth_named >= 0 else remembered_depth()
        done.call(guessed.with_depth(depth as SaColorSpace.Depth))
        return

    var dialog := for_host(host)
    if dialog._waits(func() -> void: choose_depth(host, image, source, done, named, profile)):
        return
    # Every call rebinds, for the reason `place` rebinds: the payload of the
    # last picture opened is not this one's.
    for connection: Dictionary in dialog.depth_chosen.get_connections():
        dialog.depth_chosen.disconnect(connection["callable"])
    dialog.depth_chosen.connect(func(chosen: SaColorSpace) -> void: done.call(chosen))
    dialog.configure_open(image.get_size(), guessed, depth_named, named, profile)
    dialog.popup_centered()


## The message bar's line for a paste placed without the window: what it did,
## and where the painter asks to be asked.
static func placed_line(fit: SaImageImport.Fit) -> String:
    var did := (
        TranslationServer.translate("Pasted at its own size, centred.")
        if fit == SaImageImport.Fit.ACTUAL
        else TranslationServer.translate("Pasted fitted inside the canvas, centred.")
    )
    return (
        did
        + " "
        + TranslationServer.translate(
            "Edit > Paste Special asks how to fit, and Preferences > Files keeps the choice for every paste and drop."
        )
    )


## Whether *question* has to wait, kept to be asked once the window closes.
##
## A drop calls `place` once per picture before any answer, and the one
## window holds one question, so rebinding it lost all but the last picture.
## Each waits its turn and is asked on its own, since each has its own size and
## colour space. A waiting question is the whole call again, so a fit "Do not
## ask again" stored places the rest unasked, and a closed document is skipped.
func _waits(question: Callable) -> bool:
    if _taking_next or (not visible and _waiting.is_empty()):
        return false
    _waiting.append(question)
    return true


## The window closed, by an answer or a Cancel. The next question is asked
## once idle, after the answer has placed its picture, as `_confirm` hides first.
func _on_question_closed() -> void:
    if not visible and not _waiting.is_empty():
        _ask_the_next.call_deferred()


func _ask_the_next() -> void:
    # A question under a fit the last answer stored places without opening.
    while not visible and not _waiting.is_empty():
        var question: Callable = _waiting.pop_front()
        _taking_next = true
        question.call()
        _taking_next = false


## The dialog this host already owns, built on first use. One per host and
## never freed, the way the Select menu keeps its radius dialogs: a dialog
## built per picture would leave a hidden window behind every Escape.
static func for_host(host: Node) -> SaImportFitDialog:
    var existing := host.get_node_or_null(NodePath("ImportFitDialog")) as SaImportFitDialog
    if existing != null:
        return existing
    var dialog := SaImportFitDialog.new()
    # A `Window` is built visible, and the first question would wait on it.
    dialog.visible = false
    host.add_child(dialog)
    return dialog


static func _place_and_report(
    document: SaDocument,
    image: Image,
    layer_name: String,
    source: SaColorSpace,
    fit: SaImageImport.Fit,
    done: Callable,
    step: String
) -> void:
    _report(SaImageImport.place(document, image, layer_name, source, fit, step), done)
