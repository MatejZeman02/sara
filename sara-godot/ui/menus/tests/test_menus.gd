## What every menu under the top bar offers, item by item.
##
## Written before the menu population moved out of `ui/top_bar/top_menu_bar.gd` into one
## file per menu under `ui/menus/`, so that "behaviour identical" is a list the
## split has to reproduce rather than a claim. A screenshot cannot check this:
## the menus are closed in every capture, so the bar looks the same whatever the
## popups hold.
##
## Built detached and `_ready()`ed by hand, the way `test_top_menu_bar.gd` does
## it: a menu's list is a Window, and one in the tree hangs a headless run.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Every menu in the order the bar shows them, and what each holds. The File
## menu has Import Picture under Open Recent: Save and
## Save As split, and Open Recent between Open and Save. A row is
## `[text, id]`, `["---", -1]` for a separator, `["*", text, id]` for a check
## item and `[">", text]` for a heading.
##
## **A heading is what a submenu became.** `SaChoicePopup` has
## no second window to hang a list off, so Open Recent and the Dockers menu's
## Layouts are a title with their rows under it, in the one list. Active Modules
## is a list beside the menu, since `open_child` gives
## the popup a child window. What the Modules menu holds after its first row is
## whatever the loader found, so it is checked as far as that row and
## `test_the_modules_menu_lists_what_the_loader_found` takes it from there.
const EXPECTED := {
    "File":
    [
        ["New...", 199],
        ["New from Clipboard", 210],
        ["---", -1],
        ["Open File...", 200],
        [">", "Open Recent"],
        ["No recent files", 250],
        ["Import Picture...", 206],
        ["---", -1],
        ["Save", 201],
        ["Save As...", 205],
        ["Save as JPEG XL...", 209],
        ["---", -1],
        ["Export...", 202],
        ["Export Target...", 211],
        ["---", -1],
        ["Quit", 207],
    ],
    "Edit":
    [
        ["Undo", 101],
        ["Redo", 102],
        ["Repeat Last", 111],
        ["---", -1],
        ["Cut", 104],
        ["Copy", 105],
        ["Copy Merged", 107],
        ["Paste", 106],
        ["Paste Special...", 114],
        ["---", -1],
        ["Fill with Foreground Colour", 108],
        ["Fill with Background Colour", 109],
        ["Clear", 110],
        ["---", -1],
        ["Search Commands...", 112],
        ["Quick Favourites...", 113],
        ["---", -1],
        ["Preferences...", 100],
    ],
    "View":
    # Grouped into submenus, so the menu fits a 1080 screen.
    [
        [
            "Bars",
            80,
            [
                ["*", "Show Window Buttons", 0],
                ["*", "Show Tool Options Bar", 1],
                ["*", "Show Second Row", 3],
                ["*", "Show Status Line", 72],
            ],
        ],
        ["---", -1],
        [
            "Zoom",
            81,
            [
                ["Zoom In", 10],
                ["Zoom Out", 11],
                ["Reset Zoom", 12],
                ["Actual Pixels", 73],
                ["---", -1],
                ["Fit to View", 13],
                ["Fit to Window", 71],
                ["Centre View", 14],
            ],
        ],
        [
            "Rotate and Flip",
            82,
            [
                ["Rotate Left", 15],
                ["Rotate Right", 16],
                ["Reset Rotation", 17],
                ["---", -1],
                ["*", "Flip View Horizontally", 18],
                ["*", "Flip View Vertically", 19],
            ],
        ],
        ["*", "Isolate Active Layer", 75],
        ["*", "Toggle Grid", 70],
        ["---", -1],
        [
            "Page Edges",
            85,
            [
                ["*", "Fixed", 86],
                ["*", "Grows", 87],
                ["*", "Wraps Sides", 88],
                ["*", "Wraps All Edges", 89],
            ],
        ],
        ["*", "Environment View", 90],
        ["*", "Double Resolution", 91],
        ["---", -1],
        [
            "Display",
            84,
            [
                ["*", "Tonemap Highlights", 2],
            ],
        ],
    ],
    # The three ids are in the six hundreds: the docker rows
    # the Window menu now carries are numbered from zero, and the two families
    # must not meet. Written out rather than read from `SaWindowMenu`, because a
    # const holding another class's constant is not a constant expression.
    "Window":
    [
        ["*", "Fullscreen", 602],
        ["---", -1],
        ["New Window for Second Monitor", 600],
        ["---", -1],
        ["Move All Dockers to Main Window", 601],
    ],
    "Image":
    [
        ["Image Size...", 303],
        ["Canvas Size...", 302],
        ["Crop to Selection", 301],
        ["---", -1],
        ["Flip Horizontally", 304],
        ["Flip Vertically", 305],
        ["Rotate 90° Clockwise", 306],
        ["Rotate 90° Anticlockwise", 307],
        ["Rotate 180°", 308],
        ["---", -1],
        ["Colour Space...", 300],
        ["Projection...", 309],
        [">", "Gamut"],
        ["sRGB / Rec. 709", 310],
        ["Display P3", 311],
        ["Rec. 2020", 312],
        [">", "Depth"],
        ["16-bit float", 320],
        ["32-bit float", 321],
        ["*", "Round Colour at Save", 330],
    ],
    # The rows the Layers docker's More menu reads as well,
    # with Rename and Blend Group on Its Own from it. A detached bar has no
    # layer type registry, so the kinds that follow New Layer at Double
    # Resolution in the running app are
    # `test_the_layer_menu_and_the_more_menu_read_one_list.gd`'s.
    "Layer":
    # The rows of one kind under a submenu each, so the menu fits a 1080
    # screen, each submenu where the first of its rows stood.
    [
        ["New Layer", 400],
        ["New Layer at Double Resolution", 440],
        [
            "New Layer via",
            565,
            [
                ["Layer via Copy", 419],
                ["Layer via Cut", 420],
                ["Layer via Seamless Cut", 429],
            ],
        ],
        ["---", -1],
        ["Rename...", 442],
        ["Duplicate Layer", 401],
        ["Duplicate To", 428],
        ["Delete Layer", 402],
        ["---", -1],
        ["Group", 407],
        ["*", "Blend Group on Its Own", 443],
        ["Clip to Layer Below", 408],
        [
            "Mask",
            560,
            [
                ["Add Mask", 412],
                ["Add Mask from Selection", 413],
                ["Delete Mask", 414],
                ["Apply Mask", 415],
                ["Invert Mask", 416],
                ["*", "Disable Mask", 417],
                ["Mask to Selection", 418],
            ],
        ],
        ["---", -1],
        [
            "Arrange",
            566,
            [
                ["Move Up", 403],
                ["Move Down", 404],
            ],
        ],
        ["---", -1],
        ["Merge Down", 405],
        ["Merge Visible", 448],
        ["Flatten", 406],
        [
            "Convert",
            561,
            [
                ["Resample to Document Resolution", 441],
                ["Rasterize Impasto", 446],
                ["Export Effects as LUT...", 449],
                ["Rasterize Layer", 427],
            ],
        ],
        ["---", -1],
        [
            "Lock",
            567,
            [
                ["*", "Lock Layer", 410],
                ["*", "Lock Alpha", 411],
            ],
        ],
        ["---", -1],
        ["Clear Layer", 409],
        ["---", -1],
        [
            "Flip",
            562,
            [
                ["Flip Horizontally", 444],
                ["Flip Vertically", 445],
            ],
        ],
        [
            "Smart Layer",
            563,
            [
                ["Make Smart Layer", 436],
                ["*", "Edit Smart Layer Contents", 438],
                ["Reset Transform", 437],
                ["Convert to Ordinary Layer", 447],
                ["---", -1],
                ["Share Source with a Copy", 439],
                ["Make Source Independent", 435],
                ["---", -1],
                ["Link to File...", 421],
                ["Reload Linked File", 422],
                ["---", -1],
                ["Make Path Absolute", 423],
                ["Make Path Relative", 424],
                ["Embed Linked File", 425],
                ["Clear Override", 426],
            ],
        ],
    ],
    "Select":
    [
        ["All", 200],
        ["Deselect", 201],
        ["Reselect", 205],
        ["Invert", 202],
        ["Colour Range...", 204],
        ["---", -1],
        ["Feather...", 300],
        ["Border...", 400],
        ["Grow...", 500],
        ["Shrink...", 600],
        ["---", -1],
        ["*", "Quick Mask", 203],
    ],
    # A detached bar has no canvas and so no tool machine, which
    # is the one row the menu builds without one. The tools and the stabilizer
    # modes it lists on the running app are `test_tools_menu.gd`'s, where the
    # menu is handed a bound machine.
    "Tools": [["No tools are registered", 1100]],
    # A bar with no filter registry has the browser's row and no line under
    # it, and Apply Again above it, named after no filter on a bar that has
    # applied none.
    "Filter": [["Apply Filter Again", 408], ["Browse Filters...", 407]],
    "Modules": [["Active Modules", SaModulesMenu.ID_ACTIVE_MODULES]],
    # The Display and Tablet rows are here with Keyboard Shortcuts, so the three
    # pages of Preferences are one group. Documentation and Connect an Agent are
    # in the Develop section of Modules. The colour space browser sits beside the
    # manual, and the ways of learning come first under a heading, with the
    # three pages under one of their own.
    "Help":
    [
        [">", "Learn to paint"],
        ["Manual", 506],
        ["---", -1],
        ["Welcome", 505],
        ["Colour Spaces...", 510],
        ["Report a Problem", 503],
        ["Take a Note", 504],
        ["---", -1],
        [">", "Settings"],
        ["Display Settings...", 508],
        ["Tablet Settings...", 509],
        ["Keyboard Shortcuts", 501],
        ["---", -1],
        ["About Sara", 500],
    ],
}

