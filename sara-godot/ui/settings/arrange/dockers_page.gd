## Preferences > Layouts and dockers: the named docker layouts, the settings
## every docker shares, each drawn once, whether they live inside the main
## window among them, and one line for each docker, which leads to that docker's
## own parts and options.
##
## A page per docker would double the sidebar for pages of mostly the same rows,
## so the shared rows are here once, with one line per docker carrying an
## Elements… button, and Options… for the dockers that have more. No docker is
## in the sidebar, and what its page held is a part of `SaLayoutPage`, opened
## from here by one of the two buttons and drawn in the page area with a Back
## row that returns to the docker's line.
##
## **The window opens a docker's part, not this page.** A press says which
## docker and which part through [signal docker_wanted], and the window, which
## owns the page area, draws it there the way it draws any page. A part drawn
## inside this page would be a page inside a page, sections under sections,
## which `SaPageSection` rules out, and the reorder, the capture steps and the
## search would each have had to learn a second place a list can be.
##
## **The pop-up palette's switch is not here.** It sat beside the two summon
## rows, because a summon is the only way the palette appears, and a painter
## whose chord did nothing never thought to look for it on a page about dockers.
## It is on Brush Slots, beside the ten slots the palette shows.
class_name SaDockersPage
extends SaSettingsPage

## A docker's Elements… or Options… button was pressed: *part* is
## `SaLayoutPage.ELEMENTS` or `SaLayoutPage.OPTIONS`.
signal docker_wanted(category: String, part: StringName)

## The page's title in the sidebar, and what a door names it by.
const TITLE := "Layouts and dockers"

## What turning "Dockers inside the main window" off does, said by this page and
## by the welcome window's switch for the same setting.
const EMBED_HINT := "When off, every docker and dialog is a window of its own, which can be moved to another screen."

## The one layout list that is no docker's. It has no line among the dockers',
## because the bar is not a docker: it has a section of its own, the top bar's,
## whose Elements… button opens its list the way a docker's opens.
const TOP_BAR := "TopMenuBar"

## A docker's line is keyed by its settings category after this, so a door and
## a scenario can name it before the page exists.
const LINE_PREFIX := "docker_"

## The layouts dropdown, kept so it can be refilled after a save or a delete.
var _preset_opt: SaChoiceButton = null

## The Delete row, whose button is dimmed while the chosen layout has no file of
## the painter's to forget, the same check `forget` makes.
var _delete_row: SaPageRow = null

## What the Maximize button switch and the two summon rows bind to, the
## skeleton's own preferences rather than properties of `SaSettings`.
var _maximise := SaDockerMaximise.new()
var _pin := SaDockerPin.new()
var _borrow := SaDockerBorrow.new()

## Line key -> `{"category", "title", "elements", "options", "delete"}`, the
## buttons of each docker's line, Options… null for a docker with no options
## and Delete null for any but a docker of your own. Kept so the capture door
## presses the button a hand would without walking the page.
var _lines: Dictionary = {}

## The top bar's section, which keeps the Elements… button of the bar's line.
var _top_bar_section := SaTopBarSection.new()

## The row that makes a docker of your own and the Delete on each one's line,
## which draws the lines again when it made or deleted one.
var _composed := SaComposedDockersSection.new()


func _ready() -> void:
    super()
    refresh_layouts()


func build(ui: SaPage) -> void:
    _declare_layouts(ui)
    _declare_every_docker(ui)
    _top_bar_section.declare(ui, docker_wanted.emit)
    _declare_summoned(ui)
    _declare_each_docker(ui)
    _composed.declare(ui)
    if not _composed.changed.is_connected(redraw):
        _composed.changed.connect(redraw, CONNECT_DEFERRED)


## The page drawn again from its declaration, for a docker made or deleted:
## its line comes or goes, and the layouts dropdown is filled again.
##
## The pane stays where the painter had it. Its rows are freed and drawn again,
## and a pane with nothing in it for a frame falls back to its top, so Make
## pressed at the foot of the page would leave the page at its top with the new
## line out of sight.
func redraw() -> void:
    var pane := SaLayoutPage.scrolling_pane_of(self)
    var kept := pane.scroll_vertical if pane != null else 0
    page.rebuild()
    refresh_layouts()
    if pane != null and is_inside_tree():
        _scroll_back(pane, kept)


