## A MIDI message from the driver's thread reaches the window. Godot's MIDI
## drivers hand a message to the engine from a thread of their own, and Sara
## keeps input accumulation off for the pen, so a message is dispatched on the
## main thread only when the engine buffers events and flushes them there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The setting is the project's and a suite cannot start a driver thread, so it
## is the setting that is asserted.
extends "res://tests/test_framework.gd"


## The Done when: the project buffers input and flushes it on the main thread.
func test_the_project_flushes_buffered_events_on_the_main_thread() -> void:
    assert_true(
        bool(ProjectSettings.get_setting("input_devices/buffering/agile_event_flushing", false)),
        "agile event flushing is on, or a message from the driver's thread is dropped"
    )
