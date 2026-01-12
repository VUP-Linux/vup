#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>
#include "index.h"
#include "utils.h"
#include "cache.h"

#define PATH_MAX_SIZE 4096
#define INDEX_URL_MAX 2048

/**
 * Get cache directory path, respecting XDG_CACHE_HOME.
 */
static const char *get_cache_dir(void) {
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
 * Create directory if it doesn't exist.
 */
static int ensure_dir(const char *path) {
    if (!path) return -1;
    
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 0 : -1;
    }
    
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    
    return 0;
}

/**
 * Trim leading and trailing whitespace in-place.
 */
static char *str_trim(char *str) {
    if (!str) return NULL;
    
    while (isspace((unsigned char)*str)) str++;
    
    if (*str == '\0') return str;
    
    char *end = str + strlen(str) - 1;
    while (end > str && isspace((unsigned char)*end)) {
        *end-- = '\0';
    }
    
    return str;
}

/**
 * Validate URL to prevent command injection.
 * Only allows http/https URLs with safe characters.
 */
static int is_valid_url(const char *url) {
    if (!url) return 0;
    
    // Must start with http:// or https://
    if (strncmp(url, "https://", 8) != 0 && strncmp(url, "http://", 7) != 0) {
        return 0;
    }
    
    // Check for shell metacharacters
    for (const char *p = url; *p; p++) {
        char c = *p;
        if (c == ';' || c == '|' || c == '&' || c == '$' ||
            c == '`' || c == '\'' || c == '"' || c == '\\' ||
            c == '\n' || c == '\r' || c == '>' || c == '<' ||
            c == '(' || c == ')' || c == '{' || c == '}') {
            return 0;
        }
    }
    
    return 1;
}

/**
 * Run curl using fork/exec instead of system() for safety.
 * Returns 0 on success, -1 on failure.
 */
static int run_curl(const char *header_path, const char *output_path, 
                    const char *etag, const char *url) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        // Child process - use paths directly with separate flag arguments
        if (etag && etag[0] != '\0') {
            char etag_header[512];
            snprintf(etag_header, sizeof(etag_header), "If-None-Match: %s", etag);
            
            execlp("curl", "curl", "-s", "-L", 
                   "-D", header_path, 
                   "-o", output_path, 
                   "-H", etag_header,
                   url, (char *)NULL);
        } else {
            execlp("curl", "curl", "-s", "-L", 
                   "-D", header_path, 
                   "-o", output_path, 
                   url, (char *)NULL);
        }
        
        // If exec fails
        _exit(127);
    }
    
    // Parent process
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        log_error("waitpid() failed: %s", strerror(errno));
        return -1;
    }
    
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return 0;
    }
    
    return -1;
}

/**
 * Parse HTTP headers file for status code and ETag.
 */
static void parse_headers(const char *header_path, int *status, char *etag, size_t etag_size) {
    if (!header_path || !status || !etag) return;
    
    *status = 0;
    etag[0] = '\0';
    
    FILE *hf = fopen(header_path, "r");
    if (!hf) return;
    
    char line[1024];
    while (fgets(line, sizeof(line), hf)) {
        // Parse HTTP status line (handle redirects - use last status)
        if (strncmp(line, "HTTP/", 5) == 0) {
            char *space = strchr(line, ' ');
            if (space) {
                *status = atoi(space + 1);
            }
        }
        
        // Parse ETag header (case-insensitive)
        if (strncasecmp(line, "ETag:", 5) == 0) {
            char *value = line + 5;
            value = str_trim(value);
            
            size_t len = strlen(value);
            if (len > 0 && len < etag_size) {
                strncpy(etag, value, etag_size - 1);
                etag[etag_size - 1] = '\0';
            }
        }
    }
    
    fclose(hf);
}

/**
 * Load index from cache file.
 */
static Index *load_index_from_file(const char *path) {
    char *content = read_file(path);
    if (!content) return NULL;
    
    cJSON *json = cJSON_Parse(content);
    free(content);
    
    if (!json) {
        log_error("Failed to parse index JSON");
        return NULL;
    }
    
    Index *idx = malloc(sizeof(Index));
    if (!idx) {
        cJSON_Delete(json);
        return NULL;
    }
    
    idx->json = json;
    return idx;
}

