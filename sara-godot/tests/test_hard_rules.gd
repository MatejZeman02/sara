## The hard rules, as far as a source scan can hold them.
##
## Sara's hard rules are listed in full in the maintainers' onboarding page and
## repeated in the agent guide at the repository root. Neither page is in a
## public copy of the source, where the check of the list skips. Most of them were held by convention: nothing failed if a new
## caller broke one, so "we follow this rule" meant "nobody has checked lately".
## Three of them are a grep, so they are one here instead.
##
## The list itself is checked first, because it had already drifted. One file's
## rule 5 was colour precision and the other's was UI scale, and two documentation
## files cited a rule 6 that neither list defined. A rule that cannot be counted
## cannot be proven, so the two lists have to agree before anything else runs.
##
## What this suite cannot see:
##
##   Rule 2, dirty-rect dispatch. Nothing in the source says how large a
##   dispatch is. `test_sa_easel.gd` and `test_sa_document.gd` cover the dirty
##   set behaviourally instead.
##   Rule 3, sparse chunks. Allocation is a runtime shape, and the two live
##   breaches are recorded in the maintainer's audit notes.
##   Rule 5, colour precision. `test_no_clamp.gd` is the whole answer.
##   Rule 6, the public door. `test_module_api_contract.gd` registers a
##   synthetic third-party feature and asserts it reaches where a built-in does,
##   which is stronger than any grep.
extends "res://tests/test_framework.gd"

## Never descend into these. `.godot` is the engine's import cache, `.conda` the
## vendored gdtoolkit env, `build/` is output, and `scratch/` is gitignored
## experiments that are allowed to break every rule in here.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "scratch"]

## Rule 1. The only places allowed to pull texels back to the CPU, each one of
## the kinds the full text of rule 1 lists: a file out, one texel
## at a click, a kernel's result, a brush built outside a stroke and a test's
## reading. A file added here is added to that list in the same commit.
const READBACK_ALLOWED: Array[String] = [
    "core/export/sa_export.gd",
    # Export's own gamut conversion, reading through export's float reader.
    "core/export/sa_export_gamut.gd",
    "core/sad-file/sa_sad_file.gd",
    "core/sad-file/sa_sad_layer_entry.gd",
    "core/sad-file/sa_sad_blob.gd",
    "core/sad-file/sa_older_reading.gd",
    # The background save reads its snapshot's copies back, never the canvas
    # itself, a few a frame and asynchronously, outside any stroke.
    "core/sad-file/sa_sad_save.gd",
    # A save's sweep reads one word per chunk its pass set on its copies, with
    # the save's own readback and asynchronously in the background, never texels.
    "core/sad-snapshot/sa_sad_clear_chunks.gd",
    "modules/sara-base-modules/base/tools/state_eyedropper.gd",
    "modules/sara-base-modules/base/filters/levels/sa_levels_sampler.gd",
    "modules/sara-base-modules/base/filters/white_point/white_point_square.gd",
    "modules/sara-base-modules/stamp-brush/pattern/sa_dab_pattern.gd",
    "harness/report/sa_texel_probe.gd",
    # A scenario's and the door's readings: `look`, `find` and the pixels step.
    "harness/sa_color_find.gd",
    "harness/scenario/sa_scenario_document.gd",
    "harness/scenario/sa_scenario_pixels.gd",
    # A generated pattern's tile, a brush built outside a stroke.
    "core/api/pattern/sa_pattern_kernel.gd",
    # A filter that asks for its pixels by name, once, as an explicit command.
    "core/api/filter/sa_filter_pixels.gd",
    # A scratch easel's picture, never the painter's canvas.
    "ui/dockers/layers/lut/effects_lut_scratch.gd",
    "core/presets/sa_preset_thumbs.gd",
    "ui/drive/sa_app_drive.gd",
    # A welcome card's picture, read a few cells a frame from a copy on the card.
    "ui/welcome/preview_cache.gd",
    # A door stroke's answer reads the texels its committed step names, after
    # the commit and never while it paints, for the largest alpha it laid.
    "harness/scenario/sa_scenario_alpha_laid.gd",
    # A buffer a kernel filled is read back here, never the canvas: the door's
    # one blocking read of a result, the reductions the dockers fold a frame
    # late, and a filter's few guard bytes, both of those asked asynchronously.
    "core/custom-shader/sa_compute.gd",
    "modules/sara-base-modules/base/filters/sa_point_adjust.gd",
    "core/api/reduction/sa_reduction_service.gd",
    "ui/dockers/reduction/spectrum/sa_power_spectrum.gd",
    # Eviction past the card's budget reads a chunk of a layer nobody is
    # painting on back to RAM, after a stroke's release and never inside one.
    "core/residency/sa_residency.gd",
]

