#include "bolt_compression.h"

#include <bzlib.h>
#include <errno.h>
#include <lz4.h>
#include <lz4frame.h>
#include <lzma.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>
#include <zstd.h>

#define BOLT_CHUNK_SIZE (128 * 1024)

static bolt_status_t status_ok(void) {
    bolt_status_t s;
    s.code = 0;
    s.message[0] = '\0';
    return s;
}

static bolt_status_t status_err(int32_t code, const char *fmt, const char *detail) {
    bolt_status_t s;
    s.code = code != 0 ? code : -1;
    if (detail != NULL && detail[0] != '\0') {
        snprintf(s.message, sizeof(s.message), "%s: %s", fmt, detail);
    } else {
        snprintf(s.message, sizeof(s.message), "%s", fmt);
    }
    return s;
}

static int32_t clamp_i32(int32_t v, int32_t lo, int32_t hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

typedef struct {
    uint8_t *data;
    size_t size;
    size_t capacity;
} dyn_buf_t;

static int dyn_buf_init(dyn_buf_t *b, size_t initial_cap) {
    size_t cap = initial_cap > 0 ? initial_cap : 4096;
    b->data = (uint8_t *)malloc(cap);
    if (!b->data) return -1;
    b->size = 0;
    b->capacity = cap;
    return 0;
}

static int dyn_buf_append(dyn_buf_t *b, const uint8_t *src, size_t len) {
    if (len == 0) return 0;
    if (b->size + len > b->capacity) {
        size_t new_cap = b->capacity;
        while (new_cap < b->size + len) {
            if (new_cap > SIZE_MAX / 2) return -1;
            new_cap *= 2;
        }
        uint8_t *next = (uint8_t *)realloc(b->data, new_cap);
        if (!next) return -1;
        b->data = next;
        b->capacity = new_cap;
    }
    memcpy(b->data + b->size, src, len);
    b->size += len;
    return 0;
}

static void dyn_buf_free(dyn_buf_t *b) {
    free(b->data);
    b->data = NULL;
    b->size = 0;
    b->capacity = 0;
}

void bolt_free_buffer(bolt_buffer_t *buf) {
    if (buf && buf->data) {
        free(buf->data);
        buf->data = NULL;
        buf->size = 0;
    }
}

uint32_t bolt_crc32(uint32_t initial, const uint8_t *data, size_t length) {
    if (!data || length == 0) {
        return initial;
    }
    return (uint32_t)crc32_z((uLong)initial, data, (z_size_t)length);
}

/* ============================================================================
 * Generic sink abstraction so buffer and file paths share codec logic
 * ============================================================================ */

typedef struct {
    int is_file;
    int is_null;
    int track_crc;
    FILE *fp;
    dyn_buf_t buf;
    uint32_t crc;
    uint64_t bytes_written;
} bolt_sink_t;

static int sink_write(bolt_sink_t *sink, const uint8_t *data, size_t len) {
    if (len == 0) return 0;
    if (sink->track_crc) {
        sink->crc = bolt_crc32(sink->crc, data, len);
    }
    sink->bytes_written += (uint64_t)len;
    if (sink->is_null) {
        return 0;
    }
    if (sink->is_file) {
        return fwrite(data, 1, len, sink->fp) == len ? 0 : -1;
    }
    return dyn_buf_append(&sink->buf, data, len);
}

typedef struct {
    int is_file;
    FILE *fp;
    const uint8_t *buf;
    size_t buf_len;
    size_t buf_pos;
    uint64_t total_bytes;
    uint64_t bytes_read;
    bolt_progress_cb progress_cb;
    void *progress_ctx;
    bolt_control_cb control_cb;
    void *control_ctx;
} bolt_source_t;

static int source_read(bolt_source_t *src, uint8_t *dst, size_t max_len, size_t *out_len) {
    if (src->control_cb && src->control_cb(src->bytes_read, src->total_bytes, src->control_ctx) != 0) {
        return -2;
    }
    if (src->is_file) {
        size_t n = fread(dst, 1, max_len, src->fp);
        if (ferror(src->fp)) return -1;
        *out_len = n;
        src->bytes_read += n;
    } else {
        size_t rem = src->buf_len - src->buf_pos;
        size_t n = rem < max_len ? rem : max_len;
        if (n > 0) {
            memcpy(dst, src->buf + src->buf_pos, n);
            src->buf_pos += n;
        }
        *out_len = n;
        src->bytes_read += n;
    }
    if (src->progress_cb) {
        src->progress_cb(src->bytes_read, src->total_bytes, src->progress_ctx);
    }
    if (src->control_cb && src->control_cb(src->bytes_read, src->total_bytes, src->control_ctx) != 0) {
        return -2;
    }
    return 0;
}

static int source_read_checked(bolt_source_t *src, uint8_t *dst, size_t max_len, size_t *out_len, bolt_status_t *err_out) {
    int sr = source_read(src, dst, max_len, out_len);
    if (sr == 0) return 0;
    if (sr == -2) {
        *err_out = status_err(BOLT_STATUS_CANCELLED, "Operation cancelled", NULL);
    } else {
        *err_out = status_err(EIO, "Failed reading input", src->is_file ? strerror(errno) : NULL);
    }
    return sr;
}

/* ============================================================================
 * Core compression runners
 * ============================================================================ */

static bolt_status_t run_compress_store(bolt_source_t *src, bolt_sink_t *sink) {
    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf) return status_err(ENOMEM, "Out of memory", NULL);

    bolt_status_t res = status_ok();
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        if (n == 0) break;
        if (sink_write(sink, in_buf, n) != 0) {
            res = status_err(EIO, "Failed writing output", NULL);
            break;
        }
    }
    free(in_buf);
    return res;
}

