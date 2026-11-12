## Preferences > Files: what a save leaves behind, how a dropped picture is
## fitted, the depth an opened one is stored at, the name and the place an
## export carries, and at the foot the folder Sara keeps its settings in.
##
## A page of their own rather than on the Workspace page below the docker
## layouts, where a newcomer looking under General does not find them, and
## rather than more of General, because General would then read as two pages
## stacked, and the row after General in the sidebar is where the eye lands
## next.
##
## Reset all preferences is at the foot of the sidebar, where it asks first, and
## not here under Author, where a painter looking for how to reset one page
## would press it and put every page back.
##
## The settings folder is a path, which is no first row on the page a painter
## opens to change what they change first, so it is at the foot here, below what
## a painter sets once per picture, since moving it is a choice about the
## machine made once if ever.
class_name SaFilesPage
extends SaSettingsPage

var _restart_row: SaPageRow = null


func build(ui: SaPage) -> void:
    _declare_saving(ui)
    _declare_importing(ui)
    _declare_exporting(ui)
    _declare_settings_folder(ui)


func _init() -> void:
    super()
    _restart_row.line.visible = false
    page.row_changed.connect(_on_row_changed)


func _declare_saving(ui: SaPage) -> void:
    var rows := ui.section("Saving")

    # How many `.sad1`, `.sad2` files an explicit save leaves beside the
    # document. Zero keeps none, which is what a painter short of disk wants.
    var versions := rows.number("Previous versions kept", 0.0, SaSettings.MAX_SAD_VERSIONS, SaSettings, ^"sad_versions")
    versions.explain(tr("How many .sad1, .sad2 copies a save leaves beside the document. 0 keeps none."))

    # The autosave: how often, and whether it writes a recovery copy beside the
    # document or the document itself. A slider, so the minutes are in the
    # readout beside it as "2 min": a spin box draws as many decimals as its
    # step has, and at the half minute this one steps by it read 2.0.
    var every := rows.slider("Autosave every", 0.0, SaSettings.MAX_AUTOSAVE_MINUTES, SaSettings, ^"autosave_interval_minutes")
    every.step(0.5).with_suffix(tr(" min"))
    every.explain(tr("Minutes between autosaves, once the last stroke is a second old. 0 never autosaves."))

    var target := rows.toggle("Autosave writes the working file", SaSettings, ^"autosave_to_working_file")
    target.explain(
        tr(
            (
                "When off, Sara writes <name>.autosave.sad beside the document and offers it on the next launch. "
                + "When on, it saves the document itself, as Ctrl+S would, and keeps the previous version as .sad1."
            )
        )
    )

    # The Reference docker's pictures stored in the `.sad` beside their paths,
    # off by default so a file stays the size of its painting.
    var references := rows.toggle("Keep reference pictures inside the file", SaSettings, ^"sad_keeps_reference_pictures")
    references.explain(
        tr(
            (
                "When on, a save stores every picture on the Reference docker's boards inside the .sad, "
                + "so the boards open whole on another machine. The file grows by the size of each picture. "
                + "When off, it keeps only where each picture is on disk."
            )
        )
    )


## The two settings a dialog writes for itself, so these rows are the way back
## to them: the fit from a "Do not ask again", and the depth from the last
## answer the open question was given.
func _declare_importing(ui: SaPage) -> void:
    var rows := ui.section("Importing")

    var titles := {
        "ask": tr("Ask every time"),
        "stretch": tr("Stretch to the canvas"),
        "actual": tr("Place at actual size"),
        "inside": tr("Fit inside the canvas"),
        "grow": tr("Grow the canvas to fit"),
    }
    var fits: Array = []
    for id: String in SaSettings.IMPORT_FITS:
        fits.append({"id": id, "label": String(titles[id])})
    var row := rows.choice("Fit a dropped or pasted picture", fits, SaSettings, ^"import_fit")
    row.node("ImportFitOpt").explain(
        tr(
            (
                "What happens to a picture that is not the canvas's size. Ask every time opens the dialog for a drop, "
                + "and a paste lands at once, at its own size when it fits. Edit > Paste Special always asks."
            )
        )
    )

    # The open question's Bit depth row in its own words, `depth_name`'s, keyed
    # by what the setting stores, so the two read as one choice.
    var depths: Array = []
    for stored: String in SaSettings.IMPORT_DEPTHS:
        depths.append({"id": stored, "label": tr(SaColorSpace.depth_name(SaImportFitDialog.depth_from_setting(stored)))})
    var depth := rows.choice("Bit depth for opened pictures", depths, SaSettings, ^"import_depth")
    depth.named(&"import_depth").node("ImportDepthOpt").explain(
        tr(
            (
                "The depth a picture or an .ora file opens at when the file does not say, 16-bit float by default. "
                + "The open dialog starts with this value. "
                + "The colour space is not set here, it is still read from the file."
            )
        )
    )
    var asks := rows.toggle("Ask about a picture's colour space and depth when opening it", SaSettings, ^"ask_when_opening")
    asks.named(&"ask_when_opening").node("AskWhenOpeningCheck").explain(
        tr(
            (
                "When off, a picture opens at once, in the gamut its file names or its format's usual one, "
                + 'at the depth above. The window that asks has "Show this next time" to turn it off.'
            )
        )
    )
    var every := rows.toggle("Ask every time, for an 8-bit picture too", SaSettings, ^"ask_eight_bit_when_opening")
    every.named(&"ask_eight_bit_when_opening").node("AskEightBitWhenOpeningCheck").explain(
        tr(
            (
                "A JPEG, an 8-bit PNG or a WebP holds 8 bits a channel and names no float depth, "
                + "so it opens at once at the depth above. When on, it asks as a float picture does."
            )
        )
    )
    var panorama := rows.toggle("Ask whether a 2:1 picture is a panorama when opening it", SaSettings, ^"ask_panorama")
    panorama.named(&"ask_panorama").node("AskPanoramaCheck").explain(
        tr(
            (
                "A picture twice as wide as it is tall may be an equirectangular panorama. "
                + "When on, opening one asks whether to assign that projection. "
                + "When off, it opens flat, and Image > Projection... assigns it later."
            )
        )
    )


