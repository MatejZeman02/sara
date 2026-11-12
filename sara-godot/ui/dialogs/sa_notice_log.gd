## The last few distinct pop-up messages, newest first.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## [SaMessage.notice] writes every line it is handed here before it shows it, so
## the Info docker can show what a notice said after it has gone from the
## corner. A line said again moves to the front rather than being kept twice,
## because a refusal at tablet rate would otherwise fill the list with one
## sentence.
class_name SaNoticeLog
extends RefCounted

## How many messages are kept.
const KEEP := 3

## The messages, newest first.
static var recent := PackedStringArray()


## Remembers *line*, at the front, and forgets the oldest past [constant KEEP].
static func record(line: String) -> void:
    var text := line.strip_edges()
    if text.is_empty():
        return
    var at := recent.find(text)
    if at == 0:
        return
    if at > 0:
        recent.remove_at(at)
    recent.insert(0, text)
    while recent.size() > KEEP:
        recent.remove_at(recent.size() - 1)


## The messages as one block, newest first, a line each.
static func as_text() -> String:
    return "\n".join(recent)


## Forgets everything, for a suite.
static func clear() -> void:
    recent = PackedStringArray()