## The recent list as the run left it, held empty while the File menu is read
## for its No recent files row. A suite that saves through `SaDocumentFiles`
## puts its file at the front, so the list is held empty here.
var _saved_recent: Array = []


func before_each() -> void:
    SaSettings.tonemap_highlights = false
    _saved_recent = SaSettings.recent_files()
    SaSettings.recent_file_paths.clear()


## Back to a fresh profile's rolloff, which is on, so the
## suites after this one see the default.
func after_each() -> void:
    SaSettings.tonemap_highlights = true
    SaSettings.recent_file_paths.assign(_saved_recent)


## A bar bound to every command the menus list, the way main binds it. The note
## mode that owns Take a Note is parented to the bar, so it goes when the bar does.
func _make_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    var note_mode := SaNoteMode.new()
    bar.add_child(note_mode)
    bar.bind_commands(SaTestFixtures.make_menu_registries(note_mode).commands)
    return bar


## The list's own column, in order: rows, separators and headings alike.
##
## Walked rather than read off `row_ids()`, because a separator and a heading are
## not rows and the order they stand in is half of what this suite is about.
## A row of *menu*'s that opens a submenu is `[words, id, its rows]`, the
## submenu walked the same way, so the table says what each group holds.
func _rows(popup: SaChoicePopup, menu: SaMenu = null) -> Array:
    var rows := []
    var column := popup.get_node_or_null(NodePath("ChoiceBody/ChoiceScroll/ChoiceColumn"))
    if column == null:
        return rows
    for child in column.get_children():
        if child is HSeparator:
            rows.append(["---", -1])
            continue
        if child is Label:
            rows.append([">", (child as Label).text])
            continue
        var row := child as SaChoiceRow
        if row == null:
            continue
        var button := popup.label_button(row.id)
        var text := button.text if button != null else ""
        var group := SaMenu.group_list(menu.popup, SaMenu.id_of(row.id)) if menu != null else null
        if group != null:
            rows.append([text, SaMenu.id_of(row.id), _rows(group, menu)])
        elif popup.check_box(row.id) != null:
            rows.append(["*", text, SaMenu.id_of(row.id)])
        else:
            rows.append([text, SaMenu.id_of(row.id)])
    return rows


