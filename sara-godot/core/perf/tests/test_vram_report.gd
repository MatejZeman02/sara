## VRAM three ways: the driver's own count, Sara's texture accounting, and
## a chunk count that never assumes an edge length.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func test_sara_and_device_textures_track_one_allocation() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var on_main_device := RenderingServer.get_rendering_device() != null

    var before_sara := SaTexture.allocated_bytes
    var before_device := rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES)

    var texture := SaTexture.new(Vector2i(256, 256), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    assert_eq(texture.bytes, 1048576, "a 256x256 RGBA32F texture is exactly 1048576 bytes")
    assert_eq(SaTexture.allocated_bytes - before_sara, texture.bytes, "sara_textures grows by the same figure")

    var after_create := rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES)
    assert_true(after_create - before_device >= texture.bytes, "device_textures grows by at least what Sara counted")

    texture = null
    assert_eq(SaTexture.allocated_bytes, before_sara, "sara_textures falls back the moment the texture is dropped")

    if on_main_device:
        # The main device defers the free by its own frame delay. The local
        # fallback never gives VRAM back without a submit() and a sync() Sara
        # does not make, so that half runs only on the main device.
        RenderingServer.force_draw(false)
        RenderingServer.force_draw(false)
        var after_free := rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES)
        assert_true(after_free < after_create, "device_textures drops once the driver has actually freed the texture")
        # Whether the figure then lands on the start or short of it is the
        # engine's, drawing whatever the suite before this one left in the
        # tree, and not asserted. It landed short while a message dialog suite
        # ran just before, and on the start once that suite moved beside
        # its dialog, so it said something about the order and nothing about
        # Sara's accounting.


func test_block_agrees_with_allocated_bytes_and_holds_no_readback() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var block := SaVramReport.block(easel.document)

    assert_eq(block["sara_textures"], SaTexture.allocated_bytes, "sara_textures is the same figure vram_bytes reports")
    assert_true(block["unaccounted_textures"] >= 0, "the driver never reports less than Sara's own accounting")

    print("SaVramReport.block: %s" % JSON.stringify(block))

    easel.free()


func test_a_new_chunk_moves_the_total_by_one() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var before: int = SaVramReport.block(easel.document)["chunks"]["total"]

    var chunk := easel.document.active_layer.get_or_create_chunk(Vector2i(0, 0))
    var after_block := SaVramReport.block(easel.document)

    assert_eq(
        after_block["chunks"]["total"] - before, 1, "one chunk allocated on the active layer moves the total by exactly one"
    )
    assert_eq(after_block["chunk_edge"], chunk.pixel_size(), "chunk_edge is asked of the chunk, never assumed")

    easel.free()
