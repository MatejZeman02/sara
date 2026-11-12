## The colour store behind the pair, the swatches and the recent list.
##
## F5 items 7 and 8. The foreground goes out as the `color_picked` every tool
## already listens to, the background as its own signal, and the store keeps
## up with a pick announced by someone else without announcing it twice.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_colors.cfg")


func _store() -> SaColorStore:
    var store := SaColorStore.new()
    store.path = scratch_path
    return store


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func after_each() -> void:
    _remove(scratch_path)


func test_the_pair_starts_black_over_white_and_swaps_and_resets() -> void:
    var store := _store()
    assert_eq(store.foreground, Color.BLACK, "Black foreground")
    assert_eq(store.background, Color.WHITE, "over white")
    store.foreground = Color.RED
    store.swap()
    assert_eq(store.foreground, Color.WHITE, "X puts the background in front")
    assert_eq(store.background, Color.RED, "and the foreground behind")
    store.reset()
    assert_eq(store.foreground, Color.BLACK, "D is black")
    assert_eq(store.background, Color.WHITE, "over white again")
    store.free()


func test_both_colours_announce_on_the_bus_once_per_change() -> void:
    var store := _store()
    var picked: Array = []
    var backgrounds: Array = []
    var on_picked := func(color: Color) -> void: picked.append(color)
    var on_background := func(color: Color) -> void: backgrounds.append(color)
    EventBus.color_picked.connect(on_picked)
    EventBus.background_color_changed.connect(on_background)

    store.foreground = Color.RED
    store.foreground = Color.RED
    store.background = Color.BLUE
    store.swap()

    EventBus.color_picked.disconnect(on_picked)
    EventBus.background_color_changed.disconnect(on_background)
    assert_eq(picked, [Color.RED, Color.BLUE], "The foreground announced twice: the set, and the swap. Not the repeat.")
    assert_eq(backgrounds, [Color.BLUE, Color.RED], "The background likewise")
    store.free()


## The eyedropper emits `color_picked` itself. The store has to follow it, and
## must not echo it, or every pick would be announced twice.
func test_a_pick_announced_by_someone_else_is_followed_without_an_echo() -> void:
    var store := _store()
    store._ready()
    var picked: Array = []
    var on_picked := func(color: Color) -> void: picked.append(color)
    EventBus.color_picked.connect(on_picked)
    EventBus.color_picked.emit(Color.GREEN)
    EventBus.color_picked.disconnect(on_picked)
    assert_eq(store.foreground, Color.GREEN, "The store followed the pick")
    assert_eq(picked, [Color.GREEN], "and announced nothing of its own")
    store.free()


func test_the_recent_list_is_what_was_used_newest_first_once_each_and_capped() -> void:
    var store := _store()
    for i in SaColorStore.MAX_RECENT + 3:
        store.note_used(Color(float(i) / 20.0, 0.0, 0.0))
    store.note_used(Color(0.25, 0.0, 0.0))
    assert_eq(store.recent.size(), SaColorStore.MAX_RECENT, "Capped")
    assert_true(store.recent[0].is_equal_approx(Color(0.25, 0.0, 0.0)), "The colour used again is first")
    var count := 0
    for color: Color in store.recent:
        if color.is_equal_approx(Color(0.25, 0.0, 0.0)):
            count += 1
    assert_eq(count, 1, "and once")
    store.free()


func test_swatches_are_kept_in_order_and_removed_by_index() -> void:
    var store := _store()
    store.add_swatch(Color.RED)
    store.add_swatch(Color.GREEN)
    store.add_swatch(Color.BLUE)
    store.remove_swatch(1)
    assert_eq(store.swatches, [Color.RED, Color.BLUE], "Green went")
    store.remove_swatch(7)
    assert_eq(store.swatches.size(), 2, "An index past the end is ignored")
    store.free()


func test_the_pair_and_both_lists_survive_a_reload() -> void:
    var store := _store()
    store.foreground = Color.RED
    store.background = Color.BLUE
    store.add_swatch(Color.GREEN)
    store.note_used(Color.YELLOW)
    store.save()
    store.free()

    var again := _store()
    again.load_from(scratch_path)
    assert_eq(again.foreground, Color.RED, "The foreground came back")
    assert_eq(again.background, Color.BLUE, "and the background")
    assert_eq(again.swatches, [Color.GREEN], "and the swatches")
    assert_eq(again.recent, [Color.YELLOW], "and the recent list")
    again.free()