static bolt_status_t run_compress_deflate(
    bolt_source_t *src,
    bolt_sink_t *sink,
    bolt_container_t container,
    int32_t level
) {
    int lvl = clamp_i32(level, 0, 9);
    int window_bits = (container == BOLT_CONTAINER_GZIP) ? (MAX_WBITS + 16) : (-MAX_WBITS);

    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    int zret = deflateInit2(&strm, lvl, Z_DEFLATED, window_bits, 8, Z_DEFAULT_STRATEGY);
    if (zret != Z_OK) {
        return status_err(zret, "zlib deflateInit2 failed", strm.msg);
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        deflateEnd(&strm);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    int flush = Z_NO_FLUSH;
    do {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        flush = (n == 0) ? Z_FINISH : Z_NO_FLUSH;
        strm.avail_in = (uInt)n;
        strm.next_in = in_buf;

        do {
            strm.avail_out = BOLT_CHUNK_SIZE;
            strm.next_out = out_buf;
            zret = deflate(&strm, flush);
            if (zret == Z_STREAM_ERROR) {
                res = status_err(zret, "zlib deflate failed", strm.msg);
                goto cleanup;
            }
            size_t have = BOLT_CHUNK_SIZE - strm.avail_out;
            if (sink_write(sink, out_buf, have) != 0) {
                res = status_err(EIO, "Failed writing deflate output", NULL);
                goto cleanup;
            }
        } while (strm.avail_out == 0);
    } while (flush != Z_FINISH);

cleanup:
    free(in_buf);
    free(out_buf);
    deflateEnd(&strm);
    return res;
}

static bolt_status_t run_decompress_deflate(
    bolt_source_t *src,
    bolt_sink_t *sink,
    bolt_container_t container
) {
    int window_bits = (container == BOLT_CONTAINER_GZIP) ? (MAX_WBITS + 32) : (-MAX_WBITS);

    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    int zret = inflateInit2(&strm, window_bits);
    if (zret != Z_OK) {
        return status_err(zret, "zlib inflateInit2 failed", strm.msg);
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        inflateEnd(&strm);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        if (n == 0) {
            if (zret != Z_STREAM_END) {
                res = status_err(Z_DATA_ERROR, "Unexpected end of deflate stream", NULL);
            }
            break;
        }

        strm.avail_in = (uInt)n;
        strm.next_in = in_buf;

        do {
            strm.avail_out = BOLT_CHUNK_SIZE;
            strm.next_out = out_buf;
            zret = inflate(&strm, Z_NO_FLUSH);
            if (zret != Z_OK && zret != Z_STREAM_END && zret != Z_BUF_ERROR) {
                res = status_err(zret, "Corrupted deflate stream", strm.msg);
                goto cleanup;
            }
            size_t have = BOLT_CHUNK_SIZE - strm.avail_out;
            if (sink_write(sink, out_buf, have) != 0) {
                res = status_err(EIO, "Failed writing output", NULL);
                goto cleanup;
            }
        } while (strm.avail_out == 0);

        if (zret == Z_STREAM_END) {
            break;
        }
    }

cleanup:
    free(in_buf);
    free(out_buf);
    inflateEnd(&strm);
    return res;
}

static bolt_status_t run_compress_bzip2(bolt_source_t *src, bolt_sink_t *sink, int32_t level) {
    int lvl = clamp_i32(level, 1, 9);
    bz_stream strm;
    memset(&strm, 0, sizeof(strm));
    int ret = BZ2_bzCompressInit(&strm, lvl, 0, 30);
    if (ret != BZ_OK) {
        return status_err(ret, "BZ2_bzCompressInit failed", NULL);
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        BZ2_bzCompressEnd(&strm);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    int action = BZ_RUN;
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        action = (n == 0) ? BZ_FINISH : BZ_RUN;
        strm.next_in = (char *)in_buf;
        strm.avail_in = (unsigned int)n;

        do {
            strm.next_out = (char *)out_buf;
            strm.avail_out = BOLT_CHUNK_SIZE;
            ret = BZ2_bzCompress(&strm, action);
            if (ret != BZ_RUN_OK && ret != BZ_FINISH_OK && ret != BZ_STREAM_END) {
                res = status_err(ret, "BZ2_bzCompress failed", NULL);
                goto cleanup;
            }
            size_t have = BOLT_CHUNK_SIZE - strm.avail_out;
            if (sink_write(sink, out_buf, have) != 0) {
                res = status_err(EIO, "Failed writing bzip2 output", NULL);
                goto cleanup;
            }
        } while (ret == BZ_FINISH_OK || (action == BZ_RUN && strm.avail_in > 0) || strm.avail_out == 0);

        if (ret == BZ_STREAM_END) break;
    }

cleanup:
    free(in_buf);
    free(out_buf);
    BZ2_bzCompressEnd(&strm);
    return res;
}

static bolt_status_t run_decompress_bzip2(bolt_source_t *src, bolt_sink_t *sink) {
    bz_stream strm;
    memset(&strm, 0, sizeof(strm));
    int ret = BZ2_bzDecompressInit(&strm, 0, 0);
    if (ret != BZ_OK) {
        return status_err(ret, "BZ2_bzDecompressInit failed", NULL);
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        BZ2_bzDecompressEnd(&strm);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        if (n == 0) {
            if (ret != BZ_STREAM_END) {
                res = status_err(BZ_DATA_ERROR, "Unexpected end of bzip2 stream", NULL);
            }
            break;
        }
        strm.next_in = (char *)in_buf;
        strm.avail_in = (unsigned int)n;

        do {
            strm.next_out = (char *)out_buf;
            strm.avail_out = BOLT_CHUNK_SIZE;
            ret = BZ2_bzDecompress(&strm);
            if (ret != BZ_OK && ret != BZ_STREAM_END) {
                res = status_err(ret, "Corrupted bzip2 stream", NULL);
                goto cleanup;
            }
            size_t have = BOLT_CHUNK_SIZE - strm.avail_out;
            if (sink_write(sink, out_buf, have) != 0) {
                res = status_err(EIO, "Failed writing output", NULL);
                goto cleanup;
            }
            if (ret == BZ_STREAM_END) goto cleanup;
        } while (strm.avail_out == 0 || strm.avail_in > 0);
    }

cleanup:
    free(in_buf);
    free(out_buf);
    BZ2_bzDecompressEnd(&strm);
    return res;
}

static uint32_t resolve_mt_workers(int32_t requested_workers, uint32_t max_cap) {
    uint32_t hw = bolt_active_cores();
    uint32_t effective_cap = hw < max_cap ? hw : max_cap;
    if (effective_cap < 1) effective_cap = 1;
    if (requested_workers <= 0) {
        return effective_cap;
    }
    uint32_t req = (uint32_t)requested_workers;
    return req < effective_cap ? req : effective_cap;
}

uint32_t bolt_active_cores(void) {
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    return cores > 0 ? (uint32_t)cores : 1;
}

static bolt_status_t run_compress_zstd(bolt_source_t *src, bolt_sink_t *sink, int32_t level, int32_t max_workers) {
    int lvl = clamp_i32(level, 1, ZSTD_maxCLevel());
    ZSTD_CCtx *cctx = ZSTD_createCCtx();
    if (!cctx) return status_err(ENOMEM, "ZSTD_createCCtx failed", NULL);

    ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, lvl);
    ZSTD_CCtx_setParameter(cctx, ZSTD_c_checksumFlag, 1);
    if (max_workers != 1 && src->total_bytes > 512 * 1024) {
        uint32_t workers = resolve_mt_workers(max_workers, 16);
        if (workers > 1) {
            ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, (int)workers);
        }
    }

    size_t in_cap = ZSTD_CStreamInSize();
    size_t out_cap = ZSTD_CStreamOutSize();
    uint8_t *in_buf = (uint8_t *)malloc(in_cap);
    uint8_t *out_buf = (uint8_t *)malloc(out_cap);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        ZSTD_freeCCtx(cctx);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, in_cap, &n, &res) != 0) {
            break;
        }
        int last_chunk = (n == 0);
        ZSTD_EndDirective mode = last_chunk ? ZSTD_e_end : ZSTD_e_continue;
        ZSTD_inBuffer input = { in_buf, n, 0 };

        int finished = 0;
        do {
            ZSTD_outBuffer output = { out_buf, out_cap, 0 };
            size_t remaining = ZSTD_compressStream2(cctx, &output, &input, mode);
            if (ZSTD_isError(remaining)) {
                res = status_err(-1, "Zstandard compression failed", ZSTD_getErrorName(remaining));
                goto cleanup;
            }
            if (sink_write(sink, out_buf, output.pos) != 0) {
                res = status_err(EIO, "Failed writing zstd output", NULL);
                goto cleanup;
            }
            finished = last_chunk ? (remaining == 0) : (input.pos == input.size);
        } while (!finished);

        if (last_chunk) break;
    }

