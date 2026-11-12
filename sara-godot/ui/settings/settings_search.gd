## The search over every Preferences page: the field, the index, the narrowing
## of the category list, and the mark on the first matching row.
##
## Built with what it works on rather than with the window: the category titles,
## the scroll the pages sit inside, and a way to build one off the tree to index
## it. It owns its own field rather than the window building one and handing it
## over, and it speaks back through two signals, `narrowed` and `page_wanted`,
## rather than reaching into a window it does not hold.
class_name SaSettingsSearch
extends RefCounted

## The categories still matching `text`, or every one of them while the field
## is empty. The window listens and hides every other button. *why* is what
## the page area says under "Nothing matches" when *titles* is empty, from
## `nothing_says`, and "" otherwise.
signal narrowed(titles: PackedStringArray, why: String)

## Enter, with something still matching: the first category the search left.
## The window listens and opens it, the same way a click on its button would.
signal page_wanted(title: String)

## Words a painter types for a setting whose title says it otherwise, keyed by
## the title the row or the list item is drawn with. Each word is one a painter
## types and finds nothing with, or the wrong page: "backup" for Previous
## versions kept, "hdr" for the view transforms, "brush size" for the two chords
## that set it, "smoothing" for the top bar's stabiliser.
##
## Here rather than declared on each page with `SaPageRow.words`, because
## those pages are other rows' to change and a word a painter types is the
## search's business. Keyed by the title as drawn, which is the English one
## while Sara is English only, and `test_preferences_search.gd` fails the run
## when a key names nothing any page draws, so a row retitled under a key is
## caught rather than quietly unfound.
const PAINTER_WORDS := {
    "Hide button": "hide close",
    "Previous versions kept": "backup backups",
    "View transform": "hdr tonemap high dynamic range",
    "Display profile": "colour management color management icc",
    "Colour theme": "dark mode light mode",
    "Larger brush": "brush size",
    "Smaller brush": "brush size",
    "Top bar": "menu bar stabiliser smoothing",
    "Window button position": "minimise maximise",
}

## The languages whose capital I is the dotless one, for `fold`.
const DOTLESS_I_LANGUAGES := ["tr", "az"]

## Set by the window on a page built for a category, holding the category.
const CATEGORY_META := &"sa_settings_category"

## Built here, so a search box is one thing rather than a field the window
## builds and a filter that reaches for it afterwards.
var field: LineEdit

## `{category title: one folded string per place a search can land}`, the
## page's own title first. Every page has to be built to know what is on it,
## and a painter types a letter at a time, so a page is built for it once, and
## again only after it was on screen, where a line can come or go.
var index: Dictionary = {}
## The search, folded and trimmed, or "" while the list shows everything.
var text: String = ""
## The row the open page's search marked, so the next one can put it back.
var highlighted: Control = null

var _categories: Array
var _content_scroll: ScrollContainer
var _build_page: Callable

## What `narrowed` last carried, for `report()`.
var _shown: PackedStringArray = PackedStringArray()

## The category the window last opened, for `report()`'s "open_page". The
## search marks a row on it but does not choose it.
var _open_page: String = ""


func _init(categories: Array, content_scroll: ScrollContainer, build_page: Callable) -> void:
    _categories = categories
    _content_scroll = content_scroll
    _build_page = build_page
    _shown = PackedStringArray(_categories)

    field = SaMake.line_edit(null, "PreferencesSearch", "", tr("Search settings"))
    field.clear_button_enabled = true
    SaSearchField.mark(field)
    field.text_changed.connect(apply)
    field.text_submitted.connect(_on_submitted)


## Narrows the categories to the ones holding *needle*, and marks the first
## match on whichever page is open. "" puts every category back.
func apply(needle: String) -> void:
    if field.text != needle:
        field.text = needle
    text = fold(needle.strip_edges())
    if text.is_empty():
        clear_highlight()
        _shown = PackedStringArray(_categories)
        narrowed.emit(_shown, "")
        return
    build_index()
    _read_on_screen()
    _shown = PackedStringArray()
    for category: String in _categories:
        if _category_matches(category):
            _shown.append(category)
    narrowed.emit(_shown, nothing_says() if _shown.is_empty() else "")
    # Marked and not focused, because this call is one keystroke of the painter's
    # typing and the box has to keep the keyboard to receive the next one.
    highlight_first_match(false)


