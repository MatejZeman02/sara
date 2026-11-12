## Preferences > Presets: bring Krita's presets in, and read what arrived.
## Declared onto the page layer.
##
## Here rather than on the Brush Presets docker, because an import is rare and
## its report is long: a painter who imports a bundle of forty presets is told
## the count and which ones were refused, and a page has room for both.
##
## The importer itself is a module's, reached through the `preset_import` role
## the way the door's own step reaches it, so the button and the scenario cannot
## import differently. With no module registering that role the page says so
## rather than failing quietly.
##
## Import is an action row whose title is not its button's words, and the
## summary and the scroll are two spanning custom rows: neither has a label of
## its own, so each keeps the width it was handed over with rather than the
## label column beside it.
class_name SaBrushPresetsPage
extends SaSettingsPage

## The last import's lines, one per preset, and the three counts over them.
##
## Public because the dump and the test read them, and written by this class
## alone: an import through the button and an import through the door both land
## in [method import_path].
var report_lines: PackedStringArray = PackedStringArray()
var imported: int = 0
var refused: int = 0
var kept: int = 0

## The file the last import read, which the offer to replace reads again.
var last_path: String = ""

var _summary: Label = null
var _empty: Label = null
var _replace: Button = null
var _report: Label = null


func build(ui: SaPage) -> void:
    var rows := ui.section("Krita presets")
    (
        rows
        . action("Import", _on_import_pressed)
        . button("Import Krita presets...")
        . node("PresetsImportButton")
        . explain(tr("Reads a .kpp file or a .bundle. What a preset does not carry into Sara becomes a tag on it."))
        # A plain Button's own words are not walked by the search
        # (`SaSettingsSearch.row_haystack` reads a choice list's labels, not a
        # button's text), so "Krita" is only findable through this.
        . words("Krita")
    )

    _summary = SaMake.label(null, "PresetsImportSummary")
    _summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaSettingsRows.embolden(_summary)
    # Before any import the line says only that nothing happened, which is a
    # hint and not a finding, so it is drawn dimmed and small in a label of its
    # own rather than in the summary's bold.
    _empty = SaSettingsRows.hint_label(tr("Nothing imported yet."))
    _empty.name = "PresetsImportEmpty"
    # The offer to replace sits on the summary's line and shows only while the
    # last import left a preset alone, so a page with nothing to offer shows no
    # trace of it.
    _replace = SaMake.button(null, "PresetsImportReplace", tr("Replace them"))
    _replace.tooltip_text = tr(
        (
            "Imports the file again over the presets of the same name, with their settings and their tags afresh."
            + " A preset you saved under another name is kept."
        )
    )
    _replace.pressed.connect(replace_held)
    var line := HBoxContainer.new()
    line.name = "PresetsImportSummaryLine"
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.add_child(_empty)
    line.add_child(_summary)
    line.add_child(_replace)
    rows.custom("", line).named(&"summary")

    # In a scroll of its own, because a bundle is forty lines and a page that
    # grows with what was imported pushes every section under it off the window.
    var scroll := SaMake.scroll(null, "PresetsImportScroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.custom_minimum_size = Vector2(0.0, float(SaUI.px(160)))

    _report = SaSettingsRows.hint_label("")
    _report.name = "PresetsImportReport"
    scroll.add_child(_report)
    rows.custom("", scroll).named(&"report")

    _show_report()


## Asks for a `.kpp` or a `.bundle` and imports it.
##
## The platform's own picker, because the file is anywhere on the disk.
func _on_import_pressed() -> void:
    var filters := PackedStringArray(
        [tr("*.kpp, *.bundle ; Krita presets"), tr("*.kpp ; Krita preset"), tr("*.bundle ; Krita bundle")]
    )
    SaFilePicker.open(self, SaFilePicker.Mode.OPEN_FILE, filters, import_path, tr("Import Krita Presets"))


## Imports *path* through the `preset_import` role and shows what it answered.
##
## The one way in, so the button and the door leave the same page behind. The
## role's answer is its console report, several lines with a log prefix on each,
## and the page keeps the sentences and drops the prefixes.
##
## **A preset already held is left alone first and offered after**. A bundle
## imported with an older importer holds presets that lost what the importer
## carries now. Importing the same file again leaves every preset the store
## holds as it is, counts it as kept, and shows "Replace them" beside the count,
## which is [method replace_held]. Asking before the import would read the file
## twice for one press, and a painter reading the report sees which presets the
## offer is about.
func import_path(path: String, report_dir: String = "", replace: bool = false) -> void:
    last_path = path
    imported = 0
    refused = 0
    kept = 0
    var script := _import_script()
    if script == null:
        report_lines = PackedStringArray([tr("No module registers the preset importer, so nothing can be read.")])
        _show_report()
        return

    # The role is handed the tree and the folder its report goes in, empty for a
    # painter's own press. It answers the counts itself, so no English phrase in
    # a line is what the page counts by.
    var answer: Dictionary = script.call("report", get_tree(), report_dir, path, replace)
    report_lines = PackedStringArray()
    for raw: String in answer.get("lines", PackedStringArray()):
        report_lines.append(_without_prefix(raw))
    imported = int(answer.get("imported", 0))
    refused = int(answer.get("refused", 0))
    kept = int(answer.get("kept", 0))
    _show_report()


## Imports the last file again over the presets it left alone, the offer the
## summary line makes. The presets it had just written are written again,
## which changes nothing, and the report is the second import's.
func replace_held() -> void:
    if last_path.is_empty():
        return
    import_path(last_path, "", true)


## The sentence over the list, in the painter's terms rather than the log's.
func _show_report() -> void:
    if _summary == null or _report == null:
        return
    _replace.visible = kept > 0
    _empty.visible = report_lines.is_empty()
    _summary.visible = not report_lines.is_empty()
    if report_lines.is_empty():
        _summary.text = ""
        _report.text = ""
        return
    # Each count through its own plural form, since one sentence carrying three
    # numbers has no single count a language could pick a form by.
    var parts := PackedStringArray(
        [
            tr_n("%d imported", "%d imported", imported) % imported,
            tr_n("%d could not be read", "%d could not be read", refused) % refused,
        ]
    )
    if kept > 0:
        parts.append(tr_n("%d already present", "%d already present", kept) % kept)
    _summary.text = ", ".join(parts) + "."
    _report.text = "\n".join(report_lines)


## *line* with the log tag its writer put in front of the sentence taken off.
##
## The importer is a module's and prefixes every line with its own class name,
## the way the capture runner prefixes its own. Matched as a shape, one
## identifier and a colon, rather than by name: naming the module's class here
## would put a module identifier in the skeleton, which
## `tests/test_the_skeleton_without_modules.gd` refuses and rightly, because
## the page has to read whatever module registers the role. A sentence's own
## colon survives, "x.kpp refused: no tip" having no identifier in front of it.
func _without_prefix(line: String) -> String:
    var out := line.strip_edges()
    var mark := out.find(": ")
    if mark <= 0:
        return out
    return out.substr(mark + 2) if out.substr(0, mark).is_valid_identifier() else out


## The module's importer, or null when no module registers the role.
func _import_script() -> Script:
    var main := get_tree().current_scene if get_tree() != null else null
    var registries: Variant = main.get("registries") if main != null else null
    var roles: Variant = (registries as Object).get("roles") if registries != null else null
    return roles.script_for(&"preset_import") if roles != null else null


## Imports on the Brushes page: `{"preset_page": {"import": "<path>"}}`, and
## `{"preset_page": {"replace": true}}` presses the offer it may leave.
##
## Through the page rather than through the module's own `preset_import` step,
## because what matters is what the *page* shows: the count and the refusals on
## screen, which the module's step leaves in the run log.
static func capture_import(tree: SceneTree, spec: Dictionary, out_dir: String = "") -> String:
    var found: SaBrushPresetsPage = null
    for node in tree.root.find_children("*", "SaBrushPresetsPage", true, false):
        if not node.is_queued_for_deletion():
            found = node as SaBrushPresetsPage
            break
    if found == null:
        return "SaCapture: Preferences is not open on the Brush Presets page"
    if spec.get("replace", false):
        found.replace_held()
        return "SaCapture: preset_page replaced from %s, %d in, %d refused" % [found.last_path, found.imported, found.refused]
    if not spec.has("import"):
        return 'SaCapture: preset_page takes {"import": "<path>"} or {"replace": true}'
    var path := String(spec["import"])
    if path.begins_with("~/"):
        path = OS.get_environment("HOME").path_join(path.substr(2))
    found.import_path(path, out_dir)
    return (
        "SaCapture: preset_page imported %s, %d in, %d refused, %d kept"
        % [spec["import"], found.imported, found.refused, found.kept]
    )


## What the page shows, for the dump.
static func capture_state(root: Window) -> Dictionary:
    for node in root.find_children("*", "SaBrushPresetsPage", true, false):
        var found := node as SaBrushPresetsPage
        if found == null or node.is_queued_for_deletion():
            continue
        return {
            "summary": found._summary.text if found._summary.visible else found._empty.text,
            "imported": found.imported,
            "refused": found.refused,
            "kept": found.kept,
            "offers_replace": found._replace.visible,
            "lines": Array(found.report_lines),
            "has_import_button": found.find_child("PresetsImportButton", true, false) != null,
        }
    return {}
