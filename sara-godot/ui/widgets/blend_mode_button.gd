## The blend mode chooser: Krita's sections, and a favourites list on top.
##
## One control for both places a blend mode is picked, the tool options bar and
## the Layers docker, so the two cannot drift apart, and in sections rather than
## twenty modes listed flat.
##
## A plain `Button` opening an `SaChoicePopup`, rather than a `MenuButton`, whose
## `PopupMenu` item cannot carry a control beside its label, so favouriting a
## mode would mean finding the same name a second time in a second list. One row
## does both: the label picks the mode and the box beside it keeps the mode in the
## favourites at the top.
##
## Neither shape fits itself the way an `OptionButton` does, so the button still
## clips its text and asks for the width its caller gives it: on the top bar the
## row is already tight at 1920. The button under the rows is `SaDropdownButton`,
## shared with `SaChoiceButton`.
##
## **The favourite is a star and the mode in use is the accent.** A tick in
## every other Sara menu marks what is on, so a tick here would read the
## favourited modes at the top as the modes in use. The box draws the Brush
## Presets docker's star,
## filled for a favourite and an outline for the rest, and in the body colour
## rather than the presets' accent, so in this list the accent on a row's words
## is the one mark that says which mode is in use.
##
## **A mode's name is translated and its English is kept**, a rule for the
## blend modes only, because a painter following an
## English tutorial looks for Multiply and has to find it. The row and the button
## read the catalogue's word, the hover keeps the English under it, and the search
## finds the row by either. The descriptor's `label_for` and `tip_for` stay English.
class_name BlendModeButton
extends SaDropdownButton

## A mode was chosen. The registry's id, never an index.
signal mode_selected(mode_id: StringName)

## The label shown while no registry has been bound, so a button on screen
## before the modules have registered is not a blank one.
const NO_MODES := "Blend"

## The narrowest the button goes, in logical pixels, found from the capture:
## what "Normal (sRGB)" needs at the size the bar asks for, which is the label a
## fresh profile shows. A MenuButton does no fitting of its own, so without a
## floor the default label reads "Norm". The three long Normals clip, and the
## tooltip carries the whole of it.
const MIN_WIDTH: int = 140

## What a brush's blend mixes with, the last line of the brush's chip's hover,
## two lines a catalogue translates one by one.
const BRUSH_SCOPE := "The brush's blend mixes the stroke with the paint of the layer it lands on, not with the layers below."
const BRUSH_SCOPE_BELOW := "To mix with the layers below, set the blend on the layer in the Layers docker."

## The box's two faces, the Brush Presets docker's star, under `res://assets/icons/`.
const FAVORITE_ICON := "star"
const NOT_FAVORITE_ICON := "star_outline"

## The modes the list offers, and null for none yet. [method refresh] reads it.
var registry: SaBlendModeRegistry = null
## Whether the modes a layer may not carry belong in the list. The bar shows
## them, the Layers docker does not.
var include_hidden_in_layers: bool = true
## The document's colour space, which plain Normal's label carries in brackets.
var space: SaColorSpace = null
var current: StringName = &""
## What the list's mark was last drawn for: the mode and the two colours the
## rows are drawn in. Empty after the list is refilled, which draws no mark.
var _marked_for: Array = []
## Whether this button is a brush's blend, on the bar or in a docker the bar's
## controls are placed in, rather than a layer's. A painter who chose
## Multiply there and stroked an empty layer saw the stroke's own colour and
## read it as Multiply doing nothing, so its hover says [constant BRUSH_SCOPE]
## under the mode's own sentence. The Layers docker's says nothing more.
var _for_brush: bool = false


func _init(for_brush: bool = false) -> void:
    _for_brush = for_brush
    # The list is built once and refilled. Not `one_of`: a favourited mode has
    # two rows and both carry the mark.
    super(SaChoicePopup.new(false), "BlendChoicePopup")
    text = tr(NO_MODES)
    # Here rather than in `_ready`, because a button a test never adds to the
    # tree has to follow the setting too, and because the engine drops the
    # connection when this is freed either way.
    SaSettings.blend_favorites_changed.connect(_on_favorites_changed)
    popup.chosen.connect(_on_row_chosen)
    popup.marked.connect(_on_row_marked)


## Fills the list again from `registry`, `include_hidden_in_layers` and
## `space`, which the caller writes first.
func refresh() -> void:
    _rebuild()


