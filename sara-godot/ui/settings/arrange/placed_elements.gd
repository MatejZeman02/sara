## The elements placed in a docker, as its Elements… page draws them: a row per
## placed element after the docker's own rows, each with a Take out beside its
## switch, and under the list an Add Element button whose list offers every
## placeable element under its home docker's title.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker of your own arranges elements from any other docker, laid out for a
## painter's own way of working. So the list is every element
## `SaSettings.placeable_elements` answers, and a pick places the element at the
## end of the docker, where `SaComposedDockers.change` has the window build its
## view at once.
##
## **What is placed is the library's.** The drag, the switch, a pick and a Take
## out write `SaComposedDockers` alone, never `SaSettings` and never a layout,
## so the profile and `docker_layout.cfg` hold none of it and every layout opens
## the docker holding the same. That is why a placed row is a row of its own,
## [PlacedRow], whose switch writes here where a home row's writes the profile,
## and why the page hands this class its drop rather than storing an order.
##
## **A shipped docker takes them too**, since every
## docker is a composition in this sense, the defaults included. Its page lists
## its own rows first and the placed ones after them, as its window draws them,
## the library keeps them under the docker's settings id, and its Reset to
## shipped takes them out through [method take_out_all].
##
## **An element is placed once in a docker.** A row already placed is dimmed in
## the list and says so, since two views of one element side by side are one
## control drawn twice, and nothing in the library tells the two apart. A
## shipped docker's own elements are dimmed on its own page for the same reason.
##
## Built by `SaLayoutPage` for every docker's elements part, which hands it the
## docker's id and its own redraw. The top bar's page is no docker's and builds
## none.
##
## `@tool` because [OfferList] extends [SaChoicePopup], which carries it, and
## the editor's language server warns MISSING_TOOL on a subclass that drops it.
@tool
class_name SaPlacedElements
extends RefCounted

## The key of the Add Element... row under the list.
const ADD_ROW := &"add_element"


## One placed element's row: the home row's drag and switch, the title of the
## docker it comes from, and a Take out. Its switch writes the library rather
## than the profile, which is the one thing the home row's does differently.
class PlacedRow:
    extends SaLayoutPage.DragRow

    ## Takes this element out of the docker.
    var take_out_button: Button

    ## The title of the docker the element comes from, in the painter's language.
    var home_title: String

    var _placed: SaPlacedElements

    func _init(entry: Dictionary, page: Node, placed: SaPlacedElements) -> void:
        super(String(entry["category"]), String(entry["element"]), bool(entry["visible"]), page)
        _placed = placed
        home_title = SaPlacedElements.title_of(category)
        var line := check_button.get_parent()
        # A shipped docker's line is whole, so a language with cases can decline
        # its name. A module's own reads the generic one.
        var whence := tr("from %s") % home_title
        if SaWholeSentences.DOCKER_FROM.has(SaPlacedElements.english_title_of(category)):
            whence = tr(SaWholeSentences.DOCKER_FROM[SaPlacedElements.english_title_of(category)])
        var from := SaSettingsRows.hint_label(whence)
        from.name = "From"
        from.autowrap_mode = TextServer.AUTOWRAP_OFF
        from.size_flags_horizontal = Control.SIZE_SHRINK_END
        from.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        line.add_child(from)
        line.move_child(from, check_button.get_index())
        var title := SaSettings.translated_element_title(category, element_name)
        var says := tr("Takes %s out of this docker. It stays in the %s.") % [title, home_title]
        take_out_button = SaMake.button(line, "TakeOut", tr("Take out"), says)
        line.move_child(take_out_button, check_button.get_index())
        # Deferred, because the take out draws the list again and frees this
        # row, which a button cannot be while it is still saying it was pressed.
        take_out_button.pressed.connect(placed.take_out.bind(self), CONNECT_DEFERRED)

    func holds_control_at(at: Vector2) -> bool:
        return super(at) or take_out_button.get_global_rect().has_point(at)

    func _on_toggled(_pressed: bool) -> void:
        _placed.write()