## Puts *pane* back at *kept* once the rows drawn again have their places, two
## frames on for the reason `SaSettingsSearch._scroll_to` gives.
func _scroll_back(pane: ScrollContainer, kept: int) -> void:
    var tree := get_tree()
    await tree.process_frame
    await tree.process_frame
    if is_instance_valid(pane):
        pane.scroll_vertical = kept


## The key of *category*'s line.
static func line_key(category: String) -> StringName:
    return StringName(LINE_PREFIX + category)


## Every docker that has a line here, in the order the lines are drawn: by the
## title a painter reads, because thirteen names are found by reading down them
## and the order they were registered in means nothing on screen. A docker a
## module declared through `register_layout_category` is among them, which is
## rule six read from the other end.
static func dockers() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for entry: Dictionary in SaSettings.reorderable_categories():
        if String(entry["id"]) != TOP_BAR:
            out.append(entry)
    out.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool:
            var first := TranslationServer.translate(String(a["title"]))
            return first.naturalnocasecmp_to(TranslationServer.translate(String(b["title"]))) < 0
    )
    return out


## The title a docker's line carries, or "" for a category that has no line.
static func docker_title(category: String) -> String:
    for entry: Dictionary in dockers():
        if String(entry["id"]) == category:
            return String(entry["title"])
    return ""


## The Preferences page *category*'s rows are on, or "" for a key nobody
## registered: this page for a docker, where its line is, and for the bar, whose
## line is in the top bar's section. The ALT double click on a drag handle
## asks it, and a docker a module registered at runtime is found the same way
## a built-in is, which is rule six read from the other end.
static func page_of(category: String) -> String:
    for entry: Dictionary in SaSettings.reorderable_categories():
        if not category.is_empty() and String(entry["id"]) == category:
            return TITLE
    return ""


## *category*'s line on this page, the top bar's included, or empty for a key
## nobody registered.
static func line_of(category: String) -> StringName:
    return line_key(category) if page_of(category) == TITLE else &""


## Named docker layouts: the dropdown that switches between them, a name to save
## the current arrangement under, the delete the Dockers menu's submenu
## deliberately does not offer, and whether the dockers live inside the main
## window.
##
## That last was a row of the first page Preferences opens, which holds only
## what a painter changes in their first sessions, and it belongs beside the
## layouts it acts on: a layout is kept for one of the two answers, and turned
## off, every docker is a window of its own.
func _declare_layouts(ui: SaPage) -> void:
    var rows := ui.section("Layouts")

    _preset_opt = SaMake.choice(null, "WorkspacePresetOpt")
    _preset_opt.choice_picked.connect(
        func(id: Variant) -> void:
            var chosen := String(id)
            var store := _layout_store()
            if store != null and not chosen.is_empty():
                store.load_preset(chosen)
            _show_deletable()
    )
    var current := rows.custom("Current layout", _preset_opt).node("WorkspacePresetOpt")
    current.explain(tr("Where every docker sits. Switching puts them where the layout says, at once."))

    var save_box := SaMake.row(null, "WorkspacePresetSaveBox")
    var name_edit := SaMake.line_edit(save_box, "WorkspacePresetName", "", tr("Layout name"))
    name_edit.custom_minimum_size.x = SaUI.px(140)
    var save_btn := SaMake.button(save_box, "WorkspacePresetSave", tr("Save As"))
    save_btn.pressed.connect(
        func() -> void:
            var store := _layout_store()
            if store == null or name_edit.text.strip_edges().is_empty():
                return
            if store.save_preset(name_edit.text.strip_edges()):
                name_edit.text = ""
                refresh_layouts()
    )
    var saving := rows.custom("Save the current layout", save_box)
    saving.explain(tr("Keeps where the dockers are now under a name. Saving over a name replaces it."))

    _delete_row = rows.action("Delete the chosen layout", delete_chosen_layout)
    _delete_row.button("Delete").node("WorkspacePresetDelete").explain(tr("Delete the layout. The dockers stay where they are."))

    # Titled for what a painter sees rather than for the engine's setting, and
    # the hint says what off does, since on is what every painter starts with.
    # The key stays the setting's, which every scenario that drives it names.
    var embed := rows.toggle("Dockers inside the main window", SaSettings, ^"embed_subwindows")
    embed.explain(EMBED_HINT).named(&"embed_subwindows")


