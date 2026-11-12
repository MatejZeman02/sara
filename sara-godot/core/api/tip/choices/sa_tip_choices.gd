## The Tip Image list a brush engine's page offers, and whether a picture in it
## is one the brush can paint with.
##
## The door's [SaBrushTipMask] owns the tip folders, and this is an engine's
## reading of them: every file the folders hold, then every picture loaded
## from elsewhere this run, then the file a preset holds when it came from
## none of those. It reads the stored tip and the mask the brush bound last and
## nothing of a stroke.
##
## **In the door because two engines read it.** The stamp brush and the noise
## brush's Tip row offer the same Tip Image list. Both declare it as `SaOptionSpec.Kind.TIP_IMAGE`, whose
## grid lists through [method listing], so the two engines list the same tips
## under the same folders. Beside the tip rather than in it, because what a page
## offers is a question of its own and `core/api/tip` is the tip's GPU half and
## the readers of its files.
##
## **A tip's folder is its tag.** The grid's filter is a row per folder a tip
## sits in, All first, so the grid is chosen as the brush presets are without a
## tag store beside the files: Sara's own tips, the painter's imported ones and each folder a picture was
## loaded from are three kinds of tag a painter already keeps by where a file is.
##
## Built with the tip and the mask it answers about, each time a list is asked
## for, so it never holds either past the question.
class_name SaTipChoices
extends RefCounted

var _tip: Resource = null
var _mask: SaBrushTipMask = null


## *tip* is the stored tip resource, whose `image_path` is the file the brush
## holds, and *mask* is the one the brush bound last, null before any bind.
func _init(tip: Resource, mask: SaBrushTipMask) -> void:
    _tip = tip
    _mask = mask


## The Tip Image list as it stands now: the procedural entry, then
## [method tips]. `{"ids": [...], "labels": [...]}`, the shape `make_enum`
## takes, so a list can be rebuilt without knowing where tips live.
func choices() -> Dictionary:
    var ids: Array = [""]
    var labels: Array = ["Procedural"]
    for entry: Dictionary in tips():
        ids.append(entry["path"])
        labels.append(entry["label"])
    return {"ids": ids, "labels": labels}


## [method listing] for the file the brush holds, its label saying so when the
## brush cannot read it.
##
## **A held file that cannot be read says so in its label**. A preset whose
## picture is gone keeps the path, so the preset saves back unchanged and
## paints again the day the file returns, and the brush meanwhile stamps the
## empty stand-in and paints nothing, which the toast already says. The row
## named the file as though the brush held it, over an empty preview, and
## reading Procedural instead named a tip the brush does not paint either.
func tips() -> Array[Dictionary]:
    var held := str(_tip.get(&"image_path")) if _tip != null else ""
    var listed := listing(held)
    for entry: Dictionary in listed:
        if entry["path"] == held and not readable(held):
            entry["label"] = TranslationServer.translate("%s (unreadable)") % entry["label"]
    return listed


## Whether the picture at *path* is one the brush can paint with. The mask the
## brush bound last answers when it holds this path, because it tried the
## read, and a file that is not on disk answers without a read, which is the
## case of a preset whose picture was deleted.
func readable(path: String) -> bool:
    if _mask != null and _mask.path == path and not path.is_empty():
        return _mask.error.is_empty()
    return FileAccess.file_exists(path)


## Every tip the list offers while the brush holds *held*, in the order it
## shows them: the files of the two tip folders, every picture loaded from
## elsewhere this run, then *held* when it is none of those. Each is
## `{"path": String, "label": String, "folder": String}`, the folder being the
## one the file sits in.
##
## Static and handed the held path, because the grid reads that path through
## the row's own property and holds no tip resource to build one of these with.
static func listing(held: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var available := SaBrushTipMask.available()
    for path: String in available:
        out.append(_entry(path, String(available[path])))
    var extra: Array[String] = SaBrushTipMask.loaded_elsewhere()
    if not held.is_empty() and not extra.has(held):
        extra.append(held)
    for path: String in extra:
        if not available.has(path):
            out.append(_entry(path, path.get_file().get_basename().capitalize()))
    return out


## The filter's rows over *listed*, as [method listing] answers it: All first,
## then each folder a tip of it sits in, in the order the folder's first tip
## comes. `{"id": folder, "label": name}`, All's id empty, the shape
## `SaChoiceButton.set_choices` takes.
static func folders(listed: Array[Dictionary]) -> Array[Dictionary]:
    var out: Array[Dictionary] = [{"id": "", "label": TranslationServer.translate("All")}]
    var seen: Dictionary[String, bool] = {}
    for entry: Dictionary in listed:
        var folder: String = entry["folder"]
        if seen.has(folder):
            continue
        seen[folder] = true
        out.append({"id": folder, "label": folder_name(folder)})
    return out


## What the filter calls *folder*: Sara for the tips Sara ships, Imported for
## the painter's folder, where the Krita import writes the tips it brings, and
## the folder's own name for one a picture was loaded from.
static func folder_name(folder: String) -> String:
    if folder == SaBrushTipMask.SHIPPED_DIR:
        return TranslationServer.translate("Sara")
    if folder == SaBrushTipMask.saved_dir():
        return TranslationServer.translate("Imported")
    var named := folder.trim_suffix("/").get_file()
    return named if not named.is_empty() else folder


static func _entry(path: String, label: String) -> Dictionary:
    return {"path": path, "label": label, "folder": path.get_base_dir()}
