## The Info docker's composite rows: the mean spans the
## easel's recent composites rather than the session, and the unit is written
## out so a mean of 75 microseconds cannot be read as 75 milliseconds again.
extends "res://tests/test_framework.gd"


func test_the_recent_mean_forgets_the_composites_older_than_its_window() -> void:
    var easel := SaEasel.new()
    var count := SaEasel.RECENT_COMPOSITES + 10
    for usec in range(count):
        easel._remember_recent(usec)
    assert_eq(easel.composite_usec_recent.size(), SaEasel.RECENT_COMPOSITES, "the ring holds its window and no more")
    var expected := 0
    for usec in range(10, count):
        expected += usec
    assert_eq(easel.composite_usec_recent_total, expected, "and its sum is the latest composites alone")
    easel.free()


func test_the_recent_mean_is_the_whole_ring_while_it_fills() -> void:
    var easel := SaEasel.new()
    easel._remember_recent(40)
    easel._remember_recent(80)
    assert_eq(easel.composite_usec_recent.size(), 2, "two composites are two samples")
    assert_eq(easel.composite_usec_recent_total, 120, "summed as they came")
    easel.free()


func test_the_row_says_how_many_composites_it_spans() -> void:
    assert_true(
        SaInfoSection.RECENT_MEAN.contains(str(SaEasel.RECENT_COMPOSITES)),
        "the row's name and the easel's window are the same number"
    )


func test_a_cost_is_written_in_microseconds_by_name() -> void:
    assert_eq(SaInfoSection.microseconds(75), "75 microseconds", "the unit is a word, never a fraction of a millisecond")
