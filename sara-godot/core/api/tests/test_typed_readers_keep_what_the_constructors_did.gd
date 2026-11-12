## SaTyped's readers stand where `int()`, `float()` and `String()` were handed
## a Variant, so each one answers what the constructor answered for a value it
## accepted, and the fallback where the constructor would have stopped the run.
extends "res://tests/test_framework.gd"


func test_a_json_float_reads_as_the_int_it_holds() -> void:
    assert_eq(SaTyped.whole(3.0), 3, "JSON hands 3 back as 3.0")
    assert_eq(SaTyped.whole(2.9), 2, "truncated as int() truncates")
    assert_eq(SaTyped.whole(true), 1, "a bool is a number to int()")


func test_text_is_parsed_the_way_the_constructor_parsed_it() -> void:
    # An ORA offset is an XML attribute, which is always text.
    assert_eq(SaTyped.whole("12"), 12, "int() parses text")
    assert_eq(SaTyped.whole(&"-4"), -4, "a StringName reads as its text")
    assert_almost_eq(SaTyped.real("0.25"), 0.25, 0.0001, "float() parses text")
    assert_eq(SaTyped.int_at({"x": "7"}, "x", 0), 7, "an attribute read at its key")
    assert_eq(SaTyped.whole("much", 3), 3, "text that spells no number falls back")
    assert_almost_eq(SaTyped.real("much", 0.5), 0.5, 0.0001, "for a float as well")


func test_anything_else_falls_back() -> void:
    assert_eq(SaTyped.whole(null, 5), 5, "a missing value")
    assert_eq(SaTyped.whole([1], 5), 5, "an Array is no number")
    assert_almost_eq(SaTyped.real(Vector2.ONE, 0.5), 0.5, 0.0001, "a vector is no number")
    assert_eq(SaTyped.int_at({}, "x", 9), 9, "an absent key")
    assert_eq(SaTyped.flag("yes", true), true, "bool() takes no text")
    assert_eq(SaTyped.flag(0.0, true), false, "nought is false")


func test_text_reads_only_text() -> void:
    assert_eq(SaTyped.text(&"soft"), "soft", "a StringName comes back as its String")
    assert_eq(SaTyped.text(5, "none"), "none", "String() takes no number")
    assert_eq(SaTyped.name_at({"id": "mask"}, "id", &""), &"mask", "a name read at its key")
    assert_eq(SaTyped.list({"a": 1}), [], "a Dictionary is no list")
