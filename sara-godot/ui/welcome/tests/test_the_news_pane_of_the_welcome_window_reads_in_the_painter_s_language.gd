## The News pane of the welcome window reads in the painter's
## language.
##
## Under Czech the pane's title and button read Czech and its paragraph, the
## open section's heading and the release notes read English, because the
## paragraph was joined once in `_init`, before the boot registers the Czech
## catalogue, and the notes were the English file alone. This suite registers
## the Czech module's own catalogue, builds the pane, reads the paragraph, the
## first section's heading and its first line in Czech, then switches to
## English and reads all three in English.
##
## The pane is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives, so a change of language is delivered to it by
## hand as the notification the tree would send. The notes are the checkout's
## own `CHANGELOG.md` and the Czech module's beside its catalogue, so the lines
## expected are read from those two files rather than written out here.
extends "res://tests/test_framework.gd"

## The Czech module's catalogue, which its `module.gd` registers.
const CATALOGUE: String = "res://modules/sara-language-cs/cs.po"

## The four sentences of the feedback request in `cs.po`, the last with the address in it.
const CZECH_ASK: Array[String] = [
    "Zapsat poznámku, v nabídce Nápověda, otevře nad plátnem záznamník poznámek.",
    "Jeho tlačítko Exportovat zapíše poznámky a obrázky tohoto sezení do zipu a řekne vám cestu.",
    "Zip obsahuje i vlastní log Sary z tohoto sezení a z toho předchozího, což ukazuje pád.",
    "Pošlete ten zip na %s, aby to, co jste našli, došlo k lidem, kteří to čtou.",
]

## The same four in English, the source text.
const ENGLISH_ASK: Array[String] = [
    "Take a Note, under Help, opens the note recorder over the canvas.",
    "Its Export button writes this session's notes and pictures into a zip and tells you the path.",
    "The zip also holds Sara's own log of this session and the one before it, which is what shows a crash.",
    "Send that zip to %s so what you found reaches the people who read it.",
]

## The locale the run had, put back after each test.
var _locale: String = ""

## The registry each test registers the Czech catalogue into, dropped after it
## so the catalogue leaves `TranslationServer` with it.
var _registry: SaTranslationRegistry = null


func before_each() -> void:
    _locale = TranslationServer.get_locale()
    _registry = SaTranslationRegistry.new()


func after_each() -> void:
    TranslationServer.set_locale(_locale)
    _registry = null


## The note's first clause: Czech set, the pane built, and its paragraph, the
## open section's heading and a section's first line read Czech. Then English,
## and all three read English.
func test_czech_reads_czech_and_english_reads_english_again() -> void:
    assert_true(_registry.register(CATALOGUE, &"language-cs"), "the Czech module's catalogue registers")
    TranslationServer.set_locale("cs")
    var pane := WelcomeNewsPane.new()
    pane.follow_catalogues(_registry)

    var notes := SaChangelog.notes_path(_registry, "cs")
    assert_eq(notes, "res://modules/sara-language-cs/RELEASE-NOTES.md", "the notes are the file beside the catalogue")
    assert_eq(pane.report()["notes"], notes, "and the pane's report names them")
    assert_eq(_paragraph(pane), _joined(CZECH_ASK), "the paragraph is the four Czech sentences joined")
    assert_eq(pane.heading("Unreleased"), "Nevydáno", "the open section's heading is Czech")
    _assert_first_section(pane, "cs", notes)

    TranslationServer.set_locale("en_GB")
    pane.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
    assert_eq(pane.report()["notes"], "", "under English no module's notes are read")
    assert_eq(_paragraph(pane), _joined(ENGLISH_ASK), "the paragraph reads English again")
    assert_eq(pane.heading("Unreleased"), "Unreleased", "and so does the open section's heading")
    _assert_first_section(pane, "en_GB", "")
    pane.free()


## The boot's order, which is what left the paragraph English: the window is
## built under Czech before the module registers its catalogue. The catalogue
## coming is what redraws the pane, with no switch of language after it.
func test_a_catalogue_registered_after_the_pane_was_built_redraws_it() -> void:
    TranslationServer.set_locale("cs")
    var pane := WelcomeNewsPane.new()
    pane.follow_catalogues(_registry)
    assert_eq(_paragraph(pane), _joined(ENGLISH_ASK), "with no catalogue yet the paragraph is the source text")

    assert_true(_registry.register(CATALOGUE, &"language-cs"), "the module registers its catalogue")
    assert_eq(_paragraph(pane), _joined(CZECH_ASK), "and the pane reads Czech at once")
    _assert_first_section(pane, "cs", "res://modules/sara-language-cs/RELEASE-NOTES.md")
    pane.free()


