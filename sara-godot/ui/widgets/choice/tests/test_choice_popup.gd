## The one-of list, and the half of the mark's move it finishes.
##
## The radio dots were taken off Sara's menus and the chosen row is marked with the
## `hover` stylebox, which is a `PopupMenu`'s only per-row highlight. So the mark
## followed the pointer and the current choice was unreadable exactly while a
## painter was choosing, which is the half-done state this suite guards. A row
## here is a toggle in a `ButtonGroup` and carries its own pressed box, so the
## two are different states and this suite is about them staying different.
extends "res://tests/test_framework.gd"


func _list(rows: Array[String], one_of: bool = true) -> SaChoicePopup:
    var popup := SaChoicePopup.new()
    popup.one_of = one_of
    popup.clear()
    for row in rows:
        popup.add_row(StringName(row), row.capitalize())
    return popup


func test_a_one_of_row_is_a_toggle_in_a_group_and_never_a_radio() -> void:
    var popup := _list(["one", "two", "three"])

    for id in popup.row_ids():
        var button := popup.label_button(id)
        assert_true(button.toggle_mode, "%s is a toggle" % id)
        assert_not_null(button.button_group, "and in the one group")
    assert_eq(
        popup.label_button(&"one").button_group,
        popup.label_button(&"three").button_group,
        "which is the same group for every row, so exactly one can be down"
    )

    popup.free()


func test_the_mark_is_the_pressed_state_and_not_a_colour() -> void:
    var popup := _list(["one", "two", "three"])

    popup.set_current(&"two")

    assert_true(popup.label_button(&"two").button_pressed, "The chosen row is down")
    assert_false(popup.label_button(&"one").button_pressed, "and the rows either side are not")
    assert_false(popup.label_button(&"three").button_pressed, "on both sides")
    assert_true(popup.is_marked(&"two"), "which is what is_marked reads")

    popup.free()


## The bug this cost a capture to find. A `ButtonGroup` unpresses its siblings
## whenever one of them is written, so a single loop that marks the chosen row
## and then clears the rows after it clears the chosen row with them.
func test_marking_a_row_before_the_rows_after_it_are_cleared() -> void:
    var popup := _list(["one", "two", "three"])

    popup.set_current(&"one")

    assert_true(popup.is_marked(&"one"), "The first row can be the chosen one")
    assert_eq(popup.current, &"one", "and current() agrees with the row that is down")

    popup.set_current(&"three")

    assert_true(popup.is_marked(&"three"), "and the mark moves to the last row")
    assert_false(popup.is_marked(&"one"), "leaving the first")

    popup.free()


func test_a_plain_list_still_marks_with_the_accent() -> void:
    var popup := _list(["one", "two"], false)

    popup.set_current(&"two")

    assert_false(popup.label_button(&"two").toggle_mode, "A plain list's rows are not toggles")
    assert_true(popup.is_marked(&"two"), "and the mark is the colour rather than the pressed box")
    assert_false(popup.is_marked(&"one"), "on one row only")

    popup.free()


## What the dump reports, and the reason it reports two things rather than one.
func test_the_report_says_which_row_is_marked_and_which_is_hovered() -> void:
    var popup := _list(["one", "two"])
    popup.set_current(&"two")

    var report := popup.row_report()

    assert_eq(report.size(), 2, "Two rows")
    assert_false(bool(report[0]["current"]), "The first is not the chosen one")
    assert_true(bool(report[1]["current"]), "and the second is")
    assert_true(report[0].has("hovered"), "Every row says whether the pointer is on it")
    assert_true(report[1].has("hovered"), "including the chosen one, which is the whole question")

    popup.free()


## The claim these two cases were written for was that an `OptionButton` kept
## every name its callers read while the list under it changed, so nothing that
## owned one had to change. There is no
## `OptionButton` left in the tree, and the button and its list are one object.
## What is asserted is the same pair of claims against that object.
func test_a_choice_button_answers_with_the_callers_own_value() -> void:
    var button := SaChoiceButton.new()
    button.set_choices([{"id": &"first", "label": "First"}, {"id": &"second", "label": "Second"}])
    button.select_value(&"first")

    var announced: Array[StringName] = []
    button.choice_picked.connect(func(value: Variant) -> void: announced.append(StringName(value)))

    button.toggle_list()
    var popup := button.popup
    assert_not_null(popup, "Pressing the button opens the row list")
    assert_eq(popup.row_labels(), ["First", "Second"] as Array[String], "out of the button's own rows")
    assert_true(popup.is_marked(&"first"), "with the chosen row marked")

    popup.press_row(&"second")

    assert_eq(button.selected_value(), &"second", "Choosing a row writes the caller's own value")
    assert_eq(announced, [&"second"] as Array[StringName], "and emits choice_picked, which every caller listens to")

    button.free()


