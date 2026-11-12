## The New Document dialog: canvas size, colour space, bit depth and what the
## painting is laid on.
##
## This is the chooser `SaColorSpace.presets()` and `display_name()` are shaped
## for, and the one place a painter picks a new document's colour space rather
## than taking whatever `setup_default_document()` defaults to.
##
## The facade of `ui/dialogs/document/new_document`. The colour space rows and
## the rules between them are `SaColorSpacePicker`, the one picker every place
## that asks for a colour space shares, and the capture door is `Capture`,
## reached through the constant below. What is here is the window, the page's
## order, the size, what the painting is laid on and the templates, which fill
## rows of every kind.
@tool
class_name NewDocumentDialog
extends SaDialogWindow

## The `new_document_row` step and the dump's `new_document` block.
const Capture := preload("res://ui/dialogs/document/new_document/new_document_capture.gd")

## Emitted when the user confirms. The size is in document pixels, the
## resolution in pixels per inch, and the background is
## `SaDocumentBackground`'s dictionary.
signal document_requested(size: Vector2i, space: SaColorSpace, dpi: float, background: Dictionary)

const DEFAULT_SIZE := Vector2i(1920, 1080)

## The highest resolution the row accepts. Print work tops out well under this,
## and the cap only exists so a typo cannot ask for a million.
const MAX_DPI := 9600

## Godot's own maximum for a 2D texture dimension is far higher, but a canvas
## this size is already 4 GiB of RGBA32F chunks if it is painted edge to edge.
const MAX_DIMENSION := 16384

## The Size row's last entry, the word the preset row ends on as well, so one
## space has one name and a size no entry names reads the same.
const CUSTOM_LABEL := SaColorSpacePicker.CUSTOM_LABEL

## The sizes the Size row offers above Width and Height, Custom one past them.
## An entry fills what its name says, the resolution only where it names one,
## and the row reads the entry whose numbers the rows hold. Each name is the
## shipped template's of the same size, so one size has one name in the dialog.
const SIZES: Array[Dictionary] = [
    {"label": "Screen, 1920 × 1080 px", "size": DEFAULT_SIZE},
    {"label": "A4 portrait, 300 dpi", "size": Vector2i(2480, 3508), "dpi": 300.0},
    {"label": "Square, 2048 × 2048 px", "size": Vector2i(2048, 2048)},
]

## The rows behind the details switch: the ground, the memory line, the
## colour space preset and the bit depth, then the picker's rows of
## `SaColorSpacePicker.DETAIL_KEYS`. Someone who has never painted on a
## computer can answer none of them, and a document made with them folded
## takes the space and depth the last one took or the profile default.
const DETAIL_ROWS: Array[StringName] = [
    &"ground",
    &"memory",
    &"space",
    &"depth",
    &"gamut",
    &"primaries",
    &"white",
    &"white_xy",
    &"transfer",
    &"gamma",
    &"coordinates",
    &"save_space",
]

## The rows a newcomer is asked with the details closed, Create beside them.
## The Save as template line, the swap and the background's colour are not
## rows of their own to a painter but parts of the Template, the size and the
## Background rows, and go with them.
const FIRST_ROWS: Array[StringName] = [&"template", &"size", &"width", &"height", &"dpi", &"background"]

## The states Create draws in the accent. Disabled keeps the plain box, because
## a Create that cannot be pressed is not what Enter takes.
const DEFAULT_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed"]

## The buttons of the question a taken template name asks, Replace first.
const REPLACE := 0
const REPLACE_CANCEL := 1

## The window with the details closed, the size, the background and the
## buttons, and with them open, beside the chooser's picture of the space. The
## rows need 487 high at scale 1, which the fit grows this to.
const CLOSED_SIZE := Vector2i(640, 480)
const CLOSED_MIN := Vector2i(480, 360)
const OPEN_SIZE := Vector2i(900, 660)
const OPEN_MIN := Vector2i(760, 420)