## Enter jumps to the first category the search still shows, the way a click on
## its button would. Nothing to jump to while the field is empty or nothing
## matches.
func _on_submitted(_new_text: String) -> void:
    var first := first_page()
    if not first.is_empty():
        page_wanted.emit(first)


## The page Enter opens: the first whose own title the search names, and
## otherwise the first holding a match. "tablet" opens the Tablet page rather
## than a page above it in the list that names the tablet on one of its rows.
## "" while the field is empty or nothing matches.
func first_page() -> String:
    if text.is_empty():
        return ""
    for category: String in _shown:
        if matches(_title_words(category), text):
            return category
    return _shown[0] if not _shown.is_empty() else ""


## What the page area says under "Nothing matches", for a word a painter types
## and Sara has no setting for, or "" for every other word, so a search that
## finds nothing can say why. No word needs a reason today, and the next one
## goes here.
func nothing_says() -> String:
    return ""


## Builds each page the index lacks, reads its landings and throws it away.
##
## Off the tree on purpose. Every `SaSettingsRows.row` call a page makes is in
## its `_init`, and the three pages that also have a `_ready` only refresh what
## `_init` already built, so a page never added to anything already carries all
## the words it can be found by. `free` rather than `queue_free` for the same
## reason: nothing here entered a tree, so nothing is waiting on a frame.
##
## The page's title goes in first, because a page's rows alone leave "tablet"
## without the Tablet page and "performance" with nothing.
func build_index() -> void:
    for category: String in _categories:
        if not index.has(category):
            var page: Control = _build_page.call(category)
            index[category] = _words_of(category, page)
            if page != null:
                page.free()


## The page on screen read again, so a line it drew since is found at once.
func _read_on_screen() -> void:
    for node: Node in _content_scroll.find_children("*", "", true, false):
        if node.has_meta(CATEGORY_META):
            var category := String(node.get_meta(CATEGORY_META))
            index[category] = _words_of(category, node)
            return


## The page's title and every place on *page* a search can land, folded.
static func _words_of(category: String, page: Node) -> PackedStringArray:
    var words := PackedStringArray([_title_words(category)])
    if page != null:
        for landing: Control in landings(page):
            words.append(haystack(landing))
    return words


## *page* carrying *category*, for the window's `build_page`.
static func tagged(page: Control, category: String) -> Control:
    if page != null:
        page.set_meta(CATEGORY_META, category)
    return page


func _category_matches(category: String) -> bool:
    for words: String in index.get(category, PackedStringArray()):
        if matches(words, text):
            return true
    return false


## A page's title as the sidebar draws it and as it is declared, folded.
static func _title_words(category: String) -> String:
    return fold("%s %s" % [category, TranslationServer.translate(category)])


## *words* folded for a search under *locale*, or the locale Sara shows when it
## is empty, the query and the words it is matched against alike, here and in
## the command search. Under Turkish and Azeri the capital I pairs with the
## dotless ı and the dotted İ with i, which Godot's `to_lower()` does not do,
## and every other locale folds by `to_lower()` as before. Read on each call,
## so a switch of language while Sara runs folds the next keystroke by it.
static func fold(words: String, locale: String = "") -> String:
    if locale.is_empty():
        locale = TranslationServer.get_locale()
    if DOTLESS_I_LANGUAGES.has(locale.replace("-", "_").get_slice("_", 0).to_lower()):
        words = words.replace("I", "ı").replace(String.chr(0x130), "i")
    return words.to_lower()


## Whether *needle* starts a word somewhere in *words*, both already folded.
##
## The start of a word rather than anywhere, because "pen" anywhere leaves nine
## pages by the "pen" inside "open", "happens" and "expensive". A start rather
## than a whole word, because the list narrows a letter at a time and "tab" has
## to keep the Tablet page before the rest of the word is typed.
static func matches(words: String, needle: String) -> bool:
    if needle.is_empty():
        return false
    var at := words.find(needle)
    while at != -1:
        if at == 0 or not _is_letter_or_digit(words[at - 1]):
            return true
        at = words.find(needle, at + 1)
    return false