## Pressing the row that is already chosen. The `OptionButton` this pair was once
## written against said nothing, because writing `selected` delivers no
## `item_selected` and the signal was emitted by hand only when the index moved.
## `SaChoiceButton` announced it instead, the press reaching
## `_on_row_chosen` whether or not the value moves. The guard is on the move, so a
## caller that rebuilds on every pick no longer rebuilds once for nothing, and
## the claim the pair was written as is a claim again. The row still takes the
## press and the list still closes on it, because the painter pressed something.
func test_choosing_the_row_that_is_already_chosen_stays_quiet() -> void:
    var button := SaChoiceButton.new()
    button.set_choices([{"id": &"first", "label": "First"}, {"id": &"second", "label": "Second"}])
    button.select_value(&"second")

    var announced: Array[StringName] = []
    button.choice_picked.connect(func(value: Variant) -> void: announced.append(StringName(value)))

    button.toggle_list()
    assert_true(button.popup.press_row(&"second"), "The row that is already marked still takes the press")

    assert_eq(button.selected_value(), &"second", "The button is where it was")
    assert_eq(announced, [] as Array[StringName], "and said nothing, the value never having moved")
    assert_true(button.popup.is_marked(&"second"), "The mark is still on the row that was pressed")
    assert_false(button.popup.visible, "and the list closed, because the painter did press a row")
    # What the `choice` step reads, and the only thing about this that a capture
    # of the running app can see: everything above is the same either way.
    assert_eq(button._announced, 0, "The count the capture reads has not moved either")

    button.popup.press_row(&"first")

    assert_eq(button.selected_value(), &"first", "A row that does move the value")
    assert_eq(announced, [&"first"] as Array[StringName], "is announced once, so the guard is on the move and not on the press")
    assert_eq(button._announced, 1, "and the capture's count follows the signal")

    button.free()


## The four things a `PopupMenu` item could never be told. The engine's default
## menu drew the Layers menu with Duplicate and
## Clear tower over Merge Down because the engine draws an icon at the texture's
## own size and grows the item around it.
##
## The icon is capped rather than expanded, so every row draws
## it at one size whatever its label's length, and a capped icon counts in the
## row's minimum. That minimum is read with the popup in the tree, hidden, because
## a button out of the tree never takes the `icon_max_width` written on it into
## the cache its minimum is measured from, and detached Duplicate's 64-pixel
## texture counts whole and asks for 72 where the row draws 28.
func test_an_icon_row_is_no_taller_than_a_plain_one() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"plain", "Merge Down")
    popup.add_row(&"iconed", "Duplicate", false, false, "duplicate")
    var host := Node.new()
    EventBus.add_child(host)
    host.add_child(popup)

    var plain := popup.label_button(&"plain")
    var iconed := popup.label_button(&"iconed")

    assert_not_null(iconed.icon, "The row carries the icon it named")
    assert_false(iconed.expand_icon, "capped rather than fitted into what the label leaves")
    assert_eq(
        int(iconed.get_theme_constant("icon_max_width")),
        SaChoicePopup.ICON_SIZE,
        "which is the list's own cap and not the texture's size"
    )
    assert_eq(iconed.custom_minimum_size.y, plain.custom_minimum_size.y, "so an icon row and a plain row are the same height")
    assert_eq(int(plain.custom_minimum_size.y), SaChoicePopup.ROW_HEIGHT, "and both are the row height")
    assert_eq(
        iconed.get_combined_minimum_size().y,
        plain.get_combined_minimum_size().y,
        "and the capped icon grows its row no taller than the plain one"
    )

    host.free()


## An icon name nothing ships leaves the row a plain row rather than raising, so
## a module naming an icon Sara does not have loses the picture and keeps the
## menu.
func test_an_icon_that_does_not_exist_leaves_a_plain_row() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"missing", "Nothing", false, false, "no-such-icon-anywhere")

    assert_null(popup.label_button(&"missing").icon, "No texture")
    assert_eq(popup.row_labels(), ["Nothing"] as Array[String], "and the row is still a row")

    popup.free()


