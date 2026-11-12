## Every Preferences page is built from the one row shape, and the window
## that switches between them is nothing but the list and the switching.
##
## A page built by hand, some labels the control's own text and some a Label
## beside it, reads badly. What this
## suite holds is the shape: a control never carries its own label, and the
## label column is the same width on every row of every page.
##
## A Preferences row has its own shape, held at the end: the
## title and the control share the first line in a column the page measures,
## and the explanation runs under both across the whole row.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the gamut solid on the Colour Spaces page.
const REQUIRES_GPU := true


## The controls under *root* that are not on their way out.
##
## Walked up to *root* rather than asked of the node alone, because `queue_free`
## marks the page it was called on and none of its children, and a window
## outside the tree never reaches the frame that frees it. Asked of the node
## alone, every page the sweep had left stayed live under the next page's title,
## so the Display page's three gamut rows were graded again as Tablet's,
## Timelapse's and every page's after them (d33).
func _live_controls(root: Node, cls: String) -> Array[Node]:
    var out: Array[Node] = []
    for node in root.find_children("*", cls, true, false):
        var walk: Node = node
        while walk != root and walk != null and not walk.is_queued_for_deletion():
            walk = walk.get_parent()
        if walk == root:
            out.append(node)
    return out


func test_every_page_builds_through_the_row_builder() -> void:
    var window := SaSettingsWindow.new()
    for title: String in window.categories:
        assert_true(window.show_page(title), "'%s' opens" % title)
        var pages: Array[Node] = []
        for child in window.content_container.get_children():
            if child is VBoxContainer and not child.is_queued_for_deletion():
                pages.append(child)
        assert_eq(pages.size(), 1, "'%s' is one page under the title" % title)
        if pages.is_empty():
            continue
        var page := pages[0]

        for check: Node in _live_controls(page, "CheckButton"):
            assert_eq((check as CheckButton).text, "", "'%s': a switch carries no label of its own" % title)
        for spin: Node in _live_controls(page, "SpinBox"):
            assert_eq((spin as SpinBox).prefix, "", "'%s': a spin box carries no label of its own" % title)

        var widths := {}
        for line: Node in _live_controls(page, "HBoxContainer"):
            if not line.has_meta(SaSettingsRows.ROW_META):
                continue
            var labels := line.get_child(0) as VBoxContainer
            assert_not_null(labels, "'%s': a row starts with its label column" % title)
            if labels != null:
                widths[labels.custom_minimum_size.x] = true
        assert_true(widths.size() <= 1, "'%s': every label column is the same width, got %s" % [title, widths.keys()])
        # Measured on the page rather than one number for every page, and a window off the tree lays nothing out, so the lines
        # keep the dialog's column until the first frame sorts them.
        var column := int(window.content_container.get_meta(SaSettingsRows.COLUMN_META, -1))
        assert_true(column >= 0, "'%s': the page measured its title column" % title)
        assert_true(column <= SaUI.px(SaSettingsRows.COLUMN_MAX), "'%s': no wider than COLUMN_MAX, %d" % [title, column])
    window.free()


## The page open in *window*, the last child under its title.
func _open_page(window: SaSettingsWindow) -> Control:
    return window.content_container.get_child(window.content_container.get_child_count() - 1) as Control


## The Workspace part of the Interface page *window* has open, or null when the
## page open is not Interface. Workspace is a part of Interface.
func _workspace(window: SaSettingsWindow) -> SaWorkspacePage:
    var parts := _open_page(window) as SaSettingsWindow.PageParts
    return parts.part_of(SaWorkspacePage) as SaWorkspacePage if parts != null else null


