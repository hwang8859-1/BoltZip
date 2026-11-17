#ifndef BOLT_COMPRESSION_H
#define BOLT_COMPRESSION_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BOLT_ALGO_STORE   = 0,
    BOLT_ALGO_DEFLATE = 1,
    BOLT_ALGO_BZIP2   = 2,
    BOLT_ALGO_ZSTD    = 3,
    BOLT_ALGO_XZ      = 4,
    BOLT_ALGO_LZ4     = 5
} bolt_algo_t;

typedef enum {
    BOLT_CONTAINER_RAW  = 0, /* Raw deflate (RFC 1951) for ZIP; raw stream otherwise */
    BOLT_CONTAINER_GZIP = 1  /* Gzip wrapper (RFC 1952) for DEFLATE */
} bolt_container_t;

#define BOLT_STATUS_CANCELLED (-499)

typedef struct {
    int32_t code;       /* 0 on success, BOLT_STATUS_CANCELLED on cancel, non-zero on error */
    char message[256];  /* Human-readable error message */
} bolt_status_t;

typedef struct {
    uint8_t *data;
    size_t size;
} bolt_buffer_t;

void bolt_free_buffer(bolt_buffer_t *buf);

uint32_t bolt_crc32(uint32_t initial, const uint8_t *data, size_t length);

/* Progress & pause/cancel control callback (return 0 to continue, non-zero to cancel) */
typedef int (*bolt_control_cb)(uint64_t bytes_read, uint64_t total_bytes, void *ctx);

/* In-memory compression & decompression */
bolt_status_t bolt_compress_buffer(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output
);

bolt_status_t bolt_compress_buffer_ex(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output,
    bolt_control_cb control_cb,
    void *ctx
);

bolt_status_t bolt_decompress_buffer(
    bolt_algo_t algo,
    bolt_container_t container,
    const uint8_t *input,
    size_t input_len,
    size_t expected_output_len, /* 0 if unknown */
    bolt_buffer_t *output
);

bolt_status_t bolt_decompress_buffer_ex(
    bolt_algo_t algo,
    bolt_container_t container,
    const uint8_t *input,
    size_t input_len,
    size_t expected_output_len, /* 0 if unknown */
    bolt_buffer_t *output,
    bolt_control_cb control_cb,
    void *ctx
);

/* File-to-file streaming compression & decompression (low memory footprint) */
typedef void (*bolt_progress_cb)(uint64_t bytes_read, uint64_t total_bytes, void *ctx);

bolt_status_t bolt_compress_file(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const char *src_path,
    const char *dst_path,
    bolt_progress_cb progress_cb,
    void *ctx
);

bolt_status_t bolt_decompress_file(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    const char *dst_path,
    bolt_progress_cb progress_cb,
    void *ctx
);

/* Version strings of linked open-source engines */
const char *bolt_zlib_version(void);
const char *bolt_zstd_version(void);
const char *bolt_lzma_version(void);
const char *bolt_bz2_version(void);
const char *bolt_lz4_version(void);

#ifdef __cplusplus
}
#endif

#endif /* BOLT_COMPRESSION_H */
