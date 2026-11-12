## The New Module dialog: the name becomes a folder and an id, the starter is
## written into the user's modules folder, and a name already taken is refused.
extends "res://tests/test_framework.gd"

var _opened: Array[String] = []


func before_each() -> void:
    _opened.clear()
    NewModuleDialog.opener = func(path: String) -> void: _opened.append(path)


func after_each() -> void:
    NewModuleDialog.opener = OS.shell_open


func test_a_name_becomes_a_folder_with_hyphens_and_an_id_with_underscores() -> void:
    var dialog := NewModuleDialog.new()
    assert_eq(dialog._slug_and_id("perlin noise"), ["perlin-noise", "perlin_noise"], "Words join with a hyphen and an underscore")
    assert_eq(dialog._slug_and_id("  Box  Blur!! "), ["box-blur", "box_blur"], "Case, space and punctuation fold away")
    assert_eq(dialog._slug_and_id("3D blur"), ["3d-blur", "_3d_blur"], "An id never starts with a digit")
    assert_eq(dialog._slug_and_id(" !! "), ["", ""], "A name with no word in it is no name")
    assert_eq(dialog._slug_and_id("šum"), ["sum", "sum"], "Accented letters fold to base Latin letters")
    assert_eq(dialog._slug_and_id("čáp"), ["cap", "cap"], "Every Czech accent folds")
    assert_eq(dialog._slug_and_id("žluť"), ["zlut", "zlut"], "Even several in one word")
    dialog.free()


func test_create_with_diacritics_writes_starter_and_cyrillic_refuses() -> void:
    var dialog := NewModuleDialog.new()
    var slug := "sum"
    var dir_path := ModuleLoader.user_modules_path().path_join(slug)
    var file_path := dir_path.path_join("module.gd")
    DirAccess.remove_absolute(file_path)
    DirAccess.remove_absolute(dir_path)

    dialog._name_field.text = "šum"
    dialog._on_confirmed()
    assert_true(FileAccess.file_exists(file_path), "Create writes module.gd into the user's modules folder under sum")
    assert_true(FileAccess.get_file_as_string(file_path).contains('return &"sum"'), "with the id sum")
    assert_eq(_opened, [dir_path], "and shows the painter that folder, once")

    _opened.clear()
    dialog._name_field.text = "шум"
    dialog._on_confirmed()
    assert_true(dialog._status.visible, "A name of Cyrillic letters only still shows the refusal on the dialog")
    assert_true(dialog._status.text.contains("name"), "and asks for a name")
    assert_eq(_opened.size(), 0, "and nothing is opened")
    var cyrillic_dir := ModuleLoader.user_modules_path().path_join("шум")
    assert_false(DirAccess.dir_exists_absolute(cyrillic_dir), "and writes nothing on disk")

    DirAccess.remove_absolute(file_path)
    DirAccess.remove_absolute(dir_path)
    dialog.free()


func test_the_starter_carries_the_id_and_the_two_methods_the_loader_asks_for() -> void:
    var dialog := NewModuleDialog.new()
    var text := dialog._template("perlin_noise")
    assert_true(text.contains("extends SaModule"), "The starter is a module")
    assert_true(text.contains('return &"perlin_noise"'), "and answers its own id")
    assert_true(text.contains("func register(_ctx: SaContext) -> void:"), "with the register the base class declares")
    dialog.free()


func test_create_writes_the_starter_shows_the_folder_and_refuses_the_name_twice() -> void:
    var dialog := NewModuleDialog.new()
    var slug := "zz-new-module-suite"
    var dir_path := ModuleLoader.user_modules_path().path_join(slug)
    var file_path := dir_path.path_join("module.gd")
    DirAccess.remove_absolute(file_path)
    DirAccess.remove_absolute(dir_path)

    dialog._name_field.text = "zz new module suite"
    dialog._on_confirmed()
    assert_true(FileAccess.file_exists(file_path), "Create writes module.gd into the user's modules folder")
    assert_true(FileAccess.get_file_as_string(file_path).contains('return &"zz_new_module_suite"'), "with the id the name gives")
    assert_eq(_opened, [dir_path], "and shows the painter that folder, once")

    dialog._name_field.text = "zz new module suite"
    dialog._on_confirmed()
    assert_true(dialog._status.visible, "The same name again is refused on the dialog")
    assert_true(dialog._status.text.contains(slug), "and the refusal names the folder that exists")
    assert_eq(_opened.size(), 1, "with nothing opened a second time")

    dialog._name_field.text = "   "
    dialog._on_confirmed()
    assert_true(dialog._status.text.contains("name"), "An empty name asks for one")

    DirAccess.remove_absolute(file_path)
    DirAccess.remove_absolute(dir_path)
    dialog.free()
