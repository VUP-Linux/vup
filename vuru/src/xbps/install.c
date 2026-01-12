#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include "install.h"
#include "diff.h"
#include "../utils.h"
#include "../cache.h"

/**
 * Run xbps-install with the given repository and package.
 */
static int run_xbps_install(const char *repo_url, const char *pkg_name, int yes) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        if (yes) {
            execlp("sudo", "sudo", "xbps-install", 
                   "-R", repo_url, "-S", "-y", pkg_name, (char *)NULL);
        } else {
            execlp("sudo", "sudo", "xbps-install", 
                   "-R", repo_url, "-S", pkg_name, (char *)NULL);
        }
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return -1;
    }
    
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return 0;
    }
    
    return -1;
}

int xbps_install_pkg(Index *idx, const char *pkg_name, int yes) {
    if (!idx || !idx->json || !pkg_name) {
        log_error("Invalid arguments");
        return -1;
    }

    cJSON *pkg = cJSON_GetObjectItem(idx->json, pkg_name);
    if (!pkg) {
        log_error("Package '%s' not found in VUP index", pkg_name);
        return -1;
    }

    cJSON *cat = cJSON_GetObjectItem(pkg, "category");
    cJSON *repo_urls = cJSON_GetObjectItem(pkg, "repo_urls");
    
    if (!cat || !cJSON_IsString(cat) || !cat->valuestring ||
        !repo_urls || !cJSON_IsObject(repo_urls)) {
        log_error("Invalid package metadata for '%s'", pkg_name);
        return -1;
    }
    
    // Get architecture-specific repo URL
    const char *arch = get_arch();
    if (!arch) {
        log_error("Failed to detect system architecture");
        return -1;
    }
    
    cJSON *url = cJSON_GetObjectItem(repo_urls, arch);
    if (!url || !cJSON_IsString(url) || !url->valuestring) {
        log_error("Package '%s' is not available for architecture '%s'", pkg_name, arch);
        return -1;
    }

    log_info("Found %s in category '%s' for %s", pkg_name, cat->valuestring, arch);
    
    // Fetch template for review
    log_info("Fetching template for review...");
    char *new_tmpl = fetch_template(cat->valuestring, pkg_name);
    if (!new_tmpl) {
        log_error("Failed to fetch template");
        return -1;
    }

    char *cached_tmpl = cache_get_template(pkg_name);
    
    // Review unless --yes flag
    if (!yes) {
        if (!review_changes(pkg_name, new_tmpl, cached_tmpl)) {
            log_info("Installation aborted by user");
            free(new_tmpl);
            free(cached_tmpl);
            return 0;  // User cancelled, not an error
        }
    }

    // Cache the template for future comparisons
    if (!cache_save_template(pkg_name, new_tmpl)) {
        log_error("Warning: Failed to cache template");
        // Continue anyway
    }
    
    free(new_tmpl);
    free(cached_tmpl);

    log_info("Installing from: %s", url->valuestring);

    if (run_xbps_install(url->valuestring, pkg_name, yes) != 0) {
        log_error("xbps-install failed for %s", pkg_name);
        return -1;
    }

    log_info("Successfully installed %s", pkg_name);
    return 0;
}
