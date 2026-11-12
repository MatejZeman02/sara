## The pairing the transform proof is graded on: each transform row reads its
## own field of the `transform` block.
##
## `scenarios/transform.json` rerun from a deleted profile puts all six rows
## beside the block in dumps 04, 07, 09 and 11, and every one agrees to within a
## hundredth. That agreement is what the proof rests on, and it is only
## meaningful while the rows and the fields line up the way the record says they
## do.
##
## **This suite exists because the pairing is the fragile half.** Both numbers
## come from the same tool, so a rename on either side leaves a rerun that still
## agrees and a record naming rows nobody can find. Row six is the case in point:
## the row is called Shear, its property is `shear_degrees`, and the dump's field
## is `skew_degrees`. Three names for one angle, and the record quotes two of
## them.
extends "res://tests/test_framework.gd"

# The file the transform's rows are declared in.
const BASE_MODULE := "res://modules/sara-base-modules/base/sa_transform_options.gd"
# The `transform` block is written by the tool it is about, because the state
# report merges what each registered tool answers rather than reading the active
# one by method name. This suite reads the file the block is in, which is the
# transform tool's own.
const CAPTURE_DUMP := "res://modules/sara-base-modules/base/transform/state_transform.gd"


## The six rows the record names are still declared, under the keys it uses.
##
## Read out of the module's source rather than off a built descriptor, because
## the descriptor needs every module loaded and this has to be a cheap check that
## fails in the gate rather than a second copy of the loader.
func test_the_six_transform_rows_are_still_declared_under_the_keys_the_record_uses() -> void:
    var source := FileAccess.get_file_as_string(BASE_MODULE)
    assert_false(source.is_empty(), "The base module is readable")
    # Four of the six are built over an axis list, so their keys never appear as
    # a literal. The prefix and the pair of axes are what there is to pin, and
    # pinning the literal instead is how this method failed the first time it
    # ran.
    for built: String in ["transform_move_%s", "transform_scale_%s"]:
        assert_true(source.contains(built), "The %s pair is still built over the axes" % built)
    for key: String in ["transform_angle", "transform_shear"]:
        assert_true(source.contains('&"%s"' % key), "The %s row is still declared by name" % key)


## The four fields those rows are read against are still what the dump publishes.
##
## `offset`, `scale`, `degrees` and `skew_degrees` are the names a proof reads
## out of dumps 04, 07, 09 and 11. A rename here makes a record name fields a
## reader cannot find.
func test_the_transform_block_still_publishes_the_fields_the_record_quotes() -> void:
    var source := FileAccess.get_file_as_string(CAPTURE_DUMP)
    assert_false(source.is_empty(), "The capture dump is readable")
    for field: String in ['"offset"', '"scale"', '"degrees"', '"skew_degrees"']:
        assert_true(source.contains(field), "The transform block still publishes %s" % field)

    # The one that costs a reader a minute: the Shear row's property and the
    # block's field are different words for the same angle, so a search for
    # either finds only half the pair.
    assert_true(source.contains("move_skew()"), "and the shear field is read off the tool's own `move_skew`")
    var module := FileAccess.get_file_as_string(BASE_MODULE)
    assert_true(module.contains("shear_degrees"), "while the row writes `shear_degrees`")