## A character with a case, or a digit. Asked by case so an accented letter
## counts as a letter too.
static func _is_letter_or_digit(character: String) -> bool:
    return character.to_lower() != character.to_upper() or character.is_valid_int()


## Every place on *root* a search can land, in the order a mark tries them: the
## rows and the items of an element list, top to bottom, and then the section
## headings.
##
## The headings come last, so a word in both a heading and the row under it,
## "undo" in Undo history and Undo steps, marks the row and gives its control
## the keyboard rather than marking a heading that has nothing to focus.
static func landings(root: Node) -> Array[Control]:
    var found: Array[Control] = []
    var headings: Array[Control] = []
    _collect(root, found, headings, false)
    found.append_array(headings)
    return found


## The walk behind `landings`, in tree order. *bare* is true under a control a
## section holds bare, which is how `SaPage._place_bare` puts an element list
## on a page: no row around it, so each of its items is a landing of its own.
## Nothing inside a row is, because the row is.
static func _collect(node: Node, found: Array[Control], headings: Array[Control], bare: bool) -> void:
    var under := bare or node.has_meta(SaSettingsRows.SECTION_META)
    for child: Node in node.get_children():
        var control := child as Control
        if control == null:
            continue
        if control.has_meta(SaSettingsRows.ROW_META):
            found.append(control)
        elif control is Label:
            if control.name == &"Heading":
                headings.append(control)
        elif under and control is HBoxContainer and _item_label(control) != null:
            found.append(control)
        else:
            _collect(control, found, headings, under)


## The words a landing is found by: a row's from `row_haystack`, a heading's
## text, and an item's labels, each with the words a painter types for it.
static func haystack(landing: Control) -> String:
    if landing.has_meta(SaSettingsRows.ROW_META):
        return row_haystack(landing)
    var parts := PackedStringArray()
    var heading := landing as Label
    if heading != null:
        parts.append(heading.text)
    else:
        for child: Node in landing.get_children():
            var label := child as Label
            if label != null:
                parts.append(label.text)
    parts.append(String(PAINTER_WORDS.get(landing_title(landing), "")))
    return fold(" ".join(parts))


## What a landing is called: a row's title, a heading's text, an item's label.
static func landing_title(landing: Control) -> String:
    if landing.has_meta(SaSettingsRows.ROW_META):
        return String(landing.get_meta(SaSettingsRows.TITLE_META, ""))
    var label := _mark_label(landing)
    return label.text if label != null else ""


## An item's own label: the first under it that carries a word, past the drag
## glyph an element list's row starts with.
static func _item_label(box: Control) -> Label:
    for child: Node in box.get_children():
        var label := child as Label
        if label != null and label.text.to_lower() != label.text.to_upper():
            return label
    return null


## The words a row can be found by: its title, the explanation under it, what
## a dropdown on it offers, and the words a painter types for it.
##
## The labels are the label column only, which `SaSettingsRows.row` puts first.
## A slider row packs its own readout in beside the slider, and "0.50" is not a
## word anybody searches for.
##
## A dropdown's items are words though, and they are on screen. The window
## buttons row has offered "Auto (Left on macOS)" and a search for mac found
## nothing, because the index stopped at the label column. Every row on every
## page gains its dropdown's words from this, which is the point: what a painter
## can read they can search for.
static func row_haystack(row: Control) -> String:
    var title := String(row.get_meta(SaSettingsRows.TITLE_META, ""))
    var parts := PackedStringArray([title, String(PAINTER_WORDS.get(title, ""))])
    if row.has_meta(SaSettingsRows.WORDS_META):
        parts.append(String(row.get_meta(SaSettingsRows.WORDS_META)))
    if row.get_child_count() > 0:
        for node in row.get_child(0).find_children("*", "Label", true, false):
            parts.append((node as Label).text)
    for i in range(1, row.get_child_count()):
        parts.append_array(_choice_words(row.get_child(i)))
    return fold(" ".join(parts))