## The three buttons every docker's drag bar carries, each one switch.
##
## Each is one setting for every docker, so it is drawn once, beside the
## layouts, rather than on every docker's page, where it reads as the docker's
## own. Hide first and Maximize second.
func _declare_every_docker(ui: SaPage) -> void:
    var rows := ui.section("Every docker")
    rows.toggle("Hide button", SaSettings, ^"docker_hide_button").named(&"hide_button").node("HideButtonCheck").explain(
        tr("A button on every docker's drag bar that closes it, for when its shortcut is out of reach.")
    )
    rows.toggle("Maximize button", _maximise, ^"button_on").named(&"maximise_button").node("MaximiseButtonCheck").explain(
        tr("A button beside the hide button that fills the window with its docker, and puts it back.")
    )
    rows.toggle("Pin button", _pin, ^"button_on").named(&"pin_button").node("PinButtonCheck").explain(
        tr(
            (
                "A button on every docker's drag bar that keeps its docker shown when Tab hides the rest. "
                + "Pins already set still hold while the button is hidden, and the Toolbox never shows one."
            )
        )
    )


## A docker summoned under the pointer by its Alt+Shift chord: one pair of
## settings for every docker, in a section of its own, since they are about the
## chord and not about any docker's frame.
func _declare_summoned(ui: SaPage) -> void:
    var rows := ui.section("Summoned dockers")
    (
        rows
        . number("Summoned docker delay", 0, 10000, _borrow, ^"dwell_ms")
        . step(100)
        . with_suffix(tr(" ms"))
        . named(&"borrow_dwell")
        . explain(tr("How long the pointer stays away before a summoned docker goes back."))
    )
    (
        rows
        . number("Summoned docker distance", 0, 50, _borrow, ^"distance")
        . scale(100)
        . step(0.5)
        . with_suffix(tr("%"))
        . named(&"borrow_distance")
        . explain(tr("How far the pointer goes, as a share of the screen's width, before the wait starts."))
    )


## One line per docker: its name, the parts it has hidden when it has any, and
## Elements… beside Options… where the docker registered options of its own,
## or beside Delete for a docker of your own, which has no options.
##
## Elements… always comes first, so it sits in one column down the page and
## Options… beside it on the three lines that have it. Each line carries the
## words of what is behind its buttons, every part and every option by the
## title its page draws, so a search for "Hex Input" or "Orientation" still
## finds the docker it belongs to, which the thirteen pages answered by being
## pages.
func _declare_each_docker(ui: SaPage) -> void:
    var rows := ui.section("Each docker")
    rows.note(
        tr(
            (
                "Customize... chooses which parts of a docker are shown, and their order. Options... holds one docker's "
                + "own settings, and Delete removes a docker of your own."
            )
        )
    )
    _lines.clear()
    for entry: Dictionary in dockers():
        var category := String(entry["id"])
        var title := String(entry["title"])
        # A shipped docker's tooltips are whole sentences, so a language with
        # cases can decline its name. A module's own reads the generic ones.
        var parts := tr("Choose which parts the %s docker shows, and their order.") % tr(title)
        if SaWholeSentences.DOCKER_PARTS.has(title):
            parts = tr(SaWholeSentences.DOCKER_PARTS[title])
        var buttons := SaMake.row(null, "DockerButtons_%s" % category, SaTheme.GAP)
        var elements := SaMake.button(buttons, "Elements_%s" % category, tr("Customize..."), parts)
        elements.pressed.connect(docker_wanted.emit.bind(category, SaLayoutPage.ELEMENTS))
        var options: Button = null
        if not SaSettings.docker_options(category).is_empty():
            var says := tr("%s docker settings") % tr(title)
            if SaWholeSentences.DOCKER_SETTINGS.has(title):
                says = tr(SaWholeSentences.DOCKER_SETTINGS[title])
            options = SaMake.button(buttons, "Options_%s" % category, tr("Options..."), says)
            options.pressed.connect(docker_wanted.emit.bind(category, SaLayoutPage.OPTIONS))
        var delete: Button = null
        if SaComposedDockers.is_composed(category):
            delete = _composed.delete_button(buttons, category, title, self)
        var key := line_key(category)
        rows.custom(title, buttons).named(key).explain(hidden_parts(category)).words(_words_behind(category))
        _lines[key] = {"category": category, "title": title, "elements": elements, "options": options, "delete": delete}


