## Preferences > Timelapse: the recorder's own folder, settle time and cap, so a
## choice made here or in the docker survives a restart instead of resetting to
## SaRecorder's own defaults. Named apart from the RecorderDocker's own
## auto-generated "Recorder" reorder page.
class_name SaRecorderPage
extends SaSettingsPage


func build(ui: SaPage) -> void:
    var rows := ui.section("Timelapse")
    var folder := rows.path("Folder", SaSettings, ^"recorder_directory")
    folder.named(&"folder").globalized().explain(tr("Where the timelapse writes its frames."))

    # The unit is in the readout beside the slider, "2 s" and "1024 MB", and not
    # in the title, where it read "Settle (s)" over a bare number.
    var settle := rows.slider("Pause before frame", 0.5, 30.0, SaSettings, ^"recorder_settle_seconds")
    settle.named(&"settle").step(0.5).with_suffix(tr(" s"))
    settle.explain(tr("Seconds of quiet after the last edit before a frame is taken."))

    # The row's range is stored units, not shown ones, so a millionth of a
    # megabyte to a tenth would be a trap.
    var cap := rows.slider("Size limit", 1048576.0, 100000.0 * 1048576.0, SaSettings, ^"recorder_cap_bytes")
    cap.named(&"cap").scale(1.0 / 1048576.0).step(1.0).decimals(0).with_suffix(tr(" MB"))
    cap.explain(tr("Stops the recording rather than filling the disk."))