## Every row a choice in *node* offers, itself included. Walked rather than cast,
## because a row holds its control directly and a boxed one holds it a level
## down.
##
## By `Button` and a cast to `SaChoiceButton`, because that is what a dropdown
## is now and `find_children` matches on the engine's class rather than on a
## script's `class_name`.
static func _choice_words(node: Node) -> PackedStringArray:
    var out := PackedStringArray()
    var choices: Array[Node] = [node]
    choices.append_array(node.find_children("*", "Button", true, false))
    for child: Node in choices:
        var option := child as SaChoiceButton
        if option == null:
            continue
        out.append_array(PackedStringArray(option.choice_labels()))
    return out


## Marks the open page's first matching landing and, when *take_focus* asks,
## puts the keyboard on its control, which a narrowed list alone does not do:
## the option found is highlighted and focused, the first one if there are more.
## A page found by its title alone has nothing to mark, the page being the
## answer.
##
## **The focus is the caller's to ask for, and only the page-opening call does**.
## The keyboard lands on the row when the painter opens a page. It would land
## there on every keystroke if `apply` asked for it too, so the first
## letter typed into the search moved the focus to a row and the second went to
## that row rather than into the box. A capture typed `gam` and the field read
## `G`. Marking is what the narrowing wants and it still happens either way.
func highlight_first_match(take_focus: bool = true) -> void:
    clear_highlight()
    if text.is_empty():
        return
    for landing: Control in landings(_content_scroll):
        if _is_going(landing) or not matches(haystack(landing), text):
            continue
        highlighted = landing
        _paint(landing, true)
        _scroll_to(landing)
        if take_focus:
            _focus(landing)
        return


## A door's landing, the public half of the mark: the row the open page
## declared under *key* is marked, its control takes the keyboard the way Enter
## on a search gives it, and the pane scrolls it to the top with its section's
## heading above it. False when the open page has no row of that key, which
## leaves the page at its top and unmarked.
##
## To the top rather than just into view, because a door is a fresh arrival and
## not a word typed a letter at a time. The first chord on Keyboard Shortcuts
## stood at y 762 of 976, in view and under a whole section of profile rows, so
## a scroll that only brought the row into view would have moved nothing.
func land_on(key: StringName) -> bool:
    return _land(row_line(_content_scroll, key))


## The same landing for a place that has no key, found by its title on the open
## page: the search over every action knows a setting by its page and its title
## alone. Rows come before headings, as `landings` orders them.
func land_titled(title: String) -> bool:
    for landing: Control in landings(_content_scroll):
        if not _is_going(landing) and landing_title(landing) == title:
            return _land(landing)
    return false


func _land(line: Control) -> bool:
    if line == null:
        return false
    clear_highlight()
    highlighted = line
    _paint(line, true)
    _focus(line)
    _scroll_to(line, true)
    return true


## Every place a search can land on every one of *categories*, built the way
## `build_index` builds them and freed: `{"page", "title", "words"}` each, the
## words being `haystack`'s, so a search over these finds what Preferences' own
## does. A page that builds to nothing is left out.
static func catalogue(categories: Array, build_page: Callable) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for category: String in categories:
        var page: Control = build_page.call(category)
        if page == null:
            continue
        for landing: Control in landings(page):
            out.append({"page": category, "title": landing_title(landing), "words": haystack(landing)})
        page.free()
    return out


## The line of the row declared under *key* on whichever page *root* holds,
## or null. Asked of every page realized under it, because a page may hold
## two: Keyboard Shortcuts realizes its chords as a second page under its
## Profile section.
static func row_line(root: Node, key: StringName) -> Control:
    var hosts: Array[Node] = [root]
    hosts.append_array(root.find_children("*", "Container", true, false))
    for host: Node in hosts:
        if not host.has_meta(SaPage.PAGE_META) or _is_going(host):
            continue
        var declared := (host.get_meta(SaPage.PAGE_META) as SaPage).row(key)
        if declared != null and declared.line != null and is_instance_valid(declared.line):
            return declared.line
    return null