## The chord at the row's right. Its own Label rather than text inside the
## button, because a chord written into the label is text the type-ahead would
## then match on.
func test_a_hint_sits_beside_the_label_and_is_reported() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"undo", "Undo", false, false, "", "Ctrl+Z")
    popup.add_row(&"bare", "Bare")

    assert_eq(popup.label_button(&"undo").text, "Undo", "The button carries the label and nothing else")
    var report := popup.row_report()
    assert_eq(String(report[0]["hint"]), "Ctrl+Z", "and the hint is reported beside it")
    assert_eq(String(report[1]["hint"]), "", "A row with no hint reports none")
    assert_eq(String(report[0]["icon"]), "", "and a row with no icon reports none")

    popup.free()


## A disabled row is dimmed and takes no press, from the pointer or from a
## scenario. Emitting `pressed` by hand walks past `Button.disabled`, which the
## engine only consults on a real press.
func test_a_disabled_row_is_dimmed_and_chooses_nothing() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"isolate", "Isolate Group", false, false, "", "", true)
    popup.add_row(&"merge", "Merge Down")

    var chosen: Array[StringName] = []
    popup.chosen.connect(func(id: StringName) -> void: chosen.append(id))

    assert_true(popup.is_disabled(&"isolate"), "The row says it takes no press")
    assert_true(popup.label_button(&"isolate").disabled, "and the button agrees")
    assert_almost_eq(
        popup.label_button(&"isolate").modulate.a,
        SaChoicePopup.DISABLED_ALPHA,
        0.001,
        "It is dimmed, because a control that cannot be pressed has to look like one"
    )

    assert_false(popup.press_row(&"isolate"), "Pressing it does nothing")
    assert_true(chosen.is_empty(), "and announces nothing")

    assert_true(popup.press_row(&"merge"), "The row beside it still presses")
    assert_eq(chosen, [&"merge"] as Array[StringName], "and announces itself")

    popup.free()


## The dim survives the mark moving. `set_current_where` writes `modulate` over
## every row, which is the write that would otherwise undo it.
func test_the_dim_outlives_a_mark_moving_over_it() -> void:
    var popup := SaChoicePopup.new()
    popup.one_of = false
    popup.clear()
    popup.add_row(&"one", "One")
    popup.add_row(&"two", "Two", false, false, "", "", true)

    popup.set_current(&"one")
    popup.set_current(&"two")

    assert_almost_eq(
        popup.label_button(&"two").modulate.a, SaChoicePopup.DISABLED_ALPHA, 0.001, "The disabled row is still dimmed"
    )
    assert_false(popup.is_marked(&"two"), "and does not read as the chosen one")

    popup.free()


## The arrow keys and enter. `move_highlight` and `choose_highlighted` are what
## `_input` calls, and they are public so a test can ask them without a window:
## a popup out of the tree takes no key events at all.
func test_the_arrow_keys_move_the_highlight_and_enter_chooses() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"one", "One")
    popup.add_row(&"two", "Two")
    popup.add_row(&"three", "Three")

    var chosen: Array[StringName] = []
    popup.chosen.connect(func(id: StringName) -> void: chosen.append(id))

    assert_eq(popup.highlighted(), &"", "A list nobody has arrowed through highlights nothing")
    assert_false(popup.choose_highlighted(), "and enter on it chooses nothing")

    assert_true(popup.move_highlight(1), "Down from nowhere lands somewhere")
    assert_eq(popup.highlighted(), &"one", "which is the first row")
    popup.move_highlight(1)
    assert_eq(popup.highlighted(), &"two", "and down again is the next")
    popup.move_highlight(-1)
    assert_eq(popup.highlighted(), &"one", "up is the one before")
    popup.move_highlight(-1)
    assert_eq(popup.highlighted(), &"three", "and up off the top wraps to the last")

    assert_true(popup.choose_highlighted(), "Enter chooses the highlighted row")
    assert_eq(chosen, [&"three"] as Array[StringName], "which is the row the arrows landed on")

    popup.free()


## The keyboard walks past a disabled row rather than stopping on it, so enter
## can never land on a row that chooses nothing.
func test_the_highlight_skips_a_row_that_takes_no_press() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"one", "One")
    popup.add_row(&"off", "Off", false, false, "", "", true)
    popup.add_row(&"three", "Three")

    popup.move_highlight(1)
    popup.move_highlight(1)

    assert_eq(popup.highlighted(), &"three", "Down from the first row steps over the disabled one")
    assert_false(popup.set_highlight(&"off"), "and it cannot be landed on by name either")
    assert_eq(popup.highlighted(), &"three", "which leaves the highlight where it was")

    popup.free()


