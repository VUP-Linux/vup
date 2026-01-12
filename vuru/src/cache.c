#include "cache.h"
#include "utils.h"
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define PATH_MAX_SIZE 4096

/**
 * Get cache directory path, respecting XDG_CACHE_HOME if set.
 * Returns pointer to static buffer, or NULL on failure.
 */
static const char *get_cache_base(void) {
  static char path[PATH_MAX_SIZE];

  const char *xdg_cache = getenv("XDG_CACHE_HOME");
  if (xdg_cache && xdg_cache[0] == '/') {
    int ret = snprintf(path, sizeof(path), "%s/vup", xdg_cache);
    if (ret > 0 && (size_t)ret < sizeof(path)) {
      return path;
    }
  }

  const char *home = getenv("HOME");
  if (!home || home[0] != '/') {
    return NULL;
  }

  int ret = snprintf(path, sizeof(path), "%s/.cache/vup", home);
  if (ret < 0 || (size_t)ret >= sizeof(path)) {
    return NULL;
  }

  return path;
}

/**
 * Recursively create directory path (like mkdir -p).
 * Returns 0 on success, -1 on failure.
 */
static int ensure_dir_recursive(const char *path) {
  if (!path || path[0] == '\0')
    return -1;

  char tmp[PATH_MAX_SIZE];
  int ret = snprintf(tmp, sizeof(tmp), "%s", path);
  if (ret < 0 || (size_t)ret >= sizeof(tmp)) {
    return -1;
  }

  size_t len = strlen(tmp);
  if (len > 0 && tmp[len - 1] == '/') {
    tmp[len - 1] = '\0';
  }

  for (char *p = tmp + 1; *p; p++) {
    if (*p == '/') {
      *p = '\0';
      if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
        return -1;
      }
      *p = '/';
    }
  }

  if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
    return -1;
  }

  return 0;
}

/**
 * Validate package name to prevent path traversal attacks.
 * Only allows alphanumeric, dash, underscore, and period.
 */
static int is_valid_pkg_name(const char *name) {
  if (!name || name[0] == '\0' || name[0] == '.') {
    return 0;
  }

  for (const char *p = name; *p; p++) {
    char c = *p;
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.')) {
      return 0;
    }
  }

  // Prevent directory traversal
  if (strstr(name, "..") != NULL) {
    return 0;
  }

  return 1;
}

char *cache_get_template(const char *pkg_name) {
  if (!is_valid_pkg_name(pkg_name)) {
    log_error("Invalid package name: %s", pkg_name ? pkg_name : "(null)");
    return NULL;
  }

  const char *base = get_cache_base();
  if (!base)
    return NULL;

  char path[PATH_MAX_SIZE];
  int ret = snprintf(path, sizeof(path), "%s/templates/%s", base, pkg_name);
  if (ret < 0 || (size_t)ret >= sizeof(path)) {
    return NULL;
  }

  return read_file(path);
}

int cache_save_template(const char *pkg_name, const char *content) {
  if (!is_valid_pkg_name(pkg_name) || !content) {
    return 0;
  }

  const char *base = get_cache_base();
  if (!base)
    return 0;

  char dir_path[PATH_MAX_SIZE];
  int ret = snprintf(dir_path, sizeof(dir_path), "%s/templates", base);
  if (ret < 0 || (size_t)ret >= sizeof(dir_path)) {
    return 0;
  }

  if (ensure_dir_recursive(dir_path) != 0) {
    log_error("Failed to create cache directory: %s", dir_path);
    return 0;
  }

  char file_path[PATH_MAX_SIZE];
  ret = snprintf(file_path, sizeof(file_path), "%s/%s", dir_path, pkg_name);
  if (ret < 0 || (size_t)ret >= sizeof(file_path)) {
    return 0;
  }

  return write_file(file_path, content);
}

char *cache_get_index_path(void) {
  const char *base = get_cache_base();
  if (!base)
    return NULL;

  static char path[PATH_MAX_SIZE];

  if (ensure_dir_recursive(base) != 0) {
    log_error("Failed to create cache directory: %s", base);
    return NULL;
  }

  int ret = snprintf(path, sizeof(path), "%s/index.json", base);
  if (ret < 0 || (size_t)ret >= sizeof(path)) {
    return NULL;
  }

  return path;
}
