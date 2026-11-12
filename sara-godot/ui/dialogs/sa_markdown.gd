## Markdown into BBCode for one `RichTextLabel`, the subset the manual's pages
## and a module's `README.md` are written in. The manual (`SaManualWindow`) and
## the Modules window (`SaModulesWindow`) both draw with it, so a page and a
## README read alike and a fix reaches both.
##
## Headings, paragraphs, lists, bold, italic, code and fenced code, quotes,
## tables, links and pictures, and the few HTML tags a README on GitHub writes:
## `<img>` with its width, `<br>`, `<p align="center">` and `<details>` with its
## `<summary>`. Any other tag stays on screen as its text, and so does markdown
## outside the subset, which is what the manual's suite looks for.
##
## A picture is shown only from inside the folder of the page that names it. A
## picture on the web is never fetched, so Sara reaches no network, and shows as
## its alt text with its address. A picture that is not an imported resource, a
## module's in the painter's own folder, is read from its file here.
##
## One instance per page, since it collects what the page names as it goes.
class_name SaMarkdown
extends RefCounted

## The size of a heading of each level, in points at the default Font size.
## A README writes up to six levels, and the fourth to the sixth read as the third.
const HEADING_SIZES := [0, 22, 17, 14, 14, 14, 14]

## The files a picture is read from when it is not an imported resource.
const PICTURE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]

## What became of each HTML tag a page writes, the values of [member tags].
const RENDERED := "rendered"
const DROPPED := "dropped"
const AS_TEXT := "shown as text"

## The page's first level-one heading.
var title: String = ""
## Every link the page writes, as written.
var links: PackedStringArray = PackedStringArray()
## Every picture inside the folder the page names, as written.
var pictures: PackedStringArray = PackedStringArray()
## Every picture on the web the page names, shown as text and never fetched.
var web_pictures: PackedStringArray = PackedStringArray()
## One sentence for each link or picture that does not resolve.
var problems: PackedStringArray = PackedStringArray()
## Each HTML tag the page wrote, by its name, and what it became: rendered,
## dropped or shown as text. Read by the suite and the Modules window's dump.
var tags: Dictionary[String, String] = {}
## The pictures read from their files, each put in the resource cache under its
## path so `[img]` finds it. Held here, because the cache keeps a resource only
## while something else holds it, so whoever shows the page holds this.
var textures: Array[Texture2D] = []

var _folder: String
var _picture_width: int
var _pages: bool
var _blocks: PackedStringArray = PackedStringArray()
var _paragraph: PackedStringArray = PackedStringArray()
var _items: PackedStringArray = PackedStringArray()
var _ordered: bool = false
var _quote: PackedStringArray = PackedStringArray()
var _table: Array[PackedStringArray] = []
var _fence: PackedStringArray = PackedStringArray()
var _in_fence: bool = false
var _centered: bool = false
var _link := RegEx.create_from_string("(!?)\\[([^\\]]*)\\]\\(([^)\\s]+)\\)|<img\\b[^>]*>|<br\\s*/?>")
var _picture_line := RegEx.create_from_string("^!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)$")
var _img_line := RegEx.create_from_string("^<img\\b[^>]*>$")
var _attribute := RegEx.create_from_string("([a-zA-Z-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))")
var _tag := RegEx.create_from_string("<(/?)([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*?(/?)>")
var _bullet := RegEx.create_from_string("^[-*] +(.*)$")
var _number := RegEx.create_from_string("^\\d+\\. +(.*)$")
var _code := RegEx.create_from_string("`([^`]+)`")
var _strong := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
var _emphasis := RegEx.create_from_string("\\*(.+?)\\*")
var _rule := RegEx.create_from_string("^:?-{3,}:?$")


## *folder* is where the page's relative links and pictures are read from, and
## *picture_width* the widest a picture is drawn, none when it is nought or
## less. *pages* says a relative link has to name another page of the folder,
## which the manual's links do and a README's need not.
func _init(folder: String, picture_width: int, pages: bool = true) -> void:
    _folder = folder.trim_suffix("/") if folder != "res://" else folder
    _picture_width = picture_width
    _pages = pages


