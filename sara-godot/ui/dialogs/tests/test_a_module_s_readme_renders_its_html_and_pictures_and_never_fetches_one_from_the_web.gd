## The Modules window draws a module's README with the
## manual's renderer, `SaMarkdown`, and reads HTML only as far as a GitHub
## README writes it.
##
## A README is written into a folder of its own with a picture beside it, read
## the way the window reads one, and what each tag became is found in the text
## a painter sees: `<img>` with its width, `<br>`, `<p align="center">` and
## `<details>` with its `<summary>` are drawn or dropped, any other tag stays
## as its text, a picture in the folder is drawn, one on the web is never
## fetched and shows its alt text and address, and one outside the folder is
## named as a problem. The window itself on three modules' pages is
## `scenarios/the-modules-window-shows-each-module-s-page-its-readme-with-pictures.json`.
extends "res://tests/test_framework.gd"

const WEB := "https://example.org/shot.png"

## Every tag the subset reads, one line each, and one it does not.
const README := """# A module

<p align="center">
<img src="pictures/dot.png" width="40" alt="A dot">
</p>

One line<br>and the next.

<details>
<summary>More</summary>

Folded text.
</details>

Press <kbd>B</kbd> for the brush.

![The dot again](pictures/dot.png)

<img src="%s" alt="A shot on the web">

![Outside](../dot.png)
"""


func _folder() -> String:
    var folder := OS.get_temp_dir().path_join("sara-%d" % Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(folder.path_join("pictures"))
    var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.8, 0.2, 0.1))
    image.save_png(folder.path_join("pictures/dot.png"))
    return folder


func _remove(folder: String) -> void:
    DirAccess.remove_absolute(folder.path_join("pictures/dot.png"))
    DirAccess.remove_absolute(folder.path_join("pictures"))
    DirAccess.remove_absolute(folder)


func _parsed(bbcode: String) -> String:
    var label := RichTextLabel.new()
    label.bbcode_enabled = true
    label.text = bbcode
    var text := label.get_parsed_text()
    label.free()
    return text


func test_each_supported_tag_is_drawn_or_dropped_and_any_other_stays_as_text() -> void:
    var folder := _folder()
    var markdown := SaMarkdown.new(folder, 600, false)
    var bbcode := markdown.to_bbcode(README % WEB)
    var seen := _parsed(bbcode)
    assert_eq(markdown.tags.get("img"), SaMarkdown.RENDERED, "<img> is drawn")
    assert_eq(markdown.tags.get("p"), SaMarkdown.RENDERED, "<p align=center> centres what it holds")
    assert_eq(markdown.tags.get("br"), SaMarkdown.RENDERED, "<br> breaks the line")
    assert_eq(markdown.tags.get("details"), SaMarkdown.DROPPED, "<details> is dropped, its body shown")
    assert_eq(markdown.tags.get("summary"), SaMarkdown.RENDERED, "<summary> becomes a bold line")
    assert_eq(markdown.tags.get("kbd"), SaMarkdown.AS_TEXT, "and <kbd>, which the subset does not read, stays as text")
    assert_true(
        bbcode.contains("[center][img width=40]%s[/img]" % folder.path_join("pictures/dot.png")),
        "the centred <img> is drawn 40 wide: %s" % bbcode
    )
    assert_true(seen.contains("One line\nand the next."), "the <br> is a line break")
    assert_true(bbcode.contains("[b]More[/b]"), "the summary is bold")
    assert_true(seen.contains("Folded text."), "the fold's body shows")
    assert_true(seen.contains("Press <kbd>B</kbd> for the brush."), "the unread tag is shown as it was written")
    for tag: String in ["<p", "</p>", "<img", "<br", "<details>", "</details>", "<summary>", "</summary>"]:
        assert_false(seen.contains(tag), "no %s is left for the painter to read" % tag)
    _remove(folder)