## Rule 1 again. The readers of `SaExport` that read the card back for their
## caller, so that calling one is held to `READBACK_ALLOWED` as a direct read is.
## `take_preview` is not one: it copies on the card and reads nothing.
const EXPORT_READERS: Array[String] = [
    "get_preview_image",
    "get_texture_image_float",
    "get_easel_image_float",
    "get_canvas_image",
    "ask_texture_bytes",
]

## Rule 4. The files that own RIDs and free them in `NOTIFICATION_PREDELETE`.
## Everyone else holds a `RefCounted` and lets it go.
const RID_OWNERS: Array[String] = [
    "core/api/gpu/sa_texture.gd",
    "core/custom-shader/sa_compute.gd",
    "core/custom-shader/sa_pipelines.gd",
    "core/custom-shader/compiler/global_shader_compiler.gd",
]

## Rule 7. The single writer.
const SCALE_WRITER: String = "ui/themes/sa_ui.gd"

## Not one of the seven, but held here because it is the same kind of thing: a
## grep that stops a convention rotting. Every string the app puts on screen
## goes through `tr()`, so that a translation is a catalogue rather than a
## second sweep over every call site. Under `ui/` only, which is where the
## screen is written, and the modules get the rule when they get a docker.
const STRING_ROOT: String = "ui/"

## Markdown that is allowed to cite a rule by number.
const DOC_ROOTS: Array[String] = ["docs", "AGENTS.md", "README.md"]


## The list has to be one list. Titles and their numbers, in order, in both
## files. Adding a rule to one file only is the failure this catches, and it is
## the failure that already happened.
func test_the_two_rule_lists_agree() -> void:
    if not _has_the_rule_pages():
        skip("the rule pages are not in this copy of the source")
        return
    var canonical := _rule_titles(_read(_repo_path("docs/agents/ONBOARDING.md")))
    var repeated := _rule_titles(_read(_repo_path("AGENTS.md")))

    assert_false(canonical.is_empty(), "No numbered rules found under ONBOARDING's hard rules heading")
    assert_false(repeated.is_empty(), "No numbered rules found under AGENTS.md's hard rules heading")
    assert_eq(repeated, canonical, "AGENTS.md and ONBOARDING.md list different hard rules")

    var expected: Array[String] = []
    for i in canonical.size():
        expected.append(str(i + 1))
    var numbers: Array[String] = []
    for title: String in canonical:
        numbers.append(title.split(".")[0])
    assert_eq(numbers, expected, "The canonical list is not numbered 1..%d in order" % canonical.size())


## A citation of "hard rule 6" is a claim that rule 6 exists. Two documentation files
## made that claim while both lists stopped at five.
func test_no_document_cites_a_rule_the_list_does_not_define() -> void:
    if not _has_the_rule_pages():
        skip("the rule pages are not in this copy of the source")
        return
    var count := _rule_titles(_read(_repo_path("docs/agents/ONBOARDING.md"))).size()
    var citation := RegEx.create_from_string("hard rule (\\d+)")

    var bad: Array[String] = []
    for path: String in _documents():
        for found: RegExMatch in citation.search_all(_read(_repo_path(path))):
            var cited := int(found.get_string(1))
            if cited < 1 or cited > count:
                bad.append("%s cites hard rule %d" % [path, cited])
    bad.sort()
    assert_true(bad.is_empty(), "Only %d hard rules are defined: %s" % [count, ", ".join(bad)])


