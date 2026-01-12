#ifndef UTILS_H
#define UTILS_H

#include <stdio.h>

/**
 * Log an informational message to stdout.
 * @param fmt printf-style format string
 */
void log_info(const char *fmt, ...);

/**
 * Log an error message to stderr.
 * @param fmt printf-style format string
 */
void log_error(const char *fmt, ...);

/**
 * Read entire file contents into a newly allocated buffer.
 * @param path Path to the file to read
 * @return Null-terminated string (caller must free), or NULL on failure
 */
char *read_file(const char *path);

/**
 * Write string content to a file, overwriting if exists.
 * @param path Path to the file to write
 * @param content Null-terminated string to write
 * @return 1 on success, 0 on failure
 */
int write_file(const char *path, const char *content);

/**
 * Get the current system architecture name.
 * @return Static string with architecture (e.g., "x86_64", "aarch64"), or NULL on failure
 */
const char *get_arch(void);

#endif /* UTILS_H */