## The Tablet and Colour Spaces pages carry a control of their own, which they
## rebuild, so the shape is only checked on the pages this suite covers,
## on Files, which took Workspace's file rows, and on Pen and tablet, which
## took its pen rows.
func test_the_workspace_and_display_pages_have_a_row_for_every_setting() -> void:
    var window := SaSettingsWindow.new()
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    var workspace := _workspace(window)
    var rows := 0
    for line: Node in _live_controls(workspace, "HBoxContainer"):
        if line.has_meta(SaSettingsRows.ROW_META):
            rows += 1
    assert_eq(
        rows,
        4,
        (
            "Workspace: I'm coming from, scale, font size and interface font, "
            + "the file rows having gone to Files, the pen's three to Tablet, "
            + "the three layout rows and the five every docker shares to Layouts and dockers, "
            + "and embed after them"
        )
    )
    for moved: String in ["TabletDriverMode", "SoftwarePointerMode", "CursorLeadMode"]:
        assert_null(workspace.find_child(moved, true, false), "%s is no longer on Workspace" % moved)

    # The pen's rows sit together on Tablet, in the order a painter sets a pen
    # up: the driver, the calibration's three, the four
    # buttons, then the pointer and the ring.
    window.show_page("Pen and tablet")
    var tablet := _open_page(window)
    var tablet_rows := 0
    for line: Node in _live_controls(tablet, "HBoxContainer"):
        if line.has_meta(SaSettingsRows.ROW_META):
            tablet_rows += 1
    assert_eq(
        tablet_rows,
        11,
        (
            "Tablet: tablet driver, the calibration's strip, maximum and curve, the right, middle and two extra "
            + "buttons, the mouse's middle button beside the pen's, Sara's own pointer and cursor lead"
        )
    )
    for moved: String in ["TabletDriverMode", "SoftwarePointerMode", "CursorLeadMode"]:
        assert_not_null(tablet.find_child(moved, true, false), "%s is on Tablet" % moved)

    window.show_page("Files")
    var files := _open_page(window)
    var file_rows := 0
    for line: Node in _live_controls(files, "HBoxContainer"):
        if line.has_meta(SaSettingsRows.ROW_META):
            file_rows += 1
    assert_eq(
        file_rows,
        14,
        (
            "Files: versions, autosave interval, autosave target, "
            + "whether a .sad keeps its reference pictures, import fit, open depth, "
            + "whether opening asks, whether an 8-bit picture asks too, "
            + "whether a 2:1 picture is a panorama, export author, "
            + "location, place and whether exports carry the location, "
            + "the settings folder from General, the reset at the sidebar's foot"
        )
    )
    assert_not_null(files.find_child("ExportAuthorEdit", true, false), "the export author row")

    window.show_page("Canvas and colour")
    var display := _open_page(window)
    var sections := 0
    for sep: Node in _live_controls(display, "HSeparator"):
        sections += 1
    assert_eq(
        sections,
        10,
        (
            "Display: view transform, the Shape Check's options, roll-off, gamut mapping, exposure, "
            + "relief, gamuts, proofs, grid, zoom"
        )
    )
    window.free()


## The gamut mapping row belongs on Display beside the roll-off, next to the
## tonemapper, not on Colour Spaces.
##
## The row is asked of the page by its own key rather than looked for by a title,
## because the key is what the setting is bound to and a title is free to be
## reworded. A page carries the key exactly when it declared the row, which is
## what makes this the assertion: the row is on Display and is
## nowhere on Colour Spaces.
func test_the_gamut_mapping_row_is_on_display_and_not_on_colour_spaces() -> void:
    var display := SaDisplayPage.new()
    assert_not_null(display.page.row(&"gamut_mapping"), "Display carries the gamut mapping row")
    display.free()

    var spaces := SaColorSpacesPage.new()
    assert_null(spaces.page.row(&"gamut_mapping"), "and Colour Spaces no longer does")
    spaces.free()


## A reset rebuilds the page that was open, not page 0. Page 0 is not always Workspace,
## which is a part of Interface.
func test_a_reset_rebuilds_the_page_that_was_open() -> void:
    var window := SaSettingsWindow.new()
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    var before := _workspace(window)
    assert_not_null(before, "The Workspace part is open")
    if before == null:
        window.free()
        return
    before.rebuild_requested.emit()
    var after := _workspace(window)
    assert_not_null(after, "and it is the Workspace part again")
    assert_true(after != before, "built anew rather than kept")
    window.free()