## Rule 1. `texture_get_data` stalls the pipeline until the GPU catches up, which
## is the whole thing the rule exists to prevent. A test may read back freely,
## because reading the result is how a GPU test asserts anything at all.
##
## A buffer read stalls the same way, so `buffer_get_data` is held to the same
## list, and each needle also catches its `_async` form. So is a call of one of
## `SaExport`'s readers, which make that read on the caller's behalf: a file
## that reads the card through export is a file that reads the card.
func test_only_export_and_the_eyedropper_read_the_canvas_back() -> void:
    var offenders: Array[String] = []
    for path: String in _sources():
        if not READBACK_ALLOWED.has(path) and _reads_back(_code(_read(_source_path(path)))):
            offenders.append(path)
    assert_true(offenders.is_empty(), "Readback outside export and the eyedropper breaks hard rule 1: %s" % ", ".join(offenders))


## The welcome window is on the list for one reading only, a copy on the card
## asked a few cells a frame through `ask_texture_bytes`, a painter's answer of
## 2026-10-31. A blocking reader called from any file under `ui/welcome`
## would hold the frame the welcome window draws in, so none of them may be.
func test_no_welcome_file_makes_a_blocking_read() -> void:
    var offenders: Array[String] = []
    for path: String in _sources():
        if path.begins_with("ui/welcome/") and _reads_blocking(_code(_read(_source_path(path)))):
            offenders.append(path)
    assert_true(offenders.is_empty(), "A blocking read in the welcome window holds its frame: %s" % ", ".join(offenders))
    var blocking := "var x := SaExport.get_preview_image(easel)"
    assert_true(_reads_blocking(blocking), "A call of get_preview_image was not read as blocking")
    assert_false(_reads_blocking("SaExport.ask_texture_bytes(scratch, done)"), "The asynchronous reader was read as blocking")