## Menus that opened nothing could be hidden until something filled them. None
## is left.
const HIDDEN_BY_DEFAULT := []


func test_the_bar_shows_the_populated_menus_in_the_default_order() -> void:
    var bar := _make_bar()
    var names := []
    for child in bar.menu_bar.get_children():
        names.append(String(child.name))
    assert_eq(names, EXPECTED.keys(), "The bar's menu buttons, in order")
    for i in bar.menu_bar.get_child_count():
        var hidden: bool = HIDDEN_BY_DEFAULT.has(names[i])
        var button := bar.menu_bar.get_child(i) as Button
        assert_eq(button.visible, not hidden, "%s is %s by a default profile" % [names[i], "hidden" if hidden else "shown"])
    bar.free()


func test_every_menu_holds_exactly_what_it_held() -> void:
    var bar := _make_bar()
    for menu_name: String in EXPECTED:
        var popup: SaChoicePopup = bar.menus.get(menu_name)
        assert_not_null(popup, "%s exists" % menu_name)
        var rows := _rows(popup, bar.menu(menu_name))
        # The Modules menu lists whatever the loader found, which is the run's
        # own business rather than this table's, so it is checked to its first row.
        if menu_name == "Modules":
            assert_eq(rows.slice(0, 1), EXPECTED[menu_name], "%s opens with its list's row" % menu_name)
            continue
        assert_eq(rows, EXPECTED[menu_name], "%s holds its items" % menu_name)
    bar.free()