## The figure under the size that says what one full layer of it costs.
##
## A shared-memory GPU runs out long before a discrete one, and without the
## figure a painter finds out by Sara slowing. The figure is a whole layer's grid of chunks,
## every chunk the grid needs and each one full, which is the most a layer of
## this size can take. Hard rule 3 means a layer only takes the chunks paint
## lands in, and the row's explanation says so, or a painter would read 4 GB as
## the price of opening the document.
class MemoryLine:
    extends Label

    ## How many times the device's memory one layer may take before the line
    ## turns to a warning. A document has several layers, undo holds copies of
    ## chunks, and the display and every other program share the same memory.
    const SHARE_OF_DEVICE := 4

    ## One full layer above this many bytes is a cost a laptop's GPU notices
    ## whatever Godot says of the device. A gigabyte is a quarter of the four
    ## many integrated GPUs share from the machine, and lies between A4 at
    ## 300 dpi, 147 MB at float 32, and the largest size, 4.3 GB.
    const LAPTOP_BYTES := 1_000_000_000

    ## The device memory the warning is judged against, zero when Godot names
    ## none. Read once, the dialog is built at start and the device never changes.
    var device_bytes: int = device_memory()

    func _init() -> void:
        name = "MemoryLine"
        autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        size_flags_horizontal = Control.SIZE_EXPAND_FILL

    ## Bytes one layer of *canvas* in *space* takes with every chunk of its
    ## grid allocated. The chunk side is `SaLayer.CHUNK_SIZE` and a texel's width is
    ## whatever `SaFieldSpec` says the space's schema stores, never 256 or 16.
    static func layer_bytes(canvas: Vector2i, space: SaColorSpace) -> int:
        var side := SaLayer.CHUNK_SIZE
        var chunks := ceili(canvas.x / float(side)) * ceili(canvas.y / float(side))
        var texel := 0
        for spec: SaFieldSpec in SaFieldSpec.schema_for_space(space):
            texel += spec.bytes_per_texel()
        return chunks * side * side * texel

    ## The memory the GPU paints in, when Godot names it, else zero.
    ##
    ## Godot 4.7 has no call for a discrete card's memory:
    ## `RenderingDevice.get_device_total_memory` is what Sara has allocated, not
    ## what the card holds. An integrated GPU or a CPU renderer has no memory of
    ## its own and allocates from the machine's, which `OS.get_memory_info` does
    ## name, and that is the case the line is for.
    static func device_memory() -> int:
        var kind := RenderingServer.get_video_adapter_type()
        if kind != RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU and kind != RenderingDevice.DEVICE_TYPE_CPU:
            return 0
        return int(OS.get_memory_info().get("physical", 0))

    ## `21 MB` or `4.3 GB`, in decimal units, a million bytes to the megabyte,
    ## the way a drive or a graphics card's box counts them, rather than a binary
    ## figure under a decimal unit's name. A tenth
    ## is shown below 10 MB, where a whole number would round a small canvas to
    ## nothing.
    static func size_text(bytes: int) -> String:
        var megabytes := bytes / 1e6
        if megabytes >= 1000.0:
            return "%.1f GB" % (megabytes / 1000.0)
        return "%.1f MB" % megabytes if megabytes < 10.0 else "%d MB" % roundi(megabytes)

    ## Whether one layer of *bytes* would take more than its share of *device*.
    static func too_large(bytes: int, device: int) -> bool:
        return device > 0 and bytes * SHARE_OF_DEVICE > device

    ## Whether one layer of *bytes* is a cost a laptop's GPU would notice: more
    ## than [constant LAPTOP_BYTES], or more than its share of *device* when
    ## Godot names the device's memory. Only then is the warning beside Create
    ## shown, so a beginner is told of the one cost that bites and asked
    ## nothing else.
    static func bites(bytes: int, device: int) -> bool:
        return bytes > LAPTOP_BYTES or too_large(bytes, device)

    ## The words beside Create when a layer bites, in the painter's terms:
    ## what it costs and what it does to the machine, with no row to answer.
    func warning_text(bytes: int) -> String:
        var said := tr("A canvas this large can use %s of graphics memory for every layer, which may slow a laptop.")
        return said % size_text(bytes)

    func show_cost(canvas: Vector2i, space: SaColorSpace) -> void:
        var bytes := layer_bytes(canvas, space)
        var figure := size_text(bytes)
        if too_large(bytes, device_bytes):
            text = tr("One layer uses %s, more than a quarter of this GPU's %s.") % [figure, size_text(device_bytes)]
        else:
            text = tr("One layer uses %s.") % figure

    ## What the line shows and the figures behind it, for the dialog's capture.
    ## A wrapping label in a row can collapse to its minimum width and run to a
    ## line a word, which a screenshot shows and a test cannot.
    func capture_state(canvas: Vector2i, space: SaColorSpace) -> Dictionary:
        return {
            "memory": text,
            "memory_bytes": layer_bytes(canvas, space),
            "device_bytes": device_bytes,
            "memory_lines": get_line_count(),
            "memory_width": size.x,
        }


