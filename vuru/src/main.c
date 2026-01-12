#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include "cJSON.h"
#include "index.h"
#include "xbps.h"
#include "utils.h"

#define INDEX_URL "https://vup-linux.github.io/vup/index.json"
#define VERSION   "0.1.0"

static void print_version(void) {
    printf("vuru %s\n", VERSION);
}

static void print_help(const char *prog_name) {
    printf("Usage: %s [OPTIONS] [COMMAND] [ARGS...]\n\n", prog_name);
    printf("A package manager frontend for VUP repository.\n\n");
    printf("Commands:\n");
    printf("  search  <query>     Search for packages\n");
    printf("  install <pkgs...>   Install one or more packages\n");
    printf("  remove  <pkgs...>   Remove one or more packages\n");
    printf("  update              Update all installed packages\n");
    printf("\nOptions:\n");
    printf("  -S, --sync          Force sync/refresh the package index\n");
    printf("  -u, --update        Update all packages\n");
    printf("  -y, --yes           Assume yes to prompts\n");
    printf("  -v, --version       Show version information\n");
    printf("  -h, --help          Show this help message\n");
    printf("\nExamples:\n");
    printf("  %s search editor           Search for packages\n", prog_name);
    printf("  %s install visual-studio-code\n", prog_name);
    printf("  %s -Sy install ferdium     Sync and install\n", prog_name);
    printf("  %s update                  Update all packages\n", prog_name);
}

typedef enum {
    CMD_NONE,
    CMD_SEARCH,
    CMD_INSTALL,
    CMD_REMOVE,
    CMD_UPDATE
} Command;

static Command parse_command(const char *cmd) {
    if (!cmd) return CMD_NONE;
    
    if (strcmp(cmd, "search") == 0)  return CMD_SEARCH;
    if (strcmp(cmd, "install") == 0) return CMD_INSTALL;
    if (strcmp(cmd, "remove") == 0)  return CMD_REMOVE;
    if (strcmp(cmd, "update") == 0)  return CMD_UPDATE;
    
    return CMD_NONE;
}

int main(int argc, char *argv[]) {
    int sync_flag = 0;
    int update_flag = 0;
    int yes_flag = 0;

    static struct option long_options[] = {
        {"sync",    no_argument, 0, 'S'},
        {"update",  no_argument, 0, 'u'},
        {"yes",     no_argument, 0, 'y'},
        {"version", no_argument, 0, 'v'},
        {"help",    no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "Suyvh", long_options, NULL)) != -1) {
        switch (opt) {
            case 'S': sync_flag = 1; break;
            case 'u': update_flag = 1; break;
            case 'y': yes_flag = 1; break;
            case 'v': print_version(); return 0;
            case 'h': print_help(argv[0]); return 0;
            default:
                fprintf(stderr, "Try '%s --help' for more information.\n", argv[0]);
                return 1;
        }
    }

    // Handle -u flag without explicit command
    if (update_flag && optind >= argc) {
        Index *idx = index_load_or_fetch(INDEX_URL, sync_flag);
        if (!idx) {
            log_error("Failed to load package index");
            return 1;
        }
        xbps_upgrade_all(idx, yes_flag);
        index_free(idx);
        return 0;
    }

    // No command or packages specified
    if (optind >= argc) {
        if (sync_flag) {
            // Just sync the index
            Index *idx = index_load_or_fetch(INDEX_URL, 1);
            if (!idx) {
                log_error("Failed to sync package index");
                return 1;
            }
            log_info("Package index synchronized");
            index_free(idx);
            return 0;
        }
        print_help(argv[0]);
        return 1;
    }

    // Parse command
    Command cmd = parse_command(argv[optind]);
    if (cmd != CMD_NONE) {
        optind++;  // Skip command argument
    } else {
        // Default to install if first arg isn't a known command
        cmd = CMD_INSTALL;
    }

    // Load index
    Index *idx = index_load_or_fetch(INDEX_URL, sync_flag);
    if (!idx) {
        log_error("Failed to load package index");
        return 1;
    }

    int exit_code = 0;

    switch (cmd) {
        case CMD_SEARCH:
            if (optind >= argc) {
                log_error("search requires a query argument");
                exit_code = 1;
            } else {
                for (int i = optind; i < argc; i++) {
                    if (i > optind) printf("\n");
                    printf("Searching for '%s':\n", argv[i]);
                    xbps_search(idx, argv[i]);
                }
            }
            break;

        case CMD_INSTALL:
            if (optind >= argc) {
                log_error("install requires at least one package name");
                exit_code = 1;
            } else {
                for (int i = optind; i < argc; i++) {
                    if (xbps_install_pkg(idx, argv[i], yes_flag) != 0) {
                        exit_code = 1;
                    }
                }
            }
            break;

        case CMD_REMOVE:
            if (optind >= argc) {
                log_error("remove requires at least one package name");
                exit_code = 1;
            } else {
                for (int i = optind; i < argc; i++) {
                    if (xbps_uninstall(argv[i], yes_flag) != 0) {
                        exit_code = 1;
                    }
                }
            }
            break;

        case CMD_UPDATE:
            xbps_upgrade_all(idx, yes_flag);
            break;

        default:
            log_error("Unknown command");
            exit_code = 1;
            break;
    }

    index_free(idx);
    return exit_code;
}