## Gives the keyboard to the first control on *landing* that takes it.
static func _focus(landing: Control) -> void:
    for child: Node in landing.get_children():
        var control := _first_focusable(child)
        if control != null:
            control.grab_focus()
            return


## Called by the window once it has opened a page, so the mark follows the page
## that is actually open and `report()` can say which one that is, and the page
## that left is read again. *row* is the key of a row a door opened the page
## for, or the title of one that has no key, which is marked in place of the
## search's first match.
func mark_page_open(title: String, row: StringName = &"") -> void:
    index.erase(_open_page)
    _open_page = title
    if row.is_empty():
        highlight_first_match()
    elif not land_on(row) and not land_titled(String(row)):
        push_warning("Preferences: the %s page has no row '%s' to open on" % [title, row])


## Brings the marked row into view, a couple of frames later.
##
## The page was added in the same call that marks the row, and a container sorts
## its children in a later frame, so a scroll asked for now reads every row at
## position zero and stays at the top. That is what the first capture of this
## showed: the list narrowed to Display, Display open, and Proof gamut still
## eight rows below the fold. `call_deferred` was not enough either, the rows
## being three containers deep and each depth sorting in its own pass.
##
## *to_top* is a door's: the row's section starts at the top of the pane when
## the row still fits under it, and the row itself does when it does not.
func _scroll_to(row: Control, to_top: bool = false) -> void:
    var tree := _content_scroll.get_tree()
    if tree == null:
        return
    await tree.process_frame
    await tree.process_frame
    if not is_instance_valid(_content_scroll) or not is_instance_valid(row) or highlighted != row:
        return
    if not to_top:
        _content_scroll.ensure_control_visible(row)
        return
    _content_scroll.scroll_vertical = _top_of(row)


## The scroll that puts *row*'s section, heading first, at the top of the pane,
## or the row itself when the section down to the row is taller than the pane.
## The section is the column `SaSettingsRows.section` puts the heading and the
## marked rows box in.
func _top_of(row: Control) -> int:
    var down := _content_scroll.scroll_vertical - _content_scroll.global_position.y
    var top := row.global_position.y
    var rows := row.get_parent()
    var block := rows.get_parent() as Control if rows != null and rows.has_meta(SaSettingsRows.SECTION_META) else null
    if block != null and row.global_position.y + row.size.y - block.global_position.y <= _content_scroll.size.y:
        top = block.global_position.y
    return int(top + down)


## Where the marked row stands in the pane: its top below the pane's top, and
## whether the whole of it is inside, for `report()`. A door's claim is that the
## row is in view, and a shot of a long page cannot say where the fold was.
func _marked_in_view() -> Dictionary:
    if highlighted == null or not is_instance_valid(highlighted) or not highlighted.is_inside_tree():
        return {"at": -1, "in_view": false}
    var at := highlighted.global_position.y - _content_scroll.global_position.y
    return {"at": int(at), "in_view": at >= 0.0 and at + highlighted.size.y <= _content_scroll.size.y}


func clear_highlight() -> void:
    if highlighted != null and is_instance_valid(highlighted):
        _paint(highlighted, false)
    highlighted = null


## Drops the pointer without touching what it points at, for a page on its way
## to `queue_free`.
func forget_highlight() -> void:
    highlighted = null


## The mark itself: the landing's own title in the accent colour.
##
## A panel behind the row would read louder and would need a stylebox bound to
## the theme to survive a palette switch. The title is one colour override on
## one Label, and it is the Label with nothing else on it: the explanation under
## it carries `text_muted` through `SaTheme.bind_font`, so clearing an override
## there would strip the dimming rather than the mark.
static func _paint(landing: Control, on: bool) -> void:
    var name_label := _mark_label(landing)
    if name_label == null:
        return
    if on:
        name_label.add_theme_color_override("font_color", SaTheme.palette.accent_primary)
    else:
        name_label.remove_theme_color_override("font_color")


