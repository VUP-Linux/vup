#ifndef INDEX_H
#define INDEX_H

#include "cJSON.h"

/**
 * Package index structure.
 */
typedef struct {
    cJSON *json;  /**< Parsed JSON index data */
} Index;

/**
 * Load the package index, fetching from URL if needed.
 * Uses ETag-based caching for efficient updates.
 * 
 * @param url URL to fetch the index from
 * @param force_update If non-zero, bypass cache and fetch fresh
 * @return Index pointer (caller must free with index_free), or NULL on failure
 */
Index *index_load_or_fetch(const char *url, int force_update);

/**
 * Search the index for packages matching a query.
 * Prints matching results to stdout.
 * 
 * @param idx Package index
 * @param query Search string (case-insensitive substring match)
 */
void index_search(Index *idx, const char *query);

/**
 * Get package metadata from the index.
 * 
 * @param idx Package index
 * @param pkg_name Exact package name
 * @return cJSON object for the package, or NULL if not found
 */
cJSON *index_get_package(Index *idx, const char *pkg_name);

/**
 * Free an Index structure and its contents.
 * @param idx Index to free (safe to pass NULL)
 */
void index_free(Index *idx);

#endif /* INDEX_H */
