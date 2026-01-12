#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include "upgrade.h"
#include "diff.h"
#include "../cache.h"

#define MAX_UPGRADES 64

typedef struct {
    char name[256];
    char installed_ver[128];
    char new_ver[128];
    char repo_url[512];
    char category[128];
    char *new_template;
    char *cached_template;
} UpgradeInfo;

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
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execlp("xbps-uhelper", "xbps-uhelper", "cmpver", v1, v2, (char *)NULL);
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return 0;
    }
    
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status) == 1;
    }
    
    return 0;
}

/**
 * Get the currently installed version of a package.
 */
static char *get_installed_version(const char *pkg_name) {
    if (!pkg_name) return NULL;
    
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "xbps-query %s 2>/dev/null", pkg_name);
    
    FILE *fp = popen(cmd, "r");
    if (!fp) return NULL;
    
    char line[1024];
    char *version = NULL;
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "pkgver:", 7) == 0) {
            char *p = line + 7;
            while (*p == ' ' || *p == '\t') p++;
            
            char *dash = strrchr(p, '-');
            if (dash && dash > p) {
                char *end = dash + 1;
                while (*end && *end != '\n' && *end != '\r') end++;
                *end = '\0';
                version = strdup(dash + 1);
            }
            break;
        }
    }
    
    pclose(fp);
    return version;
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
                   "-R", repo_url, "-Su", "-y", pkg_name, (char *)NULL);
        } else {
            execlp("sudo", "sudo", "xbps-install", 
                   "-R", repo_url, "-Su", pkg_name, (char *)NULL);
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
 */
static int parse_installed_pkg(const char *line, char *name, size_t name_size, 
                               char *version, size_t ver_size) {
    if (!line || !name || !version) return 0;
    
    const char *p = line;
    while (*p && *p != ' ') p++;
    while (*p == ' ') p++;
    
    const char *start = p;
    while (*p && *p != ' ') p++;
    
    size_t full_len = (size_t)(p - start);
    if (full_len == 0 || full_len >= name_size) return 0;
    
    char full[512];
    if (full_len >= sizeof(full)) return 0;
    strncpy(full, start, full_len);
    full[full_len] = '\0';
    
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

/**
 * Show batched diffs in less pager.
 */
static int show_batch_review(UpgradeInfo *upgrades, int count) {
    char review_path[256];
    
    int fd = diff_create_temp_file("vuru_review", review_path, sizeof(review_path));
    if (fd < 0) {
        log_error("Failed to create review file");
        return 0;
    }
    
    FILE *review = fdopen(fd, "w");
    if (!review) {
        close(fd);
        unlink(review_path);
        return 0;
    }
    
    fprintf(review, "VUP Package Upgrade Review\n");
    fprintf(review, "==========================\n\n");
    fprintf(review, "%d package(s) to upgrade:\n\n", count);
    
    for (int i = 0; i < count; i++) {
        fprintf(review, "  [%d] %s: %s -> %s\n", 
                i + 1, upgrades[i].name, upgrades[i].installed_ver, upgrades[i].new_ver);
    }
    fprintf(review, "\n");
    
    for (int i = 0; i < count; i++) {
        fprintf(review, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
        fprintf(review, "[%d/%d] %s: %s -> %s\n", 
                i + 1, count, upgrades[i].name, upgrades[i].installed_ver, upgrades[i].new_ver);
        fprintf(review, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n");
        
        if (upgrades[i].cached_template) {
            char *diff = diff_generate(upgrades[i].cached_template, 
                                        upgrades[i].new_template);
            if (diff) {
                fprintf(review, "%s\n", diff);
                free(diff);
            }
        } else {
            fprintf(review, "(New package - showing full template)\n\n");
            fprintf(review, "%s\n", upgrades[i].new_template);
        }
        fprintf(review, "\n");
    }
    
    fclose(review);
    
    // Show in less with color support
    diff_show_pager(review_path);
    unlink(review_path);
    
    // Prompt for confirmation
    printf("Proceed with %d upgrade(s)? [Y/n] ", count);
    fflush(stdout);
    
    char input[100];
    if (fgets(input, sizeof(input), stdin)) {
        input[strcspn(input, "\n")] = '\0';
        if (input[0] == '\0' || 
            strcasecmp(input, "y") == 0 || 
            strcasecmp(input, "yes") == 0) {
            return 1;
        }
    }
    
    return 0;
}

/**
 * Free upgrade info resources.
 */
static void free_upgrades(UpgradeInfo *upgrades, int count) {
    for (int i = 0; i < count; i++) {
        free(upgrades[i].new_template);
        free(upgrades[i].cached_template);
    }
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

    UpgradeInfo upgrades[MAX_UPGRADES];
    int upgrade_count = 0;
    char line[1024];

    // Phase 1: Collect packages needing upgrade
    while (fgets(line, sizeof(line), fp) && upgrade_count < MAX_UPGRADES) {
        char name[256];
        char installed_ver[128];
        
        if (!parse_installed_pkg(line, name, sizeof(name), 
                                  installed_ver, sizeof(installed_ver))) {
            continue;
        }

        cJSON *info = cJSON_GetObjectItem(idx->json, name);
        if (!info) continue;
        
        cJSON *idx_ver = cJSON_GetObjectItem(info, "version");
        cJSON *repo_urls = cJSON_GetObjectItem(info, "repo_urls");
        cJSON *category = cJSON_GetObjectItem(info, "category");
        
        if (!idx_ver || !cJSON_IsString(idx_ver) || !idx_ver->valuestring ||
            !repo_urls || !cJSON_IsObject(repo_urls) ||
            !category || !cJSON_IsString(category) || !category->valuestring) {
            continue;
        }
        
        // Get architecture-specific repo URL
        const char *arch = get_arch();
        if (!arch) continue;
        
        cJSON *repo_url = cJSON_GetObjectItem(repo_urls, arch);
        if (!repo_url || !cJSON_IsString(repo_url) || !repo_url->valuestring) {
            continue;  // Package not available for this architecture
        }
        
        if (version_gt(idx_ver->valuestring, installed_ver)) {
            UpgradeInfo *u = &upgrades[upgrade_count];
            memset(u, 0, sizeof(*u));
            snprintf(u->name, sizeof(u->name), "%s", name);
            snprintf(u->installed_ver, sizeof(u->installed_ver), "%s", installed_ver);
            snprintf(u->new_ver, sizeof(u->new_ver), "%s", idx_ver->valuestring);
            snprintf(u->repo_url, sizeof(u->repo_url), "%s", repo_url->valuestring);
            snprintf(u->category, sizeof(u->category), "%s", category->valuestring);
            upgrade_count++;
        }
    }
    pclose(fp);

    if (upgrade_count == 0) {
        log_info("All VUP packages are up to date");
        return 0;
    }

    // Print summary
    printf("\n%d package(s) to upgrade:\n", upgrade_count);
    for (int i = 0; i < upgrade_count; i++) {
        printf("  %s: %s -> %s\n", 
               upgrades[i].name, upgrades[i].installed_ver, upgrades[i].new_ver);
    }
    printf("\n");

    // Phase 2: Fetch templates (unless --yes)
    if (!yes) {
        log_info("Fetching templates for review...");
        
        for (int i = 0; i < upgrade_count; i++) {
            upgrades[i].new_template = fetch_template(upgrades[i].category, upgrades[i].name);
            upgrades[i].cached_template = cache_get_template(upgrades[i].name);
            
            if (!upgrades[i].new_template) {
                log_error("Failed to fetch template for %s", upgrades[i].name);
                free_upgrades(upgrades, upgrade_count);
                return -1;
            }
        }
        
        // Phase 3: Show batch review
        if (!show_batch_review(upgrades, upgrade_count)) {
            log_info("Upgrade cancelled by user");
            free_upgrades(upgrades, upgrade_count);
            return 0;
        }
    }

    // Phase 4: Perform upgrades
    int upgraded = 0;
    int errors = 0;
    
    for (int i = 0; i < upgrade_count; i++) {
        log_info("Upgrading %s...", upgrades[i].name);
        
        if (run_xbps_upgrade(upgrades[i].repo_url, upgrades[i].name, yes) != 0) {
            log_error("Failed to upgrade %s", upgrades[i].name);
            errors++;
        } else {
            // Verify upgrade happened
            char *new_ver = get_installed_version(upgrades[i].name);
            if (new_ver) {
                if (strcmp(new_ver, upgrades[i].installed_ver) != 0) {
                    upgraded++;
                    // Update template cache
                    if (upgrades[i].new_template) {
                        cache_save_template(upgrades[i].name, upgrades[i].new_template);
                    }
                }
                free(new_ver);
            }
        }
    }
    
    free_upgrades(upgrades, upgrade_count);

    if (upgraded > 0) {
        log_info("Upgraded %d package(s)", upgraded);
    } else if (errors == 0) {
        log_info("All VUP packages are up to date");
    }
    
    return errors > 0 ? -1 : 0;
}
