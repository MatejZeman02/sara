## No kernel in the tree declares a workgroup the start-up floor does not ask for.
##
## `SaDeviceFloor` refuses a GPU whose invocations per workgroup fall under
## `NEEDS_WORKGROUP_INVOCATIONS`. The floor was 64 while the magic wand's two
## kernels declared 256, so a device that allowed 64 to 255 passed the floor and
## failed the first time the wand ran, which is the failure the floor exists to
## turn into a sentence at start.
##
## This walks every `.gmacs` under `res://`, the modules' included, reads each
## declared size and holds the product of its three numbers to the floor's
## figure. The next kernel that asks for more fails this run and not a
## painter's GPU. It reads text and asks no device, so it runs offscreen on any
## machine.
extends "res://tests/test_framework.gd"

## What is not shipped. The gate's own data root and the engine's caches are
## generated, and a fixture module is a test's input and not a kernel a painter
## runs.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "scratch", "tests"]

## The decorators the dialect reads and the GLSL-side form it came from, each
## alone on its line. A comment that names one starts with `#`, so it is not one.
const DECLARATION_PATTERN: String = "^\\s*(?:@(?:workgroup_size|numthreads)\\s*\\(([^)]*)\\)|\\[numthreads\\s*\\(([^)]*)\\)\\])"

## A kernel with no decorator takes this, `SaDialect.DEFAULT_WORKGROUP`, and the
## figure is 64 whatever the floor says.
const DEFAULT_INVOCATIONS: int = 64


func test_no_declared_workgroup_is_wider_than_the_floor_asks_for() -> void:
    var declarations := _declarations("res://", "")
    var floor_figure := SaDeviceFloor.NEEDS_WORKGROUP_INVOCATIONS
    for path: String in declarations:
        for declared: Dictionary in declarations[path]:
            var where := "%s:%d" % [path, declared["line"]]
            var invocations: int = declared["invocations"]
            assert_true(invocations > 0, "%s declares a size that is not plain numbers: %s" % [where, declared["text"]])
            assert_true(
                invocations <= floor_figure,
                (
                    "%s declares %d invocations, the floor asks for %d, so a device between them fails this kernel"
                    % [where, invocations, floor_figure]
                ),
            )


func test_the_default_workgroup_is_inside_the_floor() -> void:
    assert_true(
        DEFAULT_INVOCATIONS <= SaDeviceFloor.NEEDS_WORKGROUP_INVOCATIONS,
        "a kernel that declares nothing is 8 by 8, and the floor must ask for at least that",
    )


## The walk is the whole of the suite's evidence, so it has to be seen to reach
## both roots and to read a decorator, or a wrong path would pass it for good.
func test_the_walk_reaches_the_shared_kernels_and_the_modules() -> void:
    var declarations := _declarations("res://", "")
    var shared := 0
    var modules := 0
    for path: String in declarations:
        if path.begins_with("shaders/"):
            shared += declarations[path].size()
        elif path.begins_with("modules/"):
            modules += declarations[path].size()
    assert_true(shared > 0, "no workgroup declaration was read under shaders/")
    assert_true(modules > 0, "no workgroup declaration was read under modules/")


func test_a_declaration_is_read_as_the_product_of_its_three_numbers() -> void:
    assert_eq(_invocations("256"), 256, "a missing number is one")
    assert_eq(_invocations("8, 8"), 64)
    assert_eq(_invocations("16, 4, 2"), 128)
    assert_eq(_invocations("64, 1, 1"), 64)
    assert_eq(_invocations("TILE, 8"), 0, "a name is not a number this suite can multiply")
    assert_eq(_invocations(""), 0, "an empty list declares nothing it can hold")


## `{relative path: [{line, text, invocations}]}` for every `.gmacs` under *dir_path*.
func _declarations(dir_path: String, prefix: String) -> Dictionary:
    var found: Dictionary = {}
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return found
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                found.merge(_declarations(dir_path.path_join(entry), prefix + entry + "/"))
        elif entry.get_extension() == "gmacs":
            var kernels := _read_declarations(dir_path.path_join(entry))
            if not kernels.is_empty():
                found[prefix + entry] = kernels
        entry = dir.get_next()
    dir.list_dir_end()
    return found


func _read_declarations(path: String) -> Array:
    var kernels: Array = []
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return kernels
    var pattern := RegEx.create_from_string(DECLARATION_PATTERN)
    var number := 0
    for line: String in file.get_as_text().split("\n"):
        number += 1
        var found := pattern.search(line)
        if found == null:
            continue
        var args := found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2)
        kernels.append({"line": number, "text": line.strip_edges(), "invocations": _invocations(args)})
    return kernels


## The product of the numbers in *args*, a missing one counting as one the way
## the dialect reads it. Zero when any of them is not a plain number, or when
## there are none.
func _invocations(args: String) -> int:
    var parts := args.split(",", false)
    if parts.is_empty() or parts.size() > 3:
        return 0
    var product := 1
    for part: String in parts:
        var text := part.strip_edges()
        if not text.is_valid_int():
            return 0
        product *= text.to_int()
    return product
