## Every file Sara reads straight from `res://` is in the build.
##
## The kernel prompt Modules > Copy the kernel prompt reads is a `.txt`, and
## a preset's `include_filter` has to name it, or the installed build cannot
## read it. The harness pen's two tables are the same. The dither's blue noise
## tile has a texture importer, so the pack would hold the imported `.ctex` and
## not the PNG whose bytes `SaDitherFilter.thresholds()` decodes, and
## Layer > Add kind > Adjustment Layer would raise a Problem dialog every time
## it listed the filters. The editor and the suites read the
## checkout's disk, so the gate saw none of it.
##
## This finds every such read rather than the three. It scans each script a
## build runs for a call that reads a file's bytes, follows the call's path
## through the script's own constants, locals, parameters and members, and
## holds each `res://` file it reaches to the rule the exporter keeps: a file
## with an import sidecar ships its bytes only with the `keep` importer and a
## filter that names it, and a file without one only when it is a type a pack
## carries under its own path or every preset's `include_filter` names it. The
## filters are matched the way `test_the_export_pack_leaves_scratch_out.gd`
## matches them, on the path with its `res://` prefix and without it.
extends "res://tests/test_framework.gd"

const PRESETS := "res://export_presets.cfg"

## The folders whose scripts no build runs, wherever they sit.
const SKIPPED_DIRS: Array[String] = ["tests", "scratch", "scenarios", ".godot"]

## The calls that read a file off the disk rather than through `load()`. The
## `load` of a `ConfigFile` or an `Image` is matched apart, on the names a
## script declares one under.
const CALLS: Array[String] = [
    "FileAccess.open(",
    "FileAccess.get_file_as_bytes(",
    "FileAccess.get_file_as_string(",
    "FileAccess.file_exists(",
    "Image.load_from_file(",
]

## The extensions a pack carries under their own path with no filter, read off
## the listing of a real pack. A `.gd` is packed as tokens beside a `.remap`,
## and a `.tscn` or a `.tres` is converted to binary under `.godot/exported`, so
## none of the three can be read raw in a build, and the `.res` the listing
## holds are those converted ones.
const PACKED_AS_THEY_ARE: Array[String] = ["json", "gdshader"]

## Files the scan has to reach, one per way a path is written, so a scan that
## stops seeing anything fails rather than passing on nothing.
const MUST_FIND: Array[String] = [
    # A constant of the script's own.
    "res://core/custom-shader/kernel_prompt.txt",
    "res://core/custom-shader/gmacs_names.json",
    # A local joined to a constant that names a file beside the script.
    "res://modules/sara-base-modules/base/usual/dither_blue_noise.png",
    # A member set from a parameter whose default is a constant.
    "res://step_catalogue.json",
    # Another class's constant.
    "res://docker_layout_default.cfg",
]

## Every read the scan found, filled by the first suite that asks.
var _found: Array[Dictionary] = []


func test_the_scan_reaches_every_way_a_path_is_written() -> void:
    var reached := {}
    for read: Dictionary in _reads():
        reached[read["file"]] = true
    for wanted: String in MUST_FIND:
        assert_true(reached.has(wanted), "the scan reaches %s, found %s" % [wanted, reached.keys()])


func test_every_raw_read_of_a_res_file_ships_in_every_preset() -> void:
    var config := ConfigFile.new()
    assert_eq(config.load(PRESETS), OK, "the export presets file loads")
    var sections := _presets(config)
    assert_true(sections.size() > 0, "export_presets.cfg declares at least one preset")
    for read: Dictionary in _reads():
        var file: String = read["file"]
        for section: String in sections:
            var why := _why_it_does_not_ship(file, config, section)
            assert_eq(why, "", "%s:%d reads %s, which %s does not ship: %s" % [read["script"], read["line"], file, section, why])


## Why *file* would be missing from the pack of *section*, or empty when it ships.
func _why_it_does_not_ship(file: String, config: ConfigFile, section: String) -> String:
    if _matches(file, str(config.get_value(section, "exclude_filter", ""))):
        return "the exclude_filter leaves it out"
    var named := _matches(file, str(config.get_value(section, "include_filter", "")))
    var sidecar := ConfigFile.new()
    if sidecar.load(file + ".import") == OK:
        var importer := str(sidecar.get_value("remap", "importer", ""))
        if importer != "keep":
            return "its importer is %s, so only the imported resource is packed, not the file's bytes" % importer
        if not named:
            return "it is kept as it is, and a kept file is no resource, so only the include_filter packs it"
        return ""
    if named or file.get_extension().to_lower() in PACKED_AS_THEY_ARE:
        return ""
    return "it is no resource the pack carries under its own path, and the include_filter does not name it"