## Shows *mode_id* as the chosen one. False when no such mode is registered,
## which leaves the button on what it showed.
func select_mode(mode_id: StringName) -> bool:
    if registry == null or not registry.has(mode_id):
        return false
    var descriptor := registry.get_descriptor(mode_id)
    if not include_hidden_in_layers and descriptor.hidden_in_layer_list:
        return false
    current = mode_id
    text = shown_label(descriptor)
    tooltip_text = shown_tip(descriptor)
    if _for_brush:
        tooltip_text += "\n" + tr(BRUSH_SCOPE) + "\n" + tr(BRUSH_SCOPE_BELOW)
    _mark_current()
    return true


## Every mode the menu holds, in the order it holds them, for a test.
func mode_ids() -> Array[StringName]:
    var ids: Array[StringName] = []
    if registry == null:
        return ids
    for section: Dictionary in registry.list_sections(include_hidden_in_layers):
        for descriptor: SaBlendModeDescriptor in section["modes"]:
            ids.append(descriptor.id)
    return ids


## The section titles the menu shows, in order, for a test and for a state dump.
func section_titles() -> Array[String]:
    var titles: Array[String] = []
    if registry == null:
        return titles
    for section: Dictionary in registry.list_sections(include_hidden_in_layers):
        titles.append(String(section["title"]))
    return titles


## The labels under a section's heading, in order. What `section_menu` answered
## once, in the form a column of rows can answer it: the section is a heading
## over its rows rather than a submenu holding them, so there is no `PopupMenu`
## to hand back.
func section_labels(title: String) -> Array[String]:
    var out: Array[String] = []
    if registry == null:
        return out
    for section: Dictionary in registry.list_sections(include_hidden_in_layers):
        if String(section["title"]) != title:
            continue
        for descriptor: SaBlendModeDescriptor in section["modes"]:
            out.append(shown_label(descriptor))
    return out


## The ids under a section's heading, for a caller that wants the mode rather
## than the words.
func section_ids(title: String) -> Array[StringName]:
    var out: Array[StringName] = []
    if registry == null:
        return out
    for section: Dictionary in registry.list_sections(include_hidden_in_layers):
        if String(section["title"]) != title:
            continue
        for descriptor: SaBlendModeDescriptor in section["modes"]:
            out.append(descriptor.id)
    return out


## The favourites, filtered to what this button may show: a painter who
## favourites Erase from the bar has not put it in the Layers docker.
func favorite_ids() -> Array[StringName]:
    var ids: Array[StringName] = []
    if registry == null:
        return ids
    for entry: Variant in SaSettings.blend_favorites:
        var mode_id := StringName(String(entry))
        if not registry.has(mode_id):
            continue
        if not include_hidden_in_layers and registry.get_descriptor(mode_id).hidden_in_layer_list:
            continue
        ids.append(mode_id)
    return ids


func _on_favorites_changed() -> void:
    _rebuild()


## The list written again in the locale set now, which a switch of language in
## Preferences otherwise never reached. The engine sends this on every change of
## locale and as the button enters the tree.
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED:
        _rebuild()


## The label a row and the button show: the mode's name through the catalogue,
## then what `label_for` writes after the name, plain Normal's bracket, a colour
## space's name, which no catalogue translates.
func shown_label(descriptor: SaBlendModeDescriptor) -> String:
    var english := descriptor.label_for(space)
    return tr(descriptor.display_name) + english.trim_prefix(descriptor.display_name)


## The hover of a row and of the button: `tip_for` read through the catalogue,
## with a translated name's English on the line between label and sentence. A
## name the catalogue does not translate adds no line, so under English this is
## `tip_for` word for word, which
## `test_a_blend_mode_keeps_its_english_name_in_the_tooltip.gd` holds for every row.
## Nor does a variant of English, American English's Color Dodge only
## respelling Colour Dodge.
func shown_tip(descriptor: SaBlendModeDescriptor) -> String:
    var lines: Array[String] = [shown_label(descriptor)]
    var english := TranslationServer.get_locale().get_slice("_", 0) == "en"
    if not english and tr(descriptor.display_name) != descriptor.display_name:
        lines.append(tr("In English: %s") % descriptor.display_name)
    if not descriptor.sentence.is_empty():
        var said := tr(descriptor.sentence)
        if descriptor.follows_document_space and space != null:
            said += " " + tr("On this document it mixes in %s.") % space.blend_space_name()
        lines.append(said)
    return "\n".join(lines)


