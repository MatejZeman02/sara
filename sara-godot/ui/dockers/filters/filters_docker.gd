## The Filters docker: every registered filter in one list, with a search, what
## the picked one says and does to the active layer, and Open, which is the
## Filter menu row's own invoke, and under them the parameters of the filter
## picked in the Layers docker, edited live.
##
## **A docker and no window beside it**, so the filters are listed in one
## place. The list, the search, the detail and Open are [SaFilterBrowser], which
## the layer kind browser's window stands on as well, and this is the frame a
## docker gives it: a drag bar, a place in the layout, a row in the Window menu
## and a summon. Filter > Browse Filters... summons it under the pointer and back
## when the pointer leaves, the Window menu's row summons it locked ([method
## answer_row]), and a fresh profile leaves it closed
## (`DockerLayoutStore.HIDDEN_UNTIL_ASKED`).
##
## **The list is a sidebar beside the detail**, so the filters stay in sight
## while one is read. A summon opens the docker at [constant OPEN_SIZE], wide
## enough for the sidebar and the whole detail, and the borrow puts it back in
## its place in the layout, a strip 160 wide in the shipped layouts, when it
## goes. A docker narrower than [constant SIDEBAR_FROM] stands the list over the
## detail instead.
##
## **The parameters part is under Open.** It holds the panel Tool Options shows
## for a picked filter row, or the active adjustment layer's own record, and both
## panels write the one record, so either moves the other (`filter_parameters.gd`,
## reached by a Layers docker's pick through [method follow_pick]). **The Looks
## part under it** is the saved looks, a group of filter layers saved under a name
## and added back as a group (`filter_looks.gd`, over the file `filter_look.gd`
## writes). Every part shows whole and the column scrolls, because a scroll inside
## a scroll gave each part its floor alone.
##
## **Open sends a summoned docker back.** Left up beside the filter's dialog, a
## docker out on a summon would cover the picture the dialog previews. Open sends
## it back to the place, the size and the visibility the summon found it with,
## which is [method _go_back] and not the rest of the close: the close also hides
## the docker and writes the layout as the painter's edit, which forks a shipped
## layout under a name the painter never chose. A docker shown in its own place
## in the layout and not summoned stays up after Open, so a second filter is one
## press away.
@tool
extends DockerWindow

class_name FiltersDocker

const FilterParameters := preload("res://ui/dockers/filters/filter_parameters.gd")
const FilterLooks := preload("res://ui/dockers/filters/filter_looks.gd")
const DockerColumnScroll := preload("res://ui/dockers/docker_column_scroll.gd")

## What the docker opens at under a layout with no section for it, and the
## place the shipped default gives it, the free strip right of Undo History
## and under the Reference.
const DEFAULT_SIZE := Vector2i(160, 504)
const DEFAULT_POSITION := Vector2i(1440, 544)

## What a summon opens the docker at, logical, at the least: the sidebar and a
## detail column wide enough for the sentence and the preview, and tall enough
## for those, Open, the parameters' sentence and the Looks part whole. At 600
## by 760 the blur's column wanted 815, the parameters' sentence three lines.
const OPEN_SIZE := Vector2i(640, 820)

## How wide the docker is, logical, from which the list stands beside the
## detail rather than over it. The sidebar's 240 and a detail column of 200.
const SIDEBAR_FROM := 480

## The name `MainDockers` takes, by which a summon finds the manager it goes
## through.
const MANAGER_NAME := "MainDockers"

## The list, the search, the detail and Open, which the layer kind browser's
## window holds one of as well.
var browser: SaFilterBrowser = null

## The parameters of the record the painter last picked, under the browser.
var parameters: FilterParameters = null

## The saved looks under the parameters, with Save Look..., Add, Rename... and
## Delete.
var looks: FilterLooks = null

## The column the drag bar and the browser stand in, whose minimum is what the
## docker asks of a layout.
var _column: VBoxContainer = null


func _init() -> void:
    _init_docker(SaDockerIds.FILTERS, "Filters", DEFAULT_SIZE, Vector2i(150, 320))
    position = DEFAULT_POSITION

    _column = SaMake.column(_control_node, "VBoxContainer")
    _column.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Filters")
    _column.add_child(drag_handle)

    # Scrolled, because the Looks part took the column past the half screen
    # `grow_to_content` opens a docker at, and a column that does not fit is
    # clipped from the bottom, which is where the Looks' buttons are.
    var margin := SaMake.margin(null, "MarginContainer", SaUI.BASE_MARGIN)
    DockerColumnScroll.wrap(_column, margin)

    # Over, as the 160 a docker is built at asks, and beside from the first
    # size wide enough.
    browser = SaFilterBrowser.new(false, _open_filter)
    margin.add_child(browser)
    visibility_changed.connect(browser.follow_window)
    size_changed.connect(_follow_width)

    parameters = FilterParameters.new()
    looks = FilterLooks.new()
    browser.hold([parameters, looks])