func test_a_picture_in_the_folder_is_drawn_and_one_on_the_web_is_never_fetched() -> void:
    var folder := _folder()
    var markdown := SaMarkdown.new(folder, 600, false)
    var bbcode := markdown.to_bbcode(README % WEB)
    var seen := _parsed(bbcode)
    var dot := folder.path_join("pictures/dot.png")
    assert_eq(
        markdown.pictures,
        PackedStringArray(["pictures/dot.png", "pictures/dot.png", "../dot.png"]),
        "the folder's pictures and the one outside it are read"
    )
    assert_true(bbcode.contains("[img width=16]%s[/img]" % dot), "the markdown picture is drawn at its own width")
    assert_eq(markdown.textures.size(), 1, "and the file, which nothing imported, is read once into a texture the page holds")
    assert_true(ResourceLoader.has_cached(dot), "under the path [img] names")
    assert_eq(markdown.web_pictures, PackedStringArray([WEB]), "the web picture is noted")
    assert_true(seen.contains("A shot on the web (%s)" % WEB), "and shows as its alt text and address: %s" % seen)
    assert_false(
        bbcode.contains("[img width=0]%s" % WEB) or bbcode.contains("]%s[/img]" % WEB), "and is never drawn, so never fetched"
    )
    assert_eq(
        markdown.problems,
        PackedStringArray(["The picture ../dot.png lies outside the folder"]),
        "the one outside the folder is the only problem"
    )
    assert_true(seen.contains("../dot.png"), "and shows as its name")
    _remove(folder)


func test_a_width_as_a_share_is_of_the_page_and_no_picture_is_wider_than_it() -> void:
    var folder := _folder()
    var markdown := SaMarkdown.new(folder, 200, false)
    var bbcode := markdown.to_bbcode('<img src="pictures/dot.png" width="50%">\n\n<img src="pictures/dot.png" width="900">\n')
    var dot := folder.path_join("pictures/dot.png")
    assert_true(bbcode.contains("[img width=100]%s[/img]" % dot), "50%% of a 200 wide page is 100: %s" % bbcode)
    assert_true(bbcode.contains("[img width=200]%s[/img]" % dot), "and 900 is held to the page's 200")
    _remove(folder)


func test_a_module_with_no_readme_of_its_own_shows_its_repositorys() -> void:
    var folder := String(ModuleLoader.module_dirs.get(&"exposure", ""))
    if folder.is_empty():
        assert_true(true, "exposure is not loaded in this run")
        return
    assert_false(FileAccess.file_exists(folder.path_join(SaModulesWindow.README)), "exposure has no README of its own")
    assert_eq(
        SaModulesWindow.readme_of("exposure"),
        folder.get_base_dir().path_join(SaModulesWindow.README),
        "so the window shows its repository's"
    )
    var page := SaModulesWindow.render({"id": "exposure", "name": "Exposure", "origin": "", "state": "on", "reason": ""}, 600)
    var markdown: SaMarkdown = page["markdown"]
    assert_eq(markdown.problems, PackedStringArray(), "and the repository's README draws with no problem")
    assert_true(markdown.pictures.size() >= 1, "a picture of what the modules do among it")
    var seen := _parsed(String(page["bbcode"]))
    assert_true(seen.contains(SaModulesWindow.manifest_for("exposure").version), "the page shows the version")


## Switching a module off and on stays on Preferences, Modules, and the
## window's button beside the page asks for that page.
func test_the_window_offers_the_switch_on_preferences_beside_the_page() -> void:
    var window := SaModulesWindow.new()
    var button := window.find_child("SwitchModulesButton", true, false) as Button
    assert_not_null(button, "the window has the button")
    if button == null:
        window.free()
        return
    var asked: Array[String] = []
    var listen := func(page: String) -> void: asked.append(page)
    EventBus.settings_page_requested.connect(listen)
    button.pressed.emit()
    EventBus.settings_page_requested.disconnect(listen)
    assert_eq(asked, [SaModulesPage.TITLE] as Array[String], "and a press asks for Preferences, Modules")
    window.free()


## A refused module's page says why it was refused, and one with no folder and
## no README says that it has none.
func test_a_refused_module_s_page_says_why() -> void:
    var entry := {"id": "refused", "name": "Refused One", "origin": "", "state": "refused", "reason": "needs sara-stats 9.0.0"}
    var seen := _parsed(String(SaModulesWindow.render(entry, 600)["bbcode"]))
    assert_true(seen.contains("Refused One"), "the page has the module's name: %s" % seen)
    assert_true(seen.contains("Refused at this start, needs sara-stats 9.0.0."), "and the reason it was refused")
    assert_true(seen.contains("This module has no README."), "and says it has no README")
