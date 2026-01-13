package main

import "core:fmt"
import "core:os"
import "core:strings"
import "errors"

VERSION :: "0.5.0"
INDEX_URL :: "https://vup-linux.github.io/vup/index.json"

Command :: enum {
	None,
	Search,
	Install,
	Remove,
	Update,
	Info,     // Show package info (renamed from Query)
	Build,    // Build from source only
	Clone,    // Clone/update VUP repo
	Src,      // xbps-src wrapper
	Sync,     // Sync index (explicit command)
	Help,     // Show help
}

Args :: struct {
	command:       Command,
	packages:      []string,
	yes:           bool,      // Skip confirmations
	dry_run:       bool,      // Show what would happen
	force_build:   bool,      // Force build from source
	vup_only:      bool,      // Search VUP only
}

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}

run :: proc() -> int {
	args := parse_args()

	// Commands that don't need the index
	#partial switch args.command {
	case .None:
		print_help()
		return 1
	
	case .Help:
		print_help()
		return 0
	
	case .Clone:
		return cmd_clone()
	
	case .Src:
		return cmd_src(&args)
	
	case .Sync:
		return cmd_sync()
	}

	// Load index (force sync for update command)
	force_sync := args.command == .Update
	idx, ok := index_load_or_fetch(INDEX_URL, force_sync)
	if !ok {
		log_error("Failed to load package index")
		log_error("Try: vuru sync")
		return 1
	}
	defer index_free(&idx)

	#partial switch args.command {
	case .Search:
		return cmd_search(&idx, &args)

	case .Install:
		return cmd_install(&idx, &args)

	case .Remove:
		return cmd_remove(&args)

	case .Update:
		return cmd_update(&idx, &args)

	case .Info:
		return cmd_info(&idx, &args)

	case .Build:
		return cmd_build(&idx, &args)
	}

	return 0
}

// --- Command implementations ---

cmd_sync :: proc() -> int {
	_, ok := index_load_or_fetch(INDEX_URL, true)
	if !ok {
		log_error("Failed to sync package index")
		return 1
	}
	log_info("Package index synchronized")
	return 0
}

cmd_search :: proc(idx: ^Index, args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("Usage: vuru search <query>")
		return 1
	}

	for query, i in args.packages {
		if i > 0 {fmt.println()}
		unified_search(idx, query, args.vup_only)
	}

	return 0
}

cmd_install :: proc(idx: ^Index, args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("Usage: vuru install <package> [packages...]")
		return 1
	}

	exit_code := 0

	for pkg_name in args.packages {
		// Resolve dependencies
		res, ok := resolve_deps(pkg_name, idx, args.force_build)
		if !ok {
			// Print detailed errors if available
			if len(res.errors) > 0 {
				for err in res.errors {
					errors.print_error(err)
				}
			} else {
				log_error("Failed to resolve dependencies for %s", pkg_name)
			}
			resolution_free(&res)
			exit_code = 1
			continue
		}
		defer resolution_free(&res)

		// Check for missing packages
		if len(res.missing) > 0 {
			// Use detailed errors if available
			if len(res.errors) > 0 {
				for err in res.errors {
					errors.print_error(err)
				}
			} else {
				log_error("Cannot resolve: %s", strings.join(res.missing[:], ", ", context.temp_allocator))
			}
			exit_code = 1
			continue
		}

		// Dry run - just show what would happen
		if args.dry_run {
			resolution_print(&res)
			continue
		}

		// Create transaction
		tx := transaction_from_resolution(&res)
		defer transaction_free(&tx)

		transaction_print(&tx)

		// Confirm unless -y
		if !args.yes && !transaction_confirm(&tx) {
			log_info("Installation cancelled")
			continue
		}

		// Get build config if needed
		cfg: Build_Config
		has_build := false
		for item in tx.items {
			if item.op == .Build_Install {
				has_build = true
				break
			}
		}

		if has_build {
			cfg_result, cfg_ok := default_build_config()
			if !cfg_ok {
				log_error("VUP repository not found. Run 'vuru clone' first.")
				exit_code = 1
				continue
			}
			cfg = cfg_result
		}

		// Execute
		if !transaction_execute(&tx, &cfg, args.yes) {
			exit_code = 1
		}
	}

	return exit_code
}