## The name an exported picture carries, which is `SaExportMetadata`'s author.
## Beside Saving because it is the one export preference that is not a view's.
##
## Under it, where the painter lives, next to the Author information.
##
## **One picker for the country and its zone.** Every country is a row under
## tzdata's long name, and a country whose zones keep different clocks, or stand
## on both sides of a tropic, is a row for each, named by the places of the
## zones that keep that clock: Australia is asked about and Czech Republic is
## not. One list rather than a second picker that appears for some countries,
## because the list's search finds every row of Australia from "aus" and a
## second row would come and go under the hand. The binding stores the country
## and the zone apart, so the Welcome picture and an export read a country.
##
## Then the Place, a free text the sun never reads, and the box that lets an
## export name the two.
func _declare_exporting(ui: SaPage) -> void:
    var rows := ui.section("Exporting")
    var author := rows.text("Author", SaSettings, ^"export_author")
    author.named(&"export_author").node("ExportAuthorEdit").explain(SaExportDialog.author_sentence())

    var binding := SaPageBinding.new(
        func(_property: StringName) -> Variant:
            return SaFilesPage.location_id(SaSettings.location_country, SaSettings.location_zone),
        func(_property: StringName, value: Variant) -> void:
            SaSettings.location_country = str(value).get_slice(" ", 0)
            SaSettings.location_zone = str(value).get_slice(" ", 1) if str(value).contains(" ") else ""
    )
    var location := rows.choice("Location", SaFilesPage.location_choices(), binding, ^"location")
    location.named(&"location").node("LocationOpt").explain(
        tr(
            (
                "The country the Welcome picture's sun and seasons follow. "
                + "Automatic guesses it from the time zone, and the guess is in brackets."
            )
        )
    )
    var place := rows.text("Place", SaSettings, ^"location_place")
    place.named(&"location_place").node("LocationPlaceEdit").explain(
        tr("Your town or region, for an export's metadata beside the country. Empty writes none, and the sun never reads it.")
    )
    var writes := rows.toggle("Write the location into exported pictures", SaSettings, ^"location_in_exports")
    writes.named(&"location_in_exports").node("LocationInExportsCheck").explain(
        tr(
            (
                "When on, an exported PNG or TIFF names the country and the place. "
                + "With Automatic, the guessed country is written. A .sad document never carries either."
            )
        )
    )


## The picker's rows: Automatic with the guessed country in brackets, then one
## row for each of `SaLocation.choices`, its id the country's two capitals and,
## for a row of a country with several clocks, a space and the zone.
static func location_choices() -> Array:
    var guessed := SaLocation.guessed(Time.get_datetime_dict_from_system()["month"])
    var guessed_name := SaLocation.country_name(guessed.country)
    # With no country the row is one message, so a language can agree the
    # words. A country's name stands alone in the brackets, as a label.
    var automatic := TranslationServer.translate("Automatic (no country found)")
    if not guessed_name.is_empty():
        automatic = TranslationServer.translate("Automatic (%s)") % guessed_name
    var out: Array = [{"id": "", "label": automatic}]
    for choice: SaLocation.Choice in SaLocation.choices():
        var label := SaLocation.country_name(choice.country)
        var id := choice.country
        if not choice.zone.is_empty():
            id += " " + choice.zone
            var shown := choice.places.slice(0, 3)
            label += " (%s%s)" % [", ".join(shown), "…" if choice.places.size() > 3 else ""]
        out.append({"id": id, "label": label})
    return out


## The id of the picker's row for *country* at *zone*: Automatic for no
## country, the country itself when it has one row, and the row of its zone
## when it has several, its first when the zone is none of them.
static func location_id(country: String, zone: String) -> String:
    if country.is_empty():
        return ""
    var first := ""
    for choice: SaLocation.Choice in SaLocation.choices():
        if choice.country != country:
            continue
        if choice.zone.is_empty() or choice.zone == zone:
            return (country + " " + choice.zone).strip_edges()
        if first.is_empty():
            first = country + " " + choice.zone
    return first if not first.is_empty() else country


## Where the settings folder currently is, a native folder picker to move it,
## and the restart note, since this process has already loaded its settings from
## the folder shown when the page opened. The folder binds through
## `SaPageBinding`, because it is a call and not a property, and the restart note
## has no rule of its own, so it is shown and hidden by hand from
## `page.row_changed` rather than from `.dims`, which only reads a fixed set of
## values and not "the folder just changed".
func _declare_settings_folder(ui: SaPage) -> void:
    var folder := ui.section("Settings folder")
    var pointer := SaPageBinding.new(
        func(_property: StringName) -> Variant: return SaSettings.get_settings_dir(),
        func(_property: StringName, value: Variant) -> void: SaSettingsFile.set_pointer(value)
    )
    folder.path("Folder", pointer, ^"folder").explain(
        tr("Where Sara keeps its settings, docker layout and profiles. A change takes effect on the next launch.")
    )
    _restart_row = folder.note(tr("Sara needs to restart for this to take effect.")).named(&"restart")


func _on_row_changed(key: StringName, _value: Variant) -> void:
    if key == &"folder":
        _restart_row.line.visible = true
