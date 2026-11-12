## Whether a stored preset names a file this build does not have.
##
## A profile written by an older build can hold presets whose script lives in a
## module the release does not carry. Loading one prints an engine error for
## every resource it names, so the store asks here first, by reading the
## `.tres` header as text. The file is never touched, because the module may come
## back.
class_name SaPresetMissingModule
extends RefCounted

## The preset files already warned about this run, so a profile holding such a
## preset says so once and not on every listing.
static var _warned: Dictionary[String, bool] = {}


## True when the `.tres` at *path*, the preset *preset_name*, names a missing
## file, after one warning line for the run.
static func skips(path: String, preset_name: String) -> bool:
    var missing := first_missing_resource(path)
    if missing.is_empty():
        return false
    if not _warned.has(path):
        _warned[path] = true
        push_warning('Preset "%s" is skipped, its module file %s is missing' % [preset_name, missing])
    return true


## The first `res://` path an `ext_resource` line of the `.tres` at *path* names
## that is not there, or an empty string when all are there. Only the header
## is read, and a path whose uid still resolves counts as there.
static func first_missing_resource(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var path_pattern := RegEx.create_from_string('path="(res://[^"]+)"')
    var uid_pattern := RegEx.create_from_string('uid="(uid://[^"]+)"')
    while not file.eof_reached():
        var line := file.get_line()
        if line.begins_with("[ext_resource"):
            var hit := path_pattern.search(line)
            if hit != null and not ResourceLoader.exists(hit.get_string(1)):
                var uid_hit := uid_pattern.search(line)
                if uid_hit != null and ResourceUID.has_id(ResourceUID.text_to_id(uid_hit.get_string(1))):
                    continue
                return hit.get_string(1)
        elif line.begins_with("[resource]") or line.begins_with("[sub_resource"):
            break
    return ""
