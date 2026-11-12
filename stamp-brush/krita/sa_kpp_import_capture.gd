## The door's `preset_import` step: imports a `.kpp`, a folder or a `.bundle`
## into the painter's presets and writes what each preset said where a
## reviewer reads it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `{"preset_import": "res://.../sara-fixtures.bundle"}`, the path as the
## reader takes it. Reached by the `preset_import` role the module registers,
## the same door the docker's Import button takes, so the step and the button
## cannot import differently. Every result's console line is printed and
## appended to `import.txt`, and the presets group is refreshed so the bar
## and the docker list what arrived.
class_name SaKppImportCapture
extends RefCounted

const REPORT_FILE: String = "import.txt"


## *_tree* goes unread, the presets group being asked through `SaPresetsInHand`,
## and stays because the role is called with it. *out_dir* is the run's folder,
## passed in rather than read off whatever node the caller has to hand, and
## empty for a caller with no folder, which the presets page is when no capture
## is running. *replace* is whether a preset already held under the same name is
## written over, on for the door's step and off for the page's first press,
## which then offers the replacing.
static func capture(_tree: SceneTree, out_dir: String, path: String, replace: bool = true) -> String:
    var results := _import(path, replace)
    var lines := _describe_all(results, out_dir)
    return "SaCapture: preset_import %s from %s\n%s" % [_tally(results), path, "\n".join(lines)]


## What the presets page asks for: the same import as [method capture], with
## the lines and the three counts told apart from the results themselves. The
## page used to count by searching the lines for English phrases, which a
## sentence reworded or translated would have silently miscounted. The lines
## are still the importer's English, the reasons inside them being phrases of
## its own that no catalogue holds yet. `imported` counts a bundle that stored
## only tips as imported, as the page always has.
static func report(_tree: SceneTree, out_dir: String, path: String, replace: bool = false) -> Dictionary:
    var results := _import(path, replace)
    var counts := {"imported": 0, "refused": 0, "kept": 0}
    for result: Dictionary in results:
        if not String(result.get("error", "")).is_empty():
            counts["refused"] += 1
        elif result.has("kept"):
            counts["kept"] += 1
        else:
            counts["imported"] += 1
    counts["lines"] = _describe_all(results, out_dir)
    return counts


static func _import(path: String, replace: bool) -> Array[Dictionary]:
    var importer := func(store: SaPresetStore, template: Resource) -> Array[Dictionary]:
        return SaKppImport.import_path(path, store, template, replace)
    var results: Array[Dictionary] = []
    if SaPresetsInHand.has_group():
        results.assign(SaPresetsInHand.import_through(importer))
    else:
        results.assign(importer.call(SaPresetStore.new(), null))
    return results


## One line a result, each also appended to the run's report file.
static func _describe_all(results: Array[Dictionary], out_dir: String) -> PackedStringArray:
    var lines := PackedStringArray()
    for result: Dictionary in results:
        lines.append(SaKppImport.describe(result))
    for line in lines:
        _append_line(out_dir, line)
    return lines


## What the run amounts to, for the summary line. Presets, brush tips and
## refusals are three different things and the line names each that happened,
## rather than counting the answers, one per file read: a bundle that stored no
## preset at all would read "1 preset(s)" with the refusal on the line below it.
static func _tally(results: Array[Dictionary]) -> String:
    var stored := 0
    var tips := 0
    var refused := 0
    var kept := 0
    for result: Dictionary in results:
        if not String(result.get("error", "")).is_empty():
            refused += 1
        elif result.has("kept"):
            kept += 1
        elif int(result.get("tips", 0)) > 0:
            tips += int(result["tips"])
        else:
            stored += 1
    var parts := PackedStringArray(["%d preset(s)" % stored])
    if tips > 0:
        parts.append("%d brush tip(s)" % tips)
    if refused > 0:
        parts.append("%d refused" % refused)
    if kept > 0:
        parts.append("%d kept" % kept)
    return ", ".join(parts)


static func _append_line(dir: String, line: String) -> void:
    # An empty folder means there is nowhere to write, which is every import a
    # painter presses the button for. The folder was read off a node by name
    # once, and a node with no such member answered "<null>".
    if dir.is_empty():
        return
    var path := dir.path_join(REPORT_FILE)
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaKppImportCapture: could not write %s" % path)
        return
    file.seek_end()
    file.store_line(line)