## The Label a mark colours: a row's title, a heading itself, an item's own
## label.
static func _mark_label(landing: Control) -> Label:
    if landing is Label:
        return landing as Label
    if not landing.has_meta(SaSettingsRows.ROW_META):
        return _item_label(landing)
    if landing.get_child_count() == 0:
        return null
    for child in landing.get_child(0).get_children():
        var label := child as Label
        if label != null:
            return label
    return null


## Whether *node* is on a page that has already been queued for deletion.
##
## `queue_free` runs at the end of the frame and marks the node it was called
## on, not its children, and a category switch queues the outgoing page and
## builds the incoming one in the same call. So the tree holds both pages for a
## moment, and without walking up the mark landed on the one on its way out.
static func _is_going(node: Node) -> bool:
    var walk := node
    while walk != null:
        if walk.is_queued_for_deletion() or walk.has_meta(SaSettingsKeptPages.HIDDEN_META):
            return true
        walk = walk.get_parent()
    return false


static func _first_focusable(node: Node) -> Control:
    var control := node as Control
    if control != null and control.focus_mode != Control.FOCUS_NONE:
        return control
    for child in node.get_children():
        var found := _first_focusable(child)
        if found != null:
            return found
    return null


## What the search did, for a capture.
##
## A screenshot of the left panel shows the categories that are left, and says
## nothing about how many there were, which row was marked or what has the
## keyboard, the three things a search promises.
func report() -> Dictionary:
    var marked := ""
    if highlighted != null and is_instance_valid(highlighted):
        marked = landing_title(highlighted)
    var seen := _marked_in_view()
    return {
        "text": field.text,
        "categories": _shown,
        "categories_in_all": _categories.size(),
        "open_page": _open_page,
        "highlighted_row": marked,
        # Preferences is its own Window, so what has the keyboard in it is not
        # what `focused_control` reads: that one asks the root viewport, and an
        # embedded subwindow keeps its own focus owner. The row is
        # focused as well as marked, so the claim is answered here.
        "focused_control": _focus_path(),
        # How far down the page the scroll went, because "scrolls to" is the
        # one clause a screenshot answers and a number answers better.
        "scrolled_to": _content_scroll.scroll_vertical,
        "indexed": index.size(),
        # The marked row's top below the pane's, and whether all of it shows.
        "highlighted_at": int(seen["at"]),
        "highlighted_in_view": bool(seen["in_view"]),
    }


## The focused control by the row title it was given, since Godot names a
## control nobody named `@OptionButton@2933` and that says nothing. Asked of
## the content scroll's own viewport rather than of a window, which is that
## same embedded window either way.
func _focus_path() -> String:
    var viewport := _content_scroll.get_viewport()
    var focused := viewport.gui_get_focus_owner() if viewport != null else null
    if focused == null:
        return "<none>"
    var titled := String(focused.get_meta(SaSettingsRows.TITLE_META, ""))
    return titled if not titled.is_empty() else String(focused.name)


## The Preferences search, for the state dump: the field, the categories left
## showing, the row it marked, and whether the page area says "Nothing matches"
## and what it says under it, or an empty dictionary when the window has never
## been built.
##
## Untyped window on purpose: a cast to a `class_name` in a static function
## leaks the script.
static func capture_state(root: Window) -> Dictionary:
    for node in root.find_children("*", "Window", true, false):
        if node.has_method("show_page") and node.get("search") != null:
            var out: Dictionary = node.search.report()
            var nothing: Control = node.get("nothing_matches")
            var why: Label = node.get("_nothing_why")
            out["nothing_matches"] = nothing != null and nothing.visible
            out["nothing_says"] = why.text if why != null and bool(out["nothing_matches"]) else ""
            # The words the window writes itself, as drawn, which a change of
            # catalogue has to reach as well as the page's rows.
            var page_title: Label = node.content_container.get_node_or_null(^"PageTitle")
            out["words"] = {
                "title": node.title,
                "headings": node.group_headings.values().map(func(heading: Label) -> String: return heading.text),
                "sidebar": node.category_buttons.map(func(button: Button) -> String: return button.text),
                "page_title": page_title.text if page_title != null else "",
            }
            return out
    return {}