## A list whose rows are all disabled ends rather than spinning, which is the
## bound `move_highlight` carries for exactly this case.
func test_a_list_of_disabled_rows_moves_nowhere_rather_than_looping() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"one", "One", false, false, "", "", true)
    popup.add_row(&"two", "Two", false, false, "", "", true)

    assert_false(popup.move_highlight(1), "Down finds no row to land on")
    assert_eq(popup.highlighted(), &"", "and the highlight stays nowhere")

    popup.free()


## Type-ahead on the label's first letters. One letter steps through the rows
## sharing it, a longer needle is a search still being typed and may stay on the
## row it is already on.
func test_type_ahead_walks_the_rows_that_share_a_letter() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"burn", "Burn")
    popup.add_row(&"brightness", "Brightness")
    popup.add_row(&"clear", "Clear")

    assert_true(popup.type_ahead("b"), "b finds a row")
    assert_eq(popup.highlighted(), &"burn", "the first one starting with it")
    assert_true(popup.type_ahead("b"), "b again finds another")
    assert_eq(popup.highlighted(), &"brightness", "the next one, rather than staying on the first")
    assert_true(popup.type_ahead("br"), "br is a search still being typed")
    assert_eq(popup.highlighted(), &"brightness", "and stays on the row it already matches")
    assert_true(popup.type_ahead("c"), "c reaches the last row")
    assert_eq(popup.highlighted(), &"clear", "by name rather than by position")
    assert_false(popup.type_ahead("zz"), "and a needle nothing starts with finds nothing")
    assert_eq(popup.highlighted(), &"clear", "leaving the highlight where it was")

    popup.free()


## The list scrolls past `MAX_HEIGHT` rather than opening taller than a screen.
## `wanted_size` is what `open_under` asks, and it is public because a window
## that is not in a tree cannot be opened at all.
func test_a_long_list_is_capped_at_the_scroll_height() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    for i in 80:
        popup.add_row(StringName("row_%d" % i), "Row %d" % i)

    var size := popup.wanted_size(120.0)

    assert_eq(size.y, SaChoicePopup.MAX_HEIGHT, "Eighty rows are capped at the scroll height")
    assert_true(size.x >= 120, "and the list is never narrower than the button that opened it")

    var short := SaChoicePopup.new()
    short.clear()
    short.add_row(&"one", "One")
    assert_true(short.wanted_size(120.0).y < SaChoicePopup.MAX_HEIGHT, "A short list is its own height")

    short.free()
    popup.free()


## The report is what a dump reads, and it carries four keys for those. A shot of
## a menu cannot say which row is dimmed at the size the docker has.
func test_the_report_carries_the_icon_the_hint_the_dim_and_the_highlight() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"dup", "Duplicate", false, false, "duplicate", "Ctrl+J")
    popup.add_row(&"iso", "Isolate Group", false, false, "", "", true)
    popup.move_highlight(1)

    var report := popup.row_report()

    assert_eq(String(report[0]["icon"]), "duplicate", "The icon is named")
    assert_eq(String(report[0]["hint"]), "Ctrl+J", "the chord is written out")
    assert_false(bool(report[0]["disabled"]), "the first row takes a press")
    assert_true(bool(report[1]["disabled"]), "and the second does not")
    assert_true(bool(report[0]["highlighted"]), "The keyboard is on the first row")
    assert_false(bool(report[1]["highlighted"]), "and on one row only")

    popup.free()