func _ready() -> void:
    _setup_docker_ready()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()
    # Main's registries, the ones the Filter menu is filled from. A docker built
    # outside the app has none, and a suite points the browser at its own.
    var main_node := get_tree().current_scene if is_inside_tree() else null
    var registries := main_node.get("registries") as SaRegistries if main_node != null else null
    if registries != null and browser.registry == null:
        browser.watch(registries.filters, registries.commands)
    if registries != null and parameters.registry == null:
        parameters.registry = registries.filters
        parameters.refresh()
    if registries != null and looks.layer_types == null:
        looks.layer_types = registries.layer_types


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.FILTERS)


## Stands the list beside the detail from [constant SIDEBAR_FROM] wide and over
## it under that, each time the docker's size moves.
func _follow_width() -> void:
    var wide := float(size.x) / maxf(SaUI.window_scale(self), 0.01) >= float(SIDEBAR_FROM)
    if wide != browser.side_by_side:
        browser.lay_out(wide)


## Widens the docker out on a summon to [constant OPEN_SIZE] about the centre
## the summon put it at, kept on the window, under the bar and above the status
## line, and has the borrow hold that size. The borrow writes nothing to the
## layout, so the docker goes back to its place there at the size it had.
func open_wide(store: DockerLayoutStore) -> void:
    var wanted := SaUI.window_size_for(self, OPEN_SIZE)
    if size.x >= wanted.x and size.y >= wanted.y:
        return
    var centre := Vector2(position) + Vector2(size) * 0.5
    size = size.max(wanted)
    # No floor, which `kept` never reads: the size is the one set above. Kept
    # as tall as the line again, so the foot stops above it.
    var refit := SaDockerLayoutRefit.new(store.top_inset, Callable())
    var line := Vector2i(0, SaDockerLayoutRefit.status_rows_in(SaUI.window_scale(self)))
    position = refit.kept(self, Vector2i(centre - Vector2(size) * 0.5), size + line)
    store.note_placement(self)


## The docker under the current scene, or null. What the capture step, the
## Filter menu's row and a test reach it by.
static func find_in(tree: SceneTree) -> FiltersDocker:
    if tree == null:
        return null
    for node in tree.root.find_children(String(SaDockerIds.FILTERS), "Window", true, false):
        var docker := node as FiltersDocker
        if docker != null:
            return docker
    return null


## The `MainDockers` under *tree* that holds the dockers, found by its name as
## [method find_in] finds the docker, or null. An object, for the reason
## [method _summon_through] gives. By name rather than as `Main`'s `dockers`,
## so a suite's manager under a host of its own is found the way the app's is.
static func _manager_in(tree: SceneTree) -> Object:
    var found := tree.root.find_child(MANAGER_NAME, true, false) if tree != null else null
    return found if found != null and found.has_method("summon_docker_by_id") else null


## Hands the docker under *from*'s tree the filter record a Layers docker's
## row picked, or null when a layer's row took the pick back. The list keeper
## calls this beside showing the record in Tool Options, so the two panels
## follow one pick. A list outside any tree has no docker to tell.
static func follow_pick(from: Node, record: SaAttachedFilter) -> void:
    var docker := find_in(from.get_tree()) if from != null and from.is_inside_tree() else null
    if docker != null:
        docker.parameters.pick(record)


## Summons the docker the way a docker's summon chord does, through
## `MainDockers.summon_docker_by_id`, and answers whether there was a docker
## and a manager to summon it. *locked* keeps it out until it is closed, and
## *at*, a centre in the pointer's space, puts it there rather than under the
## pointer.
##
## The list is filled again first, so a search typed before it went away is
## kept and a module loaded since is on it, and a docker the summon put out is
## opened wide, [method open_wide].
static func summon(tree: SceneTree, locked: bool = false, at: Variant = null) -> bool:
    var docker := find_in(tree)
    var dockers := _manager_in(tree)
    if docker == null or dockers == null:
        return false
    docker._summon_through(dockers, locked, at)
    return true


## The summon itself, through *dockers*, the `MainDockers` that holds this one,
## named as an object so this package does not name the one that names it.
func _summon_through(dockers: Object, locked: bool, at: Variant) -> void:
    browser.refresh()
    dockers.call("summon_docker_by_id", SaDockerIds.FILTERS, locked, at)
    var store := dockers.get("layout_store") as DockerLayoutStore
    if store != null and store.is_borrowed(String(SaDockerIds.FILTERS)):
        open_wide(store)


## What the Window menu's row does to this docker, which
## `MainDockers.toggle_docker` hands *dockers*, itself, and asks first. A shut
## docker is summoned locked about the middle of its place in the layout and
## opened wide, and one out on a summon is closed as its own close does, which
## sends it back there. Answers false for a docker shown in its place, which the
## row hides as it hides any other.
##
## The row's docker takes the keyboard and stands in front, as a docker the row
## shows does. A summon hands the keyboard back to the window that held it, which
## is right for a chord pressed over the canvas, and here put the Layers docker
## a filter row had just been picked in over the middle of the wide one.
##
## Every shipped layout keeps a strip 160 wide for this docker and every wider
## place for another, so a summon rather than a show in place is the way to a
## wide one, and it writes nothing to the layout.
func answer_row(dockers: Object) -> bool:
    var store := dockers.get("layout_store") as DockerLayoutStore
    if not visible:
        _summon_through(dockers, true, Vector2i(Vector2(position) + Vector2(size) * 0.5))
        grab_focus()
        return true
    if store == null or not store.is_borrowed(String(SaDockerIds.FILTERS)):
        return false
    close()
    return true


