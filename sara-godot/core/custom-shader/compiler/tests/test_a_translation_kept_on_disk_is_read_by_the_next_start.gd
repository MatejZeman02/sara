## The dialect's translations kept between starts: a warm start reads back what
## a cold one made, and a dialect that changed reads nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const TEXT := "#pragma kernel probe\nvoid probe() {}\n"
const GLSL := "#version 450\nvoid main() {}\n"

static var scratch: String = SaDataRoot.path("test_glsl_cache")


func before_each() -> void:
    _clear()


func after_each() -> void:
    _clear()


func _clear() -> void:
    var folder := ProjectSettings.globalize_path(scratch)
    for name: String in [SaGlslCache.CACHE_FILE, SaGlslCache.CACHE_FILE + ".partial"]:
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)


func test_a_kept_translation_is_read_by_a_second_cache_over_the_same_folder() -> void:
    var first := SaGlslCache.new(scratch, "dialect one")
    assert_eq(first.read(TEXT), "", "A cold start finds nothing")
    first.keep(TEXT, GLSL)
    first.write()
    var second := SaGlslCache.new(scratch, "dialect one")
    assert_eq(second.read(TEXT), GLSL, "and the next start reads what it made")
    assert_eq(second.read(TEXT + " "), "", "and only for the same text")


func test_a_changed_dialect_reads_nothing() -> void:
    var first := SaGlslCache.new(scratch, "dialect one")
    first.keep(TEXT, GLSL)
    first.write()
    assert_eq(SaGlslCache.new(scratch, "dialect two").read(TEXT), "", "A dialect that changed reads nothing")


func test_a_warm_start_writes_nothing() -> void:
    var first := SaGlslCache.new(scratch, "dialect one")
    first.keep(TEXT, GLSL)
    first.write()
    var path := ProjectSettings.globalize_path(scratch).path_join(SaGlslCache.CACHE_FILE)
    var written := FileAccess.get_modified_time(path)
    DirAccess.remove_absolute(path)
    var second := SaGlslCache.new(scratch, "dialect one")
    second.keep(TEXT, GLSL)
    second.write()
    assert_true(FileAccess.file_exists(path), "A translation the file did not hold is written")
    var third := SaGlslCache.new(scratch, "dialect one")
    assert_eq(third.read(TEXT), GLSL, "and read back")
    third.keep(TEXT, GLSL)
    DirAccess.remove_absolute(path)
    third.write()
    assert_false(FileAccess.file_exists(path), "and a start that made nothing new writes nothing")
    assert_true(written > 0, "the first write left a file")


func test_the_dialect_s_fingerprint_is_stable() -> void:
    assert_eq(SaGlslCache.dialect_fingerprint(), SaGlslCache.dialect_fingerprint(), "Two reads of one dialect agree")
    assert_eq(SaGlslCache.dialect_fingerprint().length(), 64, "and it is a SHA-256")
