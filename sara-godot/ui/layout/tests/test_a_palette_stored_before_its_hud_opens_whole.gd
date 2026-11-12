## A profile that stored the pop-up palette at the old default
## opens it whole.
##
## The palette grew by its brush HUD, 360 by 384 to 360 by 448, and a profile
## that already stored 384 would stay at 384, so its ring would stand 64
## smaller under the same HUD. A painter who never sized the palette did not
## choose 384, the old default did. `DockerLayoutStore.restore_all` reads that
## one size as the size the palette opens at now, once, and writes it back.
## Any other stored size is the painter's and is kept, and so is 384 in a file
## a save of this build wrote, which says so under `META_HUD`.
##
## The docker is never added to a tree, since a window in a headless tree hangs
## the run, and the store reads it as `MainDockers` hands it. The running app's check
## is `scenarios/a-profile-that-stored-the-palette-before-its-hud-opens-it-whole.json`.
extends "res://tests/test_framework.gd"

var _file: String = SaDataRoot.path("test_u5_palette_before_its_hud.cfg")
var _palette: PaletteDocker = null
var _store: DockerLayoutStore = null


func before_each() -> void:
    DirAccess.remove_absolute(_file)
    _palette = PaletteDocker.new()
    _palette.visible = false
    var table: Array = [{"id": String(SaDockerIds.PALETTE), "name": "Pop-up Palette", "node": _palette}]
    _store = DockerLayoutStore.new()
    _store.path = _file
    _store.dockers_provider = func() -> Array: return table


func after_each() -> void:
    _store.free()
    _store = null
    _palette.free()
    _palette = null
    DirAccess.remove_absolute(_file)


## A layout file with the palette alone, at *size* in the file's units, with
## the mark a save of this build writes when *marked*.
func _store_palette_at(size: Vector2i, marked: bool = false) -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_EMBEDDED, SaSettings.embed_subwindows)
    if marked:
        cfg.set_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_HUD, true)
    var section := String(SaDockerIds.PALETTE)
    cfg.set_value(section, "position", Vector2i(780, 340))
    cfg.set_value(section, "size", size)
    cfg.set_value(section, "visible", false)
    assert_eq(cfg.save(_file), OK, "the stored layout is written")


## What the file says the palette's size is now.
func _stored_size() -> Vector2i:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(_file), OK, "the layout file reads")
    return cfg.get_value(String(SaDockerIds.PALETTE), "size", Vector2i())


## *size* in the file's units, as this run's pixels for the palette.
func _shown(size: Vector2i) -> Vector2i:
    return Vector2i(Vector2(size) * SaUI.window_scale(_palette))


func test_the_old_default_is_kept_as_the_old_default_only() -> void:
    assert_eq(DockerLayoutStore.PALETTE_BEFORE_HUD, Vector2i(360, 384), "the size every profile stored before the HUD")
    assert_eq(PaletteDocker.DEFAULT_SIZE, Vector2i(360, 448), "and the size the palette opens at now")


func test_a_palette_stored_at_the_old_default_opens_at_the_new() -> void:
    _store_palette_at(Vector2i(360, 384))
    _store.restore_all()
    assert_eq(_palette.size, _shown(Vector2i(360, 448)), "a stored 360 by 384 opens at 360 by 448")
    assert_eq(_store.value_for(String(SaDockerIds.PALETTE), "size", Vector2i()), _palette.size, "and the store holds it there")
    assert_eq(_stored_size(), Vector2i(360, 448), "and the file is written so")


func test_the_old_default_is_read_once() -> void:
    _store_palette_at(Vector2i(360, 384))
    _store.restore_all()
    var stamp := FileAccess.get_modified_time(_file)
    var text := FileAccess.get_file_as_string(_file)
    _store.restore_all()
    assert_eq(FileAccess.get_modified_time(_file), stamp, "a second load finds nothing to move and writes nothing")
    assert_eq(FileAccess.get_file_as_string(_file), text, "and the file reads as the first load left it")


func test_a_size_the_painter_chose_is_kept() -> void:
    _store_palette_at(Vector2i(360, 500))
    var text := FileAccess.get_file_as_string(_file)
    _store.restore_all()
    assert_eq(_palette.size, _shown(Vector2i(360, 500)), "a stored 360 by 500 opens at 360 by 500")
    assert_eq(_stored_size(), Vector2i(360, 500), "and the file keeps it")
    assert_eq(FileAccess.get_file_as_string(_file), text, "untouched, since there was nothing to move")


## The other side of once: a painter who sizes the palette to 384 after the
## HUD came saves a file that says so, and that 384 is theirs.
func test_the_old_default_saved_by_this_build_is_the_painters() -> void:
    _store_palette_at(Vector2i(360, 384), true)
    _store.restore_all()
    assert_eq(_palette.size, _shown(Vector2i(360, 384)), "a 384 this build wrote opens at 384")
    assert_eq(_stored_size(), Vector2i(360, 384), "and the file keeps it")


func test_a_save_marks_the_file_as_written_after_the_hud() -> void:
    _store_palette_at(Vector2i(360, 500))
    _store.restore_all()
    _store.save(true)
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(_file), OK, "the saved layout reads")
    var marked := bool(cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_HUD, false))
    assert_true(marked, "a save says it knows the HUD")