## The id of the template the rows were last filled from, which the Template
## row shows, marked changed once a row it names says something else.
var template: String = ""
## Every template the row offers, read once and again after a save or a delete,
## and the row, whose list follows them.
var _templates: Array[Dictionary] = []
var _template_row: SaPageRow = null
## The name field, Save as template and Delete, under the Template row.
var template_saver: NewDocumentTemplates.SaveRow = null
## The question a save under a taken template name put up, null when none is
## waiting, so a suite and the door can answer it.
var replace_question: SaMessage = null

## The entry of `SIZES` the width and the height match, `SIZES.size()` for
## Custom.
var size_row: int = 0

## The three numbers the page binds.
var wanted_width: int = DEFAULT_SIZE.x
var wanted_height: int = DEFAULT_SIZE.y
var dpi: float = SaDocument.DEFAULT_DPI

## The colour space picker, which the page binds its colour rows to.
var picker := SaColorSpacePicker.new()

## Whether the five rows of `DETAIL_ROWS` and the chooser's picture are shown.
var details_open: bool = false

## The three background rows: Colour or Transparent, the colour in display
## terms as the swatch shows it, and the id of the ground under it, empty for
## None. Strings rather than names, because a choice row finds its entry by
## the value it holds.
var background_kind: String = String(SaDocumentBackground.COLOUR)
var background_color: Color = SaDocumentBackground.DEFAULT_SHOWN
var ground: String = ""

## Where the Ground row's entries come from: every registered type that answers
## a height, Paper and Canvas from the skeleton and any a module adds. Null
## offers None alone, which is what a dialog built without the app has.
var _layer_types: SaLayerTypeRegistry = null

## The declared rows, realized once into `NewDocumentPage`.
var page: SaPage = null

## What one full layer of the size and depth costs, behind the details switch.
var memory_line: MemoryLine = null
## The same cost beside Create, shown only when it bites.
var memory_warning: Label = null

var create_button: Button = null

## The display profile's gamut the gamut row last followed, so an open takes up
## a Preferences change made since without undoing a row the painter moved.
var _followed_gamut: StringName = &""

## Shows what the three dropdowns add up to. Read-only: it follows the choosers
## rather than being a second place to choose.
var browser: SaColorSpaceBrowser = null
## The browser's scroll view, which is what the details switch shows and hides.
var _browser_view: Control = null