cmd_remove :: proc(args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("Usage: vuru remove <package> [packages...]")
		return 1
	}

	exit_code := 0
	for pkg in args.packages {
		if xbps_uninstall(pkg, args.yes) != 0 {
			exit_code = 1
		}
	}

	return exit_code
}

cmd_update :: proc(idx: ^Index, args: ^Args) -> int {
	return xbps_upgrade_all(idx, args.yes)
}

cmd_info :: proc(idx: ^Index, args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("Usage: vuru info <package>")
		return 1
	}

	for pkg_name in args.packages {
		// Check VUP first
		if pkg, ok := index_get_package(idx, pkg_name); ok {
			fmt.println()
			fmt.printf("Package: %s\n", pkg_name)
			fmt.printf("Version: %s\n", pkg.version)
			fmt.printf("Category: %s\n", pkg.category)
			fmt.printf("Description: %s\n", pkg.short_desc)
			fmt.printf("Source: VUP\n")

			// Show architectures
			fmt.print("Architectures: ")
			first := true
			for arch, _ in pkg.repo_urls {
				if !first {fmt.print(", ")}
				fmt.print(arch)
				first = false
			}
			fmt.println()

			// Try to fetch and show template info
			if template, tmpl_ok := fetch_and_parse_template(pkg.category, pkg_name, context.temp_allocator); tmpl_ok {
				if len(template.depends) > 0 {
					fmt.printf("Dependencies: %s\n", strings.join(template.depends, " ", context.temp_allocator))
				}
				if len(template.makedepends) > 0 {
					fmt.printf("Build deps: %s\n", strings.join(template.makedepends, " ", context.temp_allocator))
				}
			}

			fmt.println()
		} else {
			// Check official repos
			if run_command({"xbps-query", "-R", pkg_name}) != 0 {
				log_error("Package '%s' not found", pkg_name)
				return 1
			}
		}
	}

	return 0
}

cmd_build :: proc(idx: ^Index, args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("Usage: vuru build <package> [packages...]")
		return 1
	}

	cfg, cfg_ok := default_build_config()
	if !cfg_ok {
		log_error("VUP repository not found. Run 'vuru clone' first.")
		return 1
	}

	exit_code := 0

	for pkg_name in args.packages {
		pkg, ok := index_get_package(idx, pkg_name)
		if !ok {
			log_error("Package '%s' not found in VUP index", pkg_name)
			exit_code = 1
			continue
		}

		if !build_package(&cfg, pkg_name, pkg.category) {
			exit_code = 1
		} else {
			log_info("Successfully built %s", pkg_name)

			// Show where the package is
			if path, path_ok := get_built_package_path(&cfg, pkg_name, context.temp_allocator); path_ok {
				log_info("Package file: %s", path)
			}
		}
	}

	return exit_code
}

cmd_clone :: proc() -> int {
	home := os.get_env("HOME", context.temp_allocator)
	if len(home) == 0 {
		log_error("HOME not set")
		return 1
	}

	target := path_join(home, ".local/share/vup", allocator = context.temp_allocator)

	if !mkdir_p(path_join(home, ".local/share", allocator = context.temp_allocator)) {
		log_error("Failed to create directory")
		return 1
	}

	if vup_clone_or_update(target) {
		log_info("VUP repository ready at %s", target)
		return 0
	}

	log_error("Failed to clone/update VUP repository")
	return 1
}