cleanup:
    free(in_buf);
    free(out_buf);
    ZSTD_freeCCtx(cctx);
    return res;
}

static bolt_status_t run_decompress_zstd(bolt_source_t *src, bolt_sink_t *sink) {
    ZSTD_DCtx *dctx = ZSTD_createDCtx();
    if (!dctx) return status_err(ENOMEM, "ZSTD_createDCtx failed", NULL);

    size_t in_cap = ZSTD_DStreamInSize();
    size_t out_cap = ZSTD_DStreamOutSize();
    uint8_t *in_buf = (uint8_t *)malloc(in_cap);
    uint8_t *out_buf = (uint8_t *)malloc(out_cap);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        ZSTD_freeDCtx(dctx);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    size_t last_ret = 0;
    size_t total_in = 0;
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, in_cap, &n, &res) != 0) {
            break;
        }
        if (n == 0) {
            if (total_in == 0 || last_ret != 0) {
                res = status_err(-1, "Incomplete or empty Zstandard stream", NULL);
            }
            break;
        }
        total_in += n;
        ZSTD_inBuffer input = { in_buf, n, 0 };
        while (input.pos < input.size) {
            ZSTD_outBuffer output = { out_buf, out_cap, 0 };
            size_t ret = ZSTD_decompressStream(dctx, &output, &input);
            if (ZSTD_isError(ret)) {
                res = status_err(-1, "Corrupted Zstandard stream", ZSTD_getErrorName(ret));
                goto cleanup;
            }
            if (sink_write(sink, out_buf, output.pos) != 0) {
                res = status_err(EIO, "Failed writing output", NULL);
                goto cleanup;
            }
            last_ret = ret;
        }
    }

