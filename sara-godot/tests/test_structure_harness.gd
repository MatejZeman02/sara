## The harness reads what a feature hands it, and this is the number it reads
## instead.
##
## The fifth rule of structure, in CONTRIBUTING.md: "A docker hands the dump one dictionary of its own
## state, so a capture reads that and not the docker's members." One read of one
## private member is legal, since reading a private member from outside is allowed. Ten of
## them into one object, or a driver reaching into a runner it was handed as a
## `Node`, is the rule not being followed.
##
## So the harness is counted, file by file and receiver by receiver. A read is
## `receiver._member` where the receiver is neither `self`, nor `super`, nor the
## class the file itself declares, with comments and strings taken out first. A
## file fails the run once it reads `CROWDED` or more private members through one
## receiver, and a read on its own is left alone.
##
## A crowded receiver is drained by giving the feature
## `static func capture_state(root: Window) -> Dictionary`, and the capture file
## shrinks to the call of it.
##
## The path is relative to the Godot project, as the hard-rules suite writes them.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## How many private reads through one receiver make a file a capture that reads a
## docker's state rather than the dictionary the docker hands it. The header's
## ten, so one read, or a handful into different objects, passes.
const CROWDED: int = 10

## The package the rule is about.
const ROOT: String = "res://harness"

## What a path is displayed with, so a failure names the file the way the rest of
## the docs do rather than the way `res://` does.
const PREFIX: String = "harness/"

## Never descend into these. The harness holds no import cache, and this is here
## so a scratch folder dropped inside it one day is not read as source. A
## `tests` folder holds the harness's suites, which read what they test.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "tests"]

## Where the planted pair is written and removed again. Under `user://` rather
## than `res://`, so the editor never imports it and a run that dies between the
## write and the removal cannot leave a script in the tree.
static var scratch_dir: String = SaDataRoot.path("test_structure_harness_scratch")


## A harness file that reads `CROWDED` or more private members of one object.
func test_no_harness_file_crowds_one_object() -> void:
    var crowded := _crowded(_reads_under(ROOT, PREFIX))
    assert_true(
        crowded.is_empty(),
        (
            (
                "These read one object's private members %d times or more: %s. Hand the dump a "
                + "dictionary from a `capture_state` on the feature itself, and read that."
            )
            % [CROWDED, ", ".join(crowded)]
        )
    )


## The check is proved on files it wrote itself.
##
## One read of another object passes, as reading is allowed, and `CROWDED`
## reads into one object fail. A walk that quietly stopped early would report a
## clean harness, so the counter is shown counting something as well.
func test_the_check_passes_one_read_and_fails_a_crowded_object() -> void:
    var reader := "extends RefCounted\n\n\n"
    reader += "func describe(other: RefCounted) -> Variant:\n    return other._hidden\n"

    var crowding := "extends RefCounted\n\n\n"
    crowding += "func describe(docker: RefCounted, other: RefCounted) -> Array:\n    return [\n"
    for index in CROWDED:
        crowding += "        docker._member_%d,\n" % index
    crowding += "        other._elsewhere,\n    ]\n"

    # Many reads, none past the limit through one receiver: a file spread over
    # several objects is not the capture the rule is about.
    var spread := "extends RefCounted\n\n\n"
    spread += "func describe(first: RefCounted, second: RefCounted) -> Array:\n    return [\n"
    for index in CROWDED - 1:
        spread += "        first._member_%d,\n        second._member_%d,\n" % [index, index]
    spread += "    ]\n"

    # The near misses, none of which is a read: the file's own member, a static
    # of the class the file declares, a commented access and a quoted one. A
    # counter that saw any of these would be counting the wrong thing.
    var clean := "class_name SaScratchHarnessClean\nextends RefCounted\n\n\n"
    clean += "var _own: int = 0\n\n\n"
    clean += "func describe(shown: int) -> Array:\n"
    clean += '    # other._commented is prose, and "other._quoted" is a string\n'
    clean += "    return [self._own, shown, SaScratchHarnessClean._name_of_it()]\n\n\n"
    clean += 'static func _name_of_it() -> String:\n    return "a name of its own"\n'

    var planted := {
        "sa_scratch_harness.gd": reader,
        "sa_scratch_crowding.gd": crowding,
        "sa_scratch_spread.gd": spread,
        "sa_scratch_clean.gd": clean,
    }
    _write_scratch(planted)
    var found := _reads_under(scratch_dir, "")
    ScratchFolder.clear(scratch_dir)

    assert_eq(
        found.get("sa_scratch_harness.gd", {}),
        {"other": 1},
        "The planted read was not seen, so the check measures nothing",
    )
    assert_eq(
        found.get("sa_scratch_crowding.gd", {}),
        {"docker": CROWDED, "other": 1},
        "The crowded file was not counted receiver by receiver",
    )
    assert_false(
        found.has("sa_scratch_clean.gd"),
        "A read of self, of the file's own class, a comment and a string are none of them a read",
    )
    var expected: Array[String] = ["sa_scratch_crowding.gd (%d of docker)" % CROWDED]
    assert_eq(
        _crowded(found),
        expected,
        "Only the file that crowds one object fails, and one read or a spread of them passes",
    )