## Fills the list: the favourites at the top, then a heading and its rows per
## section. Every row carries a box drawn as a star, and a filled star is a mode
## in the favourites, so the favourites are edited on the list itself.
##
## **The favourites appear twice on purpose**, once at the top and once in the
## section they belong to, and both rows carry the same star. A painter looking
## for Multiply looks under Darken whether or not they have favourited it, and a
## favourite that vanished from its own section would be a mode that moved when
## it was starred.
func _rebuild() -> void:
    if popup == null:
        return
    popup.clear()
    _marked_for = []
    if registry == null:
        text = tr(NO_MODES)
        return

    var favorites := favorite_ids()
    if not favorites.is_empty():
        popup.add_section(tr("Favourites"))
        for mode_id in favorites:
            _add_mode(registry.get_descriptor(mode_id), "%s_fav" % mode_id)
        popup.add_gap()

    for section: Dictionary in registry.list_sections(include_hidden_in_layers):
        var title := String(section["title"])
        popup.add_section(tr(title))
        for descriptor: SaBlendModeDescriptor in section["modes"]:
            _add_mode(descriptor, String(descriptor.id))

    var mode_list := mode_ids()
    if not select_mode(current) and not mode_list.is_empty():
        select_mode(mode_list[0])
    # Widened here rather than at build, the way an OptionButton sized itself to
    # its longest item: a button with nothing in it costs its row nothing, and
    # the fit test at 1920 measures a bar whose registry was never bound.
    if not mode_list.is_empty():
        custom_minimum_size.x = maxf(custom_minimum_size.x, SaUI.pxf(MIN_WIDTH))


## One row. *row_id* is the row's key rather than the mode's, because a
## favourited mode has a row in two places and a Dictionary keyed on the mode
## would hold only the second of them.
##
## The label's hover is the mode's own sentence, which is what tells plain
## Normal from the Normal pinned to the space it names, and its box is a star.
## The English name is the row's second name, which the search finds it by
## when the label reads in another language.
## Both are written onto the row the popup built, because the popup knows
## nothing about blend modes or favourites, and the star is the box's own two
## theme icons, so the box still ticks, still emits and still reads back
## through `is_checked` the way every other list's box does.
func _add_mode(descriptor: SaBlendModeDescriptor, row_id: String) -> void:
    var ticked := SaSettings.blend_favorites.has(String(descriptor.id))
    var tip := tr("Keep this one in the favourites at the top.")
    var id := StringName(row_id)
    popup.add_row(id, shown_label(descriptor), true, ticked, "", "", false, tip, descriptor.display_name)
    popup.label_button(id).tooltip_text = shown_tip(descriptor)
    var box := popup.check_box(id)
    box.add_theme_icon_override("checked", SaUI.get_icon(FAVORITE_ICON))
    box.add_theme_icon_override("unchecked", SaUI.get_icon(NOT_FAVORITE_ICON))


## Which mode a row id names, undoing the `_fav` suffix the favourites row
## carries. A row and a mode are not the same thing here and this is the one
## place that has to know it.
static func mode_of_row(row_id: StringName) -> StringName:
    return StringName(String(row_id).trim_suffix("_fav"))


## The highlight, after the selection moved. Both of a favourited mode's rows
## carry the mark, because they are the same mode and marking one of them would
## say they were not.
##
## **Left alone when it is already drawn for this mode in these colours.** Every
## row is recoloured by a mark, a millisecond for the list, and the tool
## options bar and docker show the blend mode on every sync, which a shift-drag
## asks for four times a motion. The colours are in the key so a palette
## switch still redraws the mark on the next sync.
func _mark_current() -> void:
    if popup == null:
        return
    var wanted := current
    var marked_for: Array = [wanted, SaTheme.palette.accent_primary, SaTheme.palette.text_primary]
    if marked_for == _marked_for:
        return
    _marked_for = marked_for
    popup.set_current_where(wanted, func(row_id: StringName) -> bool: return mode_of_row(row_id) == wanted)


## Every mode in the order the list shows it, each once: the favourites at the
## top, then the sections, where a favourite already passed is not visited again.
func stepped_order() -> Array[StringName]:
    var order := favorite_ids()
    for mode_id in mode_ids():
        if not order.has(mode_id):
            order.append(mode_id)
    return order


## The next mode in `stepped_order` from the one in use, pressed on the row in
## its own section, which every mode has whether or not it is a favourite.
func _row_after(direction: int) -> StringName:
    var order := stepped_order()
    var index := order.find(current)
    if index < 0:
        index = -1 if direction > 0 else order.size()
    index += direction
    if index < 0 or index >= order.size():
        return &""
    return StringName(String(order[index]))


func _on_row_chosen(row_id: StringName) -> void:
    if select_mode(mode_of_row(row_id)):
        mode_selected.emit(current)


func _on_row_marked(row_id: StringName, _on: bool) -> void:
    # The rebuild the setting's signal starts frees this row, so the star it
    # would have shown is the one the rebuilt list is born with.
    SaSettings.toggle_blend_favorite(mode_of_row(row_id))
