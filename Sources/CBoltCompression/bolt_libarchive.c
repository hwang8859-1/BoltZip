#include "bolt_compression.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* ============================================================================
 * System /usr/lib/libarchive.2.dylib ABI declarations (macOS SDK system dylib)
 * ============================================================================ */

struct archive;
struct archive_entry;

#define BOLT_ARCHIVE_EOF    1
#define BOLT_ARCHIVE_OK     0
#define BOLT_ARCHIVE_RETRY  (-10)
#define BOLT_ARCHIVE_WARN   (-20)
#define BOLT_ARCHIVE_FAILED (-25)
#define BOLT_ARCHIVE_FATAL  (-30)

extern struct archive *archive_read_new(void);
extern int archive_read_support_format_rar(struct archive *a);
extern int archive_read_support_format_rar5(struct archive *a);
extern int archive_read_support_format_7zip(struct archive *a);
extern int archive_read_support_format_iso9660(struct archive *a);
extern int archive_read_support_format_cab(struct archive *a);
extern int archive_read_support_format_xar(struct archive *a);
extern int archive_read_support_format_all(struct archive *a);
extern int archive_read_support_format_raw(struct archive *a);
extern int archive_read_support_filter_all(struct archive *a);
extern int archive_read_add_passphrase(struct archive *a, const char *passphrase);
extern int archive_read_open_filename(struct archive *a, const char *filename, size_t block_size);
extern int archive_read_open_filenames(struct archive *a, const char **filenames, size_t block_size);
extern int archive_read_next_header(struct archive *a, struct archive_entry **entry);
extern ssize_t archive_read_data(struct archive *a, void *buff, size_t len);
extern int archive_read_data_skip(struct archive *a);
extern int archive_read_free(struct archive *a);

extern const char *archive_error_string(struct archive *a);
extern const char *archive_format_name(struct archive *a);
extern const char *archive_version_string(void);
extern const char *archive_version_details(void);
extern int archive_format(struct archive *a);
extern int archive_filter_code(struct archive *a, int filter);
extern struct archive *archive_write_new(void);
extern int archive_write_set_format_7zip(struct archive *a);
extern int archive_write_set_options(struct archive *a, const char *options);
extern int archive_write_open_filename(struct archive *a, const char *path);
extern int archive_write_header(struct archive *a, struct archive_entry *entry);
extern ssize_t archive_write_data(struct archive *a, const void *data, size_t size);
extern int archive_write_close(struct archive *a);
extern int archive_write_fail(struct archive *a);
extern int archive_write_free(struct archive *a);
extern struct archive_entry *archive_entry_new(void);
extern void archive_entry_free(struct archive_entry *entry);
extern void archive_entry_set_pathname_utf8(struct archive_entry *entry, const char *path);
extern void archive_entry_set_symlink_utf8(struct archive_entry *entry, const char *target);
extern void archive_entry_set_filetype(struct archive_entry *entry, unsigned int type);
extern void archive_entry_set_perm(struct archive_entry *entry, mode_t mode);
extern void archive_entry_set_size(struct archive_entry *entry, int64_t size);
extern void archive_entry_set_mtime(struct archive_entry *entry, time_t time, long ns);

extern const char *archive_entry_pathname_utf8(struct archive_entry *entry);
extern const char *archive_entry_pathname(struct archive_entry *entry);
extern int64_t archive_entry_size(struct archive_entry *entry);
extern int archive_entry_size_is_set(struct archive_entry *entry);
extern time_t archive_entry_mtime(struct archive_entry *entry);
extern int archive_entry_mtime_is_set(struct archive_entry *entry);
extern mode_t archive_entry_filetype(struct archive_entry *entry);
extern mode_t archive_entry_perm(struct archive_entry *entry);
extern const char *archive_entry_symlink_utf8(struct archive_entry *entry);
extern const char *archive_entry_symlink(struct archive_entry *entry);
extern int archive_entry_is_encrypted(struct archive_entry *entry);
extern int archive_entry_is_data_encrypted(struct archive_entry *entry);
extern int archive_entry_is_metadata_encrypted(struct archive_entry *entry);

const char *bolt_libarchive_version(void) {
    const char *ver = archive_version_string();
    if (!ver) return "3.7";
    const char *prefix = "libarchive ";
    size_t plen = strlen(prefix);
    if (strncmp(ver, prefix, plen) == 0) {
        return ver + plen;
    }
    return ver;
}