## The Modules menu's own rows, checked here rather than in the table above for
## the reason that one gives: what follows the first row is the loader's answer.
## What follows the list is the menu's own, the Develop section, and it is last, so it is read off the end.
func test_the_modules_menu_lists_what_the_loader_found() -> void:
    var bar := _make_bar()
    var rows := _rows(bar.menus["Modules"])
    assert_eq(rows[0], ["Active Modules", SaModulesMenu.ID_ACTIVE_MODULES], "The list's row is first")
    var develop := rows.find([">", "Develop"])
    assert_true(develop > 0, "Develop is under it")
    assert_eq(
        rows.slice(develop + 1),
        [
            ["Documentation", SaModulesMenu.ID_DOCUMENTATION],
            ["New Module...", SaModulesMenu.ID_NEW_MODULE],
            ["Open User Modules Folder...", SaModulesMenu.ID_OPEN_USER_FOLDER],
            ["Reload Modules", SaModulesMenu.ID_RELOAD],
            ["Reload Shaders", SaModulesMenu.ID_RELOAD_SHADERS],
            ["Copy the kernel prompt", SaModulesMenu.ID_COPY_PROMPT],
            ["*", "Local Server", SaModulesMenu.ID_LOCAL_SERVER],
        ],
        "and holds the developer's rows to the end of the menu"
    )
    bar.free()


## A submenu's rows are in the one list, under a title. Open Recent is checked here rather than in the table,
## because what is under its heading is what the recent list happens to hold.
func test_a_heading_carries_the_rows_the_submenu_held() -> void:
    var bar := _make_bar()
    var file: SaChoicePopup = bar.menus["File"]
    assert_true(file.section_titles().has("Open Recent"), "The File menu carries the recent heading")
    bar.free()


## The two View check items mirror the sections they toggle, and start checked
## because both sections are visible on a fresh bar.
func test_the_view_check_items_start_from_the_sections() -> void:
    var bar := _make_bar()
    var view := bar.menu("View")
    assert_true(view.is_item_checked(0), "Window controls are on")
    assert_true(view.is_item_checked(1), "and so is the tool options bar")
    assert_false(view.is_item_checked(TopMenuBar.VIEW_ID_TONEMAP), "Tonemap follows the setting")
    bar.free()


## Clicking the section toggles reaches the bar, both ways, and the bar says so.
func test_the_view_section_toggles_reach_the_bar() -> void:
    var bar := _make_bar()
    var seen := []
    bar.section_visibility_changed.connect(func(section: String, vis: bool) -> void: seen.append([section, vis]))

    bar._on_view_menu_id_pressed(0)
    assert_false(bar.is_section_visible("window_controls"), "Window controls go")
    assert_false(bar.window_buttons.visible, "and the node with them")
    bar._on_view_menu_id_pressed(1)
    assert_false(bar.is_section_visible("tool_options"), "The tool options bar goes")
    assert_false(bar.rows.brush_options_slot.visible, "and its slot with it")
    bar._on_view_menu_id_pressed(0)
    bar._on_view_menu_id_pressed(1)
    assert_true(bar.is_section_visible("window_controls"), "Both come back")
    assert_true(bar.is_section_visible("tool_options"), "on the next click")

    assert_eq(
        seen,
        [["window_controls", false], ["tool_options", false], ["window_controls", true], ["tool_options", true]],
        "and every change was announced"
    )
    bar.free()


