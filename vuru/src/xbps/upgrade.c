#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include "upgrade.h"

/**
 * Compare versions using xbps-uhelper.
 * Returns 1 if v1 > v2, 0 otherwise.
 */
static int version_gt(const char *v1, const char *v2) {
    if (!v1 || !v2) return 0;
    
    pid_t pid = fork();
    
    if (pid < 0) {
        return 0;
    }
    
    if (pid == 0) {
        // Redirect stdout/stderr to /dev/null
        freopen("/dev/null", "w", stdout);
        freopen("/dev/null", "w", stderr);
        execlp("xbps-uhelper", "xbps-uhelper", "cmpver", v1, v2, (char *)NULL);
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return 0;
    }
    
    // xbps-uhelper cmpver returns 1 if v1 > v2, 255 if v1 < v2, 0 if equal
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status) == 1;
    }
    
    return 0;
}

/**
 * Run xbps-install for upgrade.
 */
static int run_xbps_upgrade(const char *repo_url, const char *pkg_name, int yes) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        if (yes) {
            execlp("sudo", "sudo", "xbps-install", 
                   "-R", repo_url, "-u", "-y", pkg_name, (char *)NULL);
        } else {
            execlp("sudo", "sudo", "xbps-install", 
                   "-R", repo_url, "-u", pkg_name, (char *)NULL);
        }
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return -1;
    }
    
    return (WIFEXITED(status) && WEXITSTATUS(status) == 0) ? 0 : -1;
}

/**
 * Parse installed package line from xbps-query -l.
 * Format: "ii pkg-name-version description..."
 * Returns 1 on success, 0 on failure.
 */
static int parse_installed_pkg(const char *line, char *name, size_t name_size, 
                               char *version, size_t ver_size) {
    if (!line || !name || !version) return 0;
    
    // Skip first two fields (state like "ii ")
    const char *p = line;
    while (*p && *p != ' ') p++;  // Skip state
    while (*p == ' ') p++;         // Skip spaces
    
    // p now points to "pkg-name-version"
    const char *start = p;
    while (*p && *p != ' ') p++;   // Find end of pkg-name-version
    
    size_t full_len = (size_t)(p - start);
    if (full_len == 0 || full_len >= name_size) return 0;
    
    char full[512];
    if (full_len >= sizeof(full)) return 0;
    strncpy(full, start, full_len);
    full[full_len] = '\0';
    
    // Find last '-' to split name and version
    char *dash = strrchr(full, '-');
    if (!dash || dash == full) return 0;
    
    *dash = '\0';
    
    size_t nlen = strlen(full);
    size_t vlen = strlen(dash + 1);
    
    if (nlen >= name_size || vlen >= ver_size) return 0;
    
    strncpy(name, full, name_size - 1);
    name[name_size - 1] = '\0';
    
    strncpy(version, dash + 1, ver_size - 1);
    version[ver_size - 1] = '\0';
    
    return 1;
}

int xbps_upgrade_all(Index *idx, int yes) {
    if (!idx || !idx->json) {
        log_error("Invalid index");
        return -1;
    }

    log_info("Checking for VUP package updates...");
    
    FILE *fp = popen("xbps-query -l 2>/dev/null", "r");
    if (!fp) {
        log_error("Failed to run xbps-query: %s", strerror(errno));
        return -1;
    }

    char line[1024];
    int updates_found = 0;
    int errors = 0;

    while (fgets(line, sizeof(line), fp)) {
        char name[256];
        char installed_ver[128];
        
        if (!parse_installed_pkg(line, name, sizeof(name), 
                                  installed_ver, sizeof(installed_ver))) {
            continue;
        }

        // Check if this package is in our VUP index
        cJSON *info = cJSON_GetObjectItem(idx->json, name);
        if (!info) continue;
        
        cJSON *idx_ver = cJSON_GetObjectItem(info, "version");
        cJSON *repo_url = cJSON_GetObjectItem(info, "repo_url");
        
        if (!idx_ver || !cJSON_IsString(idx_ver) || !idx_ver->valuestring ||
            !repo_url || !cJSON_IsString(repo_url) || !repo_url->valuestring) {
            continue;
        }
        
        if (version_gt(idx_ver->valuestring, installed_ver)) {
            printf("  %s: %s -> %s\n", name, installed_ver, idx_ver->valuestring);
            
            if (run_xbps_upgrade(repo_url->valuestring, name, yes) != 0) {
                log_error("Failed to upgrade %s", name);
                errors++;
            } else {
                updates_found++;
            }
        }
    }
    
    pclose(fp);

    if (updates_found == 0 && errors == 0) {
        log_info("All VUP packages are up to date");
    } else if (updates_found > 0) {
        log_info("Upgraded %d package(s)", updates_found);
    }
    
    return errors > 0 ? -1 : 0;
}