int32_t bolt_la_probe(const char *path, int32_t *format, int32_t *filter) {
    struct archive *a = archive_read_new();
    if (!a) return -1;
    archive_read_support_format_all(a);
    archive_read_support_format_raw(a);
    archive_read_support_filter_all(a);
    int result = archive_read_open_filename(a, path, 65536);
    if (result == BOLT_ARCHIVE_OK || result == BOLT_ARCHIVE_WARN) {
        struct archive_entry *entry = NULL;
        result = archive_read_next_header(a, &entry);
        if (result == BOLT_ARCHIVE_OK || result == BOLT_ARCHIVE_WARN || result == BOLT_ARCHIVE_EOF) {
            *format = archive_format(a) & 0xff0000;
            *filter = archive_filter_code(a, 0);
            archive_read_free(a);
            return 0;
        }
    }
    archive_read_free(a);
    return -1;
}

static void write_err(char *err_buf, size_t err_cap, const char *msg) {
    if (!err_buf || err_cap == 0) return;
    if (!msg || msg[0] == '\0') {
        err_buf[0] = '\0';
        return;
    }
    snprintf(err_buf, err_cap, "%s", msg);
}

void *bolt_la_7z_open(const char *path, const char *options, char *err, size_t err_cap) {
    struct archive *a = archive_write_new();
    if (!a) { write_err(err, err_cap, strerror(ENOMEM)); return NULL; }
    if (archive_write_set_format_7zip(a) != BOLT_ARCHIVE_OK ||
        (options && archive_write_set_options(a, options) != BOLT_ARCHIVE_OK) ||
        archive_write_open_filename(a, path) != BOLT_ARCHIVE_OK) {
        write_err(err, err_cap, archive_error_string(a));
        archive_write_fail(a);
        archive_write_free(a);
        return NULL;
    }
    return a;
}

int32_t bolt_la_7z_header(void *writer, const char *path, uint8_t kind,
    const char *link_target, uint64_t size, uint16_t permissions, int64_t mtime,
    char *err, size_t err_cap) {
    struct archive *a = writer;
    struct archive_entry *entry = archive_entry_new();
    if (!entry) { write_err(err, err_cap, strerror(ENOMEM)); return -1; }
    archive_entry_set_pathname_utf8(entry, path);
    archive_entry_set_filetype(entry, kind == 1 ? S_IFDIR : (kind == 2 ? S_IFLNK : S_IFREG));
    archive_entry_set_perm(entry, permissions);
    archive_entry_set_mtime(entry, (time_t)mtime, 0);
    archive_entry_set_size(entry, kind == 0 ? (int64_t)size : 0);
    if (kind == 2) archive_entry_set_symlink_utf8(entry, link_target);
    int result = archive_write_header(a, entry);
    archive_entry_free(entry);
    if (result != BOLT_ARCHIVE_OK) write_err(err, err_cap, archive_error_string(a));
    return result;
}

int32_t bolt_la_7z_write(void *writer, const uint8_t *data, size_t size, char *err, size_t err_cap) {
    struct archive *a = writer;
    size_t offset = 0;
    while (offset < size) {
        ssize_t count = archive_write_data(a, data + offset, size - offset);
        if (count <= 0) { write_err(err, err_cap, archive_error_string(a)); return -1; }
        offset += (size_t)count;
    }
    return 0;
}

int32_t bolt_la_7z_close(void *writer, char *err, size_t err_cap) {
    struct archive *a = writer;
    int result = archive_write_close(a);
    if (result != BOLT_ARCHIVE_OK) write_err(err, err_cap, archive_error_string(a));
    return result;
}

void bolt_la_7z_free(void *writer) {
    if (writer) {
        /* Do not finish/recompress an abandoned archive after cancellation. */
        archive_write_fail(writer);
        archive_write_free(writer);
    }
}

static int32_t classify_la_error(const char *msg, int has_password, int entry_encrypted, int fallback_code) {
    if (msg) {
        if (strcasestr(msg, "incorrect passphrase") != NULL ||
            strcasestr(msg, "wrong password") != NULL ||
            strcasestr(msg, "bad password") != NULL) {
            return BOLT_LA_ERR_WRONG_PASSWORD;
        }
        if (strcasestr(msg, "passphrase required") != NULL ||
            strcasestr(msg, "passphrase") != NULL ||
            strcasestr(msg, "encrypted") != NULL) {
            return has_password ? BOLT_LA_ERR_WRONG_PASSWORD : BOLT_LA_ERR_PASSWORD_REQUIRED;
        }
    }
    if (entry_encrypted) {
        return has_password ? BOLT_LA_ERR_WRONG_PASSWORD : BOLT_LA_ERR_PASSWORD_REQUIRED;
    }
    return fallback_code != 0 ? fallback_code : -1;
}

