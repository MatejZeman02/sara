## Which tools share a toolbox button, and where that is kept.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The groups are the painter's, reordered by dragging a tool out of one and
## dropping it into another or in between. So a group is a list of tool ids,
## the toolbox is a list of groups, and the docker draws one button per group.
##
## **The registry's group ids are the default.** A tool is a button of its
## own unless its descriptor names a `toolbox_group` another tool names too,
## so few tools share a button by default. A group is named after its group id
## or, without one, after the category of its first member, so
## `{"toolbox": {"flyout": "select"}}` means the marquees.
##
## **Two things are stored, and the flat order is the one a preset owns.** The
## groups go under the docker's option store as `groups`, an array of arrays
## of ids, which the profile persists and which no Preferences row draws. The
## flat element order the Layout page shows and a layout preset captures is
## rewritten to the same sequence. A stored grouping counts only while the two
## agree: a preset loaded over it, or a row dragged on the Layout page,
## changes the order without the groups, and then the order wins and the
## groups fall back to the registry's categories laid out in that order. That
## is what makes a fresh preset show the registry's order, and it is the one
## thing a painter loses by reordering in Preferences rather than by dragging.
class_name SaToolBoxGroups
extends RefCounted

## The docker option the groups are stored under. Unregistered on purpose, so
## the Preferences page draws no row for a value that is not a switch.
const GROUPS_KEY := "groups"


## The registry's own grouping: a group per `toolbox_group` id that tools
## share, every other tool a group of one, the groups in the order the registry
## listed the first tool of each and members in registry order.
static func from_registry(descriptors: Array) -> Array:
    var by_key: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        var key := _group_key(descriptor)
        if not by_key.has(key):
            by_key[key] = []
        (by_key[key] as Array).append(String(descriptor.id))
    var out: Array = []
    for key: String in by_key:
        out.append(by_key[key])
    return out


## The grouping every profile drew before a tool could name a group of its own,
## one group per category in registry order. A stored grouping equal to it, laid
## out in the order the flat layout gives, is a profile that wrote the old
## default back without regrouping anything, and [method stored] gives it the
## new default instead.
static func by_category(descriptors: Array) -> Array:
    var by_name: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        var category := String(descriptor.category)
        if not by_name.has(category):
            by_name[category] = []
        (by_name[category] as Array).append(String(descriptor.id))
    var out: Array = []
    for category: String in by_name:
        out.append(by_name[category])
    return out


## The grouping in force for *descriptors*: the stored one when it agrees with
## the flat layout order and is more than the old one group per category, else
## the registry's groups, in the order the flat order draws their buttons.
static func stored(descriptors: Array) -> Array:
    var known: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        known[String(descriptor.id)] = descriptor
    var sequence := order_sequence(descriptors)
    var raw: Variant = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, GROUPS_KEY)
    var groups := _clean(raw, known)
    if not groups.is_empty() and flatten(groups) == sequence:
        var full := _with_missing(groups, descriptors)
        if full != _sorted_by(by_category(descriptors), sequence):
            return full
    return _sorted_by(from_registry(descriptors), sequence)


## The tool ids the flat layout order names, in its order, registered ones only.
static func order_sequence(descriptors: Array) -> Array:
    var out: Array = []
    for element: String in SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY):
        for descriptor: SaToolDescriptor in descriptors:
            if SaToolBoxGrid.entry_matches(element, descriptor) and not out.has(String(descriptor.id)):
                out.append(String(descriptor.id))
                break
    return out


## Every id of every group, in order.
static func flatten(groups: Array) -> Array:
    var out: Array = []
    for group: Array in groups:
        out.append_array(group)
    return out


## *groups* with *tool_id* taken out of wherever it is and put into the group
## at *group_index* at *position*, or into a new group of its own at
## *group_index* when *as_new_group* is set. A group left empty leaves the
## list. Always a new array, so a caller holding the old one can compare.
static func moved(groups: Array, tool_id: String, group_index: int, position: int, as_new_group: bool) -> Array:
    # The position was counted on the group with the tool still in it, which is
    # how `row_drop_target` reads a row. Moved down its own group, the tool
    # leaves a place above the target, so everything after that place is one
    # earlier by the time it is inserted, and without this the tool would land
    # one row past the one it was dropped before. A tool from another group, or one
    # dropped above where it was, left nothing above the target to count.
    if not as_new_group and group_index < groups.size():
        var from := (groups[group_index] as Array).find(tool_id)
        if from >= 0 and from < position:
            position -= 1
    var out: Array = []
    for group: Array in groups:
        var copy := group.duplicate()
        copy.erase(tool_id)
        out.append(copy)
    # The target index was counted on the list before the tool left it, and
    # emptying a group above the target shifts everything below it up by one.
    var target := group_index
    for i in mini(group_index, out.size()):
        if (out[i] as Array).is_empty():
            target -= 1
    var cleaned: Array = []
    for group: Array in out:
        if not group.is_empty():
            cleaned.append(group)
    target = clampi(target, 0, cleaned.size())
    if as_new_group or cleaned.is_empty():
        cleaned.insert(target, [tool_id])
        return cleaned
    target = mini(target, cleaned.size() - 1)
    var into: Array = cleaned[target]
    into.insert(clampi(position, 0, into.size()), tool_id)
    return cleaned


