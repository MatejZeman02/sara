## Select Subject's tool shows the drawing of its icon,
## a person inside a dashed selection frame, the same bytes Sara's icon
## folder carries under `select_subject.svg`.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")

const SET_COPY := "res://assets/icons/select_subject.svg"


func test_the_tools_icon_is_the_review_s_drawing() -> void:
    assert_not_null(SaUI.get_icon(SubjectModule.ICON), "The tool's icon loads")
    var own := FileAccess.get_file_as_string(SubjectModule.ICON)
    assert_eq(own, FileAccess.get_file_as_string(SET_COPY), "and is the drawing the icon folder carries")
    assert_true(own.contains('viewBox="0 0 16 16"') and own.contains('fill="#e0e0e0"'), "on the set's grid in its one fill")
