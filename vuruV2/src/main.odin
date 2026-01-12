package vuru

import "core:fmt"
import "core:os"
import "core:strings"

VERSION :: "0.4.0"
INDEX_URL :: "https://vup-linux.github.io/vup/index.json"

Command :: enum {
    None,
    Search,
    Install,
    Remove,
    Update,
}

Options :: struct {
    sync:    bool,
    update:  bool,
    yes:     bool,
    command: Command,
    args:    []string,
}

print_version :: proc() {
    fmt.println("vuru", VERSION)
}

print_help :: proc(prog_name: string) {
    fmt.printfln("Usage: %s [OPTIONS] [COMMAND] [ARGS...]\n", prog_name)
    fmt.println("A package manager frontend for VUP repository.\n")
    fmt.println("Commands:")
    fmt.println("  search  <query>     Search for packages")
    fmt.println("  install <pkgs...>   Install one or more packages")
    fmt.println("  remove  <pkgs...>   Remove one or more packages")
    fmt.println("  update              Update all installed packages")
    fmt.println("\nOptions:")
    fmt.println("  -S, --sync          Force sync/refresh the package index")
    fmt.println("  -u, --update        Update all packages")
    fmt.println("  -y, --yes           Assume yes to prompts")
    fmt.println("  -v, --version       Show version information")
    fmt.println("  -h, --help          Show this help message")
    fmt.println("\nExamples:")
    fmt.printfln("  %s search editor           Search for packages", prog_name)
    fmt.printfln("  %s install visual-studio-code", prog_name)
    fmt.printfln("  %s -Sy install ferdium     Sync and install", prog_name)
    fmt.printfln("  %s update                  Update all packages", prog_name)
}

parse_command :: proc(cmd: string) -> Command {
    switch cmd {
    case "search":  return .Search
    case "install": return .Install
    case "remove":  return .Remove
    case "update":  return .Update
    case:           return .None
    }
}

parse_args :: proc(args: []string) -> (opts: Options, ok: bool) {
    opts = Options{}
    i := 1  // Skip program name
    
    // Parse flags
    for i < len(args) {
        arg := args[i]
        
        if !strings.has_prefix(arg, "-") {
            break
        }
        
        // Handle combined short flags like -Sy
        if len(arg) > 1 && arg[0] == '-' && arg[1] != '-' {
            for c in arg[1:] {
                switch c {
                case 'S': opts.sync = true
                case 'u': opts.update = true
                case 'y': opts.yes = true
                case 'v':
                    print_version()
                    os.exit(0)
                case 'h':
                    print_help(args[0])
                    os.exit(0)
                case:
                    log_error("Unknown option: -%c", c)
                    return {}, false
                }
            }
        } else {
            switch arg {
            case "--sync":    opts.sync = true
            case "--update":  opts.update = true
            case "--yes":     opts.yes = true
            case "--version":
                print_version()
                os.exit(0)
            case "--help":
                print_help(args[0])
                os.exit(0)
            case:
                log_error("Unknown option: %s", arg)
                return {}, false
            }
        }
        i += 1
    }
    
    // Parse command
    if i < len(args) {
        opts.command = parse_command(args[i])
        i += 1
    }
    
    // Remaining args are package names
    if i < len(args) {
        opts.args = args[i:]
    }
    
    return opts, true
}

main :: proc() {
    args := os.args
    
    if len(args) < 2 {
        print_help(args[0])
        os.exit(1)
    }
    
    opts, ok := parse_args(args)
    if !ok {
        fmt.eprintfln("Try '%s --help' for more information.", args[0])
        os.exit(1)
    }
    
    // Handle -u flag without explicit command
    if opts.update && opts.command == .None {
        idx, idx_ok := index_load_or_fetch(INDEX_URL, opts.sync)
        if !idx_ok {
            log_error("Failed to load package index")
            os.exit(1)
        }
        defer index_free(&idx)
        
        xbps_upgrade_all(&idx, opts.yes)
        return
    }
    
    // Just sync the index
    if opts.sync && opts.command == .None && len(opts.args) == 0 {
        idx, idx_ok := index_load_or_fetch(INDEX_URL, true)
        if !idx_ok {
            log_error("Failed to load package index")
            os.exit(1)
        }
        defer index_free(&idx)
        
        log_info("Package index synchronized")
        return
    }
    
    // Execute command
    switch opts.command {
    case .Search:
        if len(opts.args) == 0 {
            log_error("search requires a query argument")
            os.exit(1)
        }
        idx, idx_ok := index_load_or_fetch(INDEX_URL, opts.sync)
        if !idx_ok {
            log_error("Failed to load package index")
            os.exit(1)
        }
        defer index_free(&idx)
        
        xbps_search(&idx, opts.args[0])
        
    case .Install:
        if len(opts.args) == 0 {
            log_error("install requires at least one package name")
            os.exit(1)
        }
        idx, idx_ok := index_load_or_fetch(INDEX_URL, opts.sync)
        if !idx_ok {
            log_error("Failed to load package index")
            os.exit(1)
        }
        defer index_free(&idx)
        
        for pkg in opts.args {
            xbps_install_pkg(&idx, pkg, opts.yes)
        }
        
    case .Remove:
        if len(opts.args) == 0 {
            log_error("remove requires at least one package name")
            os.exit(1)
        }
        idx, idx_ok := index_load_or_fetch(INDEX_URL, opts.sync)
        if !idx_ok {
            log_error("Failed to load package index")
            os.exit(1)
        }
        defer index_free(&idx)
        
        for pkg in opts.args {
            xbps_remove_pkg(&idx, pkg, opts.yes)
        }
        
    case .Update:
        idx, idx_ok := index_load_or_fetch(INDEX_URL, opts.sync)
        if !idx_ok {
            log_error("Failed to load package index")
            os.exit(1)
        }
        defer index_free(&idx)
        
        xbps_upgrade_all(&idx, opts.yes)
        
    case .None:
        print_help(args[0])
        os.exit(1)
    }
}
