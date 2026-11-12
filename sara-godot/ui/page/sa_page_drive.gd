## Finds any declared row on any open page, so a scenario reaches a page through
## the door rather than only through the page demo.
##
## Moving and reading are the row's own methods, which also folded the demo's
## one-line forward for them: this file keeps only the search, which is what a
## row cannot do for itself.
@tool
class_name SaPageDrive
extends RefCounted

## What every answer that found no row opens with, a page named wrong, a key no
## open page holds, or a key the named page does not hold.
const MISS := "SaCapture: page_row found no "


## Moves a page row's control: *row*'s, as a hand would, and answers the page,
## the key, what the control and the binding now hold, `{"page_row": {"row":
## "exposure", "value": 2.5}}`, and an element list is no row: `layout_rows`
## reads one and `layout_gesture` drags it or flips a switch on it.
##
## Without `"value"` the step only reads. An optional `"page"` names the
## container to search, for two open pages that share a key. Without it the
## first visible page that has the key answers. A key nobody has answers with
## the keys it found, and a `custom` row is refused, because its page has a step
## of its own. The element list of the Top Menu Bar page and of a docker's
## Elements… page is such a row, which a sweep that knew only this step read
## as "a row the page builds by hand and no step reaches it", so the two steps
## that do reach it are named in the sentence the step catalogue shows.
##
## Every miss opens with [constant MISS], which is how the harness's step tells
## a miss from a report and ends a scenario on it.
static func capture(tree: SceneTree, spec: Variant) -> String:
    var options: Dictionary = spec if spec is Dictionary else {}
    var key := StringName(String(options.get("row", "")))
    var wanted_page := String(options.get("page", ""))
    var found := _find(tree.root, key, wanted_page)
    var page := found.get("page") as SaPage
    if page == null:
        if not wanted_page.is_empty():
            return MISS + "page named '%s' for the row '%s'" % [wanted_page, String(key)]
        var known: Array = found.get("known", [])
        var pages: Array = found.get("pages", []).map(func(n: String) -> String: return "'%s'" % n)
        return MISS + "row '%s' on the open pages %s, known: %s" % [String(key), ", ".join(pages), ", ".join(known)]
    var page_name: String = found.get("name", "")
    var row := page.row(key)
    if row == null:
        var known: Array = page.rows().map(func(r: SaPageRow) -> String: return String(r.key))
        return MISS + "row '%s' on the page '%s', known: %s" % [String(key), page_name, ", ".join(known)]
    if row.kind == SaPageRow.Kind.CUSTOM:
        return "SaCapture: '%s' on '%s' is custom, its page has a step of its own" % [String(key), page_name]
    if not options.has("value"):
        return "SaCapture: '%s' on '%s' reads %s, binding %s" % [String(key), page_name, row.reads(), row.read()]
    row.drive(options["value"])
    return "SaCapture: '%s' on '%s' moved to %s, binding now %s" % [String(key), page_name, row.reads(), row.read()]


## Every visible window under *root*, walked for a container carrying
## `SaPage.PAGE_META`. *wanted_page* names the container to take outright, and
## with none the walk answers the first page whose own row carries *key*,
## gathering every key and every page name it passed on the way so a miss can
## list them.
##
## An embedded dialog is itself one of `root`'s own descendants, so its
## windows overlap: walking from `root` already reaches a container the walk
## then visits again starting from the dialog's own entry. `seen` is what
## keeps a page's keys off the known list twice.
static func _find(root: Window, key: StringName, wanted_page: String) -> Dictionary:
    var known: Array = []
    var pages: Array = []
    var seen: Dictionary = {}
    for window in ([root] as Array[Node]) + root.find_children("*", "Window", true, false):
        var win := window as Window
        if win == null or not win.visible:
            continue
        for node in win.find_children("*", "Container", true, false):
            var box := node as Container
            if box == null or not box.has_meta(SaPage.PAGE_META) or seen.has(box):
                continue
            seen[box] = true
            var page := box.get_meta(SaPage.PAGE_META) as SaPage
            if page == null:
                continue
            if not wanted_page.is_empty():
                if String(box.name) == wanted_page:
                    return {"page": page, "name": wanted_page}
                continue
            if page.row(key) != null:
                return {"page": page, "name": String(box.name)}
            pages.append(String(box.name))
            for r in page.rows():
                known.append(String(r.key))
    return {"page": null, "known": known, "pages": pages}