## Sara's own faces on *view* at the interface scale and the Font size, set on
## every draw so a size changed while a window was shut is the size its page
## comes back at. The body keeps the 20 points it drew at the default and
## follows the slider from there, as the headings do.
static func set_faces(view: RichTextLabel) -> void:
    var body := SaUI.font_size_for(SaUI.fraction_of(SaUI.BASE_FONT_SIZE))
    for kind: String in ["normal", "bold", "italics", "bold_italics", "mono"]:
        view.add_theme_font_size_override(kind + "_font_size", body)
    view.add_theme_font_override("bold_font", SaFonts.bold())
    view.add_theme_font_override("italics_font", slanted(SaFonts.regular()))
    view.add_theme_font_override("bold_italics_font", slanted(SaFonts.bold()))


## *face* leaning right with its letters on the baseline. FreeType reads the
## transform's `[0][1]` as x moved by y, so the slant goes there and not in `[1][0]`.
static func slanted(face: Font) -> FontVariation:
    var variation := FontVariation.new()
    variation.base_font = face
    variation.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)
    return variation


static func is_web(target: String) -> bool:
    return target.begins_with("https://") or target.begins_with("http://")


func to_bbcode(source: String) -> String:
    for line: String in source.replace("\r", "").split("\n"):
        _read_line(line)
    _end_blocks()
    if _in_fence:
        _end_fence()
    return "\n\n".join(_blocks)


func _read_line(line: String) -> void:
    var text := line.strip_edges()
    if text.begins_with("```"):
        _end_blocks()
        if _in_fence:
            _end_fence()
        else:
            _in_fence = true
        return
    if _in_fence:
        _fence.append(line)
        return
    if text.is_empty():
        _end_blocks()
        return
    if _read_html_block(text):
        return
    if text.begins_with(">"):
        _end_paragraph()
        _end_list()
        _end_table()
        _quote.append(text.substr(1).strip_edges())
        return
    _end_quote()
    if text.begins_with("|"):
        _end_paragraph()
        _end_list()
        _table.append(_cells(text))
        return
    _end_table()
    var level := _heading_level(text)
    if level > 0:
        _end_paragraph()
        _end_list()
        var heading := text.substr(level + 1).strip_edges()
        if level == 1 and title.is_empty():
            title = heading
        var heading_size := SaUI.font_size_for(SaUI.fraction_of(HEADING_SIZES[level]))
        _append("[font_size=%d][b]%s[/b][/font_size]" % [heading_size, _inline(heading)])
        return
    var picture := _picture_line.search(text)
    if picture != null:
        _end_paragraph()
        _end_list()
        _append(_picture_block(picture.get_string(2), picture.get_string(1)))
        return
    if _img_line.search(text) != null:
        _end_paragraph()
        _end_list()
        _append("[center]%s[/center]" % _inline(text))
        return
    var bullet := _bullet.search(text)
    var number := _number.search(text)
    if (bullet != null or number != null) and _paragraph.is_empty():
        var ordered := number != null
        if not _items.is_empty() and ordered != _ordered:
            _end_list()
        _ordered = ordered
        _items.append((number if ordered else bullet).get_string(1))
        return
    if not _items.is_empty() and line.begins_with(" "):
        _items[_items.size() - 1] += " " + text
        return
    _end_list()
    _paragraph.append(text)


## The block-level tags, each on a line of its own as GitHub reads them: a
## paragraph that opens or closes, centred when it says so, and a fold, whose
## summary is drawn as a bold line and whose body shows, since a page in Sara
## has no fold to open. True when the line was one of them.
func _read_html_block(text: String) -> bool:
    var lower := text.to_lower()
    if lower.begins_with("<p") and (lower.begins_with("<p>") or lower.begins_with("<p ")):
        _end_blocks()
        var center := lower.contains('align="center"') or lower.contains("align='center'") or lower.contains("align=center")
        _tags_met("p", RENDERED)
        _centered = center
        var rest := text.substr(text.find(">") + 1)
        if not rest.strip_edges().is_empty():
            _read_line(rest)
        return true
    if lower.ends_with("</p>"):
        var before := text.substr(0, text.length() - 4)
        if not before.strip_edges().is_empty():
            _read_line(before)
        _end_blocks()
        _centered = false
        return true
    if lower == "<details>" or lower.begins_with("<details ") or lower == "</details>":
        _end_blocks()
        _tags_met("details", DROPPED)
        return true
    if lower.begins_with("<summary>"):
        _end_blocks()
        _tags_met("summary", RENDERED)
        var summary := text.substr(9)
        if summary.to_lower().ends_with("</summary>"):
            summary = summary.substr(0, summary.length() - 10)
        _append("[b]%s[/b]" % _inline(summary.strip_edges()))
        return true
    return false


