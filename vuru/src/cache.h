#ifndef CACHE_H
#define CACHE_H

/**
 * Retrieve a cached package template.
 * @param pkg_name Package name (must be a valid identifier)
 * @return Template content (caller must free), or NULL if not cached
 */
char *cache_get_template(const char *pkg_name);

/**
 * Save a package template to the cache.
 * @param pkg_name Package name (must be a valid identifier)
 * @param content Template content to cache
 * @return 1 on success, 0 on failure
 */
int cache_save_template(const char *pkg_name, const char *content);

/**
 * Get the path to the cached index file.
 * Creates the cache directory if needed.
 * @return Static buffer with path, or NULL on failure
 */
char *cache_get_index_path(void);

#endif /* CACHE_H */