## What a docker's line says under its name: the parts it has hidden, or
## nothing when every part is drawn. Nothing rather than "every part shown",
## because that is twelve lines of one sentence on a fresh profile and the one
## line that differs is what a painter scanning the page wants to see.
func hidden_parts(category: String) -> String:
    var unseen: Array[String] = []
    for element: String in SaSettings.get_layout_order(category):
        if not SaSettings.get_element_visible(category, element):
            unseen.append(SaSettings.translated_element_title(category, element))
    if unseen.is_empty():
        return ""
    if unseen.size() == 1:
        return tr("%s is hidden.") % unseen[0]
    return tr("%s and %s are hidden.") % [", ".join(unseen.slice(0, -1)), unseen[-1]]


## The titles of every part and every option behind a docker's two buttons,
## for the search.
func _words_behind(category: String) -> String:
    var words := PackedStringArray()
    for element: String in SaSettings.get_layout_order(category):
        words.append(SaSettings.element_title(category, element))
    for spec: Dictionary in SaSettings.docker_options(category):
        words.append(String(spec.get("title", "")))
    return " ".join(words)


## Forgets the layout the dropdown shows, which is what the Delete button does.
##
## The dropdown's value rather than its index. It became an `SaChoiceButton` and
## this handler went on asking it `item_count` and `get_item_metadata(selected)`,
## which only an `OptionButton` answers, so every press was a script error and
## nothing was deleted. Public, so a test presses the button's own door without a
## pointer.
func delete_chosen_layout() -> bool:
    var store := _layout_store()
    if store == null or _preset_opt == null:
        return false
    var chosen: Variant = _preset_opt.selected_value()
    if chosen == null or String(chosen).is_empty():
        return false
    var forgotten := store.delete_preset(String(chosen))
    refresh_layouts()
    return forgotten


## The dropdown, rebuilt from disk, with the layout in use selected.
##
## Filled from `_ready` rather than from `_init`, because the store is found
## through the tree and `_init` runs before the page is in one.
##
## **There is no "Unsaved layout" row**, because an edit under no preset forks
## nothing and answers with the shipped `user` name instead. A profile that has
## never chosen a layout is in `default`, which is a row already, and the first
## edit makes `default (custom)`.
func refresh_layouts() -> void:
    if _preset_opt == null:
        return
    var store := _layout_store()
    if store == null:
        _preset_opt.set_choices([])
        _show_deletable()
        return
    var presets: Array = []
    for preset_name in store.list_presets():
        presets.append({"id": preset_name, "label": preset_name})
    _preset_opt.set_choices(presets)
    _preset_opt.select_value(store.current_preset())
    _show_deletable()


## Dims Delete while the layout the dropdown shows is shipped and unchanged, or
## there is none, which is when [method delete_chosen_layout] would forget
## nothing.
func _show_deletable() -> void:
    var button := _delete_row.control as Button if _delete_row != null else null
    if button == null:
        return
    var store := _layout_store()
    var chosen: Variant = _preset_opt.selected_value() if _preset_opt != null else null
    var named := chosen != null and not String(chosen).is_empty()
    button.disabled = store == null or not named or not store.presets().can_forget(String(chosen))


## The store lives under `MainDockers` as a named child, and Preferences is handed nothing
## but the settings. Looked up rather than injected, because injecting it would
## mean a parameter on every page for the sake of one, and the name is the same
## one `MainDockers._init` gives it.
func _layout_store() -> DockerLayoutStore:
    var tree := get_tree()
    if tree == null or tree.root == null:
        return null
    return tree.root.find_child("DockerLayoutStore", true, false) as DockerLayoutStore