## What Open does with the picked *key*: the Filter menu row's own invoke, and
## then a docker out on a summon goes back, [method _go_back]. A key nobody
## registered opens nothing and leaves the docker where it is.
func _open_filter(key: StringName) -> void:
    if browser.registry.invoke(key):
        _go_back(_manager_in(get_tree() if is_inside_tree() else null))


## Sends the docker back to where its summon found it when it is out on one,
## through the summon of *dockers*, the `MainDockers` holding it, and answers
## whether it went. That send back is the first thing its own close does, and
## the place, the size and the visibility the summon found come back with it,
## while nothing is written to the layout. A docker in its place is not out,
## and stays.
func _go_back(dockers: Object) -> bool:
    var store := dockers.get("layout_store") as DockerLayoutStore if dockers != null else null
    var lender := (dockers as Node).get_node_or_null(^"DockerSummon") as DockerSummon if dockers is Node else null
    var section := String(SaDockerIds.FILTERS)
    if store == null or lender == null or not store.is_borrowed(section):
        return false
    lender.send_back(section)
    return true


## Closes the docker the way its own close does, through `close_requested`,
## which `MainDockers` answers by sending a summoned docker back, hiding it and
## clearing its tick. A docker no manager listens to is hidden here.
func close() -> void:
    close_requested.emit()
    if visible:
        hide()


## What the docker is, for the state dump: the browser's own dump, whether the
## docker is open, what its parameters part shows, and where it and its pieces
## stand.
func describe() -> Dictionary:
    var out := browser.describe()
    out["open"] = visible
    out["parameters"] = parameters.describe()
    out["looks"] = looks.describe()
    out["layout"] = describe_layout()
    return out


## The docker's rectangle and floors beside what each piece of the browser asks
## for and where its buttons are, under the keys the window's dump had.
func describe_layout() -> Dictionary:
    var out := browser.describe_layout()
    var needed := _column.get_combined_minimum_size()
    out["window"] = [position.x, position.y, size.x, size.y]
    out["logical_min_size"] = [logical_min_size.x, logical_min_size.y]
    out["content_minimum"] = [int(needed.x), int(needed.y)]
    out["content_height"] = column_content_height(self)
    return out


## Drives the Filters docker: `{"filter_browser": "open"}` summons it with the
## lock on, at its own place, `"close"` closes it, `"invoke"` presses Open,
## `"describe"` prints what it says it is, and `{"filter_browser": {"search":
## "blur"}}` and `{"filter_browser": {"select": "sara-base-modules.box_blur"}}` type in
## the field and pick a row the way a hand would. `{"filter_browser": {"look":
## "Warm"}}` picks a row of the Looks part the same way, so a click on `LookAdd`,
## `LookRename` or `LookDelete` after it works on that look.
##
## The step and its words are the window's, so a scenario written for the window
## drives the docker. A step of its own because the rows share one name a click
## could aim by. "open" is a locked summon so it stays up while a scenario
## moves the pointer elsewhere, which an unlocked one would read as a leave.
static func capture(tree: SceneTree, spec: Variant) -> String:
    var docker := find_in(tree)
    if docker == null:
        return "SaCapture: no filter browser installed"
    var options: Dictionary = spec if spec is Dictionary else {"do": String(spec)}
    if options.has("search"):
        docker.browser.search_for(String(options["search"]))
        return "SaCapture: searched '%s', %s" % [options["search"], JSON.stringify(docker.describe())]
    if options.has("select"):
        var key := StringName(String(options["select"]))
        if not docker.browser.pick(key):
            return "SaCapture: the browser is not offering '%s'" % key
        return "SaCapture: picked '%s', %s" % [key, JSON.stringify(docker.describe())]
    if options.has("look"):
        var look_name := String(options["look"])
        if not docker.looks.pick(look_name):
            return "SaCapture: the Looks part holds no '%s', %s" % [look_name, JSON.stringify(docker.looks.describe())]
        return "SaCapture: picked the look '%s', %s" % [look_name, JSON.stringify(docker.looks.describe())]
    match String(options.get("do", "")):
        "open":
            if docker.visible:
                docker.browser.refresh()
            else:
                summon(tree, true, Vector2i(Vector2(docker.position) + Vector2(docker.size) * 0.5))
            return "SaCapture: the filter browser opened, %s" % JSON.stringify(docker.describe())
        "close":
            docker.close()
            return "SaCapture: the filter browser closed"
        "invoke":
            docker.browser.open_selected()
            return "SaCapture: opened '%s' from the browser" % docker.browser.selected
        "describe":
            return "SaCapture: the filter browser is %s" % JSON.stringify(docker.describe())
    return "SaCapture: no filter browser command %s" % JSON.stringify(spec)
