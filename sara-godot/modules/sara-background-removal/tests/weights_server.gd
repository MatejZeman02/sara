## A local HTTP server for the module's suites: one file of given bytes, sent a
## piece a frame so a download's progress is read while it runs, and a log of
## every request it was sent.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends Node

## The bytes sent a frame, so a file of a few hundred KiB takes many frames.
const PIECE := 16384

## The request lines received, one a request, `GET /u2netp.pth HTTP/1.1`.
var requests: PackedStringArray = PackedStringArray()
## The port it listens on, 0 when no port could be had.
var port: int = 0

var _body: PackedByteArray = PackedByteArray()
var _server := TCPServer.new()
## The connections open now, each { peer, asked, sent, header }.
var _open: Array[Dictionary] = []


## *body* is what every request is answered with.
func _init(body: PackedByteArray) -> void:
    name = "WeightsServer"
    _body = body
    for tried: int in range(47100, 47200):
        if _server.listen(tried, "127.0.0.1") == OK:
            port = tried
            return


## The address of the file it serves.
func url() -> String:
    return "http://127.0.0.1:%d/u2netp.pth" % port


func _process(_delta: float) -> void:
    while _server.is_connection_available():
        _open.append({"peer": _server.take_connection(), "asked": "", "sent": -1})
    for each: Dictionary in _open.duplicate():
        var peer: StreamPeerTCP = each["peer"]
        peer.poll()
        if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
            _open.erase(each)
            continue
        if each["sent"] < 0:
            var waiting := peer.get_available_bytes()
            if waiting > 0:
                each["asked"] += peer.get_utf8_string(waiting)
            if not String(each["asked"]).contains("\r\n\r\n"):
                continue
            requests.append(String(each["asked"]).get_slice("\r\n", 0))
            var head := (
                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
                % _body.size()
            )
            peer.put_data(head.to_utf8_buffer())
            each["sent"] = 0
            continue
        var from: int = each["sent"]
        var upto := mini(from + PIECE, _body.size())
        if upto > from:
            peer.put_data(_body.slice(from, upto))
            each["sent"] = upto
        else:
            peer.disconnect_from_host()
            _open.erase(each)


func _exit_tree() -> void:
    for each: Dictionary in _open:
        (each["peer"] as StreamPeerTCP).disconnect_from_host()
    _open.clear()
    _server.stop()