Index *index_load_or_fetch(const char *url, int force_update) {
    if (!is_valid_url(url)) {
        log_error("Invalid or unsafe URL provided");
        return NULL;
    }

    const char *cache_dir = get_cache_dir();
    if (!cache_dir) {
        log_error("Could not determine cache directory");
        return NULL;
    }
    
    if (ensure_dir(cache_dir) != 0) {
        log_error("Failed to create cache directory: %s", cache_dir);
        return NULL;
    }

    char index_path[PATH_MAX_SIZE];
    char etag_path[PATH_MAX_SIZE];
    char header_path[PATH_MAX_SIZE];
    char temp_index_path[PATH_MAX_SIZE];
    
    int ret = snprintf(index_path, sizeof(index_path), "%s/index.json", cache_dir);
    if (ret < 0 || (size_t)ret >= sizeof(index_path)) return NULL;
    
    ret = snprintf(etag_path, sizeof(etag_path), "%s/index.json.etag", cache_dir);
    if (ret < 0 || (size_t)ret >= sizeof(etag_path)) return NULL;
    
    ret = snprintf(header_path, sizeof(header_path), "%s/headers.txt", cache_dir);
    if (ret < 0 || (size_t)ret >= sizeof(header_path)) return NULL;
    
    ret = snprintf(temp_index_path, sizeof(temp_index_path), "%s/index.json.tmp", cache_dir);
    if (ret < 0 || (size_t)ret >= sizeof(temp_index_path)) return NULL;

    // Try to load from cache if not forced
    if (!force_update && access(index_path, F_OK) == 0) {
        Index *idx = load_index_from_file(index_path);
        if (idx) return idx;
    }

    // Read existing ETag for conditional request
    char old_etag[256] = {0};
    if (!force_update && access(etag_path, F_OK) == 0) {
        char *etag_content = read_file(etag_path);
        if (etag_content) {
            char *trimmed = str_trim(etag_content);
            if (trimmed && strlen(trimmed) < sizeof(old_etag)) {
                strncpy(old_etag, trimmed, sizeof(old_etag) - 1);
            }
            free(etag_content);
        }
    }

    log_info("Fetching index...");
    
    int curl_ret = run_curl(header_path, temp_index_path, old_etag, url);
    
    if (curl_ret != 0) {
        log_error("Failed to fetch index");
        unlink(temp_index_path);
        
        // Fallback to cached version
        if (access(index_path, F_OK) == 0) {
            log_info("Using cached index");
            return load_index_from_file(index_path);
        }
        return NULL;
    }

    // Parse response headers
    int status = 0;
    char new_etag[256] = {0};
    parse_headers(header_path, &status, new_etag, sizeof(new_etag));
    unlink(header_path);

    if (status == 304) {
        log_info("Index not modified (cached)");
        unlink(temp_index_path);
        return load_index_from_file(index_path);
    }

    if (status == 200) {
        log_info("Index updated");
        
        // Atomically replace index file
        if (rename(temp_index_path, index_path) != 0) {
            log_error("Failed to save index: %s", strerror(errno));
            unlink(temp_index_path);
            return NULL;
        }
        
        // Save new ETag
        if (new_etag[0] != '\0') {
            write_file(etag_path, new_etag);
        }

        return load_index_from_file(index_path);
    }
    
    // Unexpected status
    log_error("Unexpected HTTP status: %d", status);
    unlink(temp_index_path);
    
    // Try cached version as fallback
    if (access(index_path, F_OK) == 0) {
        log_info("Using cached index as fallback");
        return load_index_from_file(index_path);
    }
    
    return NULL;
}

void index_search(Index *idx, const char *query) {
    if (!idx || !idx->json || !query) return;

    cJSON *item = NULL;
    cJSON_ArrayForEach(item, idx->json) {
        if (!item->string) continue;
        
        if (strcasestr(item->string, query)) {
            cJSON *ver = cJSON_GetObjectItem(item, "version");
            printf("  %s (%s)\n", item->string, 
                   (ver && ver->valuestring) ? ver->valuestring : "unknown");
        }
    }
}

cJSON *index_get_package(Index *idx, const char *pkg_name) {
    if (!idx || !idx->json || !pkg_name) return NULL;
    return cJSON_GetObjectItem(idx->json, pkg_name);
}

void index_free(Index *idx) {
    if (!idx) return;
    
    if (idx->json) {
        cJSON_Delete(idx->json);
    }
    free(idx);
}