## The scan above would pass a tree that never named a reader, so a scratch file
## that calls one through `SaExport` and nothing else has to be caught, and the
## same file with the call only in a comment has to pass.
func test_a_read_through_sa_export_is_a_readback() -> void:
    var folder := OS.get_temp_dir().path_join("sara_%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    var scratch := folder.path_join("scratch_reader.gd")
    var file := FileAccess.open(scratch, FileAccess.WRITE)
    file.store_string("extends RefCounted\n\n\nfunc look(texture: SaTexture) -> Image:\n")
    file.store_string("    return SaExport.get_texture_image_float(texture)\n")
    file.close()
    assert_true(_reads_back(_code(_read(scratch))), "A call of SaExport.get_texture_image_float was not read as a readback")
    for reader: String in EXPORT_READERS:
        assert_true(_reads_back("var x := SaExport.%s(y)" % reader), "A call of SaExport.%s was not read as a readback" % reader)
    var quoted := "extends RefCounted\n## Reads through `SaExport.get_texture_image_float(texture)` elsewhere.\n"
    assert_false(_reads_back(_code(quoted)), "A reader named only in a comment was read as a readback")
    assert_false(_reads_back("var shot := SaExport.take_preview(easel)"), "A copy on the card was read as a readback")
    DirAccess.remove_absolute(scratch)
    DirAccess.remove_absolute(folder)


## Rule 4, the half that leaks. Freeing a RID by hand outside the three owners
## either double-frees what RAII is about to free, or frees something still
## bound. Tests are exempt: a suite that builds a raw shader and pipeline by hand
## owns them itself, and several do.
func test_only_the_rid_owners_free_a_rid() -> void:
    var offenders := _files_matching("free_rid", RID_OWNERS)
    assert_true(offenders.is_empty(), "Manual free_rid breaks hard rule 4: %s" % ", ".join(offenders))


## Rule 4, the half `run_tests.sh` cannot see. Its leak check catches an object
## that outlives the run. A hand-written `free()` on a `RefCounted` that would
## have been collected anyway leaks nothing and reports nothing, so it needs
## reading rather than counting.
func test_nobody_frees_a_raii_object_by_hand() -> void:
    var declared := RegEx.create_from_string(
        "var\\s+(\\w+)\\s*(?::\\s*(?:SaTexture|SaCompute)\\b|:=\\s*(?:SaTexture|SaCompute)\\.new)"
    )
    var offenders: Array[String] = []
    for path: String in _sources():
        # Per function, not per file: two functions in one suite used the name
        # `source` for an SaTexture and for a Node, and only the Node was freed.
        for block: String in _functions(_code(_read(_source_path(path)))):
            for found: RegExMatch in declared.search_all(block):
                var name := found.get_string(1)
                if RegEx.create_from_string("\\b%s\\.free\\(\\)" % name).search(block) != null:
                    offenders.append("%s (%s)" % [path, name])
    offenders.sort()
    assert_true(offenders.is_empty(), "SaTexture and SaCompute free themselves, hard rule 4: %s" % ", ".join(offenders))


## Rule 7. Godot already applies the display's own scale, so a second writer
## multiplies the two: that is the 4K bug `test_ui_scale.gd` pins the behaviour
## of. This pins the fact that nowhere else assigns it.
func test_only_sa_ui_writes_the_content_scale_factor() -> void:
    var assignment := RegEx.create_from_string("content_scale_factor\\s*=[^=]")
    var offenders: Array[String] = []
    for path: String in _sources():
        if path == SCALE_WRITER:
            continue
        if assignment.search(_code(_read(_source_path(path)))) != null:
            offenders.append(path)
    offenders.sort()
    assert_true(
        offenders.is_empty(),
        "%s is the only writer of content_scale_factor, hard rule 7: %s" % [SCALE_WRITER, ", ".join(offenders)]
    )


## The house rule from `strings-in-dockers-and-preferences`: a bare literal assigned to `text`, a title,
## a tooltip or a placeholder, or handed straight to a menu's `add_*`, is a
## string the app shows that no translation could ever reach. Only literals
## with a word in them count, so a format such as `"%.1f"` and the empty
## string stay allowed: none of them is language.
func test_every_string_shown_under_ui_goes_through_tr() -> void:
    var assigned := RegEx.create_from_string(
        '\\b(?:tooltip_text|placeholder_text|text|title)\\s*\\+?=\\s*"((?:[^"\\\\]|\\\\.)*)"'
    )
    var added := RegEx.create_from_string(
        '\\badd_(?:check_|submenu_|icon_|icon_check_|radio_check_)?(?:item|separator)\\(\\s*"((?:[^"\\\\]|\\\\.)*)"'
    )
    var word := RegEx.create_from_string("[A-Za-z]{2,}")
    var offenders: Array[String] = []
    for path: String in _sources():
        if not path.begins_with(STRING_ROOT):
            continue
        var lines := _code(_read(_source_path(path))).split("\n")
        for i in lines.size():
            for pattern: RegEx in [assigned, added]:
                for found: RegExMatch in pattern.search_all(lines[i]):
                    if word.search(found.get_string(1)) != null:
                        offenders.append("%s:%d %s" % [path, i + 1, found.get_string(0).strip_edges()])
    offenders.sort()
    assert_true(offenders.is_empty(), "A string the app shows must go through tr(): %s" % ", ".join(offenders))


## A walk that quietly returned nothing would pass every scan above. Prove it
## reached the three trees the rules are actually about.
func test_the_scan_reaches_the_code_it_claims_to_check() -> void:
    var sources := _sources()
    assert_true(sources.size() > 50, "The scan found only %d source files, so it is measuring nothing" % sources.size())
    var required: Array[String] = READBACK_ALLOWED.duplicate()
    required.append_array(RID_OWNERS)
    required.append(SCALE_WRITER)
    for expected: String in required:
        assert_true(sources.has(expected), "The scan never reached %s" % expected)
    if _has_the_rule_pages():
        assert_true(_documents().size() > 10, "The document scan found %d files" % _documents().size())
    else:
        skip("the document scan has no pages to reach in this copy of the source")


## Every production `.gd` path, relative to `res://`. Tests are excluded: they
## exist to poke at the things the rules forbid, and a suite that could not read
## a texture back could not assert anything about one.
func _sources() -> Array[String]:
    var out: Array[String] = []
    _walk_sources(ProjectSettings.globalize_path("res://"), "", out)
    out.sort()
    return out


func _walk_sources(dir_path: String, prefix: String, out: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry) and entry != "tests":
                _walk_sources(dir_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "gd":
            out.append(prefix + entry)
        entry = dir.get_next()
    dir.list_dir_end()


## Every markdown file the rules may be cited from, relative to the repository
## root.
func _documents() -> Array[String]:
    var out: Array[String] = []
    var root := _repo_path("")
    for entry in DOC_ROOTS:
        var absolute := root.path_join(entry)
        if FileAccess.file_exists(absolute):
            out.append(entry)
        elif DirAccess.dir_exists_absolute(absolute):
            _walk_documents(absolute, entry + "/", out)
    out.sort()
    return out


func _walk_documents(dir_path: String, prefix: String, out: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                _walk_documents(dir_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "md":
            out.append(prefix + entry)
        entry = dir.get_next()
    dir.list_dir_end()


## Production files whose code contains `needle`, minus the ones allowed to.
func _files_matching(needle: String, allowed: Array[String]) -> Array[String]:
    var out: Array[String] = []
    for path: String in _sources():
        if allowed.has(path):
            continue
        if _code(_read(_source_path(path))).contains(needle):
            out.append(path)
    out.sort()
    return out


## Whether code reads texels back to the CPU: a call of the device's own reads,
## or of a reader `SaExport` makes it through, whatever name the export class is
## held under.
func _reads_back(code: String) -> bool:
    if code.contains("texture_get_data") or code.contains("buffer_get_data"):
        return true
    for reader: String in EXPORT_READERS:
        if RegEx.create_from_string("\\.%s\\(" % reader).search(code) != null:
            return true
    return false


## Whether code makes a read the frame waits on: the device's own synchronous
## reads, or one of `SaExport`'s readers other than `ask_texture_bytes`.
func _reads_blocking(code: String) -> bool:
    if RegEx.create_from_string("(texture|buffer)_get_data\\(").search(code) != null:
        return true
    for reader: String in EXPORT_READERS:
        if reader != "ask_texture_bytes" and RegEx.create_from_string("\\.%s\\(" % reader).search(code) != null:
            return true
    return false


## The file with its comment lines removed. A rule quoted in a doc comment, which
## is how half of these files explain themselves, is not a breach of it.
func _code(text: String) -> String:
    var kept: Array[String] = []
    for line in text.split("\n"):
        if not line.strip_edges().begins_with("#"):
            kept.append(line)
    return "\n".join(kept)


## The file split at each top-level `func`, so a name declared in one function is
## not read as the same name in another.
func _functions(code: String) -> Array[String]:
    var blocks: Array[String] = []
    var current: Array[String] = []
    for line in code.split("\n"):
        if line.begins_with("func ") or line.begins_with("static func "):
            blocks.append("\n".join(current))
            current = []
        current.append(line)
    blocks.append("\n".join(current))
    return blocks


## Numbered rule titles under the "hard rules" heading, as `"3. Sparse chunks"`.
## The number is part of the compared string, so renumbering one file without the
## other fails too.
func _rule_titles(text: String) -> Array[String]:
    var titles: Array[String] = []
    var numbered := RegEx.create_from_string("^(\\d+)\\.\\s+\\*\\*(.+?)\\*\\*")
    var inside := false
    for line in text.split("\n"):
        if line.begins_with("## "):
            inside = line.to_lower().contains("hard rules")
            continue
        if not inside:
            continue
        var found := numbered.search(line)
        if found != null:
            titles.append("%s. %s" % [found.get_string(1), found.get_string(2)])
    return titles


## A source copy leaves the agents' pages out, and the rule lists are read
## from them, so there is nothing to hold against each other there.
func _has_the_rule_pages() -> bool:
    return FileAccess.file_exists(_repo_path("docs/agents/ONBOARDING.md")) and FileAccess.file_exists(_repo_path("AGENTS.md"))


## The repository root is one level above `res://`: the maintainers' pages sit
## outside the Godot project, so they are reached by absolute path.
func _repo_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(relative).simplify_path()


func _source_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join(relative)


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
