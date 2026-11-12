## The corner notice is never put under a docker.
##
## With subwindows off, Help > Connect an Agent put its notice
## along the bottom of the main window, and the Reference and Layers dockers
## stood over both ends of it, so only its middle could be read. A docker let out
## is a window of the operating system and stands over anything the main window
## draws, so the notice has to be drawn where none of them is.
##
## **What a suite can and cannot reach.** The fault is about native windows, and a
## suite cannot build one: adding a `Window` to the tree while the root viewport
## does not embed it maps a real OS window and stalls the run until the watchdog
## fires (`render/cursor/tests/test_a_window_of_its_own.gd` says so at its own
## fixture). What is held here is the placement itself, which is one function of
## the rectangles standing over the host and does not care which kind of window
## they are, and the whole notice with embedded windows in the places the default
## layout gives the dockers. The native half is
## `scenarios/the-corner-notice-stands-clear-of-the-let-out-dockers.json`.
##
## **What the case that bites stands on.** It does not lean on the default
## layout to put a docker over the bottom centre, because the layout's Layers
## foot can end above the notice's bottom row. It stands two dockers of its own
## over the row's ends, and the layout's columns are only what else is in the way.
extends "res://tests/test_framework.gd"

## The record of the default layout, and the window it was taken on. Read from
## the file the app ships rather than copied, so a layout that moves a docker
## moves this too. The record is a fresh profile's state dump, which
## `scripts/scenario_dockers.py --write-layout` writes from a capture whose
## window is 1920 by 1048, so its fractions are of that window. Reading it as
## 1080 would put every docker three per cent higher than the app does.
const LAYOUT_PATH := "res://scripts/default_docker_layout.json"
const LAYOUT_WINDOW := Vector2(1920.0, 1048.0)

## A sentence as long as the first message a client is offered.
const LONG_LINE := "Copied a first message for an agent: Sara is listening, and the address it says is on the clipboard too."

var _previous_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    SaProblems.announce = false
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "NoticeClearTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = true
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


## The rectangles of the dockers the default layout opens, as fractions of the
## window it was drawn for.
func _default_layout_fractions() -> Array[Rect2]:
    var found: Array[Rect2] = []
    var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
    assert_not_null(file, "the default layout is readable")
    if file == null:
        return found
    var layout: Dictionary = JSON.parse_string(file.get_as_text())
    for id: String in layout:
        var entry: Dictionary = layout[id]
        if not bool(entry.get("open", false)):
            continue
        var rect: Array = entry["rect"]
        found.append(
            Rect2(
                Vector2(float(rect[0]), float(rect[1])) / LAYOUT_WINDOW, Vector2(float(rect[2]), float(rect[3])) / LAYOUT_WINDOW
            )
        )
    return found


static func _scaled(fractions: Array[Rect2], host: Vector2) -> Array[Rect2]:
    var found: Array[Rect2] = []
    for fraction in fractions:
        found.append(Rect2(fraction.position * host, fraction.size * host))
    return found


static func _touches_any(slot: Rect2, covering: Array[Rect2]) -> bool:
    for rect in covering:
        if slot.intersects(rect):
            return true
    return false


## With nothing over the host the line goes where it always went, so a painter
## whose dockers are put away sees nothing change.
func test_an_empty_host_keeps_the_bottom_centre() -> void:
    var slot := SaClearSlot.clear_slot(Vector2(1000.0, 600.0), Vector2(300.0, 40.0), [], 24.0, 8.0)

    assert_eq(slot, Rect2(350.0, 536.0, 300.0, 40.0), "centred and a margin above the bottom edge")


## A host that has not been laid out yet is 0 by 0 for the notice, which is what
## it is at boot, and the answer there has to stay the old formula's.
func test_an_unsized_host_keeps_the_old_formula() -> void:
    var slot := SaClearSlot.clear_slot(Vector2.ZERO, Vector2(300.0, 40.0), [], 24.0, 8.0)

    assert_eq(slot.position, Vector2(-150.0, -64.0), "the same place the notice was put before the search")


## The fault itself, in numbers: a docker at each bottom corner and a line wider
## than what is left between them. The line climbs to the first row that has room
## rather than running under either.
func test_a_line_wider_than_the_bottom_gap_climbs_above_the_dockers() -> void:
    var host := Vector2(1000.0, 600.0)
    var want := Vector2(500.0, 40.0)
    var covering: Array[Rect2] = [Rect2(0.0, 400.0, 300.0, 200.0), Rect2(700.0, 380.0, 300.0, 220.0)]

    var slot := SaClearSlot.clear_slot(host, want, covering, 24.0, 8.0)

    assert_false(_touches_any(slot, covering), "no docker touches the line")
    assert_true(slot.position.y < 536.0, "and it is higher than the bottom centre it wanted")
    assert_true(slot.position.y >= host.y * 0.5, "though not past the middle of the window")
    assert_true(Rect2(Vector2.ZERO, host).encloses(slot), "and inside the window")