func _init(layer_types: SaLayerTypeRegistry = null) -> void:
    _layer_types = layer_types
    # Closed, since the details are. Opening them takes the window to the size
    # that holds the preview as well, in `_show_details`.
    _init_dialog("NewDocumentDialog", tr("New Document"), CLOSED_SIZE, CLOSED_MIN)
    picker.moved.connect(_refresh_rows)
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.PAD)

    # The choosers on the left, what is being chosen on the right. Krita's
    # new-image dialog does the same thing, and for the same reason: the name
    # "ACEScg" says nothing about what it holds, and a gamut triangle does.
    var body := SaMake.row(column, "Body", 16)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # The rows scroll when the host is shorter than they are, so the buttons
    # stay on it. At an interface scale of 2 on a 1080 screen the dialog opened
    # 660 tall in a window 540 tall, with its title over the menus and Create
    # under the bottom edge.
    var rows_view := SaMake.scroll(body, "RowsScroll")
    rows_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    rows_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rows_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = rows_view
    var rows := SaMake.column(rows_view, "NewDocumentPage")
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # The switch opens as the painter last left it, which is the profile's.
    details_open = SaSettings.new_document_details
    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(rows)
    page.row_changed.connect(_on_row_changed)
    # Width, not the first row, because the size is what a painter types first
    # and the Size row is a shortcut to it, rather than whatever control the
    # focus walk lands on first.
    first_focus = (rows.find_child("WidthSpin", true, false) as SpinBox).get_line_edit()

    # Every row opens on the default rather than on its own index 0. Five
    # separate zeroes were five separate answers that happened to agree, and the
    # one they agreed on was 1920 by 1080 sRGB at F32, which is not the
    # default.
    picker.show_space(SaEasel.default_space())
    _followed_gamut = SaSettings.display_profile_space().gamut().id
    if not apply_template(SaSettings.last_template):
        apply_template(String(NewDocumentTemplates.SHIPPED[0][NewDocumentTemplates.ID]))

    browser = picker.make_browser()
    _browser_view = SaColorSpaceBrowser.scrolled(browser)
    _browser_view.visible = details_open
    body.add_child(_browser_view)
    _refresh_rows()

    # Own buttons rather than AcceptDialog's. AcceptDialog draws Godot's title
    # bar, which sits outside the window's viewport where a CursorOverlay cannot
    # reach, so the pointer disappeared over it.
    var buttons := SaMake.row(column, "Buttons", SaTheme.GAP)
    buttons.alignment = BoxContainer.ALIGNMENT_END
    # Beside Create, where the one cost that bites is read before the press,
    # and left of the buttons so it wraps rather than pushing them off.
    memory_warning = Label.new()
    memory_warning.name = "MemoryWarning"
    memory_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    memory_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    buttons.add_child(memory_warning)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size.x = float(SaUI.px(90))
    # Their own height beside a warning three lines tall, not the row's.
    cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    cancel_button.pressed.connect(hide)
    create_button = SaMake.button(buttons, "CreateButton", tr("Create"))
    create_button.custom_minimum_size.x = float(SaUI.px(90))
    create_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    create_button.pressed.connect(_on_confirmed)
    default_button = create_button
    draw_as_default(create_button)
    _sync_memory_line()
    if details_open:
        _show_details()


## Draws *button* as the action Enter takes: the box a toggle that is on
## draws, in the accent on every state a painter meets it in, so Create stands
## apart from Cancel beside it. The toggle's pressed box rather than a box of its
## own, because that box is the palette's `toggle_on`, which is the accent moved
## until `text_primary` reads on it in every shipped palette, and it follows a
## theme switch the way a toggle does.
static func draw_as_default(button: Button) -> void:
    for state: String in DEFAULT_STATES:
        button.add_theme_stylebox_override(state, SaTheme.make_toggle_style("pressed"))


