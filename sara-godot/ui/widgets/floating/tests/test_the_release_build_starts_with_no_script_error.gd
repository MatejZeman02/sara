## The release build starts with no script error.
##
## Every start of the Windows release build wrote 68 `SCRIPT ERROR` lines, the
## first `Function "free()" not found in base self.` at the last line of
## `SaFloatingPanel._leave_the_window()`, and the debug build wrote none. A
## release build's GDScript knows no `free` member on `self`: a probe built and
## started on 2026-10-20 failed to compile `free()`, `self.free()`,
## `free.call_deferred()` and `var f := free`, and compiled `queue_free()`,
## `call(&"free")` and `node.free()` on another node, typed or not. The editor
## and the debug build compile all of them, so nothing but a release start sees
## the fault, and every class that names the failed one fails with it.
##
## So this suite reads every GDScript file under `res://` for a `free` taken
## from `self`, and first shows its reader the forms the probe failed and the
## ones it passed, so a reader that finds nothing is known to look.
extends "res://tests/test_framework.gd"

## Folders no GDScript of Sara's lives in, skipped for speed.
const SKIPPED := [".godot", ".git", "scratch"]

## The forms the release build refused, each a line of a function body.
const REFUSED := [
    "    free()",
    "    self.free()",
    "    self . free ()",
    "    free.call_deferred()",
    "    _later.call(free)",
    "    var f := free",
    "    if done: free()",
]

## The forms it compiled, and lines that only look like one.
const COMPILED := [
    "    queue_free()",
    "    node.free()",
    "    bar.free()",
    '    call(&"free")',
    "    var free := area\n    free = moved\n    return free",
    "    free.append(Vector2(edge, span.x))",
    "    # Freed with free() once the frame is over.",
    '    print("free() here")',
    "func free() -> void:",
]


## Reads GDScript source for a `free` taken from `self`, which a release build
## cannot compile.
class SelfFree:
    ## A bare `free` or `self.free` that is called or taken as a Callable.
    var _taken := RegEx.create_from_string(
        "(?<![\\w.])(?:self\\s*\\.\\s*)?free\\b(?!\\s*(?:=(?!=)|:=|\\.\\s*(?!call|callv|call_deferred|bind|bindv|unbind)\\w))"
    )
    ## `self.free`, which never names a local.
    var _of_self := RegEx.create_from_string("\\bself\\s*\\.\\s*free\\b")
    ## The names a file declares as locals or members called `free`.
    var _declared := RegEx.create_from_string("\\b(?:var|const|func)\\s+free\\b|\\bfunc\\b.*[(,]\\s*free\\s*[:,)=]")
    var _strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")

    ## The numbers of the lines of *source* that take `free` from `self`.
    func lines_in(source: String) -> Array[int]:
        var found: Array[int] = []
        var code_lines: Array[String] = []
        var shadowed := false
        for line in source.split("\n"):
            var code := _code_of(line)
            code_lines.append(code)
            if _declared.search(code) != null:
                shadowed = true
        for i in code_lines.size():
            var code := code_lines[i]
            if _of_self.search(code) != null:
                found.append(i + 1)
            elif not shadowed and _taken.search(code) != null:
                found.append(i + 1)
        return found

    ## *line* without its strings and its comment.
    func _code_of(line: String) -> String:
        var bare := _strings.sub(line, '""', true)
        var comment_at := bare.find("#")
        return bare if comment_at < 0 else bare.substr(0, comment_at)


func test_the_reader_finds_every_form_the_release_build_refused() -> void:
    var reader := SelfFree.new()
    for line: String in REFUSED:
        var source := "extends Node\n\n\nfunc go() -> void:\n%s\n" % line
        assert_eq(reader.lines_in(source), [5] as Array[int], "found: %s" % line.strip_edges())


func test_the_reader_passes_every_form_it_compiled() -> void:
    var reader := SelfFree.new()
    for line: String in COMPILED:
        var source := "extends Node\n\n\nfunc go() -> void:\n%s\n" % line
        assert_eq(reader.lines_in(source), [] as Array[int], "passed: %s" % line.strip_edges())


func test_no_gdscript_under_the_project_takes_free_from_self() -> void:
    var reader := SelfFree.new()
    var files: Array[String] = []
    _gather("res://", files)
    assert_true(files.size() > 500, "the walk reached the tree: %d files" % files.size())
    assert_true(files.has("res://ui/widgets/floating/sa_floating_panel.gd"), "and the panel among them")
    var bad: Array[String] = []
    for path in files:
        for at in reader.lines_in(FileAccess.get_file_as_string(path)):
            bad.append("%s:%d" % [path, at])
    assert_eq(bad, [] as Array[String], "no file takes free from self, which a release build cannot compile")


func _gather(dir_path: String, files: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for sub in dir.get_directories():
        if sub in SKIPPED:
            continue
        _gather(dir_path.path_join(sub), files)
    for file in dir.get_files():
        if file.ends_with(".gd"):
            files.append(dir_path.path_join(file))
