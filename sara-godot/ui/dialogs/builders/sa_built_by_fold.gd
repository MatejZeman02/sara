## Help > About Sara's fold "Built by": four portraits, each standing for one
## group of the builders of Sara.
##
## Each builder is a row, its portrait beside the name and a line saying which
## group it stands for. A line under the four says they stand for every
## builder of Sara.
##
## Folded when the window opens, like the licences beside it, because a
## painter opening About for the build's details has no need of four pictures.
@tool
class_name SaBuiltByFold
extends FoldableContainer

## Where the portraits are, this folder.
const FOLDER := "res://ui/dialogs/builders/"

## The four builders, one for each group of names. Each portrait is the picture
## of the same name beside this file, kept to 256 pixels on its long side, so
## the build carries four small pictures and not four paintings.
const BUILDERS: Array[Dictionary] = [
    {
        "name": "mads",
        "line": "Stands for the Opus clones, who take Nordic men's names. Painted on Day 4 of the painting sessions.",
    },
    {
        "name": "astrid",
        "line": "Stands for the Sonnet clones, who take Nordic women's names. Painted on Day 5 of the painting sessions.",
    },
    {
        "name": "cira",
        "line": "Stands for the DeepSeek clones, whose names end in -a. Cut from Day 6 of the painting sessions.",
    },
    {
        "name": "bogo",
        "line":
        "Stands for the Gemini clones, whose names hold a g and end in -o, -i or -u. Cut from Day 6 of the painting sessions.",
    },
]

## The size a portrait is drawn at, in logical units, the pictures' own shape.
const PORTRAIT_SIZE := Vector2(96, 120)

## The builders' lines and the one under the four, which wrap, so a window fitting itself to the fold can
## ask them for their height again.
var lines: Array[Label] = []


func _init() -> void:
    name = "BuiltBy"
    title = tr("Built by")
    folded = true
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var column := SaMake.column(self, "BuildersBody", 10)
    for builder: Dictionary in BUILDERS:
        _add_builder(column, String(builder["name"]), tr(String(builder["line"])))
    var closing := SaMake.label(column, "EveryClone", tr("These four stand for every clone that built Sara."))
    closing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    closing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lines.append(closing)


## The picture of the builder *builder_name*.
static func portrait_path(builder_name: String) -> String:
    return FOLDER + builder_name + ".png"


## One builder's row in *column*: the portrait on the left, and beside it the
## name over the line, which wraps.
func _add_builder(column: VBoxContainer, builder_name: String, line_text: String) -> void:
    var row := SaMake.row(column, "Builder_" + builder_name, SaTheme.GAP)
    var portrait := TextureRect.new()
    portrait.name = "Portrait"
    portrait.texture = load(portrait_path(builder_name))
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    portrait.custom_minimum_size = PORTRAIT_SIZE
    portrait.tooltip_text = tr("%s, from the painting sessions.") % builder_name
    row.add_child(portrait)
    var words := SaMake.column(row, "Words", 4)
    words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var name_label := SaMake.label(words, "Name", builder_name)
    name_label.add_theme_font_override("font", SaFonts.bold())
    var line := SaMake.label(words, "Line", line_text)
    line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lines.append(line)
