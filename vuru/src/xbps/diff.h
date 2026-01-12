#ifndef XBPS_DIFF_H
#define XBPS_DIFF_H

#include <stdio.h>

/**
 * Fetch the template for a package.
 * Returns a malloc'd string containing the template content, or NULL on failure.
 */
char *fetch_template(const char *category, const char *pkg_name);

/**
 * Review changes between current and previous template.
 * Returns 1 if user approves (or no changes), 0 if aborted.
 */
int review_changes(const char *pkg_name, const char *current, const char *previous);

#endif
