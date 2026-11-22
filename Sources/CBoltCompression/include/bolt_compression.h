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
);

bolt_status_t bolt_compress_buffer_workers(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const uint8_t *input,
    size_t input_len,
    bolt_buffer_t *output,
    int32_t max_workers, /* 0 = auto, 1 = single-threaded, >1 = explicit thread cap */
    bolt_control_cb control_cb,
    void *ctx
);

uint32_t bolt_active_cores(void);

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
    uint64_t exact_output_len, /* UINT64_MAX if unknown */
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

bolt_status_t bolt_compress_file_workers(
    bolt_algo_t algo,
    bolt_container_t container,
    int32_t level,
    const char *src_path,
    const char *dst_path,
    int32_t max_workers,
    bolt_control_cb control_cb,
    void *ctx
);

bolt_status_t bolt_compress_gzip_file_named(
    int32_t level,
    const char *src_path,
    const char *dst_path,
    const char *gzip_name,
    uint32_t gzip_mtime,
    int32_t max_workers,
    bolt_control_cb control_cb,
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

bolt_status_t bolt_decompress_file_ex(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    const char *dst_path,
    uint64_t exact_output_len, /* UINT64_MAX if unknown */
    bolt_control_cb control_cb,
    void *ctx
);

bolt_status_t bolt_decompress_file_prefix(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    size_t max_output_len,
    bolt_buffer_t *output
);

bolt_status_t bolt_verify_file(
    bolt_algo_t algo,
    bolt_container_t container,
    const char *src_path,
    uint32_t *out_crc32,
    uint64_t *out_uncompressed_size,
    uint64_t exact_output_len, /* UINT64_MAX if unknown */
    bolt_control_cb control_cb,
    void *ctx
);

/* Version strings of linked open-source engines */
const char *bolt_zlib_version(void);
const char *bolt_zstd_version(void);
const char *bolt_lzma_version(void);
const char *bolt_bz2_version(void);
const char *bolt_lz4_version(void);
const char *bolt_libarchive_version(void);

/* ============================================================================
 * libarchive Bridge (RAR / RAR5 / 7z / ISO / CAB / XAR + Passphrase + Multi-Volume)
 * ============================================================================ */

#define BOLT_LA_ERR_PASSWORD_REQUIRED (-1001)
#define BOLT_LA_ERR_WRONG_PASSWORD    (-1002)
#define BOLT_LA_ERR_CANCELLED         (-499)

/* Content detection uses libarchive's stable format/filter identifiers. */
int32_t bolt_la_probe(const char *path, int32_t *format, int32_t *filter);
void *bolt_la_7z_open(const char *path, const char *options, char *err, size_t err_cap);
int32_t bolt_la_7z_header(void *writer, const char *path, uint8_t kind,
    const char *link_target, uint64_t size, uint16_t permissions, int64_t mtime,
    char *err, size_t err_cap);
int32_t bolt_la_7z_write(void *writer, const uint8_t *data, size_t size, char *err, size_t err_cap);
int32_t bolt_la_7z_close(void *writer, char *err, size_t err_cap);
void bolt_la_7z_free(void *writer);

typedef struct {
    const char *path;
    const uint8_t *raw_path_bytes;
    size_t raw_path_len;
    uint8_t path_is_utf8;
    uint8_t is_directory;
    uint8_t is_symlink;
    uint8_t is_encrypted;
    uint64_t size;
    int64_t mtime;
    uint16_t permissions;
    const char *format_name;
    const char *symlink_target;
} bolt_la_entry_info_t;

typedef int (*bolt_la_entry_cb)(const bolt_la_entry_info_t *info, void *ctx);
typedef int (*bolt_la_chunk_cb)(const uint8_t *data, size_t len, void *ctx);
typedef void (*bolt_la_test_cb)(const char *path, int status_code, const char *detail, void *ctx);

int32_t bolt_la_list(
    const char **paths,
    size_t path_count,
    const char *password,
    bolt_la_entry_cb entry_cb,
    void *ctx,
    char *err_buf,
    size_t err_cap
);

int32_t bolt_la_read_entry(
    const char **paths,
    size_t path_count,
    const char *target_path,
    int target_match_raw_fallback,
    const char *password,
    bolt_buffer_t *output,
    char *err_buf,
    size_t err_cap
);

int32_t bolt_la_extract_stream(
    const char **paths,
    size_t path_count,
    const char *password,
    bolt_la_entry_cb on_entry_header,
    bolt_la_chunk_cb on_entry_chunk,
    void *ctx,
    char *err_buf,
    size_t err_cap
);

int32_t bolt_la_test_integrity(
    const char **paths,
    size_t path_count,
    const char *password,
    bolt_la_test_cb on_result,
    void *ctx,
    char *err_buf,
    size_t err_cap
);

#ifdef __cplusplus
}
#endif

#endif /* BOLT_COMPRESSION_H */
