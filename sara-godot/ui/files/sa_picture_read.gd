## The picture File > Open reads, read where the window does not wait for it.
##
## A sixteen-bit PNG is decoded in GDScript (`SaPng16Decode`), which takes
## seconds for a large one, and on the main thread the window drew nothing for
## all of them and a painter took Sara for hung. Here the decode runs as a
## `WorkerThreadPool` task while the window goes on drawing frames, and the
## open resumes on the frame after it finishes, where the rest of the read,
## which may report a refusal, runs as before.
##
## Every other picture reads at once, on the calling frame, as it always did:
## [method read] does not yield for it, so a caller that awaits it carries on
## within the same call, and the suites that open a file and look at once
## still see the document.
class_name SaPictureRead
extends RefCounted


## The picture at *path*, or null with the reason reported, as
## `SaImageImport.read` answers. Awaited, it yields frames of *host*'s tree
## while a sixteen-bit PNG decodes on a worker, and none for anything else.
static func read(host: Node, path: String) -> Image:
    if not SaImageImport.reads_png16(path) or not host.is_inside_tree():
        return SaImageImport.read(path)
    var job := Job.new(path)
    var task := WorkerThreadPool.add_task(job.run)
    var tree := host.get_tree()
    while not WorkerThreadPool.is_task_completed(task):
        await tree.process_frame
    WorkerThreadPool.wait_for_task_completion(task)
    return SaImageImport.read_png_decoded(path, job.decoded)


## One decode, the part a worker runs. It writes only its own answer, read
## once the task is complete.
class Job:
    extends RefCounted

    ## The pixels [method run] decoded, or null when the file would not unpack.
    var decoded: Image = null
    var _path: String

    func _init(path: String) -> void:
        _path = path

    func run() -> void:
        decoded = SaImageImport.decode_png16(_path)
