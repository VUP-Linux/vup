#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>
#include "diff.h"
#include "common.h"

#define TEMPLATE_URL_BASE "https://raw.githubusercontent.com/VUP-Linux/vup/main/vup/srcpkgs"

/**
 * Validate identifier (package name, category) for safe path construction.
 */
static int is_valid_identifier(const char *s) {
    if (!s || s[0] == '\0' || s[0] == '.') return 0;
    
    for (const char *p = s; *p; p++) {
        char c = *p;
        if (!((c >= 'a' && c <= 'z') ||
              (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') ||
              c == '-' || c == '_' || c == '.')) {
            return 0;
        }
    }
    
    if (strstr(s, "..") != NULL) return 0;
    
    return 1;
}

/**
 * Run a command using fork/exec.
 * Returns exit status, or -1 on error.
 */
static int run_command(char *const argv[]) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return -1;
    }
    
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    
    return -1;
}

/**
 * Create a secure temporary file.
 * Returns file descriptor, or -1 on error. Sets path in out_path.
 */
static int create_temp_file(const char *prefix, char *out_path, size_t path_size) {
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir || tmpdir[0] != '/') {
        tmpdir = "/tmp";
    }
    
    int ret = snprintf(out_path, path_size, "%s/%s_XXXXXX", tmpdir, prefix);
    if (ret < 0 || (size_t)ret >= path_size) {
        return -1;
    }
    
    return mkstemp(out_path);
}

char *fetch_template(const char *category, const char *pkg_name) {
    if (!is_valid_identifier(category) || !is_valid_identifier(pkg_name)) {
        log_error("Invalid category or package name");
        return NULL;
    }

    char url[1024];
    int ret = snprintf(url, sizeof(url), 
             "%s/%s/%s/template",
             TEMPLATE_URL_BASE, category, pkg_name);
    if (ret < 0 || (size_t)ret >= sizeof(url)) {
        log_error("URL too long");
        return NULL;
    }

    char tmp_path[512];
    char prefix[128];
    snprintf(prefix, sizeof(prefix), "vuru_tmpl_%s", pkg_name);
    
    int fd = create_temp_file(prefix, tmp_path, sizeof(tmp_path));
    if (fd == -1) {
        log_error("Failed to create temp file: %s", strerror(errno));
        return NULL;
    }
    close(fd);

    char *curl_args[] = {
        "curl", "-s", "-f", "-L", "-o", tmp_path, url, NULL
    };
    
    int status = run_command(curl_args);
    if (status != 0) {
        log_error("Failed to fetch template from %s", url);
        unlink(tmp_path);
        return NULL;
    }

    char *content = read_file(tmp_path);
    unlink(tmp_path);
    return content;
}

/**
 * Show diff between two templates using fork/exec.
 */
static void show_diff(const char *old_path, const char *new_path) {
    char *diff_args[] = {
        "diff", "-u", "--color=always", (char *)old_path, (char *)new_path, NULL
    };
    run_command(diff_args);
}

/**
 * Show file contents using less.
 */
static void show_with_pager(const char *path) {
    char *less_args[] = { "less", (char *)path, NULL };
    run_command(less_args);
}

int review_changes(const char *pkg_name, const char *current, const char *previous) {
    if (!pkg_name || !current) {
        return 0;
    }
    
    if (!is_valid_identifier(pkg_name)) {
        log_error("Invalid package name");
        return 0;
    }

    if (previous && strcmp(current, previous) == 0) {
        log_info("Template for %s unchanged since last install.", pkg_name);
    } else {
        char old_path[512] = {0};
        char new_path[512];
        char prefix_new[128];
        
        snprintf(prefix_new, sizeof(prefix_new), "vuru_%s_new", pkg_name);
        int fd_new = create_temp_file(prefix_new, new_path, sizeof(new_path));
        if (fd_new == -1) {
            log_error("Failed to create temp file");
            return 0;
        }
        close(fd_new);
        
        if (!write_file(new_path, current)) {
            unlink(new_path);
            return 0;
        }

        if (previous) {
            char prefix_old[128];
            snprintf(prefix_old, sizeof(prefix_old), "vuru_%s_old", pkg_name);
            int fd_old = create_temp_file(prefix_old, old_path, sizeof(old_path));
            if (fd_old == -1) {
                log_error("Failed to create temp file");
                unlink(new_path);
                return 0;
            }
            close(fd_old);
            
            if (!write_file(old_path, previous)) {
                unlink(new_path);
                unlink(old_path);
                return 0;
            }
            
            printf("\nTemplate for %s has changed:\n", pkg_name);
            printf("--------------------------------------------------\n");
            show_diff(old_path, new_path);
            printf("--------------------------------------------------\n");
            
            unlink(old_path);
        } else {
            printf("\nNew package %s. Review template:\n", pkg_name);
            show_with_pager(new_path);
        }
        
        unlink(new_path);
    }

    printf("Proceed with installation? [Y/n] ");
    fflush(stdout);
    
    char input[100];
    if (fgets(input, sizeof(input), stdin)) {
        // Trim newline
        input[strcspn(input, "\n")] = '\0';
        
        // Empty or yes
        if (input[0] == '\0' || 
            strcasecmp(input, "y") == 0 || 
            strcasecmp(input, "yes") == 0) {
            return 1;
        }
    }
    
    return 0;
}