## Writes *groups* to the profile and the flat order to match, which is one
## edit of the layout and forks the preset the way any other edit does: both
## writes go through `SaSettings`, whose `profile_changed` the main dockers
## already answer with the fork.
##
## The order keeps every entry that is not a tool, the drag handle among them,
## where it stood, and the tool entries take the new sequence in the slots the
## old ones held.
static func save(groups: Array, descriptors: Array) -> void:
    var entry_of: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        entry_of[String(descriptor.id)] = SaToolBoxGrid.layout_entry_for(descriptor)
    var sequence := flatten(groups)
    var old_order := SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    var new_order: Array = []
    var next := 0
    for element: String in old_order:
        if _is_tool_entry(element, descriptors):
            if next < sequence.size():
                new_order.append(entry_of[sequence[next]])
                next += 1
        else:
            new_order.append(element)
    while next < sequence.size():
        new_order.append(entry_of[sequence[next]])
        next += 1
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, GROUPS_KEY, groups)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, new_order)


## Where a drop on a group's button lands, as `[group_index, position,
## as_new_group]` for [method moved]. *along* is how far along the button the
## pointer was, 0 to 1 on the axis the buttons run on: the first third opens a
## new group before the button, the last third one after it, and the middle
## joins the group at its end.
static func button_drop_target(groups: Array, index: int, along: float) -> Array:
    if along < 1.0 / 3.0:
        return [index, 0, true]
    if along > 2.0 / 3.0:
        return [index + 1, 0, true]
    return [index, (groups[index] as Array).size() if index < groups.size() else 0, false]


## Where a drop on the row showing *row_id* in group *index* lands: before
## that row or after it, and at the end of the group for a row it does not
## hold, which is a row hidden from Preferences.
static func row_drop_target(groups: Array, index: int, row_id: String, before: bool) -> Array:
    var group: Array = groups[index] if index < groups.size() else []
    var position := group.find(row_id)
    if position < 0:
        return [index, group.size(), false]
    return [index, position if before else position + 1, false]


## Where a release that hit no row and no button lands: a group of its own at
## the end when *screen_at* was still inside *grid_rect*, and an empty array
## outside it, which is the release the docker reads as "put it back".
##
## Un-grouping needs a gesture of its own, and empty toolbox space is the one
## place inside the docker that means nothing else: a button is already three
## thirds of meaning and a flyout row is a slot between two tools, so the space
## under the last button is the only surface left to give it to. A release
## outside the docker keeps meaning "put it back", because a painter who drops a
## tool on the canvas has changed their mind rather than asked for a button of
## its own.
static func empty_drop_target(groups: Array, screen_at: Vector2, grid_rect: Rect2) -> Array:
    if grid_rect.size.x <= 0.0 or grid_rect.size.y <= 0.0 or not grid_rect.has_point(screen_at):
        return []
    return [groups.size(), 0, true]


## Where a release at *screen_at* lands, for [method moved], or an empty
## array for a point on nothing outside *grid_rect*. A row of an open flyout
## comes first, because a flyout is drawn over the buttons, then the button
## under the point, read along the axis the buttons run on: a column reads the
## drop's height and a row its width, and then the docker's own empty space,
## which is [method empty_drop_target]. *flyouts* and *buttons* are the
## docker's, by group name, and *grid_rect* is the button area in the screen
## units the buttons themselves answer in.
static func release_target(
    screen_at: Vector2, groups: Array, names: Array, flyouts: Dictionary, buttons: Dictionary, columns: int, grid_rect: Rect2
) -> Array:
    for i in names.size():
        var flyout: SaToolFlyout = flyouts.get(StringName(names[i]))
        if flyout == null or not is_instance_valid(flyout) or not flyout.visible:
            continue
        var hit := flyout.row_at(screen_at)
        if int(hit[0]) >= 0:
            return row_drop_target(groups, i, flyout.ids[hit[0]], bool(hit[1]))
    for i in names.size():
        var btn: Button = buttons.get(StringName(names[i]))
        # `is_inside_tree` beside the two it came with: `get_screen_position` on
        # a detached Control is an engine error and a `Point2()` back, so a
        # docker a suite built with no tree printed one error per button the
        # first time this was asked about a release.
        if btn == null or not is_instance_valid(btn) or not btn.visible or not btn.is_inside_tree():
            continue
        # On the host, like the release, since `btn.size` is in the docker's units
        # and a maximised toolbox draws its buttons a quarter larger.
        var rect := SaPopupRect.of_anchor(btn)
        if not rect.has_point(screen_at):
            continue
        var local := screen_at - rect.position
        return button_drop_target(groups, i, local.y / rect.size.y if columns == 1 else local.x / rect.size.x)
    return empty_drop_target(groups, screen_at, grid_rect)