## A line that fits between two dockers stays on the bottom row and moves along
## it only as far as the dockers make it, toward the centre.
func test_a_line_that_fits_between_two_dockers_stays_on_the_bottom_row() -> void:
    var host := Vector2(1000.0, 600.0)
    var want := Vector2(300.0, 40.0)
    var covering: Array[Rect2] = [Rect2(0.0, 400.0, 400.0, 200.0)]

    var slot := SaClearSlot.clear_slot(host, want, covering, 24.0, 8.0)

    assert_eq(slot.position.y, 536.0, "the bottom row")
    assert_almost_eq(slot.position.x, 408.0, 1e-3, "beside the docker with the gap kept")
    assert_false(_touches_any(slot, covering), "clear of it")


## When the windows leave no place at all the answer is the bottom centre, the
## old one, and never a position outside the host.
func test_a_host_with_no_room_falls_back_to_the_bottom_centre() -> void:
    var host := Vector2(1000.0, 600.0)
    var covering: Array[Rect2] = [Rect2(Vector2.ZERO, host)]

    var slot := SaClearSlot.clear_slot(host, Vector2(300.0, 40.0), covering, 24.0, 8.0)

    assert_eq(slot, Rect2(350.0, 536.0, 300.0, 40.0), "the old place")


## How wide a line may be made before it has nowhere to go: the widest free
## stretch of any row it is tried in, and nothing for a host with no room.
func test_the_widest_room_is_the_widest_stretch_of_any_row() -> void:
    var host := Vector2(1000.0, 600.0)
    var covering: Array[Rect2] = [Rect2(0.0, 400.0, 300.0, 200.0), Rect2(700.0, 400.0, 300.0, 200.0)]

    var empty := SaClearSlot.widest_room(host, 40.0, [], 24.0, 8.0)
    assert_almost_eq(empty, 984.0, 1e-3, "an empty host is all room, less the gap at each edge")
    var above := SaClearSlot.widest_room(host, 40.0, covering, 24.0, 8.0)
    assert_almost_eq(above, 984.0, 1e-3, "and so are the rows above the dockers, the highest a line climbs to")
    var everywhere: Array[Rect2] = [Rect2(Vector2.ZERO, host)]
    assert_eq(SaClearSlot.widest_room(host, 40.0, everywhere, 24.0, 8.0), 0.0, "a host covered end to end has none")
    assert_null(SaClearSlot.find_slot(host, Vector2(300.0, 40.0), everywhere, 24.0, 8.0), "and no slot")


## The default layout, at three window sizes, with the line as long as a client's
## message. Whatever the size, the rectangles the layout gives the dockers do not
## touch the line, and it stays inside the window.
func test_the_default_layout_never_stands_over_the_line() -> void:
    var fractions := _default_layout_fractions()
    assert_true(fractions.size() >= 4, "the layout opens several dockers")
    for host: Vector2 in [Vector2(1920.0, 1080.0), Vector2(1600.0, 900.0), Vector2(1366.0, 768.0)]:
        var covering := _scaled(fractions, host)
        var want := Vector2(host.x * 0.42, 44.0)
        var home := Rect2(Vector2((host.x - want.x) * 0.5, host.y - want.y - 24.0), want)
        var slot := SaClearSlot.clear_slot(host, want, covering, 24.0, 8.0)

        assert_false(_touches_any(slot, covering), "at %s no docker stands over the line" % [host])
        assert_true(Rect2(Vector2.ZERO, host).encloses(slot), "at %s the line is inside the window" % [host])
        assert_true(slot.position.y <= home.position.y, "at %s it is never lower than the bottom row" % [host])