## The Window menu's two entries each emit their own signal, synchronously.
func test_the_window_menu_emits_what_main_listens_for() -> void:
    var bar := _make_bar()
    var workspaces := []
    var reparents := []
    var on_workspace := func() -> void: workspaces.append(true)
    var on_reparent := func(which: String, target: Variant) -> void: reparents.append([which, target])
    EventBus.secondary_workspace_requested.connect(on_workspace)
    EventBus.docker_reparent_requested.connect(on_reparent)

    # By name rather than by number, because the numbers are the menu's own and
    # kept out of the dockers' way.
    bar.menu("Window").on_id_pressed(SaWindowMenu.ID_NEW_SECONDARY)
    bar.menu("Window").on_id_pressed(SaWindowMenu.ID_GATHER_DOCKERS)

    EventBus.secondary_workspace_requested.disconnect(on_workspace)
    EventBus.docker_reparent_requested.disconnect(on_reparent)
    assert_eq(workspaces, [true], "The secondary workspace entry asks for one")
    assert_eq(reparents, [["*all*", null]], "and the gather entry asks for every docker back")
    bar.free()


## Building the bar twice, which happens when a test calls `_ready()` and the
## tree then calls it again, must not double any menu.
func test_a_second_ready_does_not_duplicate_items() -> void:
    var bar := _make_bar()
    bar._ready()
    for menu_name: String in EXPECTED:
        var rows := _rows(bar.menus[menu_name], bar.menu(menu_name))
        if menu_name == "Modules":
            assert_eq(rows.slice(0, 1), EXPECTED[menu_name], "%s is populated once" % menu_name)
            assert_eq(rows.count(rows[0]), 1, "and draws its list's row once")
            continue
        assert_eq(rows, EXPECTED[menu_name], "%s is populated once" % menu_name)
    bar.free()


## Layer > Reset Transform and Convert to Ordinary Layer are lit only on a
## smart layer, one that carries a transform, since a transform of an ordinary
## layer is written into its pixels when it is confirmed and leaves nothing to
## reset or convert. Make Smart Layer is lit on both and says why in the corner
## where it does nothing.
func test_the_smart_layer_rows_are_lit_only_on_a_smart_layer() -> void:
    var surface := Fixtures.make_surface()
    var document := surface.get_document()
    var commands := SaMenuCommands.new(Callable(), Callable(), Callable(), Callable(), func() -> SaDocument: return document)
    var rows: Dictionary[StringName, SaCommandDescriptor] = {}
    for command: SaCommandDescriptor in commands.commands():
        rows[command.id] = command
    for id: StringName in [&"layer_make_smart", &"layer_reset_transform", &"layer_bake_transform"]:
        assert_true(rows.has(id), "The Layer menu has its %s row" % id)
    if rows.has(&"layer_make_smart") and rows.has(&"layer_reset_transform") and rows.has(&"layer_bake_transform"):
        assert_eq(rows[&"layer_bake_transform"].label, "Convert to Ordinary Layer", "under the name WORDING gives it")
        assert_false(rows[&"layer_make_smart"].enabled.is_valid(), "Make Smart Layer is always lit")
        for id: StringName in [&"layer_reset_transform", &"layer_bake_transform"]:
            assert_false(bool(rows[id].enabled.call()), "%s is dimmed on an ordinary layer" % id)
        assert_true(bool(rows[&"layer_make_smart"].handler.call()), "Make Smart Layer makes the active layer smart")
        for id: StringName in [&"layer_reset_transform", &"layer_bake_transform"]:
            assert_true(bool(rows[id].enabled.call()), "and %s is lit on it" % id)
    Fixtures.teardown(surface)