func _matches(file: String, filters: String) -> bool:
    for part: String in filters.split(","):
        var filter := part.strip_edges()
        if filter.is_empty():
            continue
        if file.matchn(filter) or file.trim_prefix("res://").matchn(filter):
            return true
    return false


func _presets(config: ConfigFile) -> Array[String]:
    var found: Array[String] = []
    for section: String in config.get_sections():
        if section.begins_with("preset.") and not section.ends_with(".options"):
            found.append(section)
    return found


## Every raw read of a `res://` file in the scripts a build runs, as the file,
## the script and the line.
func _reads() -> Array[Dictionary]:
    if _found.is_empty():
        for script_path: String in _scripts("res://"):
            _found.append_array(Source.new(script_path).reads(CALLS))
    return _found


func _scripts(dir_path: String) -> Array[String]:
    var found: Array[String] = []
    if FileAccess.file_exists(dir_path.path_join(".gdignore")):
        return found
    for entry: String in DirAccess.get_directories_at(dir_path):
        if not entry in SKIPPED_DIRS:
            found.append_array(_scripts(dir_path.path_join(entry)))
    for entry: String in DirAccess.get_files_at(dir_path):
        if entry.get_extension() == "gd" and not entry.begins_with("test_"):
            found.append(dir_path.path_join(entry))
    return found