## The page: the template and its saving, the size and its three numbers, the
## background and its colour, then the details switch and the rows behind it,
## the ground, the memory line, the colour space preset, the depth and the
## five expert colour rows. Every choice row
## is keyed on its position, because that is what the handlers and `select_row`
## have always taken and what the committed scenarios write.
func _declare(ui: SaPage) -> void:
    var rows := ui.section("")
    # First, because a template fills every row under it.
    _templates = NewDocumentTemplates.listed()
    var templates := NewDocumentTemplates.choices_of(_templates)
    # Said under its title, because a template moves the size, resolution and
    # background below it, and a painter who picks one has to know that.
    _template_row = rows.choice("Template", templates, self, ^"template").named(&"template").node("TemplateOption")
    _template_row.explain(tr("Fills every row below it."))
    template_saver = NewDocumentTemplates.SaveRow.new(save_template, delete_template)
    rows.custom("Save as template", template_saver).named(&"save_template")
    var sizes: Array = SIZES.map(func(entry: Dictionary) -> String: return tr(String(entry["label"])))
    rows.choice("Size", sizes + [tr(CUSTOM_LABEL)], self, ^"size_row").named(&"size").node("SizeOption")
    var width := rows.number("Width", 1, MAX_DIMENSION, self, ^"wanted_width").step(1).with_suffix("px")
    width.named(&"width").node("WidthSpin")
    # Between the two it trades, where a painter looks for the portrait and
    # landscape swap.
    rows.action("Swap width and height", swap_size).named(&"swap").node("SwapButton")
    var height := rows.number("Height", 1, MAX_DIMENSION, self, ^"wanted_height").step(1).with_suffix("px")
    height.named(&"height").node("HeightSpin")
    # The third dimension. This row is what stores a physical size, so a
    # document can say how big it is on paper, and the header key it writes is
    # additive rather than a migration.
    rows.number("Resolution", 1, MAX_DPI, self, ^"dpi").step(1).with_suffix("dpi").named(&"dpi").node("DpiSpin")
    # What the painting is laid on. A ground under a transparent document is
    # not offered, so the colour and the ground go away together when
    # Transparent is chosen.
    var kinds := [
        {"id": String(SaDocumentBackground.COLOUR), "label": tr("Colour")},
        {"id": String(SaDocumentBackground.TRANSPARENT), "label": tr("Transparent")},
    ]
    var kind := rows.choice("Background", kinds, self, ^"background_kind").named(&"background").node("BackgroundOption")
    rows.colour("Background colour", self, ^"background_color").named(&"background_colour").node("BackgroundColour")
    var grounds: Array = [{"id": "", "label": tr("None")}]
    for descriptor: SaLayerTypeDescriptor in ground_types():
        grounds.append({"id": String(descriptor.id), "label": tr(descriptor.display_name)})
    kind.hides(&"background_colour", String(SaDocumentBackground.COLOUR))
    # Named for what it holds, every row under it, and the node keeps its
    # name so the committed scenarios and the door still find it.
    var details := rows.toggle("Ground, colour and memory", self, ^"details_open").named(&"details").node("DetailsSwitch")
    rows.choice("Ground", grounds, self, ^"ground").named(&"ground").node("GroundOption")
    kind.hides(&"ground", String(SaDocumentBackground.COLOUR))
    # Under the ground, above the depth that is its other factor.
    memory_line = MemoryLine.new()
    # The sentence is the row's explanation rather than part of the figure, so
    # the figure is a line and not five in the value column's width.
    rows.custom("GPU memory", memory_line).named(&"memory").explain(tr("A layer costs only where it is painted."))
    picker.declare_picked(ui, self, &"picker")
    for folded: StringName in DETAIL_ROWS:
        details.hides(folded)
    picker.declare_details(ui, self, &"picker")


## The registered types a document can be laid on, in the order they were
## registered: a generated layer that answers a height, which is a ground.
func ground_types() -> Array[SaLayerTypeDescriptor]:
    var out: Array[SaLayerTypeDescriptor] = []
    if _layer_types == null:
        return out
    for descriptor: SaLayerTypeDescriptor in _layer_types.list_descriptors():
        if SaGeneratedLayer.answers_height(descriptor):
            out.append(descriptor)
    return out


## Moves the gamut row onto the display profile's when Preferences named another
## one since the dialog last followed it. Only then: a row the painter moved
## under a profile nobody has touched since is a choice, and an open does not
## take it back.
func _on_visibility_changed() -> void:
    super._on_visibility_changed()
    if not visible:
        return
    var profile := SaSettings.display_profile_space().gamut()
    if profile.id == _followed_gamut:
        return
    _followed_gamut = profile.id
    select_gamut(String(profile.id))