## One line per docker for `{"layout_rows": {}}`: its title, its category, the
## middle of each of its buttons, and what it says under its name, then the New
## docker row.
##
## The same step that reads a docker's list reads this page, because the
## capture finds whichever page of the two kinds is open, and a scenario that
## opens Layouts and dockers and then a docker's part reads both with one word.
func describe_rows(origin: Vector2) -> String:
    var lines: Array[String] = ["SaCapture: %s, %d dockers" % [TITLE, _lines.size()]]
    var seen := SaLayoutPage.pane_of(self, origin)
    for key: StringName in _lines:
        var line: Dictionary = _lines[key]
        var elements := line["elements"] as Button
        var options := line["options"] as Button
        var at := origin + elements.get_global_rect().get_center()
        var beside := "none"
        if options != null:
            var options_at := origin + options.get_global_rect().get_center()
            beside = "(%4d, %4d)" % [options_at.x, options_at.y]
        var delete := line["delete"] as Button
        if delete != null:
            var delete_at := origin + delete.get_global_rect().get_center()
            beside += " delete=(%4d, %4d)" % [delete_at.x, delete_at.y]
        (
            lines
            . append(
                (
                    "  %-18s %-20s elements=(%4d, %4d) options=%s%s"
                    % [
                        line["title"],
                        line["category"],
                        at.x,
                        at.y,
                        beside,
                        "" if SaLayoutPage.reachable(at, seen) else "  UNREACHABLE, outside the pane",
                    ]
                )
            )
        )
        var says := page.row(key).explanation
        if not says.is_empty():
            lines.append("      %s" % says)
    # The top bar's line, which is no docker's and sits in its own section above
    # the dockers' lines.
    var bar_at := origin + _top_bar_section.elements_button.get_global_rect().get_center()
    (
        lines
        . append(
            (
                "  %-18s %-20s elements=(%4d, %4d)%s"
                % [
                    "Menu bar",
                    TOP_BAR,
                    bar_at.x,
                    bar_at.y,
                    "" if SaLayoutPage.reachable(bar_at, seen) else "  UNREACHABLE, outside the pane",
                ]
            )
        )
    )
    for option_name: String in ["WindowButtonPositionOpt", "WindowButtonStyleOpt"]:
        var option := find_child(option_name, true, false) as Control
        if option != null:
            var option_at := origin + option.get_global_rect().get_center()
            (
                lines
                . append(
                    (
                        "  %-18s %-20s dropdown=(%4d, %4d)%s"
                        % [
                            option_name,
                            "window button",
                            option_at.x,
                            option_at.y,
                            "" if SaLayoutPage.reachable(option_at, seen) else "  UNREACHABLE, outside the pane",
                        ]
                    )
                )
            )
    lines.append_array(_composed.describe(origin, seen))
    return "\n".join(lines)


## Presses a docker's Elements… or Options… button the way a hand does, by the
## docker's title or its category: `{"layout_gesture": {"elements": "Layers"}}`
## or `{"layout_gesture": {"options": "Toolbox"}}`.
##
## A click at the button and not a call to the window, because what a scenario
## claims is that the line offers the button and that it leads somewhere.
##
## The New docker row and a line's Delete are `SaComposedDockersSection`'s:
## `{"name": "Mine", "start": "Empty", "make": true}` types the name, picks the
## start and presses Make, and `{"delete": "Mine"}` presses the Delete on a
## docker of your own, whose question a `{"answer": 1}` step answers.
func drive_gesture(tree: SceneTree, origin: Vector2, spec: Dictionary) -> String:
    if SaComposedDockersSection.drives(spec):
        return _composed.drive(tree, origin, spec, _lines)
    for wanted_part: StringName in [SaLayoutPage.ELEMENTS, SaLayoutPage.OPTIONS]:
        if not spec.has(String(wanted_part)):
            continue
        var wanted := String(spec[String(wanted_part)])
        if wanted_part == SaLayoutPage.ELEMENTS and (wanted == TOP_BAR or wanted == _bar_title()):
            var pressed := _top_bar_section.elements_button
            return SaLayoutPage.click(tree, origin, pressed, "%s on '%s'" % [pressed.text, wanted])
        for line: Dictionary in _lines.values():
            if wanted != String(line["title"]) and wanted != String(line["category"]):
                continue
            var button := line[String(wanted_part)] as Button
            if button == null:
                return "SaCapture: layout_gesture found no Options… on '%s', it has no options of its own" % wanted
            return SaLayoutPage.click(tree, origin, button, "%s on '%s'" % [button.text, wanted])
        return "SaCapture: layout_gesture found no docker called '%s' on %s" % [wanted, TITLE]
    return 'SaCapture: layout_gesture on %s takes {"elements": docker} or {"options": docker}' % TITLE


## The title the top bar's list carries, the one a door names it by.
func _bar_title() -> String:
    for entry: Dictionary in SaSettings.reorderable_categories():
        if String(entry["id"]) == TOP_BAR:
            return String(entry["title"])
    return ""