## The Workspace page's own numbers: the Font size slider goes under 70 per
## cent, the UI scale slider steps finer than a tenth, and the page does not run
## away under the wheel. The category list is not a different font, which is why
## the family is asserted here.
func test_the_interface_sliders_carry_b1_s_numbers() -> void:
    var window := SaSettingsWindow.new()
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    var page := _workspace(window)

    var font_slider := page.slider_named("font_size")
    # The slider reads the size Sara ships with as 100%, so 70 per cent
    # of the stored multiplier is checked in that multiplier.
    var stored_floor := font_slider.min_value * SaSettingsValues.DEFAULT_FONT_SCALE
    assert_true(stored_floor < 0.7, "the Font size slider reaches under 70 per cent stored, %.3f" % stored_floor)
    assert_almost_eq(stored_floor, SaUI.MIN_FONT_SCALE, 0.01, "and the floor is within a step of the one SaUI clamps to")

    var scale_slider := page.slider_named("ui_scale")
    assert_eq(scale_slider.step, 0.05, "the UI scale slider lands between the old tenths")
    scale_slider.value = 1.05
    assert_almost_eq(scale_slider.value, 1.05, 1e-6, "and 1.05 is a value it holds rather than rounds away")
    scale_slider.value = 1.0

    assert_true(
        window.content_scroll is SaSettingsWindow.SaSettingsScroll,
        "the page scrolls at a step that does not follow the window's height"
    )
    window.free()


## The category list draws in the same face as the page beside it, which is what
## is the whole requirement, and this is the assertion that says so out loud.
func test_the_category_list_and_the_page_share_a_face() -> void:
    var window := SaSettingsWindow.new()
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    var title := window.content_container.get_child(0) as Label
    var category := window.category_buttons[0]
    assert_eq(
        category.get_theme_font("font"), title.get_theme_font("font"), "the category list and the page's own title are one face"
    )
    # The page title is the largest text on
    # the page, so the face is what this holds and the title is not smaller.
    assert_true(
        title.get_theme_font_size("font_size") >= category.get_theme_font_size("font_size"),
        "and the title is not drawn smaller than the list, so any difference is one of weight rather than of family"
    )
    window.free()


## Minimize is two things, and which one depends on whether Preferences is
## an embedded subwindow. The button says which, because a painter who has just
## made the window vanish needs to read where it went.
func test_the_minimize_button_says_which_of_the_two_it_will_do() -> void:
    var window := SaSettingsWindow.new()
    window.frame.attach(window)
    var button: Button = window.frame.minimize_button
    assert_not_null(button, "The title bar has a minimize button")

    window.frame.sync_tooltips()
    # A window not in a tree is not embedded, which is the real-window branch.
    assert_true(button.tooltip_text.contains("Ctrl+comma"), "A real window minimizes, and the tooltip names the way back")

    window.frame.set_mode(SaSettingsFrame.Mode.COLLAPSED)
    assert_eq(button.tooltip_text, "Restore the window.", "and once it is away the button offers to bring it back")
    window.free()


## The seam that makes a real minimize
## shippable at all. `DisplayServer.window_set_mode` takes a window id, and an
## embedded Preferences shares the host's, so that call is a request about the
## whole of Sara. `Window.mode` is a property of this node and Godot ignores it
## while the window is embedded, so it cannot reach the wrong window.
func test_minimize_goes_through_the_window_and_not_the_display_server() -> void:
    var source := FileAccess.get_file_as_string("res://ui/settings/sa_settings_frame.gd")
    assert_true(source.contains("Window.MODE_MINIMIZED"), "The minimize is a Window.mode write")

    # The dangerous call is in the file once, inside the capture probe that
    # exists to show what it does. Anywhere before that is the button's path.
    var probe_at := source.find("static func capture_frame")
    var display_at := source.find("DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED")
    assert_true(probe_at != -1, "The probe is where the capture reads it")
    assert_true(display_at > probe_at, "and the only window_set_mode(MINIMIZED) is inside it, not on the button's path")


## The mode is carried across the OS window `hide()` destroys and
## `popup_centered()` builds, so a reopen that does not clear it first comes
## back minimized. The capture caught that and reading the code would not have,
## which is why the order is held here rather than left to a comment.
func test_the_reopen_clears_the_mode_while_the_window_is_hidden() -> void:
    var source := FileAccess.get_file_as_string("res://ui/settings/sa_settings_frame.gd")
    var body := source.substr(source.find("func clear_os_minimize"))
    body = body.substr(0, body.find("\nfunc ") if body.find("\nfunc ") != -1 else body.length())
    var hide_at := body.find("_window.hide()")
    var clear_at := body.find("Window.MODE_WINDOWED")
    assert_true(hide_at != -1 and clear_at != -1, "The restore hides and clears")
    assert_true(hide_at < clear_at, "and hides first, which is the order that works")