## The name a group answers to: the `toolbox_group` of its first member, or
## without one the category of its first member, and a number after it when an
## earlier group already took that name, so two groups split out of one
## category stay two names. Group ids are given out first, so the fills keep
## `fill` whichever button of their category the registry listed first.
static func names_for(groups: Array, descriptors: Array) -> Array:
    var category_of: Dictionary = {}
    var group_of: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        category_of[String(descriptor.id)] = String(descriptor.category)
        group_of[String(descriptor.id)] = String(descriptor.toolbox_group)
    var taken: Dictionary = {}
    var out: Array = []
    out.resize(groups.size())
    for i in groups.size():
        var group: Array = groups[i]
        var own := String(group_of.get(group[0], "")) if not group.is_empty() else ""
        if not own.is_empty() and not taken.has(own):
            taken[own] = true
            out[i] = own
    for i in groups.size():
        if out[i] != null:
            continue
        var group: Array = groups[i]
        var base := String(category_of.get(group[0], "tools")) if not group.is_empty() else "tools"
        var name := base
        var n := 2
        while taken.has(name):
            name = "%s_%d" % [base, n]
            n += 1
        taken[name] = true
        out[i] = name
    return out


## Whether *element* of the flat order names one of *descriptors*.
static func _is_tool_entry(element: String, descriptors: Array) -> bool:
    for descriptor: SaToolDescriptor in descriptors:
        if SaToolBoxGrid.entry_matches(element, descriptor):
            return true
    return false


## The stored value as groups of known ids, with empties dropped, or an empty
## list for anything that is not an array of arrays of strings.
static func _clean(raw: Variant, known: Dictionary) -> Array:
    var out: Array = []
    if not (raw is Array):
        return out
    var seen: Dictionary = {}
    for group: Variant in raw as Array:
        if not (group is Array):
            continue
        var members: Array = []
        for id: Variant in group as Array:
            var tool_id := String(id)
            if known.has(tool_id) and not seen.has(tool_id):
                members.append(tool_id)
                seen[tool_id] = true
        if not members.is_empty():
            out.append(members)
    return out


## A tool registered since the groups were stored, a module's, joins the group
## holding a tool of its `toolbox_group` or opens one of its own at the end, the
## way [method from_registry] would have drawn it.
##
## In the group it lands after the member the registry lists just before it,
## and last when there is none. The Ellipse Select tool is registered after the
## Marquee, and appended it would sit after a tool dragged in after the Marquee.
static func _with_missing(groups: Array, descriptors: Array) -> Array:
    var present: Dictionary = {}
    for id: Variant in flatten(groups):
        present[id] = true
    var out := groups.duplicate(true)
    var group_of: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        group_of[String(descriptor.id)] = String(descriptor.toolbox_group)
    var before := ""
    for descriptor: SaToolDescriptor in descriptors:
        var id := String(descriptor.id)
        if present.has(id):
            before = id
            continue
        var placed := false
        var own := String(descriptor.toolbox_group)
        for group: Array in out:
            if own.is_empty():
                break
            if group.any(func(member: String) -> bool: return group_of.get(member, "") == own):
                var at := group.find(before)
                group.insert(at + 1 if at >= 0 else group.size(), id)
                placed = true
                break
        if not placed:
            out.append([id])
        present[id] = true
        before = id
    return out


## The key [method from_registry] groups by: the group id when the descriptor
## names one, and the tool's own id behind a prefix no group id can carry,
## so a tool with none is alone.
static func _group_key(descriptor: SaToolDescriptor) -> String:
    var own := String(descriptor.toolbox_group)
    return "group:" + own if not own.is_empty() else "tool:" + String(descriptor.id)


## *groups* in the order *sequence* draws their first members, an id absent from
## the sequence keeping its place after the ones present. The members stay in
## the order they came in, which for the registry's groups is the registry's, so
## a flyout that nobody has dragged lists its rows as it always did.
static func _sorted_by(groups: Array, sequence: Array) -> Array:
    var rank: Dictionary = {}
    for i in sequence.size():
        rank[sequence[i]] = i
    var out := groups.duplicate(true)
    out.sort_custom(func(a: Array, b: Array) -> bool: return int(rank.get(a[0], 1 << 30)) < int(rank.get(b[0], 1 << 30)))
    return out