## One script's lines, and the `res://` files its raw reads reach. A path is
## followed through the script's constants, a local declared above the call, a
## parameter's default, a member's every assignment and another class's
## constant, and through `path_join`, whose last part alone names a file beside
## the script when what it joins to cannot be followed. Anything else, a call
## or a sum, ends the path unread.
class Source:
    ## How many names deep a path is followed before the scan gives up on it.
    const DEPTH := 6

    var path: String
    var lines: PackedStringArray
    var _loaders: Array[String] = []

    func _init(script_path: String) -> void:
        path = script_path
        lines = FileAccess.get_file_as_string(script_path).split("\n")
        var declared := RegEx.create_from_string(
            "\\bvar\\s+(\\w+)\\s*(:\\s*(ConfigFile|Image)\\b|:=\\s*(ConfigFile|Image)\\.new\\(\\))"
        )
        for line: String in lines:
            var found := declared.search(line)
            if found != null:
                _loaders.append(found.get_string(1) + ".load(")

    func reads(calls: Array[String]) -> Array[Dictionary]:
        var found: Array[Dictionary] = []
        var tokens: Array[String] = calls.duplicate()
        tokens.append_array(_loaders)
        for index in lines.size():
            var line := lines[index]
            if line.strip_edges().begins_with("#"):
                continue
            for token: String in tokens:
                var at := line.find(token)
                while at >= 0:
                    if at == 0 or not _is_name_char(line[at - 1]):
                        for file: String in _files(_read_at(line, at + token.length(), index)):
                            found.append({"file": file, "script": path, "line": index + 1})
                    at = line.find(token, at + token.length())
        return found

    ## What the call whose argument opens at *from* reads, nothing when it
    ## opens a file only to write it.
    func _read_at(line: String, from: int, index: int) -> Array[String]:
        var argument := _argument(line, from)
        var after := from + argument.length()
        if after < line.length() and line[after] == ",":
            if _argument(line, after + 1).strip_edges() == "FileAccess.WRITE":
                return []
        return _resolve(argument, index, 0)

    ## The `res://` files *candidates* name, a bare file name counted only
    ## when it lies beside this script.
    func _files(candidates: Array[String]) -> Array[String]:
        var files: Array[String] = []
        for candidate: String in candidates:
            if candidate.begins_with("res://"):
                files.append(candidate)
            elif not candidate.contains("/") and not candidate.contains(":") and candidate.get_extension() != "":
                var beside := path.get_base_dir().path_join(candidate)
                if FileAccess.file_exists(beside):
                    files.append(beside)
        return files

    func _resolve(expr: String, at: int, depth: int) -> Array[String]:
        var text := expr.strip_edges()
        if depth > DEPTH or text.is_empty():
            return []
        if text.length() >= 2 and text.begins_with('"') and text.ends_with('"') and text.count('"') == 2:
            return [text.substr(1, text.length() - 2)]
        var join := text.rfind(".path_join(")
        if join > 0 and text.ends_with(")"):
            var leaf := _argument(text, join + ".path_join(".length())
            if leaf.length() == text.length() - join - ".path_join(".length() - 1:
                return _joined(_resolve(text.substr(0, join), at, depth + 1), _resolve(leaf, at, depth + 1))
        if RegEx.create_from_string("^[A-Z]\\w*\\.[A-Z][A-Z0-9_]*$").search(text) != null:
            return _of_class(text.get_slice(".", 0), text.get_slice(".", 1), depth)
        if RegEx.create_from_string("^[A-Za-z_]\\w*$").search(text) == null:
            return []
        return _of_name(text, at, depth)

    func _joined(bases: Array[String], leaves: Array[String]) -> Array[String]:
        if bases.is_empty():
            return leaves
        var joined: Array[String] = []
        for base: String in bases:
            for leaf: String in leaves:
                joined.append(base.path_join(leaf))
        return joined

    ## What *name* holds at line *at*: a local above it in its function, else
    ## that function's parameter, else a member, else a constant.
    func _of_name(name: String, at: int, depth: int) -> Array[String]:
        var opening := _function_above(at)
        var local := RegEx.create_from_string("^\\s*var\\s+%s\\b\\s*(:[^=]*)?=\\s*(.+)$" % name)
        for index in range(at - 1, opening, -1):
            var found := local.search(lines[index])
            if found != null:
                return _resolve(found.get_string(2), index, depth + 1)
        if opening >= 0:
            var parameter: Variant = _parameter(opening, name)
            if parameter != null:
                return _resolve(str(parameter), opening, depth + 1)
        var resolved: Array[String] = []
        var member := RegEx.create_from_string("^var\\s+%s\\b\\s*(:[^=]*)?=\\s*(.+)$" % name)
        var assigned := RegEx.create_from_string("^\\s+(self\\.)?%s\\s*=(?!=)\\s*(.+)$" % name)
        var constant := RegEx.create_from_string("^\\s*const\\s+%s\\b\\s*(:[^=]*)?=\\s*(.+)$" % name)
        var is_member := RegEx.create_from_string("^var\\s+%s\\b" % name)
        var member_found := false
        for line: String in lines:
            member_found = member_found or is_member.search(line) != null
        for index in lines.size():
            for pattern: RegEx in [member, assigned] if member_found else [constant]:
                var found := pattern.search(lines[index])
                if found != null:
                    resolved.append_array(_resolve(found.get_string(2), index, depth + 1))
        return resolved

    ## The default *name* takes in the signature opening at *opening*: null
    ## when it is no parameter, an empty string when it has no default.
    func _parameter(opening: int, name: String) -> Variant:
        var signature := ""
        for index in range(opening, mini(opening + 12, lines.size())):
            signature += lines[index] + " "
            if lines[index].strip_edges().ends_with(":"):
                break
        var at := signature.find("(") + 1
        while at > 0 and at < signature.length():
            var piece := _argument(signature, at).strip_edges()
            if piece.get_slice(":", 0).get_slice("=", 0).strip_edges() == name:
                return piece.substr(piece.find("=") + 1) if piece.contains("=") else ""
            at += _argument(signature, at).length()
            if at >= signature.length() or signature[at] != ",":
                break
            at += 1
        return null

    func _function_above(at: int) -> int:
        var opening := RegEx.create_from_string("^\\s*(static\\s+)?func\\s")
        for index in range(at, -1, -1):
            if opening.search(lines[index]) != null:
                return index
        return -1

    func _of_class(class_title: String, constant: String, depth: int) -> Array[String]:
        for entry: Dictionary in ProjectSettings.get_global_class_list():
            if str(entry["class"]) == class_title:
                var other := Source.new(str(entry["path"]))
                return other._of_name(constant, 0, depth + 1)
        return []

    ## The argument that opens at *from* in *text*, up to the comma or the
    ## closing bracket at its own depth, strings stepped over whole.
    static func _argument(text: String, from: int) -> String:
        var depth := 0
        var quoted := false
        var at := from
        while at < text.length():
            var character := text[at]
            if quoted:
                quoted = character != '"'
            elif character == '"':
                quoted = true
            elif character in ["(", "[", "{"]:
                depth += 1
            elif character in [")", "]", "}"]:
                if depth == 0:
                    break
                depth -= 1
            elif character == "," and depth == 0:
                break
            at += 1
        return text.substr(from, at - from)

    static func _is_name_char(character: String) -> bool:
        return character.is_valid_identifier() or character.is_valid_int()