func _tags_met(tag_name: String, became: String) -> void:
    if not tags.has(tag_name):
        tags[tag_name] = became


## One to six hashes and a space, or nought for a line that is no heading.
static func _heading_level(text: String) -> int:
    for level: int in range(1, HEADING_SIZES.size()):
        if text.begins_with("#".repeat(level) + " "):
            return level
    return 0


func _append(block: String) -> void:
    _blocks.append("[center]%s[/center]" % block if _centered and not block.begins_with("[center]") else block)


func _end_blocks() -> void:
    _end_paragraph()
    _end_list()
    _end_quote()
    _end_table()


func _end_paragraph() -> void:
    if not _paragraph.is_empty():
        _append(_inline(" ".join(_paragraph)))
        _paragraph.clear()


func _end_list() -> void:
    if _items.is_empty():
        return
    var lines := PackedStringArray()
    for item: String in _items:
        lines.append(_inline(item))
    var tag := "[ol type=1]" if _ordered else "[ul]"
    _append(tag + "\n".join(lines) + ("[/ol]" if _ordered else "[/ul]"))
    _items.clear()


## A quote indented and in italics. GitHub's alert, `[!NOTE]` on the quote's
## first line, becomes its word in bold.
func _end_quote() -> void:
    if _quote.is_empty():
        return
    var lines := Array(_quote)
    var alert := ""
    var first := String(lines[0])
    if first.begins_with("[!") and first.ends_with("]"):
        alert = "[b]%s[/b] " % first.substr(2, first.length() - 3).capitalize()
        lines.pop_front()
    _append("[indent]%s[i]%s[/i][/indent]" % [alert, _inline(" ".join(PackedStringArray(lines)))])
    _quote.clear()


## A table, its first row in bold and the row of dashes under it left out.
func _end_table() -> void:
    if _table.is_empty():
        return
    var columns := 0
    for row: PackedStringArray in _table:
        columns = maxi(columns, row.size())
    var out := "[table=%d]" % columns
    for index: int in _table.size():
        var row := _table[index]
        if Array(row).all(func(cell: String) -> bool: return _rule.search(cell) != null):
            continue
        for column: int in columns:
            var cell := _inline(row[column]) if column < row.size() else ""
            if index == 0:
                cell = "[b]%s[/b]" % cell
            out += "[cell padding=0,2,12,2]%s[/cell]" % cell
    _append(out + "[/table]")
    _table.clear()


## A table row's cells, a pipe inside a code span kept as text.
func _cells(text: String) -> PackedStringArray:
    var body := text.trim_prefix("|").trim_suffix("|")
    var cells := PackedStringArray()
    var cell := ""
    var in_code := false
    for character: String in body:
        if character == "`":
            in_code = not in_code
        if character == "|" and not in_code:
            cells.append(cell.strip_edges())
            cell = ""
            continue
        cell += character
    cells.append(cell.strip_edges())
    return cells


func _end_fence() -> void:
    _in_fence = false
    _append("[code]%s[/code]" % escape("\n".join(_fence)))
    _fence.clear()


func _picture_block(target: String, caption: String) -> String:
    var block := "[center]%s[/center]" % _picture(target, caption)
    if not caption.is_empty() and not is_web(target):
        block += "\n[center][i]%s[/i][/center]" % _inline(caption)
    return block


## *target* drawn no wider than *width* or the page, or as text: its alt text
## and address when it is on the web, which is never fetched, and its name when
## it lies outside the page's folder or does not load.
func _picture(target: String, alt: String = "", width: int = 0) -> String:
    if is_web(target):
        web_pictures.append(target)
        var said := alt if not alt.is_empty() else target.get_file()
        return "[i]%s[/i] (%s)" % [escape(said), escape(target)]
    pictures.append(target)
    var path := _folder.path_join(target).simplify_path()
    var inside := not target.begins_with("/") and not target.contains("://") and not target.contains("..")
    var texture: Texture2D = _texture_at(path) if inside else null
    if texture == null:
        var why := "lies outside the folder" if not inside else "does not load"
        problems.append("The picture %s %s" % [target, why])
        return escape(target)
    var drawn := texture.get_width() if width <= 0 else width
    if _picture_width > 0:
        drawn = mini(drawn, _picture_width)
    return "[img width=%d]%s[/img]" % [drawn, path]