## The list Add Element... opens, a choice list that keeps beside each of its
## rows the element the row places, so a pick, a gesture and `layout_rows`
## read one table rather than a second one kept here.
class OfferList:
    extends SaChoicePopup

    ## Row id `"category/element"` to `{"category", "element", "home"}`, what
    ## each row of the list places and the title of the docker it comes from.
    var offers: Dictionary[StringName, Dictionary] = {}

    ## Every placeable element under its home docker's title, dimmed where
    ## *placed* answers true for its category and element, and where it is an
    ## element of *own*, the docker the page is.
    func fill(placed: Callable, own: String) -> void:
        clear()
        offers.clear()
        for home: Dictionary in SaSettings.placeable_elements():
            add_section(tr(String(home["title"])))
            for element: Dictionary in home["elements"]:
                var category := String(home["id"])
                var named := String(element["id"])
                var row_id := StringName("%s/%s" % [category, named])
                var here: bool = placed.call(category, named)
                var hint := tr("its own") if category == own else (tr("placed") if here else "")
                add_row(row_id, tr(String(element["title"])), false, false, "", hint, here or category == own)
                offers[row_id] = {"category": category, "element": named, "home": String(home["title"]), "own": category == own}

    ## The row offering *picked*, by the title it shows or its element, of the
    ## docker *home* by title or category, any docker's when *home* is empty.
    ## Empty for a row the list does not hold.
    func find(picked: String, home: String) -> StringName:
        for row_id: StringName in offers:
            var offer: Dictionary = offers[row_id]
            var from_home: bool = home.is_empty() or home == offer["home"] or home == offer["category"]
            if from_home and (picked == label_button(row_id).text or picked == offer["element"]):
                return row_id
        return &""

    ## The list for `layout_rows`, open or closed, and while it is open each
    ## home docker's title with its offers, a placed one marked.
    func describe() -> Array[String]:
        var out: Array[String] = ["      list %s" % ("open" if visible else "closed")]
        if not visible:
            return out
        var by_home: Dictionary[String, Array] = {}
        for row_id: StringName in offers:
            var home := String(offers[row_id]["home"])
            var why := "its own" if offers[row_id]["own"] else "placed"
            var said := label_button(row_id).text + (" (%s, dimmed)" % why if is_disabled(row_id) else "")
            if not by_home.has(home):
                by_home[home] = []
            by_home[home].append(said)
        for home: String in by_home:
            out.append("      %s: %s" % [home, ", ".join(by_home[home])])
        return out


## The list Add Element... opens, built with the button.
var choices: OfferList = null

## The Add Element... button, which the list opens under.
var add_button: Button

## Which docker's elements these are.
var _docker_id: StringName

## The page's own redraw, called once a pick or a Take out changed what the
## docker holds.
var _redraw: Callable

## The library this writes, or null for the app's.
var _given: SaComposedDockers

## The placed rows the page drew last, in the order they were drawn.
var _rows: Array[PlacedRow] = []


## *redraw* draws the page's list again. *library* is a suite's own, and left
## out the page writes the app's, `SaComposedDockers.app`, read at each write
## because the boot writes it after a page may have been built.
func _init(docker_id: String, redraw: Callable, library: SaComposedDockers = null) -> void:
    _docker_id = StringName(docker_id)
    _redraw = redraw
    _given = library


## The Add Element... row, in a section of its own under the list, the way the
## New docker row has one on Layouts and dockers. Its list is a child of the
## button so the two are freed together.
func declare(ui: SaPage) -> void:
    var says := tr("Places an element of any docker at the end of this one")
    add_button = SaMake.button(null, "AddElement", tr("Add Element..."), says)
    add_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    add_button.disabled = _library() == null
    add_button.pressed.connect(open_list)
    choices = OfferList.new()
    choices.name = "AddElementList"
    choices.chosen.connect(_on_chosen)
    add_button.add_child(choices)
    (
        ui
        . section("")
        . custom(tr("Add element"), add_button)
        . named(ADD_ROW)
        . explain(tr("Any docker's element, as a second view of the same thing. It stays at home as well."))
        . words(tr("Place Add Element Take out Remove"))
    )


## The note above the list.
static func note() -> String:
    return TranslationServer.translate(
        (
            "Add Element... places an element of any docker at the end. "
            + "Drag a row to reorder it, switch it off to hide it, or take it out."
        )
    )


## A row per element the docker holds, in the library's order, for the page to
## put in its list after the drag bar and the grip.
func rows(page: Node) -> Array[PlacedRow]:
    _rows.clear()
    var held := _library()
    if held == null:
        return _rows
    for entry: Dictionary in held.elements_of(_docker_id):
        _rows.append(PlacedRow.new(entry, page, self))
    return _rows


## Writes what the rows say, in the order they stand in the list, to the
## library, which has the docker hold it. The page's drop and every switch.
func write() -> bool:
    var held := _library()
    if held == null:
        return false
    _rows.sort_custom(func(a: PlacedRow, b: PlacedRow) -> bool: return a.get_index() < b.get_index())
    return held.change(_docker_id, entries())


## What the rows hold, as the library keeps it.
func entries() -> Array:
    var out: Array = []
    for row: PlacedRow in _rows:
        out.append({"category": row.category, "element": row.element_name, "visible": row.check_button.button_pressed})
    return out


## Places *element* of *category* at the end of the docker and draws the list
## again. False when it is not placeable, is placed here already or is the
## docker's own, or there is no library.
func add(category: String, element: String) -> bool:
    var held := _library()
    if held == null or not SaSettings.is_placeable(category, element) or is_placed(category, element):
        return false
    if category == String(_docker_id):
        return false
    var elements := held.elements_of(_docker_id)
    elements.append({"category": category, "element": element, "visible": true})
    if not held.change(_docker_id, elements):
        return false
    _redraw.call()
    return true