## The reader's half of the fallback: a section the module's file has line for
## line is its own, one it lacks or has with another count of lines stays
## English, and a section only the module's file has is never added.
func test_a_section_the_notes_lack_or_carry_short_stays_english() -> void:
    var english := SaChangelog.parse("## 0.2.0\n\nTwo.\nTwo more.\n\n## 0.1.0\n\nOne.\n\n## 0.0.1\n\nZero.\n")
    var czech := SaChangelog.parse(
        "## 0.2.0\n\n<!-- machine draft, not reviewed -->\nDvě.\n\n## 0.1.0\n\nJedna.\n\n## 9.0.0\n\nNikdy.\n"
    )
    var mixed := SaChangelog.localised(english, czech)
    var versions := mixed.map(func(s: Dictionary) -> String: return s["version"])
    assert_eq(versions, ["0.2.0", "0.1.0", "0.0.1"], "the English list of releases")
    assert_eq(mixed[0]["lines"], PackedStringArray(["Two.", "Two more."]), "a section short of a line stays English")
    assert_eq(mixed[1]["lines"], PackedStringArray(["Jedna."]), "a section carried line for line is the module's")
    assert_eq(mixed[2]["lines"], PackedStringArray(["Zero."]), "and one the module lacks stays English")
    assert_eq(english[1]["lines"], PackedStringArray(["One."]), "the parsed English is never written over")


## Every section of the Czech notes is one the English file has, with as many
## lines, so none of them falls back to English as the module ships today.
func test_the_czech_notes_carry_every_english_section_line_for_line() -> void:
    var english := SaChangelog.read()
    if english["source"] == "none":
        assert_true(true, "a build with no changelog has no notes to compare")
        return
    var czech := SaChangelog.parse(FileAccess.get_file_as_string("res://modules/sara-language-cs/RELEASE-NOTES.md"))
    var by_version := {}
    for section: Dictionary in czech:
        by_version[section["version"]] = section
    for section: Dictionary in english["sections"]:
        var version := str(section["version"])
        assert_true(by_version.has(version), "the Czech notes have %s" % version)
        if by_version.has(version):
            var theirs: PackedStringArray = by_version[version]["lines"]
            var ours: PackedStringArray = section["lines"]
            assert_eq(theirs.size(), ours.size(), "and as many lines in it")


## The first section drawn: its heading as the pane writes it, and its first
## line, which is the notes' line under *locale* and the English one otherwise.
func _assert_first_section(pane: WelcomeNewsPane, locale: String, notes: String) -> void:
    var shown: Array = pane.report()["sections"]
    var drawn := _sections(pane)
    assert_false(shown.is_empty(), "the pane shows a section")
    assert_false(drawn.is_empty(), "and draws it")
    if shown.is_empty() or drawn.is_empty():
        return
    var version := str(shown[0])
    var heading := drawn[0].find_child("Heading", true, false) as Label
    var rows := drawn[0].find_child("Rows", true, false)
    assert_not_null(heading, "the section has its heading")
    if heading != null:
        var word := ("Nevydáno" if locale == "cs" else "Unreleased") if SaChangelog.is_open(version) else version
        assert_eq(heading.text, word, "the heading under %s" % locale)
    var source := SaChangelog.read()
    var expected_sections: Array = source["sections"]
    if notes != "":
        expected_sections = SaChangelog.localised(expected_sections, SaChangelog.parse(FileAccess.get_file_as_string(notes)))
    for section: Dictionary in expected_sections:
        if str(section["version"]) == version and rows != null and rows.get_child_count() > 0:
            var first := (section["lines"] as PackedStringArray)[0]
            assert_eq((rows.get_child(0) as Label).text, first, "the section's first line under %s" % locale)
            if notes != "":
                assert_false(first == (_english_lines(source, version))[0], "and it is not the English line")


func _english_lines(source: Dictionary, version: String) -> PackedStringArray:
    for section: Dictionary in source["sections"]:
        if str(section["version"]) == version:
            return section["lines"]
    return PackedStringArray()


func _sections(pane: WelcomeNewsPane) -> Array[Node]:
    var column := pane.find_child("NewsSections", true, false)
    var out: Array[Node] = []
    if column == null:
        return out
    for child in column.get_children():
        if child.name.begins_with("Section"):
            out.append(child)
    return out


func _paragraph(pane: WelcomeNewsPane) -> String:
    var label := pane.find_child(WelcomeNewsPane.ASK_PARAGRAPH, true, false) as Label
    return label.text if label != null else ""


func _joined(sentences: Array[String]) -> String:
    var out := sentences.duplicate()
    out[3] = out[3] % SaHelpMenu.REPORT_URL
    return " ".join(out)