## A row moved. Which rule a row runs is decided here and in
## `SaColorSpacePicker.row_changed`, which takes the colour rows: the Size row fills the
## numbers and the numbers move it, and a template fills every row it names.
func _on_row_changed(key: StringName, _value: Variant) -> void:
    if picker.row_changed(key):
        _mark_template()
        return
    match key:
        &"template":
            apply_template(template)
        &"size":
            _on_size_picked(size_row)
        &"width", &"height", &"dpi":
            _sync_size_row()
        &"details":
            SaSettings.new_document_details = details_open
            _show_details()
        &"ground":
            _sync_ground_tooltip()
    _mark_template()


## Fills the width, the height and a named resolution from the Size row's
## entry. Custom fills nothing, it is what the row reads once a number moved.
func _on_size_picked(index: int) -> void:
    if index < 0 or index >= SIZES.size():
        return
    var entry: Dictionary = SIZES[index]
    var picked: Vector2i = entry["size"]
    wanted_width = picked.x
    wanted_height = picked.y
    dpi = float(entry.get("dpi", dpi))
    _sync_size_row()


## Moves the Size row onto the entry the numbers now match, or onto Custom, and
## pushes the rows back into their controls.
func _sync_size_row() -> void:
    size_row = SIZES.size()
    for i in SIZES.size():
        var entry: Dictionary = SIZES[i]
        if entry["size"] == selected_size() and is_equal_approx(float(entry.get("dpi", dpi)), dpi):
            size_row = i
            break
    _refresh_rows()


## Fills every row the template *id* names, leaves the rest, and answers whether
## there was one. The Size row then follows the numbers as after a typed one.
func apply_template(id: String) -> bool:
    var record := NewDocumentTemplates.find_in(_templates, id)
    if record.is_empty():
        return false
    template = id
    if record.has(NewDocumentTemplates.SIZE):
        var picked: Vector2i = record[NewDocumentTemplates.SIZE]
        wanted_width = picked.x
        wanted_height = picked.y
    dpi = float(record.get(NewDocumentTemplates.DPI, dpi))
    var space := NewDocumentTemplates.space_of(record, selected_space().depth)
    if space != null:
        picker.show_space(space)
    var background: Dictionary = record.get(NewDocumentTemplates.BACKGROUND, {})
    if not background.is_empty():
        background_kind = String(background[SaDocumentBackground.KIND])
        background_color = background[SaDocumentBackground.COLOR]
        ground = String(background[SaDocumentBackground.GROUND])
    _sync_size_row()
    return true


## The Template row reads "(changed)" after its name once a row it names says
## something else, so the painter sees where the numbers came from.
func _mark_template() -> void:
    var entry := _template_row
    if entry == null or entry.control == null:
        return
    var record := NewDocumentTemplates.find_in(_templates, template)
    var holds := NewDocumentTemplates.matches(record, selected_size(), dpi, selected_space(), selected_background())
    if not record.is_empty() and not holds:
        (entry.control as SaChoiceButton).text = tr("%s (changed)") % record[NewDocumentTemplates.LABEL]
    template_saver.delete_button.disabled = not NewDocumentTemplates.is_saved(template)


## Keeps every row as the template *wanted* in the painter's `templates`
## folder, shows it on the row, and answers its id, or empty.
##
## A name whose file a saved template already holds writes nothing yet: it puts
## up [member replace_question], with Cancel the default as File > Save As
## has, so Enter on a question nobody read keeps the earlier template. That
## holds for the template the row shows as well, because its file is the one
## the painter saved before the rows moved, and the sentence says it is.
func save_template(wanted: String) -> String:
    var holder := NewDocumentTemplates.taken_by(wanted)
    if holder.is_empty():
        return _write_template(wanted)
    SaTrail.stage("asked whether to replace the template %s" % holder)
    replace_question = SaMessage.confirm(
        self,
        tr("Replace template"),
        tr("A template named '%s' is already saved. Replace it with these settings?") % holder,
        PackedStringArray([tr("Replace"), tr("Cancel")]),
        _on_replace_answered.bind(wanted),
        REPLACE_CANCEL,
        REPLACE_CANCEL
    )
    return ""