## Takes *row*'s element out of the docker and draws the list again.
func take_out(row: PlacedRow) -> bool:
    if not _rows.has(row):
        return false
    _rows.erase(row)
    var held := _library()
    if held == null or not held.change(_docker_id, entries()):
        return false
    _redraw.call()
    return true


## Takes every placed element out of the docker, a shipped docker's Reset to
## shipped. The page draws its list again itself. False with no library.
func take_out_all() -> bool:
    var held := _library()
    _rows.clear()
    return held != null and held.change(_docker_id, [])


## Whether the docker holds *element* of *category*.
func is_placed(category: String, element: String) -> bool:
    var held := _library()
    if held == null:
        return false
    for entry: Dictionary in held.elements_of(_docker_id):
        if entry["category"] == category and entry["element"] == element:
            return true
    return false


## Fills the list from what is placeable now and opens it under the button.
func open_list() -> void:
    fill_list()
    choices.open_under(add_button)


## Fills the list from what is placeable now, one placed here already dimmed.
func fill_list() -> void:
    choices.fill(is_placed, String(_docker_id))


## The title of the docker *category* is, in the painter's language, or the
## category itself.
static func title_of(category: String) -> String:
    return TranslationServer.translate(english_title_of(category))


## The title of the docker *category* is as the source spells it, which is what
## a whole sentence of [SaWholeSentences] is keyed by, or the category itself.
static func english_title_of(category: String) -> String:
    for entry: Dictionary in SaSettings.reorderable_categories():
        if String(entry["id"]) == category:
            return String(entry["title"])
    return category


## Whether *spec* is this class's: Add Element... pressed, a row of its list
## picked, or a placed row taken out.
static func drives(spec: Dictionary) -> bool:
    for key: String in ["add_element", "pick", "take_out"]:
        if spec.has(key):
            return true
    return false


## `{"add_element": true}` clicks Add Element..., `{"pick": "Brush Tool",
## "from": "Toolbox"}` presses that row of the open list by its title and its
## home docker's, and `{"take_out": "Brush Tool"}` clicks a placed row's Take
## out. The pick is the row pressed as `SaChoicePopup.press_row` presses it for
## a hand, since a click does not route into a list that is a window of its
## own, and it is refused while the list is closed, as a hand's would be.
func drive(tree: SceneTree, origin: Vector2, spec: Dictionary) -> String:
    if bool(spec.get("add_element", false)):
        return SaLayoutPage.click(tree, origin, add_button, "Add Element...")
    if spec.has("take_out"):
        var wanted := String(spec["take_out"])
        for row: PlacedRow in _rows:
            if row.element_name == wanted or SaSettings.translated_element_title(row.category, row.element_name) == wanted:
                return SaLayoutPage.click(tree, origin, row.take_out_button, "Take out on '%s'" % wanted)
        return "SaCapture: layout_gesture found no placed row called '%s'" % wanted
    var picked := String(spec["pick"])
    var home := String(spec.get("from", ""))
    if not choices.visible:
        return 'SaCapture: layout_gesture found the Add Element... list closed, open it with {"add_element": true}'
    var row_id := choices.find(picked, home)
    if row_id.is_empty():
        return "SaCapture: layout_gesture found no '%s' of '%s' in the Add Element... list" % [picked, home]
    var offer: Dictionary = choices.offers[row_id]
    if not choices.press_row(row_id):
        var why := "it is this docker's own" if offer["own"] else "it is placed here already"
        return "SaCapture: layout_gesture found '%s' of '%s' dimmed, %s" % [picked, offer["home"], why]
    var names: Array = _library().elements_of(_docker_id).map(func(entry: Dictionary) -> String: return entry["element"])
    return "SaCapture: layout_gesture picked '%s' of '%s', the docker holds %s" % [picked, offer["home"], ", ".join(names)]


## What `layout_rows` adds after a placed row's line: where it comes from and
## where its Take out is. Nothing for a row that is not placed.
func describe_row(row: Control, origin: Vector2) -> String:
    var placed := row as PlacedRow
    if placed == null:
        return ""
    var at := origin + placed.take_out_button.get_global_rect().get_center()
    return ", placed from %s, take_out=(%4d, %4d)" % [placed.home_title, at.x, at.y]


## The Add Element... button for `layout_rows`, where it is and whether it is
## dimmed, then its list, open or closed, and the list's offers while open.
func describe(origin: Vector2) -> Array[String]:
    var at := origin + add_button.get_global_rect().get_center()
    var dimmed := ", dimmed" if add_button.disabled else ""
    var out: Array[String] = ["  ++  %-24s add=(%4d, %4d)%s" % [add_button.text, at.x, at.y, dimmed]]
    out.append_array(choices.describe())
    return out


func _library() -> SaComposedDockers:
    return _given if _given != null else SaComposedDockers.app


func _on_chosen(row_id: StringName) -> void:
    var offer: Dictionary = choices.offers.get(row_id, {})
    if not offer.is_empty():
        add(String(offer["category"]), String(offer["element"]))