cleanup:
    free(in_buf);
    free(out_buf);
    ZSTD_freeDCtx(dctx);
    return res;
}

static bolt_status_t run_compress_xz(bolt_source_t *src, bolt_sink_t *sink, int32_t level, int32_t max_workers) {
    uint32_t preset = (uint32_t)clamp_i32(level, 0, 9);
    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_ret lret = LZMA_OK;

    if (max_workers != 1 && src->total_bytes > 512 * 1024) {
        uint32_t max_threads = preset >= 7 ? 8 : 16;
        uint32_t threads = resolve_mt_workers(max_workers, max_threads);
        if (threads > 1) {
            lzma_mt mt = {
                .flags = 0,
                .threads = threads,
                .block_size = 0,
                .timeout = 0,
                .preset = preset,
                .filters = NULL,
                .check = LZMA_CHECK_CRC64
            };
            lret = lzma_stream_encoder_mt(&strm, &mt);
        } else {
            lret = lzma_easy_encoder(&strm, preset, LZMA_CHECK_CRC64);
        }
    } else {
        lret = lzma_easy_encoder(&strm, preset, LZMA_CHECK_CRC64);
    }

    if (lret != LZMA_OK) {
        return status_err((int32_t)lret, "liblzma encoder init failed", NULL);
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        lzma_end(&strm);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    lzma_action action = LZMA_RUN;
    for (;;) {
        if (strm.avail_in == 0 && action == LZMA_RUN) {
            size_t n = 0;
            if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
                break;
            }
            strm.next_in = in_buf;
            strm.avail_in = n;
            if (n == 0) action = LZMA_FINISH;
        }

        strm.next_out = out_buf;
        strm.avail_out = BOLT_CHUNK_SIZE;
        lret = lzma_code(&strm, action);

        size_t have = BOLT_CHUNK_SIZE - strm.avail_out;
        if (sink_write(sink, out_buf, have) != 0) {
            res = status_err(EIO, "Failed writing xz output", NULL);
            break;
        }
        if (lret == LZMA_STREAM_END) break;
        if (lret != LZMA_OK) {
            res = status_err((int32_t)lret, "liblzma compression failed", NULL);
            break;
        }
    }

    free(in_buf);
    free(out_buf);
    lzma_end(&strm);
    return res;
}