func _on_replace_answered(index: int, wanted: String) -> void:
    SaTrail.stage("answered %s" % ("Replace" if index == REPLACE else "Cancel"))
    replace_question = null
    if index == REPLACE:
        _write_template(wanted)


func _write_template(wanted: String) -> String:
    var shown := NewDocumentTemplates.record_of(selected_size(), dpi, selected_space(), selected_background())
    var id := NewDocumentTemplates.save(wanted, shown)
    if not id.is_empty():
        template = id
        template_saver.name_field.text = ""
        _relist_templates()
    return id


## Moves the saved template the row shows to the trash, and puts the row on
## the first shipped one, whose rows are left as they are.
func delete_template() -> bool:
    var gone := NewDocumentTemplates.delete(template)
    if gone:
        template = String(NewDocumentTemplates.SHIPPED[0][NewDocumentTemplates.ID])
        _relist_templates()
    return gone


## Reads the templates again and gives the row the new list.
func _relist_templates() -> void:
    _templates = NewDocumentTemplates.listed()
    var entry := _template_row
    entry.choices = NewDocumentTemplates.choices_of(_templates)
    (entry.control as SaChoiceButton).set_choices(entry.choices)
    _refresh_rows()


## Width and height trade places, a portrait size for its landscape.
func swap_size() -> void:
    var width := wanted_width
    wanted_width = wanted_height
    wanted_height = width
    _sync_size_row()


## The details switch moved. The chooser's picture goes with the rows the
## page hides, and the window takes the size that holds what is now on it, about
## its own centre.
func _show_details() -> void:
    _browser_view.visible = details_open
    var before := size
    var least := OPEN_MIN if details_open else CLOSED_MIN
    # The floor first: a window holds its size at the floor it has, and the open
    # floor kept a closing window at 760 by 676 with the rows gone from it. A
    # window grown to a raised floor records that as a size it was given, so the
    # two sizes are written after it.
    if is_inside_tree():
        min_size = SaUI.window_size_for(self, least)
    logical_size = OPEN_SIZE if details_open else CLOSED_SIZE
    logical_min_size = least
    if not is_inside_tree():
        return
    apply_window_scale()
    @warning_ignore("integer_division")
    position -= (size - before) / 2
    _fit_next_frame()


## Pushes every row back into its control and brings the chooser's picture, the
## memory line and the transfer's tooltip after them. Every path that moved a
## row ends here.
func _refresh_rows() -> void:
    page.refresh()
    if browser != null:
        browser.show_space(selected_space())
    _sync_memory_line()
    _sync_transfer_tooltip()
    _sync_ground_tooltip()
    _mark_template()


## The Transfer choice says the chosen curve's full name when the pointer rests
## on it, which is what its short label left out.
func _sync_transfer_tooltip() -> void:
    var entry := page.row(&"transfer") if page != null else null
    if entry == null or entry.control == null:
        return
    entry.control.tooltip_text = picker.transfer_name()


## The Ground choice says what the chosen ground is when the pointer rests on
## it, the descriptor's own hint, and what None means when no ground is chosen.
func _sync_ground_tooltip() -> void:
    var entry := page.row(&"ground") if page != null else null
    if entry == null or entry.control == null:
        return
    var hint := tr("A plain background, with no grain under the paint.")
    for descriptor: SaLayerTypeDescriptor in ground_types():
        if String(descriptor.id) == ground and not descriptor.hint.is_empty():
            hint = tr(descriptor.hint)
    entry.control.tooltip_text = hint


## Every path ends in `_refresh_rows`, which calls this, so the figure follows
## the size and the depth alike.
func _sync_memory_line() -> void:
    if memory_line != null and picker.save_row != null:
        memory_line.show_cost(selected_size(), selected_space())
    if memory_warning != null and picker.save_row != null:
        var bytes := MemoryLine.layer_bytes(selected_size(), selected_space())
        memory_warning.visible = MemoryLine.bites(bytes, memory_line.device_bytes)
        memory_warning.text = memory_line.warning_text(bytes) if memory_warning.visible else ""


