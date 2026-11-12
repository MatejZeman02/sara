## The sizes a docker keeps per variant of itself, the Tool Options docker's per
## tool above all, in the layout file the store is bound to.
##
## A variant's size is stored under its own key inside the docker's section,
## [constant VARIANT_PREFIX] and the variant's name. The plain `size` key is
## untouched and is still what a restore reads, so an older build reads the
## file it always read and an unsized variant falls back to it. What a variant
## is belongs to the window: `tool_options_docker.gd`.
##
## Its own class rather than a part of `DockerLayoutStore`, because the table
## below is read and written apart from the rest of the layout, by its own
## write rather than the store's `save`, which takes every docker's position
## too. Bound to one file, so the store builds a new one when its path changes
## rather than telling this one where it went.
class_name SaDockerVariantSizes
extends RefCounted

## The prefix one variant of a window's size is stored under, inside that
## window's own section.
const VARIANT_PREFIX: String = "size_for_"

## How many times the methods below opened the layout file, and how many times
## they wrote it. A switch that changed no size adds to neither, which is what
## `ui/layout/tests/test_the_tool_options_docker_follows_a_switch.gd` counts.
var loads: int = 0
var saves: int = 0

## The layout file the sizes live in, the store's `path` when it built this.
var _path: String

## Section -> variant -> the size stored for it, in the file's units: every
## variant size the layout file holds, read once. A tool switch asks for one and
## files another, and this spares each of them opening and parsing the whole
## file, and writing it back when nothing had moved. The file is where they
## live, and this is what it said the last time it was read or written.
var _sizes: Dictionary = {}

## Whether `_sizes` has been read since the file last changed under it.
var _read: bool = false


func _init(file_path: String) -> void:
    _path = file_path


## Files *win*'s size now as the size for *variant* of it, under *section*.
##
## **Only a size that moved is written.** A window at the size a restore of the
## variant gives it is at the stored size, even when the scale does not divide it
## back to the same number: at 1.25 a stored 397 opens at 496, which divides back
## to 396, and comparing the numbers alone wrote a pixel less on every switch.
func save(win: Window, section: String, variant: String) -> void:
    if win == null or section.is_empty() or variant.is_empty():
        return
    var live := SaDockerStoredEntry.floored(win, win.size)
    var scale := SaUI.window_scale(win)
    var normalized := Vector2i(Vector2(live) / scale)
    var sizes: Dictionary = _table().get(section, {})
    if sizes.has(variant):
        var stored: Vector2i = sizes[variant]
        if stored == normalized or SaDockerStoredEntry.floored(win, Vector2i(Vector2(stored) * scale)) == live:
            return
    var cfg := ConfigFile.new()
    loads += 1
    cfg.load(_path)
    cfg.set_value(section, VARIANT_PREFIX + variant, normalized)
    saves += 1
    if cfg.save(_path) != OK:
        push_error("Failed to save the %s size of %s" % [variant, section])
        return
    sizes[variant] = normalized
    _sizes[section] = sizes


## *fallback*, or the size stored for the variant *win* says it is showing. Here
## rather than in the window, because a restore is the store's to make and a
## window that had to correct one afterwards would flicker through the wrong
## size on every launch.
func restored(win: Window, section: String, fallback: Vector2i) -> Vector2i:
    if not win.has_method("layout_variant"):
        return fallback
    var wanted := size_of(win, section, String(win.call("layout_variant")))
    return wanted if wanted != Vector2i() else fallback


## The size stored for *variant* of *win* in this run's pixels, or `Vector2i()`
## for one nobody has sized, scaled and floored the way the plain size is.
func size_of(win: Window, section: String, variant: String) -> Vector2i:
    if win == null or section.is_empty() or variant.is_empty():
        return Vector2i()
    var sizes: Dictionary = _table().get(section, {})
    var stored: Vector2i = sizes.get(variant, Vector2i())
    if stored == Vector2i():
        return Vector2i()
    return SaDockerStoredEntry.floored(win, Vector2i(Vector2(stored) * SaUI.window_scale(win)))


## Drops the sizes read from the file, because something other than
## [method save] has just written it: a preset loaded into it, a restore that
## moved its sections.
func forget() -> void:
    _sizes = {}
    _read = false


## Every variant size the layout file holds, read from it the first time it is
## asked for after the file changed under this table, and from memory after.
func _table() -> Dictionary:
    if _read:
        return _sizes
    _read = true
    _sizes = {}
    var cfg := ConfigFile.new()
    loads += 1
    if cfg.load(_path) != OK:
        return _sizes
    for section in cfg.get_sections():
        for key in cfg.get_section_keys(section):
            var stored: Variant = cfg.get_value(section, key)
            if not key.begins_with(VARIANT_PREFIX) or not stored is Vector2i:
                continue
            var sizes: Dictionary = _sizes.get(section, {})
            sizes[key.trim_prefix(VARIANT_PREFIX)] = stored
            _sizes[section] = sizes
    return _sizes
