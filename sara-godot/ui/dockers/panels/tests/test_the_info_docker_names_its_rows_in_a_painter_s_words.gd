## The Info docker's rows above its fold say what they measure
## in a painter's words, and the fold that holds the engine's counters is named
## for what it is.
##
## A wording sweep read "VRAM all",
## "Chunks", "Declared", "Transfer", "FG value" and "FG stops" on a docker every
## painter can open. The keys stay, being what a dump and `sara_replay.py` read,
## and `InfoDocker.ROW_TITLES` gives each its shown words.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

## Words a measure is named by in the engine, which no row above the fold
## shows.
const CODE_WORDS: Array[String] = ["vram", "chunk", "declared", "transfer", " value", "texel"]


func _docker() -> InfoDocker:
    var docker: InfoDocker = DOCKER.new()
    docker.name = "InfoDockerUnderTest"
    return docker


func _shown_name(docker: InfoDocker, section: String, key: String) -> String:
    return (docker._section_boxes[section].rows[key][0] as Label).text


func test_no_row_above_the_fold_is_named_in_the_engine_s_words() -> void:
    var docker := _docker()
    var read := 0
    for entry: Array in InfoDocker.SECTIONS:
        var section: String = entry[0]
        if InfoDocker.PERFORMANCE_SECTIONS.has(section):
            continue
        for key: String in entry[1]:
            var shown := _shown_name(docker, section, key).to_lower()
            read += 1
            for word: String in CODE_WORDS:
                assert_false(shown.contains(word), "'%s / %s' reads '%s', no '%s'" % [section, key, shown, word.strip_edges()])
    assert_eq(read, 29, "every row of the four sections above the fold was read")
    docker.free()


func test_the_renamed_rows_read_as_the_sweep_proposed() -> void:
    var docker := _docker()
    assert_eq(_shown_name(docker, "Document", "VRAM"), "GPU memory, budget used", "the document's own and its budget share")
    assert_eq(_shown_name(docker, "Document", "VRAM all"), "All documents, budget used", "and every document's")
    assert_eq(_shown_name(docker, "Document", "Tiles"), "Tiles", "the stored pieces are tiles")
    assert_eq(_shown_name(docker, "Colour space", "Transfer"), "Tone curve", "the word New document uses")
    assert_eq(_shown_name(docker, "Selected colours", "FG value"), "FG RGB", "the three channels say which three")
    assert_eq(_shown_name(docker, "Selected colours", "BG stops"), "BG stops over white", "and the stops say over what")
    docker.free()


func test_the_fold_is_diagnostics_and_a_development_build_says_so() -> void:
    var docker := _docker()
    assert_eq(docker.performance_fold.title, "Diagnostics", "the fold holds the build, the pointer and the counters")
    docker._section_boxes["Build"]._build_rows(
        {"version": "0.11.0", "commit": "ae1b0fa", "built": "", "dirty": false, "source": SaBuildInfo.SOURCE_WORKING_TREE}
    )
    var commit := (docker._section_boxes["Build"].rows["Commit"][1] as Label).text
    assert_eq(commit, "ae1b0fa, development build", "an editor run is a development build")
    assert_false(commit.contains("working tree"), "in no word of git's")
    docker.free()