## Puts the gamut row on the preset called *gamut_name* and answers whether
## there was one. The capture harness's door: the row's list is a Window, so an
## injected click cannot reach a row of it.
func select_gamut(gamut_name: String) -> bool:
    return picker.select_gamut(gamut_name)


## The choice rows a capture can move, in the order one step applies them. The
## preset row is first because picking a space fills the gamut and the transfer
## rows, so a scenario naming both means the named row to win, and the template
## is before it for the same reason. The background's two choices come after
## the colour grid, which they do not touch.
const CAPTURE_ROWS: Array[String] = [
    "template", "space", "gamut", "white", "transfer", "coordinates", "depth", "background", "ground"
]


## The dropdown behind a row name, or null for a name the page has none for.
func row_option(row: StringName) -> SaChoiceButton:
    return page.row(row).control as SaChoiceButton if CAPTURE_ROWS.has(String(row)) else null


## Puts the row called *row* on the entry *asked* names, and answers whether
## there was one.
##
## *asked* is the text the row draws, which is the text `capture_state` reads
## back, so a scenario writes what the dump reads and there is no second
## vocabulary to keep in step. A number is the row's index instead, for an entry
## whose name a translation moved.
##
## The row is driven rather than its handler called, because which rule a row
## runs is `_on_row_changed`'s business, and a door that knew it would be a
## second copy of the wiring. A scenario that has the index moves the same row
## with `page_row` on `NewDocumentPage`.
func select_row(row: StringName, asked: Variant) -> bool:
    var option := row_option(row)
    if option == null:
        return false
    var index := -1
    if asked is int or asked is float:
        index = int(asked)
    else:
        var wanted := String(asked)
        var labels := option.choice_labels()
        for i in labels.size():
            if labels[i].to_lower() == wanted.to_lower():
                index = i
                break
        # The gamut row has answered to a gamut id and three committed scenarios
        # write `ap1` rather than `ACES AP1`. The one door takes both so those
        # scenarios can move to it without being rewritten.
        if index < 0 and row == &"gamut":
            return select_gamut(wanted)
    if index < 0 or index >= option.choice_labels().size():
        return false
    page.row(row).drive(index)
    return true


## Sets New Document's rows: the harness's door to the template and the colour grid,
## `{"new_document_row": {"template": "A4 portrait, 300 dpi", "depth": "32-bit float"}}`.
##
## Every row opens a list that is a Window and an injected click cannot reach
## one, so without this step a scenario could move none of them.
##
## One step for five rows rather than five steps, because the rows are one grid
## and one `capture_state`, and a scenario that sets three of them wants one line.
## `Capture.row` runs it, and says what else a step may ask.
static func capture_row(tree: SceneTree, spec: Dictionary) -> String:
    return Capture.row(tree, spec)


## The dump's `new_document` block, which `Capture.state` reads.
static func capture_state(root: Window) -> Dictionary:
    return Capture.state(root)


## The descriptor the dialog currently describes, which the colour rows add up.
##
## Separate from the signal so it can be exercised without popping the window:
## a test that adds a Window to the scene tree maps a real OS window and hangs
## the run.
func selected_space() -> SaColorSpace:
    return picker.selected_space()


## The canvas size the dialog currently describes.
func selected_size() -> Vector2i:
    return Vector2i(wanted_width, wanted_height)


## The resolution the dialog currently describes, in pixels per inch.
func selected_dpi() -> float:
    return dpi


## What the dialog lays the painting on, `SaDocumentBackground`'s dictionary.
## Transparent carries no ground, because the row offering one is hidden.
func selected_background() -> Dictionary:
    var see_through := background_kind == String(SaDocumentBackground.TRANSPARENT)
    return {
        SaDocumentBackground.KIND: StringName(background_kind),
        SaDocumentBackground.COLOR: background_color,
        SaDocumentBackground.GROUND: &"" if see_through else StringName(ground),
    }


func _on_confirmed() -> void:
    SaSettings.last_template = template
    document_requested.emit(selected_size(), selected_space(), selected_dpi(), selected_background())
    hide()