parse_args :: proc() -> Args {
	args := Args{}
	argv := os.args[1:]

	if len(argv) == 0 {
		return args  // .None command
	}

	packages: [dynamic]string
	defer delete(packages)

	for i := 0; i < len(argv); i += 1 {
		arg := argv[i]
		
		// Check for options (can appear anywhere)
		if arg == "-h" || arg == "--help" {
			args.command = .Help
			return args
		} else if arg == "-v" || arg == "--version" {
			fmt.printf("vuru %s\n", VERSION)
			os.exit(0)
		} else if arg == "-y" || arg == "--yes" {
			args.yes = true
		} else if arg == "-n" || arg == "--dry-run" {
			args.dry_run = true
		} else if arg == "-b" || arg == "--build" {
			args.force_build = true
		} else if arg == "--vup-only" {
			args.vup_only = true
		} else if strings.has_prefix(arg, "-") {
			// Handle combined flags like -yn
			for c in arg[1:] {
				switch c {
				case 'y':
					args.yes = true
				case 'n':
					args.dry_run = true
				case 'b':
					args.force_build = true
				case:
					log_error("Unknown option: -%c", c)
					log_error("Try: vuru help")
					os.exit(1)
				}
			}
		} else if args.command == .None {
			// First non-option is the command
			switch arg {
			case "search", "s":
				args.command = .Search
			case "install", "i":
				args.command = .Install
			case "remove", "r", "uninstall":
				args.command = .Remove
			case "update", "upgrade", "u":
				args.command = .Update
			case "info", "show", "query", "q":
				args.command = .Info
			case "build":
				args.command = .Build
			case "clone":
				args.command = .Clone
			case "sync":
				args.command = .Sync
			case "help":
				args.command = .Help
			case "src":
				args.command = .Src
				// For src, remaining args go straight to xbps-src
				if i + 1 < len(argv) {
					args.packages = argv[i + 1:]
				}
				return args
			case:
				log_error("Unknown command: %s", arg)
				log_error("Try: vuru help")
				os.exit(1)
			}
		} else {
			// After command, collect as package arguments
			append(&packages, arg)
		}
	}

	// Convert dynamic to slice
	if len(packages) > 0 {
		result := make([]string, len(packages))
		for pkg, i in packages {
			result[i] = pkg
		}
		args.packages = result
	}

	return args
}

print_help :: proc() {
	fmt.println("Usage: vuru <command> [options] [arguments]")
	fmt.println()
	fmt.println("VUP package manager - AUR-like helper for Void Linux")
	fmt.println()
	fmt.println("Commands:")
	fmt.println("  search   <query>       Search packages (VUP + official)")
	fmt.println("  install  <pkg...>      Install packages")
	fmt.println("  remove   <pkg...>      Remove packages")
	fmt.println("  update                 Update all VUP packages")
	fmt.println("  info     <pkg>         Show package information")
	fmt.println("  build    <pkg...>      Build packages from source")
	fmt.println("  sync                   Refresh the package index")
	fmt.println("  clone                  Clone/update VUP repository")
	fmt.println("  src      <cmd> [args]  Run xbps-src with VUP deps")
	fmt.println("  help                   Show this help message")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -y, --yes        Skip confirmation prompts")
	fmt.println("  -n, --dry-run    Show what would be done")
	fmt.println("  -b, --build      Force build from source")
	fmt.println("  --vup-only       Search VUP packages only")
	fmt.println("  -v, --version    Show version")
	fmt.println("  -h, --help       Show help")
	fmt.println()
	fmt.println("Aliases:")
	fmt.println("  s = search,  i = install,  r = remove")
	fmt.println("  u = update,  q = info")
	fmt.println()
	fmt.println("Examples:")
	fmt.println("  vuru search code           Search for 'code'")
	fmt.println("  vuru install vlang         Install vlang")
	fmt.println("  vuru install -n ferdium    Dry-run install")
	fmt.println("  vuru remove zig15          Remove zig15")
	fmt.println("  vuru update                Update VUP packages")
	fmt.println("  vuru info odin             Show package info")
	fmt.println("  vuru build odin            Build from source")
	fmt.println("  vuru sync                  Refresh package index")
	fmt.println("  vuru src pkg myapp         Build with xbps-src")
}

// --- src command (xbps-src wrapper) ---

cmd_src :: proc(args: ^Args) -> int {
	// packages slice contains all args after 'src'
	if len(args.packages) == 0 {
		xbps_src_usage()
		return 1
	}

	// Build config for index URL
	cfg := Config{
		index_url = INDEX_URL,
		repo_url = "https://github.com/VUP-Linux/vup/releases/download",
	}

	ok, err := xbps_src_main(args.packages, &cfg)
	if !ok {
		if err.kind != nil {
			errors.print_error(err)
		}
		return 1
	}
	return 0
}