static struct archive *open_la_reader(
    const char **paths,
    size_t path_count,
    const char *password,
    int32_t *out_code,
    char *err_buf,
    size_t err_cap
) {
    if (!paths || path_count == 0 || !paths[0]) {
        if (out_code) *out_code = EINVAL;
        write_err(err_buf, err_cap, "No archive path provided");
        return NULL;
    }

    struct archive *a = archive_read_new();
    if (!a) {
        if (out_code) *out_code = ENOMEM;
        write_err(err_buf, err_cap, "archive_read_new failed");
        return NULL;
    }

    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);

    int has_password = (password != NULL && password[0] != '\0');
    if (has_password) {
        archive_read_add_passphrase(a, password);
    }

    int open_rc;
    if (path_count == 1) {
        open_rc = archive_read_open_filename(a, paths[0], 65536);
    } else {
        const char **c_paths = (const char **)calloc(path_count + 1, sizeof(const char *));
        if (!c_paths) {
            archive_read_free(a);
            if (out_code) *out_code = ENOMEM;
            write_err(err_buf, err_cap, "Out of memory");
            return NULL;
        }
        for (size_t i = 0; i < path_count; i++) {
            c_paths[i] = paths[i];
        }
        c_paths[path_count] = NULL;
        open_rc = archive_read_open_filenames(a, c_paths, 65536);
        free(c_paths);
    }

    if (open_rc != BOLT_ARCHIVE_OK && open_rc != BOLT_ARCHIVE_WARN) {
        const char *msg = archive_error_string(a);
        write_err(err_buf, err_cap, msg ? msg : "Failed opening archive");
        if (out_code) *out_code = classify_la_error(msg, has_password, 0, open_rc);
        archive_read_free(a);
        return NULL;
    }

    if (out_code) *out_code = 0;
    return a;
}

static void populate_entry_info(
    struct archive *a,
    struct archive_entry *entry,
    bolt_la_entry_info_t *info
) {
    memset(info, 0, sizeof(*info));
    const char *utf8 = archive_entry_pathname_utf8(entry);
    const char *raw = archive_entry_pathname(entry);

    info->path = utf8 ? utf8 : (raw ? raw : "");
    info->path_is_utf8 = (utf8 != NULL) ? 1 : 0;

    const char *raw_src = raw ? raw : info->path;
    info->raw_path_bytes = (const uint8_t *)raw_src;
    info->raw_path_len = strlen(raw_src);

    mode_t ftype = archive_entry_filetype(entry);
    int trailing_slash = (info->raw_path_len > 0 && raw_src[info->raw_path_len - 1] == '/');
    info->is_directory = (((ftype & S_IFMT) == S_IFDIR) || trailing_slash) ? 1 : 0;
    info->is_symlink = ((ftype & S_IFMT) == S_IFLNK) ? 1 : 0;

    int enc = (archive_entry_is_encrypted(entry) ||
               archive_entry_is_data_encrypted(entry) ||
               archive_entry_is_metadata_encrypted(entry)) ? 1 : 0;
    info->is_encrypted = (uint8_t)enc;

    if (archive_entry_size_is_set(entry)) {
        int64_t sz = archive_entry_size(entry);
        info->size = sz > 0 ? (uint64_t)sz : 0;
    } else {
        info->size = 0;
    }

    info->mtime = archive_entry_mtime_is_set(entry) ? (int64_t)archive_entry_mtime(entry) : 0;

    uint16_t perm = (uint16_t)(archive_entry_perm(entry) & 07777);
    if (perm == 0) {
        perm = info->is_directory ? 0755 : 0644;
    }
    info->permissions = perm;
    info->format_name = archive_format_name(a);
    const char *sym_utf8 = archive_entry_symlink_utf8(entry);
    const char *sym_raw = archive_entry_symlink(entry);
    info->symlink_target = sym_utf8 ? sym_utf8 : sym_raw;
}