static bolt_status_t run_decompress_xz(bolt_source_t *src, bolt_sink_t *sink) {
    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_ret lret = lzma_stream_decoder(&strm, UINT64_MAX, LZMA_CONCATENATED);
    if (lret != LZMA_OK) {
        return status_err((int32_t)lret, "liblzma decoder init failed", NULL);
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        lzma_end(&strm);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    lzma_action action = LZMA_RUN;
    for (;;) {
        if (strm.avail_in == 0 && action == LZMA_RUN) {
            size_t n = 0;
            if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
                break;
            }
            strm.next_in = in_buf;
            strm.avail_in = n;
            if (n == 0) action = LZMA_FINISH;
        }

        strm.next_out = out_buf;
        strm.avail_out = BOLT_CHUNK_SIZE;
        lret = lzma_code(&strm, action);

        size_t have = BOLT_CHUNK_SIZE - strm.avail_out;
        if (sink_write(sink, out_buf, have) != 0) {
            res = status_err(EIO, "Failed writing output", NULL);
            break;
        }
        if (lret == LZMA_STREAM_END) break;
        if (lret != LZMA_OK) {
            res = status_err((int32_t)lret, "Corrupted xz stream", NULL);
            break;
        }
    }

    free(in_buf);
    free(out_buf);
    lzma_end(&strm);
    return res;
}

static bolt_status_t run_compress_lz4(bolt_source_t *src, bolt_sink_t *sink, int32_t level) {
    LZ4F_cctx *cctx = NULL;
    LZ4F_errorCode_t err = LZ4F_createCompressionContext(&cctx, LZ4F_VERSION);
    if (LZ4F_isError(err)) {
        return status_err(-1, "LZ4F_createCompressionContext failed", LZ4F_getErrorName(err));
    }

    LZ4F_preferences_t prefs;
    memset(&prefs, 0, sizeof(prefs));
    prefs.frameInfo.blockSizeID = LZ4F_max1MB;
    prefs.frameInfo.blockMode = LZ4F_blockLinked;
    prefs.frameInfo.contentChecksumFlag = LZ4F_contentChecksumEnabled;
    prefs.frameInfo.contentSize = src->total_bytes;
    prefs.compressionLevel = clamp_i32(level, 0, 12);

    size_t out_cap = LZ4F_compressBound(BOLT_CHUNK_SIZE, &prefs);
    if (out_cap < 64) out_cap = 64;
    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(out_cap);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        LZ4F_freeCompressionContext(cctx);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    size_t hdr_size = LZ4F_compressBegin(cctx, out_buf, out_cap, &prefs);
    if (LZ4F_isError(hdr_size)) {
        res = status_err(-1, "LZ4F_compressBegin failed", LZ4F_getErrorName(hdr_size));
        goto cleanup;
    }
    if (sink_write(sink, out_buf, hdr_size) != 0) {
        res = status_err(EIO, "Failed writing LZ4 header", NULL);
        goto cleanup;
    }

    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        if (n == 0) break;
        size_t written = LZ4F_compressUpdate(cctx, out_buf, out_cap, in_buf, n, NULL);
        if (LZ4F_isError(written)) {
            res = status_err(-1, "LZ4F_compressUpdate failed", LZ4F_getErrorName(written));
            goto cleanup;
        }
        if (sink_write(sink, out_buf, written) != 0) {
            res = status_err(EIO, "Failed writing LZ4 block", NULL);
            goto cleanup;
        }
    }

    size_t end_size = LZ4F_compressEnd(cctx, out_buf, out_cap, NULL);
    if (LZ4F_isError(end_size)) {
        res = status_err(-1, "LZ4F_compressEnd failed", LZ4F_getErrorName(end_size));
        goto cleanup;
    }
    if (sink_write(sink, out_buf, end_size) != 0) {
        res = status_err(EIO, "Failed writing LZ4 trailer", NULL);
        goto cleanup;
    }

cleanup:
    free(in_buf);
    free(out_buf);
    LZ4F_freeCompressionContext(cctx);
    return res;
}

