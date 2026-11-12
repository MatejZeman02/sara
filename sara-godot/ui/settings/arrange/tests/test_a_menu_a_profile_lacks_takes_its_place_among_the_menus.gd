## A menu a stored top bar order lacks, or holds after the sentinel, is
## read among the menus.
##
## A profile saved before the Tools menu existed lacks it. `get_layout_order` appended
## what a stored order lacked at its end, which is right for a tool control and
## put Tools after "Second Row" among the tool options: "tools menu is not on
## the list and cannot be reordered". The bar drew it after Help since it
## places the menu buttons by their relative order, and Preferences listed it
## where the order held it. Both profiles are built here as the two stages of
## that story, and each is read as the list, as the page and as the bar.
extends "res://tests/test_framework.gd"

## The menus a profile from before Tools held, in the order a fresh bar has.
const MENUS_WITHOUT_TOOLS := ["File", "Edit", "View", "Window", "Image", "Layer", "Select", "Filter", "Modules", "Help"]

## A few tool controls in an order a painter chose, to see the append leave
## them as it is. Neither is the fresh order, which has radius first.
const TOOL_TAIL := ["Stabilizer Toggle", "opacity", "radius", "Brush Presets"]

var _saved_path: String = ""


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_menus.cfg"))
    _remove_profile()
    SaSettings.load_settings()


func after_each() -> void:
    _remove_profile()
    SaSettings.load_settings()
    _remove_profile()
    var fresh := SaSettings.get_layout_order("TopMenuBar")
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.set_layout_order("TopMenuBar", fresh)


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(SaDataRoot.path("test_menus.cfg")) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## The profile from before Tools: ten menus, the sentinel, a tail.
func _store_before_tools() -> void:
    var order: Array = MENUS_WITHOUT_TOOLS.duplicate()
    order.append(SaSettings.ROW_SENTINEL)
    order.append_array(TOOL_TAIL)
    SaSettings.set_layout_order("TopMenuBar", order)


## A profile after the append put Tools behind the tail.
func _store_with_tools_after_the_sentinel() -> void:
    _store_before_tools()
    var order: Array = SaSettings.get_layout_order("TopMenuBar")
    order.erase("Tools")
    order.append("Tools")
    SaSettings.set_layout_order("TopMenuBar", order)


func _menus_of(order: Array) -> Array:
    return order.slice(0, order.find(SaSettings.ROW_SENTINEL))


func test_a_profile_without_tools_reads_it_between_select_and_filter() -> void:
    _store_before_tools()
    var order := SaSettings.get_layout_order("TopMenuBar")
    var at := order.find(SaSettings.ROW_SENTINEL)
    assert_eq(order.find("Tools"), order.find("Select") + 1, "Tools follows Select")
    assert_eq(order.find("Filter"), order.find("Tools") + 1, "and Filter follows Tools")
    assert_true(order.find("Tools") < at, "so Tools stands before the sentinel")
    assert_eq(_menus_of(order), TopMenuBar.MENU_NAMES, "and the menus are the bar's eleven")
    var tail := order.slice(at + 1, at + 1 + TOOL_TAIL.size())
    assert_eq(tail, TOOL_TAIL, "while the stored tool controls keep their order after it")
    for element: String in order.slice(at + 1):
        assert_false(TopMenuBar.MENU_NAMES.has(element), "and %s after the sentinel is no menu" % element)


func test_a_tool_control_the_profile_lacks_is_still_appended() -> void:
    _store_before_tools()
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_true(order.find("Rotation") > order.find(SaSettings.ROW_SENTINEL), "Rotation is on the second row")
    assert_eq(order.back(), SaSettings.get_layout_order("TopMenuBar").back(), "and the read is stable")


func test_a_profile_holding_tools_after_the_sentinel_reads_it_among_the_menus() -> void:
    _store_with_tools_after_the_sentinel()
    var stored: Array = SaSettings.layout_orders["TopMenuBar"]
    assert_true(stored.find("Tools") > stored.find(SaSettings.ROW_SENTINEL), "The stored order holds Tools after the sentinel")
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(_menus_of(order), TopMenuBar.MENU_NAMES, "and the read has the eleven menus before it")
    assert_eq(order.find("Tools"), order.find("Select") + 1, "Tools after Select")
    assert_eq(order.count("Tools"), 1, "once")


func test_a_menu_whose_neighbour_is_missing_too_goes_after_the_one_before() -> void:
    var order: Array = ["File", "Edit", "Help", SaSettings.ROW_SENTINEL, "radius"]
    SaSettings.set_layout_order("TopMenuBar", order)
    var read := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(_menus_of(read), TopMenuBar.MENU_NAMES, "Every menu lands in the fresh sequence")
    SaSettings.set_layout_order("TopMenuBar", [SaSettings.ROW_SENTINEL, "radius", "Edit"])
    read = SaSettings.get_layout_order("TopMenuBar")
    assert_eq(read.slice(0, 2), ["File", "Edit"], "and a menu with none before it goes to the head")


func test_the_page_lists_tools_among_the_menus_and_carries_it_above_edit() -> void:
    for store: Callable in [_store_before_tools, _store_with_tools_after_the_sentinel]:
        store.call()
        var page := SaLayoutPage.new("TopMenuBar")
        var tools_row := page.row_for("Tools")
        var sentinel_at := page.row_for(SaSettings.ROW_SENTINEL).get_index()
        assert_true(tools_row.is_menu(), "Tools is a menu row")
        assert_true(tools_row.get_index() < sentinel_at, "and stands among the menu rows")
        var band := page.drop_band(tools_row)
        var edit_at := page.row_for("Edit").get_index()
        assert_true(band.x <= edit_at and band.y >= edit_at, "The band reaches Edit's place")
        assert_eq(band.y, sentinel_at - 1, "and ends at the last menu row, the sentinel being past it")

        var order := SaSettings.get_layout_order("TopMenuBar")
        order.erase("Tools")
        order.insert(clampi(edit_at, band.x, band.y), "Tools")
        SaSettings.set_layout_order("TopMenuBar", order)
        page.free()

        var bar := TopMenuBar.new()
        bar._ready()
        bar.apply_layout_settings()
        var names: Array = []
        for child: Node in bar.menu_bar.get_children():
            if child is Button:
                names.append(String(child.name))
        assert_eq(names.slice(0, 3), ["File", "Tools", "Edit"], "The bar draws Tools above Edit")
        bar.free()