int32_t bolt_la_list(
    const char **paths,
    size_t path_count,
    const char *password,
    bolt_la_entry_cb entry_cb,
    void *ctx,
    char *err_buf,
    size_t err_cap
) {
    int has_password = (password != NULL && password[0] != '\0');
    int32_t open_err = 0;
    struct archive *a = open_la_reader(paths, path_count, password, &open_err, err_buf, err_cap);
    if (!a) return open_err;

    int32_t status = 0;
    struct archive_entry *entry = NULL;
    for (;;) {
        int r = archive_read_next_header(a, &entry);
        if (r == BOLT_ARCHIVE_EOF) break;
        if (r != BOLT_ARCHIVE_OK && r != BOLT_ARCHIVE_WARN) {
            const char *msg = archive_error_string(a);
            write_err(err_buf, err_cap, msg ? msg : "Failed reading archive header");
            status = classify_la_error(msg, has_password, 0, r);
            break;
        }
        bolt_la_entry_info_t info;
        populate_entry_info(a, entry, &info);
        if (entry_cb) {
            int cb_rc = entry_cb(&info, ctx);
            if (cb_rc != 0) {
                status = BOLT_LA_ERR_CANCELLED;
                break;
            }
        }
        archive_read_data_skip(a);
    }

    archive_read_free(a);
    return status;
}

int32_t bolt_la_read_entry(
    const char **paths,
    size_t path_count,
    const char *target_path,
    int target_match_raw_fallback,
    const char *password,
    bolt_buffer_t *output,
    char *err_buf,
    size_t err_cap
) {
    if (!output || !target_path) return EINVAL;
    output->data = NULL;
    output->size = 0;

    int has_password = (password != NULL && password[0] != '\0');
    int32_t open_err = 0;
    struct archive *a = open_la_reader(paths, path_count, password, &open_err, err_buf, err_cap);
    if (!a) return open_err;

    int32_t status = ENOENT;
    struct archive_entry *entry = NULL;
    uint8_t *buf = (uint8_t *)malloc(128 * 1024);
    if (!buf) {
        archive_read_free(a);
        return ENOMEM;
    }

    for (;;) {
        int r = archive_read_next_header(a, &entry);
        if (r == BOLT_ARCHIVE_EOF) break;
        if (r != BOLT_ARCHIVE_OK && r != BOLT_ARCHIVE_WARN) {
            const char *msg = archive_error_string(a);
            write_err(err_buf, err_cap, msg ? msg : "Failed reading archive header");
            status = classify_la_error(msg, has_password, 0, r);
            break;
        }

        bolt_la_entry_info_t info;
        populate_entry_info(a, entry, &info);
        int matched = (strcmp(info.path, target_path) == 0);
        if (!matched && target_match_raw_fallback && info.raw_path_bytes) {
            matched = (strcmp((const char *)info.raw_path_bytes, target_path) == 0);
        }
        if (!matched) {
            archive_read_data_skip(a);
            continue;
        }

        size_t cap = info.size > 0 && info.size < (64ULL * 1024ULL * 1024ULL)
            ? (size_t)info.size
            : 4096;
        uint8_t *out_ptr = (uint8_t *)malloc(cap);
        if (!out_ptr) {
            status = ENOMEM;
            break;
        }
        size_t out_len = 0;
        status = 0;

        for (;;) {
            ssize_t n = archive_read_data(a, buf, 128 * 1024);
            if (n == 0) break;
            if (n < 0) {
                const char *msg = archive_error_string(a);
                write_err(err_buf, err_cap, msg ? msg : "Failed decompressing entry");
                status = classify_la_error(msg, has_password, info.is_encrypted, (int32_t)n);
                free(out_ptr);
                out_ptr = NULL;
                break;
            }
            if (out_len + (size_t)n > cap) {
                size_t next_cap = cap;
                while (next_cap < out_len + (size_t)n) {
                    next_cap = next_cap > 0 ? next_cap * 2 : 4096;
                }
                uint8_t *resized = (uint8_t *)realloc(out_ptr, next_cap);
                if (!resized) {
                    free(out_ptr);
                    out_ptr = NULL;
                    status = ENOMEM;
                    break;
                }
                out_ptr = resized;
                cap = next_cap;
            }
            memcpy(out_ptr + out_len, buf, (size_t)n);
            out_len += (size_t)n;
        }

        if (status == 0) {
            output->data = out_ptr;
            output->size = out_len;
        }
        break;
    }

    free(buf);
    archive_read_free(a);
    return status;
}

