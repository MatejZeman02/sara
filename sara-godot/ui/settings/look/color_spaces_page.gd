## Preferences > Colour Spaces: the colour space picker over the colour space
## browser, opened on whatever the current document uses and following it while
## the window stays open.
##
## **The picker in place of the browser's own chooser**, so a space can be
## built from its primaries, white and curve here and saved, renamed and
## deleted where every other picker lists it. The browser keeps its Compare
## chooser, which no other place shows.
##
## **And nothing else.** Gamut mapping is on the Display page, beside the
## roll-off whose tail it is, which is where a painter looks for it, although an
## export to an integer file reads it too.
class_name SaColorSpacesPage
extends SaSettingsPage

var browser: SaColorSpaceBrowser
## The rows over the browser and the space they add up to, bound as `picker`.
var picker := SaColorSpacePicker.new()


func build(ui: SaPage) -> void:
    # "Colour space" and not "Gamut". The picker under this heading names
    # colour spaces, and two of its presets are Oklab, which is a coordinate
    # system and has no gamut at all. The gamut is the triangle inside the
    # diagram and the Gamut row, and both of those say so themselves.
    var rows := ui.section(tr("Colour space"))
    picker.declare_picked(ui, self, &"picker", "Colour space", false)
    # The picker's chooser takes the browser's name, so a scenario that picks
    # a space here by "GamutOption" picks it on the row the painter sees.
    ui.row(&"space").node("GamutOption")
    picker.declare_details(ui, self, &"picker")
    browser = SaColorSpaceBrowser.new()
    browser.option.visible = false
    browser.option.name = "BrowserGamutOption"
    browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    browser.show_space(picker.selected_space())
    rows.custom("", browser).named(&"browser")
    if not ui.row_changed.is_connected(_on_row_changed):
        ui.row_changed.connect(_on_row_changed)
    if not picker.moved.is_connected(_on_picker_moved):
        picker.moved.connect(_on_picker_moved)


func _on_row_changed(key: StringName, _value: Variant) -> void:
    picker.row_changed(key)


## The rows show what the picker now holds, and the browser draws it.
func _on_picker_moved() -> void:
    if page != null:
        page.refresh()
    if browser != null and is_instance_valid(browser):
        browser.show_space(picker.selected_space())


## The document is only reachable through the tree, so the page opens on its
## space once it is in one. Off the tree the browser keeps its own default.
##
## **And listens from then on**, as the tool options bar, the Tool Options
## docker and the Layers docker do. A read here alone leaves the rows, the
## diagram, the gamut solid, the legend and the readout describing the last
## document after a switch to one in another space, until the page is left and
## opened again, because the Preferences frame rebuilds its controls on every
## page switch.
func _ready() -> void:
    super()
    _show_document_space()
    if not EventBus.document_color_space_changed.is_connected(_on_document_color_space_changed):
        EventBus.document_color_space_changed.connect(_on_document_color_space_changed)


## The space of the document in front, put on the picker and so the browser.
## False when there is no document to read, which is a page built off a
## running app.
func _show_document_space() -> bool:
    var canvas := SaCanvasView.front_canvas() if is_inside_tree() else null
    if canvas == null or canvas.document == null:
        return false
    picker.show_space(canvas.document.color_space)
    return true


## The page shows the document in front, so it reads that one again and a
## change to any other is passed over. The payload's own space is the fallback
## for a page with no document behind it, which is the only thing a test
## outside the app has.
func _on_document_color_space_changed(changed: SaDocument) -> void:
    if not _show_document_space() and changed != null:
        picker.show_space(changed.color_space)