## An embedded window is never OS minimized, whatever the mode says, because the
## question is about an id it does not have.
func test_an_embedded_window_is_never_reported_os_minimized() -> void:
    var window := SaSettingsWindow.new()
    window.frame.attach(window)
    assert_false(window.frame.is_os_minimized(), "A window outside a tree has no OS mode to report")
    assert_true(window.is_open() == window.visible, "so is_open is the plain visibility there")
    window.free()


## Every dropdown on every page shows the label it has chosen.
##
## A custom dropdown must show the selected option. The words are in `text`,
## and what could hide them
## is the row handing a clipping button its left edge, so that the button is drawn
## at its arrow's width. Two things are graded here, per page, per button: the
## label is there to show, and the row lets the button take the column rather
## than its minimum. The drawn width is the running app's to show, because a
## window built outside the tree lays nothing out, and
## `scenarios/a-choice-button-on-a-preferences-row-shows-its-arrow-and-no-label.json`
## is that picture on three pages and at the largest Font size.
##
## A failure names the row by the title it gave its control rather than by the
## node's name, because most of these buttons are never named and the Display
## page's gamut rows failed here as three `@Button@` numbers (d33).
func test_every_dropdown_on_a_page_fills_its_row_and_carries_its_label() -> void:
    var window := SaSettingsWindow.new()
    var seen := 0
    for title: String in window.categories:
        if not window.show_page(title):
            continue
        for node: Node in _live_controls(window.content_container, "Button"):
            var choice := node as SaChoiceButton
            if choice == null or not choice.get_parent().has_meta(SaSettingsRows.ROW_META):
                continue
            seen += 1
            var row_title := String(choice.get_meta(SaSettingsRows.TITLE_META, choice.name))
            assert_eq(
                choice.size_flags_horizontal,
                Control.SIZE_EXPAND_FILL,
                "'%s': %s fills the row's control column rather than sitting at its arrow's width" % [title, row_title]
            )
            if not choice.choice_values().is_empty() and choice.selected_value() != null:
                assert_false(choice.text.is_empty(), "'%s': %s carries the label it chose" % [title, row_title])
    window.free()
    assert_true(seen >= 4, "the sweep reached the dropdowns it is about, %d of them" % seen)