int32_t bolt_la_extract_stream(
    const char **paths,
    size_t path_count,
    const char *password,
    bolt_la_entry_cb on_entry_header,
    bolt_la_chunk_cb on_entry_chunk,
    void *ctx,
    char *err_buf,
    size_t err_cap
) {
    int has_password = (password != NULL && password[0] != '\0');
    int32_t open_err = 0;
    struct archive *a = open_la_reader(paths, path_count, password, &open_err, err_buf, err_cap);
    if (!a) return open_err;

    uint8_t *buf = (uint8_t *)malloc(128 * 1024);
    if (!buf) {
        archive_read_free(a);
        return ENOMEM;
    }

    int32_t status = 0;
    struct archive_entry *entry = NULL;

    for (;;) {
        int r = archive_read_next_header(a, &entry);
        if (r == BOLT_ARCHIVE_EOF) break;
        if (r != BOLT_ARCHIVE_OK && r != BOLT_ARCHIVE_WARN) {
            const char *msg = archive_error_string(a);
            write_err(err_buf, err_cap, msg ? msg : "Failed reading archive header");
            status = classify_la_error(msg, has_password, 0, r);
            break;
        }

        bolt_la_entry_info_t info;
        populate_entry_info(a, entry, &info);

        /* on_entry_header returns: >0 = extract/stream, 0 = skip, <0 = abort/cancel */
        int decision = on_entry_header ? on_entry_header(&info, ctx) : 0;
        if (decision < 0) {
            status = BOLT_LA_ERR_CANCELLED;
            break;
        }
        if (decision == 0 || info.is_directory) {
            archive_read_data_skip(a);
            continue;
        }

        int stop_early = 0;
        for (;;) {
            ssize_t n = archive_read_data(a, buf, 128 * 1024);
            if (n == 0) {
                if (on_entry_chunk) {
                    int end_rc = on_entry_chunk(NULL, 0, ctx);
                    if (end_rc < 0) {
                        status = BOLT_LA_ERR_CANCELLED;
                    } else if (end_rc > 0) {
                        stop_early = 1;
                    }
                }
                break;
            }
            if (n < 0) {
                const char *msg = archive_error_string(a);
                write_err(err_buf, err_cap, msg ? msg : "Failed extracting entry");
                status = classify_la_error(msg, has_password, info.is_encrypted, (int32_t)n);
                break;
            }
            if (on_entry_chunk) {
                int chk_rc = on_entry_chunk(buf, (size_t)n, ctx);
                if (chk_rc < 0) {
                    status = BOLT_LA_ERR_CANCELLED;
                    break;
                }
            }
        }

        if (status != 0 || stop_early) {
            break;
        }
    }

    free(buf);
    archive_read_free(a);
    return status;
}

int32_t bolt_la_test_integrity(
    const char **paths,
    size_t path_count,
    const char *password,
    bolt_la_test_cb on_result,
    void *ctx,
    char *err_buf,
    size_t err_cap
) {
    int has_password = (password != NULL && password[0] != '\0');
    int32_t open_err = 0;
    struct archive *a = open_la_reader(paths, path_count, password, &open_err, err_buf, err_cap);
    if (!a) return open_err;

    uint8_t *buf = (uint8_t *)malloc(128 * 1024);
    if (!buf) {
        archive_read_free(a);
        return ENOMEM;
    }

    int32_t status = 0;
    struct archive_entry *entry = NULL;

    for (;;) {
        int r = archive_read_next_header(a, &entry);
        if (r == BOLT_ARCHIVE_EOF) break;
        if (r != BOLT_ARCHIVE_OK && r != BOLT_ARCHIVE_WARN) {
            const char *msg = archive_error_string(a);
            write_err(err_buf, err_cap, msg ? msg : "Failed reading archive header");
            status = classify_la_error(msg, has_password, 0, r);
            break;
        }

        bolt_la_entry_info_t info;
        populate_entry_info(a, entry, &info);
        if (info.is_directory) {
            if (on_result) on_result(info.path, 0, "Directory OK", ctx);
            archive_read_data_skip(a);
            continue;
        }

        int entry_status = 0;
        const char *entry_detail = "OK";
        for (;;) {
            ssize_t n = archive_read_data(a, buf, 128 * 1024);
            if (n == 0) break;
            if (n < 0) {
                const char *msg = archive_error_string(a);
                entry_detail = msg ? msg : "Decompression / CRC error";
                entry_status = classify_la_error(msg, has_password, info.is_encrypted, (int32_t)n);
                break;
            }
        }
        if (on_result) {
            on_result(info.path, entry_status, entry_detail, ctx);
        }
    }

    free(buf);
    archive_read_free(a);
    return status;
}
