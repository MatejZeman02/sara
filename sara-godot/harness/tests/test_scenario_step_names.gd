## Every step kind the scenario guide names is a step kind the
## executor answers to.
##
## The page said a scenario supported twenty-four named steps and named six more
## in its prose, while `SaCapture._run_step` answered to eighty-seven, and the
## word "supporting" in front of a closed list is what made it read as all of
## them. A scenario writer had no way to learn from that page that `bar_option`,
## `curve_option`, `symmetry`, `layout_preset` and fifty-odd others exist.
##
## The list is deliberately still partial, `scripts/sara_steps.py` being the
## catalogue and a hand-kept eighty-seven being stale by the morning. What this
## suite holds is the other half: a list allowed to be partial is not allowed to
## be wrong, so a name that stops being a step kind, or is typed wrong, fails a
## run rather than sending the next reader looking for a step that is not there.
##
## Read out of the two files rather than out of a table here, for the reason
## `sara_steps.py` gives about itself: a copy of either would be a third place to
## keep in step.
extends "res://tests/test_framework.gd"

## The paragraph the page keeps its short list in, found by its opening rather
## than by a line number.
const LIST_LEAD: String = "The common ones, which are what the rest of this page is about, are"

## Named in the page and read by the runner rather than by `_run_step`, so it is
## the one backticked name in that paragraph that is not a step kind (an
## `[width, height]` is an argument and is filtered by the same rule, having no
## backticks of its own to be mistaken for a key).
const NOT_A_STEP: Array[String] = ["args"]


func test_every_step_the_page_names_is_one_the_executor_answers_to() -> void:
    if not FileAccess.file_exists(_repo_path("docs/guides/SCENARIOS.md")):
        skip("the scenarios page is not in this copy of the source")
        return
    var named := _named_steps()
    var kinds := _executor_steps()

    assert_false(named.is_empty(), "The step list paragraph was not found in the scenario guide")
    assert_true(kinds.size() > 24, "Only %d step kinds parsed out of sa_step_table.gd, which cannot be right" % kinds.size())

    var strangers: Array[String] = []
    for name in named:
        if not kinds.has(name):
            strangers.append(name)
    assert_eq(strangers, [] as Array[String], "SCENARIOS.md names steps the executor does not answer to")


## The other half of the fix, and the half a later edit is likelier to undo: the
## page has to say where the whole catalogue is, or its short list reads as the
## whole of it again.
func test_the_page_points_at_the_catalogue() -> void:
    if not FileAccess.file_exists(_repo_path("docs/guides/SCENARIOS.md")):
        skip("the scenarios page is not in this copy of the source")
        return
    var page := _read(_repo_path("docs/guides/SCENARIOS.md"))
    assert_true(page.contains("scripts/sara_steps.py"), "SCENARIOS.md must name the step catalogue")
    assert_true(page.contains("The common ones"), "and must say its own list is the common ones rather than all of them")


## The backticked names of the page's short list, without the ones that are not
## step kinds.
func _named_steps() -> Array[String]:
    var page := _read(_repo_path("docs/guides/SCENARIOS.md"))
    var start := page.find(LIST_LEAD)
    if start < 0:
        return []
    var end := page.find("\n\n", start)
    var paragraph := page.substr(start, (end if end > start else page.length()) - start)
    var out: Array[String] = []
    for match in RegEx.create_from_string("`([a-z_]+)(?:`/`([a-z_]+))?`").search_all(paragraph):
        for i in range(1, match.get_group_count() + 1):
            var name := match.get_string(i)
            if name != "" and not NOT_A_STEP.has(name) and not out.has(name):
                out.append(name)
    return out


## Every key `SaCapture._run_step` branches on, which is what `sara_steps.py`
## parses and is parsed the same way here.
func _executor_steps() -> Array[String]:
    var source := _read(_source_path("harness/sa_step_table.gd"))
    var out: Array[String] = []
    for match in RegEx.create_from_string('step\\.has\\("([a-z_]+)"\\)').search_all(source):
        var name := match.get_string(1)
        if not out.has(name):
            out.append(name)
    return out


func _repo_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(relative).simplify_path()


func _source_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join(relative)


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    return file.get_as_text() if file != null else ""