static bolt_status_t run_decompress_lz4(bolt_source_t *src, bolt_sink_t *sink) {
    LZ4F_dctx *dctx = NULL;
    LZ4F_errorCode_t err = LZ4F_createDecompressionContext(&dctx, LZ4F_VERSION);
    if (LZ4F_isError(err)) {
        return status_err(-1, "LZ4F_createDecompressionContext failed", LZ4F_getErrorName(err));
    }

    uint8_t *in_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    uint8_t *out_buf = (uint8_t *)malloc(BOLT_CHUNK_SIZE);
    if (!in_buf || !out_buf) {
        free(in_buf);
        free(out_buf);
        LZ4F_freeDecompressionContext(dctx);
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t res = status_ok();
    size_t ret = 1;
    size_t total_in = 0;
    for (;;) {
        size_t n = 0;
        if (source_read_checked(src, in_buf, BOLT_CHUNK_SIZE, &n, &res) != 0) {
            break;
        }
        if (n == 0) {
            if (total_in == 0 || ret != 0) {
                res = status_err(-1, "Incomplete or empty LZ4 frame", NULL);
            }
            break;
        }
        total_in += n;
        size_t pos = 0;
        while (pos < n) {
            size_t dst_size = BOLT_CHUNK_SIZE;
            size_t src_size = n - pos;
            ret = LZ4F_decompress(dctx, out_buf, &dst_size, in_buf + pos, &src_size, NULL);
            if (LZ4F_isError(ret)) {
                res = status_err(-1, "Corrupted LZ4 stream", LZ4F_getErrorName(ret));
                goto cleanup;
            }
            if (sink_write(sink, out_buf, dst_size) != 0) {
                res = status_err(EIO, "Failed writing output", NULL);
                goto cleanup;
            }
            pos += src_size;
            if (src_size == 0 && dst_size == 0) break;
        }
    }

cleanup:
    free(in_buf);
    free(out_buf);
    LZ4F_freeDecompressionContext(dctx);
    return res;
}

/* ============================================================================
 * Public API: Buffer and File entry points
 * ============================================================================ */

static bolt_status_t dispatch_compress(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    bolt_source_t *src,
    bolt_sink_t *sink,
    int32_t max_workers
) {
    switch (algo) {
        case BOLT_ALGO_STORE:
            return run_compress_store(src, sink);
        case BOLT_ALGO_DEFLATE:
            return run_compress_deflate(src, sink, container, level);
        case BOLT_ALGO_BZIP2:
            return run_compress_bzip2(src, sink, level);
        case BOLT_ALGO_ZSTD:
            return run_compress_zstd(src, sink, level, max_workers);
        case BOLT_ALGO_XZ:
            return run_compress_xz(src, sink, level, max_workers);
        case BOLT_ALGO_LZ4:
            return run_compress_lz4(src, sink, level);
        default:
            return status_err(EINVAL, "Unsupported compression algorithm", NULL);
    }
}

static bolt_status_t dispatch_decompress(
    bolt_algo_t algo,
    bolt_container_t container,
    bolt_source_t *src,
    bolt_sink_t *sink
) {
    switch (algo) {
        case BOLT_ALGO_STORE:
            return run_compress_store(src, sink);
        case BOLT_ALGO_DEFLATE:
            return run_decompress_deflate(src, sink, container);
        case BOLT_ALGO_BZIP2:
            return run_decompress_bzip2(src, sink);
        case BOLT_ALGO_ZSTD:
            return run_decompress_zstd(src, sink);
        case BOLT_ALGO_XZ:
            return run_decompress_xz(src, sink);
        case BOLT_ALGO_LZ4:
            return run_decompress_lz4(src, sink);
        default:
            return status_err(EINVAL, "Unsupported decompression algorithm", NULL);
    }
}

bolt_status_t bolt_compress_buffer(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output
) {
    return bolt_compress_buffer_ex(algo, container, level, input, input_len, output, NULL, NULL);
}

bolt_status_t bolt_compress_buffer_ex(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output,
    bolt_control_cb control_cb,
    void *ctx
) {
    return bolt_compress_buffer_mt(algo, container, level, input, input_len, output, 1, control_cb, ctx);
}

bolt_status_t bolt_compress_buffer_mt(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output,
    int32_t allow_mt,
    bolt_control_cb control_cb,
    void *ctx
) {
    return bolt_compress_buffer_workers(
        algo,
        container,
        level,
        input,
        input_len,
        output,
        allow_mt ? 0 : 1,
        control_cb,
        ctx
    );
}

bolt_status_t bolt_compress_buffer_workers(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output,
    int32_t max_workers,
    bolt_control_cb control_cb,
    void *ctx
) {
    if (!output) return status_err(EINVAL, "Output pointer is NULL", NULL);
    output->data = NULL;
    output->size = 0;

    if (input_len > 0 && !input) {
        return status_err(EINVAL, "Input pointer is NULL", NULL);
    }

    bolt_source_t src = {
        .is_file = 0,
        .fp = NULL,
        .buf = input ? input : (const uint8_t *)"",
        .buf_len = input_len,
        .buf_pos = 0,
        .total_bytes = input_len,
        .bytes_read = 0,
        .progress_cb = NULL,
        .progress_ctx = NULL,
        .control_cb = control_cb,
        .control_ctx = ctx
    };

    bolt_sink_t sink = {0};
    sink.is_file = 0;
    sink.fp = NULL;
    size_t initial = input_len > 0 ? (input_len < 4096 ? 4096 : input_len / 2 + 1024) : 1024;
    if (dyn_buf_init(&sink.buf, initial) != 0) {
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    int32_t sanitized_workers = max_workers < 0 ? 0 : max_workers;
    bolt_status_t status = dispatch_compress(algo, container, level, &src, &sink, sanitized_workers);
    if (status.code != 0) {
        dyn_buf_free(&sink.buf);
        return status;
    }

    output->data = sink.buf.data;
    output->size = sink.buf.size;
    return status;
}

bolt_status_t bolt_decompress_buffer(
    bolt_algo_t algo,
    bolt_container_t container,
    const uint8_t *input,
    size_t input_len,
    size_t expected_output_len,
    bolt_buffer_t *output
) {
    return bolt_decompress_buffer_ex(algo, container, input, input_len, expected_output_len, output, NULL, NULL);
}

bolt_status_t bolt_decompress_buffer_ex(
    bolt_algo_t algo,
    bolt_container_t container,
    const uint8_t *input,
    size_t input_len,
    size_t expected_output_len,
    bolt_buffer_t *output,
    bolt_control_cb control_cb,
    void *ctx
) {
    if (!output) return status_err(EINVAL, "Output pointer is NULL", NULL);
    output->data = NULL;
    output->size = 0;

    if (input_len > 0 && !input) {
        return status_err(EINVAL, "Input pointer is NULL", NULL);
    }
    if (algo == BOLT_ALGO_STORE && input_len == 0) {
        output->data = (uint8_t *)malloc(1);
        output->size = 0;
        return status_ok();
    }

    bolt_source_t src = {
        .is_file = 0,
        .fp = NULL,
        .buf = input ? input : (const uint8_t *)"",
        .buf_len = input_len,
        .buf_pos = 0,
        .total_bytes = input_len,
        .bytes_read = 0,
        .progress_cb = NULL,
        .progress_ctx = NULL,
        .control_cb = control_cb,
        .control_ctx = ctx
    };

    bolt_sink_t sink = {0};
    sink.is_file = 0;
    sink.fp = NULL;
    size_t initial = expected_output_len > 0 ? expected_output_len : (input_len * 2 + 1024);
    if (initial > 64 * 1024 * 1024) initial = 64 * 1024 * 1024;
    if (dyn_buf_init(&sink.buf, initial) != 0) {
        return status_err(ENOMEM, "Out of memory", NULL);
    }

    bolt_status_t status = dispatch_decompress(algo, container, &src, &sink);
    if (status.code != 0) {
        dyn_buf_free(&sink.buf);
        return status;
    }

    output->data = sink.buf.data;
    output->size = sink.buf.size;
    return status;
}

static bolt_status_t run_compress_file_internal(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const char *src_path,
    const char *dst_path,
    int32_t max_workers,
    bolt_progress_cb progress_cb,
    bolt_control_cb control_cb,
    void *ctx
) {
    if (!src_path || !dst_path) return status_err(EINVAL, "Invalid path", NULL);

    struct stat st;
    if (stat(src_path, &st) != 0) {
        return status_err(errno, "Cannot stat input file", strerror(errno));
    }

    FILE *in_fp = fopen(src_path, "rb");
    if (!in_fp) return status_err(errno, "Cannot open input file", strerror(errno));

    FILE *out_fp = fopen(dst_path, "wb");
    if (!out_fp) {
        fclose(in_fp);
        return status_err(errno, "Cannot create output file", strerror(errno));
    }

    bolt_source_t src = {
        .is_file = 1,
        .fp = in_fp,
        .buf = NULL,
        .buf_len = 0,
        .buf_pos = 0,
        .total_bytes = (uint64_t)st.st_size,
        .bytes_read = 0,
        .progress_cb = progress_cb,
        .progress_ctx = ctx,
        .control_cb = control_cb,
        .control_ctx = ctx
    };
    bolt_sink_t sink = { .is_file = 1, .fp = out_fp };

    int32_t sanitized_workers = max_workers < 0 ? 0 : max_workers;
    bolt_status_t status = dispatch_compress(algo, container, level, &src, &sink, sanitized_workers);
    fclose(in_fp);
    if (fclose(out_fp) != 0 && status.code == 0) {
        status = status_err(errno, "Failed closing output file", strerror(errno));
    }
    if (status.code != 0) {
        unlink(dst_path);
    }
    return status;
}

bolt_status_t bolt_compress_file(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const char *src_path,
    const char *dst_path,
    bolt_progress_cb progress_cb,
    void *ctx
) {
    return run_compress_file_internal(algo, container, level, src_path, dst_path, 0, progress_cb, NULL, ctx);
}

bolt_status_t bolt_compress_file_workers(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const char *src_path,
    const char *dst_path,
    int32_t max_workers,
    bolt_control_cb control_cb,
    void *ctx
) {
    return run_compress_file_internal(algo, container, level, src_path, dst_path, max_workers, NULL, control_cb, ctx);
}

static bolt_status_t run_decompress_file_internal(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    const char *dst_path,
    int is_verify_only,
    uint32_t *out_crc32,
    uint64_t *out_uncompressed_size,
    bolt_progress_cb progress_cb,
    bolt_control_cb control_cb,
    void *ctx
) {
    if (!src_path || (!is_verify_only && !dst_path)) {
        return status_err(EINVAL, "Invalid path", NULL);
    }

    struct stat st;
    if (stat(src_path, &st) != 0) {
        return status_err(errno, "Cannot stat input file", strerror(errno));
    }

    FILE *in_fp = fopen(src_path, "rb");
    if (!in_fp) return status_err(errno, "Cannot open input file", strerror(errno));

    FILE *out_fp = NULL;
    if (!is_verify_only) {
        out_fp = fopen(dst_path, "wb");
        if (!out_fp) {
            fclose(in_fp);
            return status_err(errno, "Cannot create output file", strerror(errno));
        }
    }

    bolt_source_t src = {
        .is_file = 1,
        .fp = in_fp,
        .buf = NULL,
        .buf_len = 0,
        .buf_pos = 0,
        .total_bytes = (uint64_t)st.st_size,
        .bytes_read = 0,
        .progress_cb = progress_cb,
        .progress_ctx = ctx,
        .control_cb = control_cb,
        .control_ctx = ctx
    };
    bolt_sink_t sink = {
        .is_file = is_verify_only ? 0 : 1,
        .is_null = is_verify_only ? 1 : 0,
        .track_crc = is_verify_only ? 1 : 0,
        .fp = out_fp,
        .crc = 0,
        .bytes_written = 0
    };

    bolt_status_t status = dispatch_decompress(algo, container, &src, &sink);
    fclose(in_fp);
    if (out_fp) {
        if (fclose(out_fp) != 0 && status.code == 0) {
            status = status_err(errno, "Failed closing output file", strerror(errno));
        }
        if (status.code != 0) {
            unlink(dst_path);
        }
    }
    if (status.code == 0) {
        if (out_crc32) *out_crc32 = sink.crc;
        if (out_uncompressed_size) *out_uncompressed_size = sink.bytes_written;
    }
    return status;
}

bolt_status_t bolt_decompress_file(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    const char *dst_path,
    bolt_progress_cb progress_cb,
    void *ctx
) {
    return run_decompress_file_internal(algo, container, src_path, dst_path, 0, NULL, NULL, progress_cb, NULL, ctx);
}

bolt_status_t bolt_decompress_file_ex(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    const char *dst_path,
    bolt_control_cb control_cb,
    void *ctx
) {
    return run_decompress_file_internal(algo, container, src_path, dst_path, 0, NULL, NULL, NULL, control_cb, ctx);
}

bolt_status_t bolt_verify_file(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    uint32_t *out_crc32,
    uint64_t *out_uncompressed_size,
    bolt_control_cb control_cb,
    void *ctx
) {
    return run_decompress_file_internal(algo, container, src_path, NULL, 1, out_crc32, out_uncompressed_size, NULL, control_cb, ctx);
}

const char *bolt_zlib_version(void) { return zlibVersion(); }
const char *bolt_zstd_version(void) { return ZSTD_versionString(); }
const char *bolt_lzma_version(void) { return lzma_version_string(); }
const char *bolt_bz2_version(void) { return BZ2_bzlibVersion(); }
const char *bolt_lz4_version(void) { return LZ4_versionString(); }