## The picture at *path*: the imported resource when there is one, which a
## packaged module's is, and otherwise the file itself read into a texture
## the cache hands `[img]` under the same path.
func _texture_at(path: String) -> Texture2D:
    if ResourceLoader.exists(path):
        return load(path) as Texture2D
    if not PICTURE_EXTENSIONS.has(path.get_extension().to_lower()) or not FileAccess.file_exists(path):
        return null
    var image := Image.load_from_file(ProjectSettings.globalize_path(path))
    if image == null or image.is_empty():
        return null
    var texture := ImageTexture.create_from_image(image)
    texture.take_over_path(path)
    textures.append(texture)
    return texture


## A link, a picture inside a sentence, an `<img>` or a `<br>`, and the text
## between them, each in its own pass so that brackets a page writes as prose
## stay brackets.
func _inline(text: String) -> String:
    var out := ""
    var at := 0
    for found: RegExMatch in _link.search_all(text):
        out += _styled(text.substr(at, found.get_start() - at))
        var whole := found.get_string()
        if whole.begins_with("<img"):
            out += _img(whole)
        elif whole.begins_with("<br"):
            _tags_met("br", RENDERED)
            out += "\n"
        elif found.get_string(1) == "!":
            out += _picture(found.get_string(3), found.get_string(2))
        else:
            var target := found.get_string(3)
            out += "[url=%s]%s[/url]" % [target, _styled(found.get_string(2))]
            _check_link(target)
        at = found.get_end()
    return out + _styled(text.substr(at))


## An `<img>` tag, its `src` drawn at its `width`, in pixels or as a share of
## the page, and its `alt` said for one on the web.
func _img(tag: String) -> String:
    _tags_met("img", RENDERED)
    var attributes := {}
    for found: RegExMatch in _attribute.search_all(tag):
        var value := found.get_string(2) + found.get_string(3) + found.get_string(4)
        attributes[found.get_string(1).to_lower()] = value
    var target := String(attributes.get("src", ""))
    var width_text := String(attributes.get("width", ""))
    var width := 0
    if width_text.ends_with("%") and _picture_width > 0:
        width = int(_picture_width * width_text.to_float() / 100.0)
    elif width_text.is_valid_int():
        width = width_text.to_int()
    return _picture(target, String(attributes.get("alt", "")), width)


func _check_link(target: String) -> void:
    links.append(target)
    if is_web(target) or target.begins_with("#"):
        return
    if not _pages:
        return
    if target.get_extension() != "md" or not FileAccess.file_exists(_folder.path_join(target)):
        problems.append("The link %s names no page of the manual" % target)


## Code spans first, so that nothing inside one is read as emphasis or a tag.
func _styled(text: String) -> String:
    var out := ""
    var at := 0
    for found: RegExMatch in _code.search_all(text):
        out += _prose(text.substr(at, found.get_start() - at))
        out += "[code]%s[/code]" % escape(found.get_string(1))
        at = found.get_end()
    return out + _prose(text.substr(at))


## Prose outside code: any tag in it the subset does not read is left as its
## text and noted, and a closing tag of one it does read is dropped.
func _prose(text: String) -> String:
    var out := ""
    var at := 0
    for found: RegExMatch in _tag.search_all(text):
        var tag_name := found.get_string(2).to_lower()
        out += text.substr(at, found.get_start() - at)
        if found.get_string(1) == "/" and tags.get(tag_name, "") in [RENDERED, DROPPED]:
            pass
        else:
            _tags_met(tag_name, AS_TEXT)
            out += found.get_string()
        at = found.get_end()
    return _emphasised(escape(out + text.substr(at)))


func _emphasised(text: String) -> String:
    return _emphasis.sub(_strong.sub(text, "[b]$1[/b]", true), "[i]$1[/i]", true)


static func escape(text: String) -> String:
    return text.replace("[", "\u0001").replace("]", "\u0002").replace("\u0001", "[lb]").replace("\u0002", "[rb]")
