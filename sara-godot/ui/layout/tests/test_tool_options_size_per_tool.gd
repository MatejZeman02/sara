## The Tool Options docker keeps a size for each tool.
##
## The size is saved for each tool separately, because some tools have fewer
## options, and the crop tool is the case: three rows sitting in
## a box the painter sized for the brush's twenty.
##
## The store keeps a size per variant of a window, and the docker says which
## variant it is showing. Both halves are read here across a save and a restore,
## because a size that survives a tool change and not a restart is half the
## job. `scenarios/the-tool-options-docker-keeps-a-size-per-tool.json` is the
## other half, on the assembled dockers.
extends "res://tests/test_framework.gd"

const StoreScript := preload("res://ui/layout/docker_layout_store.gd")

const SECTION := "ToolOptionsDocker"
const BRUSH := "brush"
const CROP := "crop"


## A window that answers `layout_variant` the way the docker does, and nothing
## else. A real `ToolOptionsDocker` builds twenty rows off a tool machine in
## `_init`, which is more than the store's half of this needs.
class VariantWindow:
    extends Window

    var variant: String = ""

    func layout_variant() -> String:
        return variant


func _store(where: String) -> DockerLayoutStore:
    var store := StoreScript.new()
    store.path = where
    return store


func _window(at: Vector2i, variant: String) -> VariantWindow:
    var window := VariantWindow.new()
    window.min_size = Vector2i(160, 120)
    window.size = at
    window.variant = variant
    return window


func after_each() -> void:
    DirAccess.remove_absolute(SaDataRoot.path("n6-layout.cfg"))


## Two tools, two sizes, and neither is the other's.
func test_two_tools_keep_two_sizes() -> void:
    var store := _store(SaDataRoot.path("n6-layout.cfg"))
    var window := _window(Vector2i(300, 396), BRUSH)

    store.save_variant_size(window, SECTION, BRUSH)
    window.size = Vector2i(300, 180)
    store.save_variant_size(window, SECTION, CROP)

    assert_eq(store.variant_size(window, SECTION, BRUSH), Vector2i(300, 396), "The brush's own size")
    assert_eq(store.variant_size(window, SECTION, CROP), Vector2i(300, 180), "and the crop tool's own")
    window.free()
    store.free()


## A tool nobody has sized answers nothing, which is what makes the caller fall
## back to the single size the file has always carried.
func test_a_tool_nobody_has_sized_answers_nothing() -> void:
    var store := _store(SaDataRoot.path("n6-layout.cfg"))
    var window := _window(Vector2i(300, 396), BRUSH)
    store.save_variant_size(window, SECTION, BRUSH)

    assert_eq(store.variant_size(window, SECTION, "gradient"), Vector2i(), "No size for a tool never sized")
    assert_eq(store.variant_size(window, "OtherDocker", BRUSH), Vector2i(), "and none under another docker")
    window.free()
    store.free()


## Written by one run and read by the next, which is the restart half of the
## note: a second store over the same file answers what the first wrote.
func test_the_sizes_survive_a_save_and_a_restore() -> void:
    var writer := _store(SaDataRoot.path("n6-layout.cfg"))
    var window := _window(Vector2i(320, 420), BRUSH)
    writer.save_variant_size(window, SECTION, BRUSH)
    window.size = Vector2i(320, 190)
    writer.save_variant_size(window, SECTION, CROP)
    writer.free()

    var reader := _store(SaDataRoot.path("n6-layout.cfg"))
    assert_eq(reader.variant_size(window, SECTION, BRUSH), Vector2i(320, 420), "The brush's size came back")
    assert_eq(reader.variant_size(window, SECTION, CROP), Vector2i(320, 190), "and the crop tool's did too")
    window.free()
    reader.free()


## The plain `size` key is what a build without this reads, and what a variant
## nobody has sized falls back to, so nothing about it may move.
func test_the_plain_size_key_is_untouched() -> void:
    var store := _store(SaDataRoot.path("n6-layout.cfg"))
    var window := _window(Vector2i(300, 396), BRUSH)
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, "size", Vector2i(300, 396))
    cfg.save(SaDataRoot.path("n6-layout.cfg"))

    store.save_variant_size(window, SECTION, CROP)

    var back := ConfigFile.new()
    assert_eq(back.load(SaDataRoot.path("n6-layout.cfg")), OK, "The file is still a file")
    assert_eq(back.get_value(SECTION, "size", Vector2i()), Vector2i(300, 396), "and the size it always had")
    assert_true(back.has_section_key(SECTION, "size_for_crop"), "with the tool's own key beside it")
    window.free()
    store.free()


## A restore prefers the variant the window says it is showing, which is what
## makes the size come back at launch rather than at the first tool change.
func test_a_restore_prefers_the_variant_the_window_names() -> void:
    var store := _store(SaDataRoot.path("n6-layout.cfg"))
    var window := _window(Vector2i(300, 396), CROP)
    window.size = Vector2i(300, 180)
    store.save_variant_size(window, SECTION, CROP)

    var restored: Vector2i = store._variants.restored(window, SECTION, Vector2i(300, 396))
    assert_eq(restored, Vector2i(300, 180), "The crop tool's size wins over the plain one")

    window.variant = "gradient"
    assert_eq(
        store._variants.restored(window, SECTION, Vector2i(300, 396)),
        Vector2i(300, 396),
        "and a tool nobody has sized gets the plain one"
    )
    window.free()
    store.free()


## A window that keeps no variant is restored exactly as it was before sizes were kept per tool.
func test_a_window_with_no_variant_is_untouched() -> void:
    var store := _store(SaDataRoot.path("n6-layout.cfg"))
    var plain := Window.new()
    plain.min_size = Vector2i(160, 120)

    assert_eq(store._variants.restored(plain, SECTION, Vector2i(300, 396)), Vector2i(300, 396), "The fallback, whole")
    plain.free()
    store.free()