## Hard rule 7 over the popup. A popup is a `Window` of its own, so it does
## not inherit the host's `content_scale_factor` and would open at the OS pixel
## size beside a scaled docker. `open_under` takes the scale through
## `SaUI.apply_to_window()`, which is the rule's only writer, so a list beside a
## docker is the docker's size.
##
## Embedded on purpose, the way `test_windows_open.gd` does it: without embedding
## a Window added to the tree maps a real OS window and the run blocks until the
## watchdog fires. An embedded window's own factor is 1 and its host does the
## scaling, which is what `SaUI.window_scale` answers and what a docker in the
## same tree is given, so the two are compared rather than a number written here.
func test_the_popup_takes_the_scale_the_way_a_docker_does() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "ChoicePopupScaleHost"
    EventBus.add_child(host)

    var anchor := Control.new()
    anchor.size = Vector2(120.0, 24.0)
    host.add_child(anchor)

    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"one", "One")
    host.add_child(popup)

    var docker := Window.new()
    host.add_child(docker)
    SaUI.apply_to_window(docker)

    popup.open_under(anchor)

    assert_true(popup.has_meta(SaUI.APPLIED_SCALE_META), "open_under wrote the scale through the one writer")
    assert_almost_eq(
        popup.content_scale_factor, SaUI.window_scale(popup), 0.001, "and the factor is the one SaUI answers for this window"
    )
    assert_almost_eq(
        popup.content_scale_factor,
        docker.content_scale_factor,
        0.001,
        "which is the same factor a docker window in the same tree is given"
    )

    popup.hide()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding


func _long_list(rows: int) -> SaChoicePopup:
    var popup := SaChoicePopup.new()
    popup.one_of = false
    popup.clear()
    for i in rows:
        popup.add_row(StringName("row_%d" % i), "Row %d" % i)
    return popup


## A list over twenty rows opens with a search field and a shorter
## one does not, so nine rows never carry a search box that failed to find
## anything. The three lists over the line today are the blend modes, the colour
## spaces and the shortcut page's commands.
func test_a_long_list_gets_a_search_field_and_a_short_one_does_not() -> void:
    var long_list := _long_list(25)
    var short_list := _long_list(19)
    var exactly := _long_list(SaChoiceSearch.MIN_ROWS)

    assert_true(long_list.search.visible, "Twenty-five rows earn a field")
    assert_false(short_list.search.visible, "nineteen do not")
    assert_false(exactly.search.visible, "and twenty is not more than twenty")

    long_list.clear()
    assert_false(long_list.search.visible, "A cleared list has no rows and so no field")

    exactly.free()
    short_list.free()
    long_list.free()


## Typing narrows the list to the labels that hold the text, anywhere in them.
## `contains` rather than `begins_with`, which is the opposite of the type-ahead
## and deliberately so: a search is for the row whose name a painter only half
## remembers.
func test_typing_leaves_the_rows_that_hold_the_text() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    for label: String in ["Colour Dodge", "Colour Burn", "Multiply", "Screen"]:
        popup.add_row(StringName(label.to_snake_case()), label)

    assert_eq(popup.filter("dodge"), 1, "A word from the middle of a name finds its row")
    assert_true(popup.is_row_shown(&"colour_dodge"), "which is the row that holds it")
    assert_false(popup.is_row_shown(&"multiply"), "and the rows that do not are gone")

    assert_eq(popup.filter("colour"), 2, "Two rows share a word")
    assert_true(popup.is_row_shown(&"colour_burn"), "and both are left")

    assert_eq(popup.filter("zzz"), 0, "A needle nothing holds leaves an empty list")
    assert_eq(popup.filter(""), 4, "and clearing the field puts every row back")

    popup.free()


## A heading is shown exactly while one of its rows is. A filtered list that
## keeps "Darken" over nothing says the filter is broken, and dropping a heading
## whose rows are all there loses what the list is grouped by.
func test_a_section_heading_lives_or_dies_with_its_rows() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_section("Darken")
    popup.add_row(&"multiply", "Multiply")
    popup.add_gap()
    popup.add_section("Lighten")
    popup.add_row(&"screen", "Screen")
    popup.add_row(&"add", "Add")

    popup.filter("screen")

    var headings := popup._column.find_children("Section*", "Label", true, false)
    assert_eq(headings.size(), 2, "Both headings are still in the column")
    assert_false((headings[0] as Label).visible, "Darken has nothing under it and goes")
    assert_true((headings[1] as Label).visible, "Lighten keeps the row that matched")

    var gaps := popup._column.find_children("*", "HSeparator", true, false)
    assert_false((gaps[0] as HSeparator).visible, "and the gap between two groups goes with the groups")

    popup.filter("")

    assert_true((headings[0] as Label).visible, "Clearing the field puts the heading back")
    assert_true((gaps[0] as HSeparator).visible, "and the gap with it")

    popup.free()