## Every file of *found* that reads `CROWDED` or more private members through one
## receiver, as `path (count of receiver)`, sorted.
static func _crowded(found: Dictionary) -> Array[String]:
    var crowded: Array[String] = []
    for path: String in found:
        var receivers: Dictionary = found[path]
        for receiver: String in receivers:
            var count: int = receivers[receiver]
            if count >= CROWDED:
                crowded.append("%s (%d of %s)" % [path, count, receiver])
    crowded.sort()
    return crowded


## Reads of another object's private member under *dir_path*, as
## `{display path: {receiver: count}}`, with the files that have none left out.
func _reads_under(dir_path: String, prefix: String) -> Dictionary:
    var found: Dictionary = {}
    _walk_reads(dir_path, prefix, found)
    return found


func _walk_reads(dir_path: String, prefix: String, found: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    var subdirs: Array[String] = []
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                subdirs.append(entry)
        elif entry.get_extension() == "gd":
            var receivers := _private_reads(_read(dir_path.path_join(entry)))
            if not receivers.is_empty():
                found[prefix + entry] = receivers
        entry = dir.get_next()
    dir.list_dir_end()

    for sub in subdirs:
        _walk_reads(dir_path.path_join(sub), prefix + sub + "/", found)


## How many times *source* reads another object's private member, as
## `{receiver: count}`.
##
## `self._x` and `super._x` are the file's own, and so is `SaFoo._x` where `SaFoo`
## is the class the file declares, which is how one part of a file reaches a
## private of another part.
static func _private_reads(source: String) -> Dictionary:
    var code := _without_comments_and_strings(source)
    var own := _own_class_name(code)
    var pattern := RegEx.create_from_string("([A-Za-z_]\\w*)\\.(_[A-Za-z_]\\w*)")
    var receivers: Dictionary = {}
    if pattern == null:
        return receivers

    for hit in pattern.search_all(code):
        var receiver := hit.get_string(1)
        if receiver == "self" or receiver == "super" or receiver == own:
            continue
        # A receiver that is itself a member, `docker.picture._texel` say, is not
        # the object being read, and neither the scan nor this one counts it.
        var start := hit.get_start(1)
        if start > 0 and _continues_a_name(code[start - 1]):
            continue
        receivers[receiver] = int(receivers.get(receiver, 0)) + 1
    return receivers


## The class name *source* declares, or "" when it declares none.
static func _own_class_name(source: String) -> String:
    for line in source.split("\n"):
        if line.begins_with("class_name "):
            return line.trim_prefix("class_name ").strip_edges().split(" ")[0]
    return ""


## Whether *character* can be part of the name before it.
static func _continues_a_name(character: String) -> bool:
    if character.is_empty():
        return false
    if character == "." or character == "_":
        return true
    var code := character.unicode_at(0)
    return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)


## *source* with every comment and every string literal taken out, so a name
## quoted in prose is not read as an access.
##
## Character by character, because a `#` inside a string is not a comment and a
## quote inside a comment does not open one.
static func _without_comments_and_strings(source: String) -> String:
    var out: Array[String] = []
    var index := 0
    var length := source.length()
    while index < length:
        var character := source[index]
        if character == "#":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if character == '"' or character == "'":
            var quote := character
            if index + 2 < length and source.substr(index, 3) == character + character + character:
                quote = character + character + character
            var triple := quote.length() == 3
            index += quote.length()
            while index < length and source.substr(index, quote.length()) != quote:
                if not triple and source[index] == "\\":
                    index += 1
                index += 1
            index += quote.length()
            # A space rather than nothing, so two names on either side of a string
            # stay two names.
            out.append(" ")
            continue
        out.append(character)
        index += 1
    return "".join(out)


static func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()


## Writes *planted*, `{file name: source}`, into the scratch directory.
func _write_scratch(planted: Dictionary) -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    for name: String in planted:
        var file := FileAccess.open(scratch_dir.path_join(name), FileAccess.WRITE)
        assert_not_null(file, "The scratch file could not be written to %s" % scratch_dir)
        if file != null:
            file.store_string(String(planted[name]))
            file.close()
