## The `autosave` step: main's autosave run once, now, and waited for until the
## file is on disk.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Without it a scenario that measures what an autosave copies would wait out
## the autosave's interval, minutes, and then guess when the background save
## had ended. This runs the save the timer would, to the
## same target, and drives it to its end before the next step.
class_name SaScenarioAutosave
extends RefCounted

const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Runs the autosave now: main's autosave once, waited for until the file it
## writes is on disk, with the result read in the autosave's end line, `SaSadSave: wrote <path> in
## <n> ms, <n> blobs compressed and <n> copied`, printed just before the step's
## own, `{"autosave": true}`. The target is the autosave's own, the recovery
## copy beside the document unless the painter's setting writes the working
## file. The document is marked modified first, as the timer only runs for a
## modified one, so the copy is kept. The autosave is read off main's node as
## the state report reads it, since its class is inside `core/sad-file` and the
## facade does not answer it. With *over_frames*, which the door asks for,
## the step returns once the save is asked for and the door holds its answer
## until the file is on disk, so the frames of the save are the ones the
## painter's timer would draw, and the end line still comes before the answer.
static func capture(run: CaptureRun, over_frames := false) -> String:
    var main_node := run.tree().current_scene
    var autosave: Node = main_node.autosave if main_node != null and "autosave" in main_node else null
    if autosave == null or autosave.document == null:
        return "SaCapture: autosave -> there is no autosave with a document"
    var document: SaDocument = autosave.document
    document.modified = true
    var err: Error = autosave.save_now()
    if err != OK:
        return "SaCapture: autosave -> %s" % error_string(err)
    if over_frames:
        return "SaCapture: autosave -> asked, written over frames, its end line says what it compressed and copied"
    if not SaSadFile.finish_saves():
        return "SaCapture: autosave -> still running after a minute"
    return "SaCapture: autosave -> written, its end line above says what it compressed and copied"