## The keyboard lands on the first row left, so enter picks the best match
## rather than whatever the arrows had reached before the painter typed. A hidden
## row cannot be highlighted, chosen or pressed.
func test_a_filter_moves_the_keyboard_and_takes_the_hidden_rows_out_of_reach() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"multiply", "Multiply")
    popup.add_row(&"screen", "Screen")
    popup.add_row(&"soft_light", "Soft Light")

    var chosen: Array[StringName] = []
    popup.chosen.connect(func(id: StringName) -> void: chosen.append(id))

    popup.move_highlight(1)
    assert_eq(popup.highlighted(), &"multiply", "The keyboard starts on the first row")

    popup.filter("s")

    assert_eq(popup.highlighted(), &"screen", "and a filter moves it to the first row left")
    assert_false(popup.press_row(&"multiply"), "A hidden row cannot be pressed")
    assert_true(chosen.is_empty(), "and chooses nothing")
    assert_false(popup.set_highlight(&"multiply"), "nor highlighted by name")

    popup.move_highlight(1)
    assert_eq(popup.highlighted(), &"soft_light", "Down walks the rows the filter left")
    popup.move_highlight(1)
    assert_eq(popup.highlighted(), &"screen", "and wraps over the hidden one rather than through it")

    assert_true(popup.choose_highlighted(), "Enter picks a row that is on screen")
    assert_eq(chosen, [&"screen"] as Array[StringName], "which is the one the filter left the keyboard on")

    popup.free()


## The report says which rows a filter left, because a dump of a filtered list
## that did not is a dump of the wrong list.
func test_the_report_says_which_rows_a_filter_left() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"multiply", "Multiply")
    popup.add_row(&"screen", "Screen")

    popup.filter("mult")
    var report := popup.row_report()

    assert_true(bool(report[0]["shown"]), "The row that matched is on screen")
    assert_false(bool(report[1]["shown"]), "and the row that did not is not")
    assert_eq(report.size(), 2, "with both still reported, because a filter hides rather than removes")

    popup.free()


## The field takes the height it needs off the list rather than off the screen,
## so a long list with a search on it is still no taller than `MAX_HEIGHT`.
func test_a_searchable_list_is_still_capped_at_the_scroll_height() -> void:
    var popup := _long_list(80)

    var size := popup.wanted_size(120.0)

    assert_true(popup.search.visible, "Eighty rows carry a field")
    assert_eq(size.y, SaChoicePopup.MAX_HEIGHT, "and the popup is still capped at the scroll height")

    popup.free()


## Escape empties the field before it closes the list, which is the order. The
## field handles the key itself, because `Popup` closes on `ui_cancel` in the
## engine's C++ and no script can veto that: what the popup does instead is put
## itself back where it was. Driven through `_input` by hand, a popup out of the
## tree taking no key events of its own.
func test_escape_empties_the_field_before_it_closes_the_list() -> void:
    var popup := _long_list(25)
    popup.filter("row 1")
    assert_true(popup.search.visible, "The list is long enough for a field")
    assert_true(popup.row_report().any(func(row: Dictionary) -> bool: return not bool(row["shown"])), "and the filter bit")

    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    popup.search._input(escape)

    assert_eq(popup.search.text, "", "The first escape empties the field")
    assert_eq(popup.filter(""), 25, "and every row is back")

    var cleared: Array[bool] = []
    popup.search.cleared.connect(func() -> void: cleared.append(true))
    popup.search._input(escape)
    assert_true(cleared.is_empty(), "A second escape on an empty field is not the field's")

    popup.free()


## The reopen after that escape waits for the hide to finish.
## `Window.set_visible` emits `popup_hide` before it takes the viewport off the
## renderer's active list, so a `popup` run inside the signal asked the renderer to
## activate a viewport that was still active, and the engine refused it twice for
## every reopen. The booking still standing once the signal has been emitted is
## what says the handler did not run inside it.
func test_the_reopen_after_an_escape_waits_for_the_hide_to_finish() -> void:
    var popup := _long_list(25)
    popup.filter("row 1")
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    popup.search._input(escape)
    var booked: Rect2i = popup._reopen_at
    assert_true(booked.size != Vector2i.ZERO, "The escape that emptied the field booked the reopen")

    popup.popup_hide.emit()

    assert_eq(popup._reopen_at, booked, "and the hide's own signal left it booked, so nothing reopened inside it")
    var deferred := popup.popup_hide.get_connections().any(
        func(link: Dictionary) -> bool: return (int(link["flags"]) & CONNECT_DEFERRED) != 0
    )
    assert_true(deferred, "The handler runs once the hide has finished, from the message queue")

    popup.free()
