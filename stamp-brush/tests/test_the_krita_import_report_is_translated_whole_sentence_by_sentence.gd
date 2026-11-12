## Every sentence the Krita import report shows goes through the catalogue.
##
## The report was English whatever language Sara was in, its lines built from
## the importer's phrases. A catalogue that marks every message it is asked
## for, as the test language does, stands in for a language: a line is right
## when every piece of it is marked, and the plain English of the same line is
## unchanged when no catalogue is installed.
extends "res://tests/test_framework.gd"

const LOCALE := "eo"

## The phrases the importer stores in `not_carried`, one of each shape, and the
## English each reads as with no catalogue.
const REASONS := [
    "masking brush",
    "masking tip",
    "masking size in pixels",
    "image tip",
    "painting mode",
    "texturing mode",
    "colour source",
    "colour gradient",
    "mask softness curve",
    "mask softness curve, it does not descend",
    "masking dynamics: Size",
    "masking composite op erase",
    "pipe selection mode velocity",
    "pipe tip: a.gih is empty.",
    "tip: a.gbr could not be read.",
    "blend mode dodge",
    "pattern pat",
]


## A catalogue of one locale that marks every message and plural form it is
## asked for, and so reads as the test language does.
class Marking:
    extends Translation

    func _get_message(src_message: StringName, _context: StringName) -> StringName:
        return StringName("‹%s›" % src_message)

    func _get_plural_message(src_message: StringName, src_plural_message: StringName, n: int, _context: StringName) -> StringName:
        return StringName("‹%s›" % (src_message if n == 1 else src_plural_message))


var _catalogue: Translation
var _locale_before := ""


func before_each() -> void:
    _locale_before = TranslationServer.get_locale()
    _catalogue = Marking.new()
    _catalogue.locale = LOCALE


func after_each() -> void:
    TranslationServer.set_locale(_locale_before)
    TranslationServer.remove_translation(_catalogue)


func _in_the_marking_language() -> void:
    TranslationServer.add_translation(_catalogue)
    TranslationServer.set_locale(LOCALE)


func _results() -> Array[Dictionary]:
    return [
        {"source": "a.kpp", "error": "a.kpp is not a PNG, and a .kpp is one."},
        {"source": "b.kpp", "kept": "Brush b"},
        {
            "source": "c.kpp",
            "name": "Brush c",
            "not_carried": REASONS.duplicate(),
            "unread": ["Some/Key"],
            "notes": [SaKppImport.GRADIENT_FROM_THE_PAINTER],
            "pressure": "Krita's pressure curve read as linear",
        },
        {"source": "d.kpp", "name": "Brush d", "replaced": true, "not_carried": [], "unread": []},
        {"source": "e.bundle", "tips": 2, "tips_skipped": ["x.gbr", "y.gbr"]},
        {"source": "f.bundle", "tips": 1},
    ]


## Strips every marked piece, innermost first, and what is left is the text no
## catalogue entry covers, apart from the commas between pieces.
func _what_no_mark_covers(body: String) -> String:
    var marked := RegEx.create_from_string("‹[^‹›]*›")
    var rest := body
    while marked.search(rest) != null:
        rest = marked.sub(rest, "", true)
    return rest.replace(",", "").strip_edges()


func test_every_phrase_of_a_line_is_marked_in_another_language() -> void:
    _in_the_marking_language()
    for result in _results():
        var line := SaKppImport.describe(result)
        assert_true(line.begins_with("SaKppImport: "), "the log tag stays, which the page takes off: '%s'" % line)
        assert_eq(_what_no_mark_covers(line.trim_prefix("SaKppImport: ")), "", "every piece of '%s' is marked" % line)
    var imported := SaKppImport.describe(_results()[2])
    for reason: String in REASONS:
        var marked := SaKppReport.reason(reason)
        assert_true(marked.begins_with("‹"), "'%s' is marked, read '%s'" % [reason, marked])
        assert_true(imported.contains(marked), "and the line carries it")
    assert_true(
        SaKppImport.describe(_results()[4]).contains(
            "‹%s holds no preset, %d brush tips into the tip list›".replace("%s", "e.bundle").replace("%d", "2")
        ),
        "the plural form is the catalogue's"
    )


func test_the_english_of_every_line_is_as_it_was() -> void:
    var results := _results()
    assert_eq(
        SaKppImport.describe(results[0]),
        "SaKppImport: a.kpp refused: a.kpp is not a PNG, and a .kpp is one.",
        "a refusal reads as it did"
    )
    assert_eq(SaKppImport.describe(results[1]), "SaKppImport: b.kpp kept 'Brush b', already in the presets", "a kept preset")
    assert_true(SaKppImport.describe(results[1]).ends_with(SaKppImport.KEPT_PHRASE), "ends as the constant says")
    assert_eq(
        SaKppImport.describe(results[2]),
        (
            "SaKppImport: c.kpp imported as 'Brush c', not carried: "
            + ", ".join(REASONS)
            + ", read by no row: Some/Key, "
            + SaKppImport.GRADIENT_FROM_THE_PAINTER
            + ", under Krita's pressure curve read as linear"
        ),
        "an imported preset reads as it did"
    )
    assert_eq(SaKppImport.describe(results[3]), "SaKppImport: d.kpp replaced 'Brush d', not carried: nothing", "a replaced one")
    assert_eq(
        SaKppImport.describe(results[4]),
        "SaKppImport: e.bundle holds no preset, 2 brush tips into the tip list, passed over: x.gbr, y.gbr",
        "a bundle of tips names the ones passed over"
    )
    assert_eq(SaKppImport.describe(results[5]), "SaKppImport: f.bundle holds no preset, 1 brush tip into the tip list", "one tip")