## The notice itself, with embedded windows where the default layout puts the
## dockers and two more over the ends of the bottom row, the way the Reference and the Layers
## stood in the fault. The line is grown until the bottom centre
## would run under them, which is the fault, and then it has to be somewhere
## else. The two are the case's own, so it bites whatever the layout's columns
## do at their feet.
func test_the_shown_notice_is_clear_of_every_window() -> void:
    SaMessage.install(_host)
    var notice := SaMessage.notice_widget()
    var tree := Engine.get_main_loop() as SceneTree
    var host := tree.root.get_visible_rect().size
    var ends: Array[Rect2] = [
        Rect2(0.0, host.y * 0.8, host.x * 0.25, host.y * 0.2), Rect2(host.x * 0.75, host.y * 0.8, host.x * 0.25, host.y * 0.2)
    ]
    var covering := _scaled(_default_layout_fractions(), host)
    covering.append_array(ends)
    for rect in covering:
        _stand_a_docker_at(rect)

    # One short word at a time until the bottom centre first runs under a docker,
    # which is the widest line that still has a free place somewhere in the row.
    var text := LONG_LINE
    var home := Rect2()
    for _round in 200:
        notice.label.text = text
        var wanted := notice.panel.get_combined_minimum_size()
        home = Rect2(
            Vector2((notice.size.x - wanted.x) * 0.5, notice.size.y - wanted.y - float(SaUI.px(SaNotice.BOTTOM_MARGIN))), wanted
        )
        if _touches_any(home, covering):
            break
        text += " Sara"
    assert_true(_touches_any(home, ends), "the bottom centre runs under the two at the ends, so the test bites")

    notice.show_line(text)
    notice.panel.size = notice.panel.get_combined_minimum_size()
    notice.show_line(text)

    var slot := Rect2(notice.panel.position, notice.panel.size)
    assert_false(_touches_any(slot, covering), "and the notice is not")
    assert_true(Rect2(Vector2.ZERO, notice.size).encloses(slot), "and it is inside the window")
    assert_true(notice.showing(), "while it is up")


## A line wider than every stretch there is: two columns leave the middle of the
## window 40 per cent wide and the line is longer than that. It is wrapped into
## the stretch rather than left running under either column.
func test_a_line_wider_than_every_stretch_is_wrapped_into_the_widest() -> void:
    SaMessage.install(_host)
    var notice := SaMessage.notice_widget()
    var tree := Engine.get_main_loop() as SceneTree
    var host := tree.root.get_visible_rect().size
    var left := Rect2(0.0, 0.0, host.x * 0.3, host.y)
    var right := Rect2(host.x * 0.7, 0.0, host.x * 0.3, host.y)
    _stand_a_docker_at(left)
    _stand_a_docker_at(right)
    var covering: Array[Rect2] = [left, right]

    var text := LONG_LINE
    for _round in 20:
        notice.label.text = text
        if notice.panel.get_combined_minimum_size().x > host.x * 0.5:
            break
        text += " " + LONG_LINE
    notice.show_line(text)

    assert_eq(notice.label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the line is wrapped")
    assert_true(notice.panel.size.x <= host.x * 0.4, "to no more than the middle stretch")
    assert_false(_touches_any(Rect2(notice.panel.position, notice.panel.size), covering), "and stands clear of both columns")

    notice.show_line("Short.")
    assert_eq(notice.label.autowrap_mode, TextServer.AUTOWRAP_OFF, "a short line after it is one line again")
    assert_almost_eq(notice.label.custom_minimum_size.x, 0.0, 1e-3, "with no width held over from the wrapped one")


## The same notice with the dockers gone goes back to the bottom centre.
func test_the_notice_returns_to_the_bottom_centre_when_the_dockers_go() -> void:
    SaMessage.install(_host)
    var notice := SaMessage.notice_widget()
    var tree := Engine.get_main_loop() as SceneTree
    var host := tree.root.get_visible_rect().size
    var docker := _stand_a_docker_at(Rect2(0.0, host.y - 200.0, host.x * 0.45, 200.0))

    notice.show_line("Nothing to read here.")
    notice.panel.size = notice.panel.get_combined_minimum_size()
    notice.show_line("Nothing to read here.")
    var beside := notice.panel.position
    docker.hide()
    notice.show_line("Nothing to read here.")

    var bottom := notice.size.y - notice.panel.size.y - float(SaUI.px(SaNotice.BOTTOM_MARGIN))
    assert_almost_eq(notice.panel.position.y, bottom, 1e-3, "back on the bottom row")
    assert_almost_eq(notice.panel.position.x, (notice.size.x - notice.panel.size.x) * 0.5, 1e-3, "and centred")
    assert_true(beside.x >= host.x * 0.45, "where the docker had pushed it clear of the docker")


func _stand_a_docker_at(rect: Rect2) -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = Vector2i(rect.position)
    docker.size = Vector2i(rect.size)
    _host.add_child(docker)
    docker.show()
    return docker
