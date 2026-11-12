## What a note says about a control, split out of `sa_note_mode.gd`.
##
## Every function here takes a bare Control and no instance state: two of the
## private statics are mutually recursive, and the group has to compose
## without a `SaNoteMode` to call back into.
class_name SaNoteDescribe
extends RefCounted


## Everything the entry says about `control`, as data, so a test can read it.
## `item_tag` is the caller's `menu_tag()`, since which menu item is under the
## pointer is instance state this helper does not hold.
static func describe(control: Control, root: Window, item_tag: String) -> Dictionary:
    var window := control.get_window()
    return {
        "name": String(control.name),
        "class": control.get_class(),
        "path": String(control.get_path()),
        "where": where(control, root),
        "label": label_of(control),
        "value": value_of(control),
        "settings": settings_for(control),
        "item": item_tag,
        # A window of its own is drawn into the picture by
        # `SaNoteImage.with_windows`, so only one past the root's edge is off it.
        "in_picture": window == root or window.is_embedded() or SaNoteImage.shows(control, root),
        "build": SaBuildInfo.describe(SaBuildInfo.read()),
    }


## "Preferences, Top Menu Bar", "Layers", or "the main window, CustomTitleBar":
## the window the control is in, and the page or the top-level piece under it.
static func where(control: Control, root: Window) -> String:
    var window := control.get_window()
    if window is Popup:
        # A row of an open menu. The menu has no title, so the entry says where
        # the menu hangs and then names the menu, "..., CustomTitleBar,
        # ImageMenu", and a popup nobody owns is placed in the main window.
        var owner := SaNoteMode.popup_owner(window)
        var host := where(owner, root) if owner != null else "the main window"
        return host + ", " + String(window.name)
    if window != null and window != root:
        var page := _settings_page(window)
        return window.title + (", " + page if not page.is_empty() else "")
    var top := _ancestor_under(control, root)
    return "the main window" + (", " + top if not top.is_empty() else "")


## The Preferences page that is open, read from the title label the window
## puts first on the page. Empty for any other window.
static func _settings_page(window: Window) -> String:
    var container: Variant = window.get("content_container")
    if not (container is Node):
        return ""
    for child in (container as Node).get_children():
        if child.is_queued_for_deletion():
            continue
        if child is Label:
            return (child as Label).text
        break
    return ""


## The name of the ancestor two below the root, which for the main window is
## the bar, the options bar, the canvas or a dialog, and empty when the control
## is that high itself.
static func _ancestor_under(control: Node, root: Node) -> String:
    var scene: Node = root.get_tree().current_scene if root.is_inside_tree() else null
    var cursor: Node = control
    var last := ""
    while cursor != null and cursor != root and cursor != scene:
        last = String(cursor.name)
        cursor = cursor.get_parent()
    return last if cursor == scene and last != String(control.name) else ""


## The control's own text, or its tooltip, or nothing.
static func label_of(control: Control) -> String:
    if control is SaChoiceRow:
        return (control as SaChoiceRow).label_button().text
    var text: Variant = control.get("text")
    if text is String and not (text as String).is_empty() and not (control is TextEdit):
        return text
    var placeholder: Variant = control.get("placeholder_text")
    if placeholder is String and not (placeholder as String).is_empty():
        return placeholder
    return control.tooltip_text


## What the control currently holds, as "pressed: true", "value: 0.5" or
## "selected: Oklab", and empty for a control with no value of its own.
static func value_of(control: Control) -> String:
    if control is OptionButton:
        var option := control as OptionButton
        return "selected: %s" % (option.get_item_text(option.selected) if option.selected >= 0 else "none")
    if control is BaseButton and (control as BaseButton).toggle_mode:
        return "pressed: %s" % str((control as BaseButton).button_pressed)
    if control is Range:
        return "value: %s" % str((control as Range).value)
    if control is LineEdit:
        return "text: %s" % JSON.stringify((control as LineEdit).text)
    if control is TextEdit:
        return "text: %s" % JSON.stringify((control as TextEdit).text)
    return ""


## The SaSettings properties the control reads, each as `[name, value, how]`
## where `how` is "named" for the meta and "by name" for the guess.
static func settings_for(control: Control) -> Array:
    var out: Array = []
    var seen: Array[String] = []
    var cursor: Node = control
    while cursor != null:
        if cursor.has_meta(SaNoteMode.SETTINGS_META):
            var named: Variant = cursor.get_meta(SaNoteMode.SETTINGS_META)
            if named is Array:
                for entry: Variant in named as Array:
                    var key := String(entry)
                    if not seen.has(key) and key in SaSettings:
                        seen.append(key)
                        out.append([key, _setting_text(key), "named"])
        cursor = cursor.get_parent()
    var guess := guess_setting(String(control.name))
    if not guess.is_empty() and not seen.has(guess):
        out.append([guess, _setting_text(guess), "by name"])
    return out


## `SecondRowCheck` to `second_row`, when that is a SaSettings property.
static func guess_setting(node_name: String) -> String:
    var snake := node_name.to_snake_case()
    for suffix in SaNoteMode.NAME_SUFFIXES:
        if snake.ends_with(suffix):
            snake = snake.substr(0, snake.length() - suffix.length())
            break
    if snake.is_empty() or snake.begins_with("_"):
        return ""
    return snake if snake in SaSettings else ""


static func _setting_text(key: String) -> String:
    return JSON.stringify(SaSettings.get(key))


## One markdown entry, from what `describe()` and `save()` collected. Pure.
static func format_entry(info: Dictionary) -> String:
    var stamp: Dictionary = info.get("stamp", {})
    var lines: PackedStringArray = PackedStringArray()
    lines.append("")
    lines.append("### %s %s, %s" % [stamp.get("date", ""), stamp.get("time", ""), info.get("where", "")])
    var text := String(info.get("text", ""))
    lines.append("**Note.** " + (text if not text.is_empty() else "(no text)"))
    var control := "`%s` `%s`" % [info.get("class", ""), info.get("name", "")]
    var label := String(info.get("label", ""))
    if not label.is_empty():
        control += ", %s" % JSON.stringify(label)
    var value := String(info.get("value", ""))
    if not value.is_empty():
        control += ", " + value
    lines.append("**Control.** " + control)
    var item := String(info.get("item", ""))
    if not item.is_empty():
        lines.append("**Item.** " + item + ", in the menu that was open")
    lines.append("**Path.** `%s`" % info.get("path", ""))
    var settings: Array = info.get("settings", [])
    if settings.is_empty():
        lines.append("**Settings.** none named")
    else:
        var parts: PackedStringArray = PackedStringArray()
        for entry: Array in settings:
            var part := "`%s` = %s" % [entry[0], entry[1]]
            if String(entry[2]) == "by name":
                part += " (matched by name)"
            parts.append(part)
        lines.append("**Settings.** " + ", ".join(parts))
    var image := String(info.get("image", ""))
    if image.is_empty():
        lines.append("**Image.** none, the readback failed")
    else:
        var caption := String(info.get("name", "control"))
        var line := "**Image.** ![%s](%s)" % [caption, image]
        if not bool(info.get("in_picture", true)):
            line += " (the control is in a separate OS window, outside the picture)"
        lines.append(line)
    lines.append("**Build.** " + String(info.get("build", "")))
    lines.append("")
    return "\n".join(lines)