## The Display page's three gamut dropdowns each read the value its setting
## holds.
##
## The Wider display row must not draw Display profile and Wider display as
## an arrow in a box. A search lays no row out: it colours one title and scrolls. The sweep
## above counts these rows among every page's. This one names them, and reads
## the words against the setting rather than against empty, so a dropdown that
## lost its pick and fell back to its first row fails here as well.
func test_the_display_pages_gamut_dropdowns_read_the_setting_they_hold() -> void:
    var wanted := {
        "Display profile": _display_profile_words(),
        "Wider display": tr(SaDisplayFill.display_name(SaSettings.display_fill)),
        "Proof gamut": tr(SaColorSpace.display_name(StringName(SaSettings.proof_profile))),
    }
    var window := SaSettingsWindow.new()
    assert_true(window.show_page("Canvas and colour"), "Canvas and colour opens")
    var found := {}
    for node: Node in _live_controls(window.content_container, "Button"):
        var choice := node as SaChoiceButton
        if choice == null:
            continue
        var row_title := String(choice.get_meta(SaSettingsRows.TITLE_META, ""))
        if not wanted.has(row_title):
            continue
        found[row_title] = true
        assert_eq(choice.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s fills the control column" % row_title)
        assert_eq(choice.text, String(wanted[row_title]), "%s reads the name of the value its setting holds" % row_title)
    window.free()
    assert_eq(found.size(), wanted.size(), "every gamut row was found on the page, got %s" % [found.keys()])


# --- The row in a measured column with its hint across it ----------------


## A Preferences window in the tree, embedded, *logical_width* wide, the way
## `test_preferences_fits_its_pane_and_opens_each_page_at_the_top.gd` opens
## one.
func _open_window(logical_width: int) -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "SettingsPagesHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    window.size = SaUI.window_size_for(window, Vector2i(logical_width, SaSettingsWindow.DEFAULT_LOGICAL_SIZE.y))
    return [window, host, was_embedding]


func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


## Lays *node* out the way drawn frames would: every container sorted outside
## in and every control asked for its minimum again, three times, since a line
## writes its title's size in its own sort and the box under it reads it in
## the next.
func _settle(node: Node) -> void:
    for _pass in range(3):
        _sort_children(node)
        _ask_again(node)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


## The lines of the page open in *window* that `SaSettingsRows.row` drew with a
## title column.
func _lines(window: SaSettingsWindow) -> Array[Node]:
    var out: Array[Node] = []
    for line: Node in _live_controls(window.content_container, "HBoxContainer"):
        if line is SaSettingsRows.Line and line.has_meta(SaSettingsRows.ROW_META):
            out.append(line)
    return out


## The longest explanation on the page open in *window*.
func _longest_hint(window: SaSettingsWindow) -> Label:
    var longest: Label = null
    for line: Node in _lines(window):
        var hint := line.get_node_or_null(^"Labels/Hint") as Label
        if hint != null and (longest == null or hint.text.length() > longest.text.length()):
            longest = hint
    return longest


## Every title on every page reads whole: on one line in its page's column,
## or, wider than `COLUMN_MAX`, wrapped between words with none cut. The
## control starts after the column, and the explanation runs under both across
## the whole row at `WIDE_HINT_SCALE`.
func test_every_title_reads_whole_and_its_hint_runs_under_the_control() -> void:
    var opened := _open_window(SaSettingsWindow.DEFAULT_LOGICAL_SIZE.x)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var cap := SaUI.px(SaSettingsRows.COLUMN_MAX)
    var titles := 0
    for page_title: String in window.categories:
        window.show_page(page_title)
        _settle(window)
        var column := int(window.content_container.get_meta(SaSettingsRows.COLUMN_META))
        for line: Node in _lines(window):
            var title := line.get_node(^"Labels/Title") as Label
            if title.text.is_empty() or not (line as Control).is_visible_in_tree():
                continue
            titles += 1
            var wide := SaSettingsRows.text_width(title)
            assert_true(wide <= column or column == cap, "'%s': %s is no wider than the column" % [page_title, title.text])
            if wide <= cap:
                assert_eq(title.get_line_count(), 1, "'%s': %s reads on one line" % [page_title, title.text])
            for word: String in title.text.split(" "):
                var cut := title.duplicate() as Label
                cut.text = word
                assert_true(SaSettingsRows.text_width(cut) <= column, "'%s': no word of %s is cut" % [page_title, title.text])
                cut.free()
            for at in range(1, line.get_child_count()):
                var control := line.get_child(at) as Control
                assert_true(control.position.x >= column, "'%s': %s's control starts after the column" % [page_title, title.text])
            var hint := line.get_node_or_null(^"Labels/Hint") as Label
            if hint == null:
                continue
            assert_almost_eq(
                hint.size.x, (line as Control).size.x, 1.0, "'%s': %s's hint spans the row" % [page_title, title.text]
            )
            assert_eq(float(hint.get_meta(SaSettingsRows.SIZE_META)), SaSettingsRows.WIDE_HINT_SCALE, "and is the larger size")
            var below := 0.0
            for at in range(1, line.get_child_count()):
                var control := line.get_child(at) as Control
                below = maxf(below, control.position.y + control.size.y)
            assert_true(hint.position.y >= below - 1.0, "'%s': %s's hint starts below its control" % [page_title, title.text])
    assert_true(titles > 60, "the sweep read the titles it is about, %d of them" % titles)
    _close_window(opened)


## A paragraph should stretch to the side so it takes fewer rows. The longest explanation on Display
## takes fewer lines in the window's opening width than in the narrower one.
func test_a_long_hint_takes_fewer_lines_at_1440_wide_than_at_1040() -> void:
    assert_eq(SaSettingsWindow.DEFAULT_LOGICAL_SIZE.x, 1440, "Preferences opens 1440 wide where the host allows")
    var counts: Array[int] = []
    for width: int in [1040, 1440]:
        var opened := _open_window(width)
        if opened.is_empty():
            return
        var window := opened[0] as SaSettingsWindow
        window.show_page("Canvas and colour")
        _settle(window)
        counts.append(_longest_hint(window).get_line_count())
        _close_window(opened)
    assert_true(counts[1] < counts[0], "Display's longest hint takes %d lines at 1440 and %d at 1040" % [counts[1], counts[0]])


## "Make some line separating it where needed": a rule under a row whose hint
## runs past one line when another row follows it, and none under a row whose
## hint is one line.
func test_a_rule_falls_under_a_hint_that_runs_past_one_line() -> void:
    var opened := _open_window(1040)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var ruled := 0
    for page_title: String in ["Canvas and colour", SaSettingsWindow.INTERFACE_PAGE]:
        window.show_page(page_title)
        _settle(window)
        for line: Node in _lines(window):
            var hint := line.get_node_or_null(^"Labels/Hint") as Label
            if hint == null or not (line as Control).is_visible_in_tree():
                continue
            if hint.get_line_count() < 2:
                assert_false(SaSettingsRows.ruled(line as Control), "'%s': a one-line hint draws no rule" % page_title)
            elif SaSettingsRows.ruled(line as Control):
                ruled += 1
    assert_true(ruled >= 3, "a rule fell under %d rows whose hint runs on" % ruled)
    _close_window(opened)


## "The final settings toggle could be above the hint, not next to it", and a
## switch says On or Off beside its knob, inside its own rect.
func test_a_switch_says_on_or_off_on_the_line_with_its_title() -> void:
    var opened := _open_window(SaSettingsWindow.DEFAULT_LOGICAL_SIZE.x)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    window.show_page(SaSettingsWindow.INTERFACE_PAGE)
    _settle(window)
    var switches := 0
    for line: Node in _lines(window):
        var check := line.get_child(line.get_child_count() - 1) as CheckButton
        if check == null:
            continue
        switches += 1
        var word := check.get_node_or_null(^"State") as Label
        assert_not_null(word, "the switch carries its word")
        if word == null:
            continue
        check.button_pressed = true
        assert_eq(word.text, "On", "a switch that is on says On")
        check.button_pressed = false
        assert_eq(word.text, "Off", "and off says Off")
        assert_true(check.custom_minimum_size.x >= word.position.x + word.size.x, "the word sits inside the switch")
        var title := line.get_node(^"Labels/Title") as Label
        assert_almost_eq(check.position.y, title.position.y, 1.0, "the switch is on the title's line, above the hint")
    assert_true(switches > 0, "Interface has a switch to read, %d" % switches)
    _close_window(opened)


## A row under no Preferences page keeps the shape dialogs and panels have:
## the hint under the title in the `LABEL_WIDTH` column, the dialog's hint
## size, and a switch with no word.
func test_a_row_outside_preferences_keeps_its_shape() -> void:
    var host := SaMake.column(EventBus, "DialogRowsHost")
    host.size = Vector2(SaUI.px(1000), SaUI.px(400))
    var check := CheckButton.new()
    var line := SaSettingsRows.row(host, "A switch", "What the switch does, at some length.", check)
    _settle(host)
    var labels := line.get_node(^"Labels") as Control
    assert_eq(int(labels.custom_minimum_size.x), SaUI.px(SaSettingsRows.LABEL_WIDTH), "the dialog's column")
    assert_true(labels.size.x < SaUI.px(SaSettingsRows.LABEL_WIDTH) + 1, "and the hint stays in it")
    var hint := line.get_node(^"Labels/Hint") as Label
    assert_eq(float(hint.get_meta(SaSettingsRows.SIZE_META)), SaSettingsRows.HINT_SCALE, "at the dialog's size")
    assert_null(check.get_node_or_null(^"State"), "and the switch says nothing")
    host.free()


## The words the Display profile dropdown shows for what the setting holds: a
## preset's name, or the system's profile, which a fresh profile starts on.
func _display_profile_words() -> String:
    if SaSettings.display_profile == SaSettingsValues.DISPLAY_PROFILE_SYSTEM:
        return tr("The system's profile")
    return tr(SaColorSpace.display_name(StringName(SaSettings.display_profile)))
