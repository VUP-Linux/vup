#ifndef XBPS_DIFF_H
#define XBPS_DIFF_H

#include <stddef.h>
#include <stdio.h>

/**
 * Fetch the template for a package.
 * Returns a malloc'd string containing the template content, or NULL on
 * failure.
 */
char *fetch_template(const char *category, const char *pkg_name);

/**
 * Review changes between current and previous template (for single install).
 * Returns 1 if user approves (or no changes), 0 if aborted.
 */
int review_changes(const char *pkg_name, const char *current,
                   const char *previous);

/**
 * Create a secure temporary file.
 * Returns file descriptor, or -1 on error. Sets path in out_path.
 */
int diff_create_temp_file(const char *prefix, char *out_path, size_t path_size);

/**
 * Write content to a temp file for diff operations.
 * Returns 0 on success, -1 on error.
 */
int diff_write_temp_file(const char *content, char *path_out, size_t path_size);

/**
 * Generate a colored unified diff between old and new content.
 * Returns malloc'd diff output string, or NULL on error.
 * Caller must free the returned string.
 */
char *diff_generate(const char *old_content, const char *new_content);

/**
 * Show content in less pager.
 */
void diff_show_pager(const char *path);

#endif
