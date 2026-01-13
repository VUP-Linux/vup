package main

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
	Query,    // Show package info
	Build,    // Build from source only
	Clone,    // Clone/update VUP repo
	Src,      // xbps-src wrapper
}

Args :: struct {
	command:       Command,
	packages:      []string,
	sync:          bool,
	yes:           bool,
	vup_only:      bool,  // Search VUP only
	show_deps:     bool,  // Show dependencies
	build_source:  bool,  // Force build from source
	all_repos:     bool,  // Search all repos (including official)
}

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}

run :: proc() -> int {
	args := parse_args()

	// Handle clone command (doesn't need index)
	if args.command == .Clone {
		return cmd_clone()
	}

	// Handle src command (xbps-src wrapper)
	if args.command == .Src {
		return cmd_src(&args)
	}

	// Handle -u flag without explicit command
	if args.command == .Update || (args.command == .None && len(args.packages) == 0) {
		if args.command == .None && !args.sync {
			print_help()
			return 1
		}

		idx, ok := index_load_or_fetch(INDEX_URL, args.sync)
		if !ok {
			log_error("Failed to load package index")
			return 1
		}
		defer index_free(&idx)

		if args.command == .Update {
			return cmd_update(&idx, &args)
		} else {
			log_info("Package index synchronized")
		}
		return 0
	}

	// Load index
	idx, ok := index_load_or_fetch(INDEX_URL, args.sync)
	if !ok {
		log_error("Failed to load package index")
		return 1
	}
	defer index_free(&idx)

	switch args.command {
	case .Search:
		return cmd_search(&idx, &args)

	case .Install:
		return cmd_install(&idx, &args)

	case .Remove:
		return cmd_remove(&args)

	case .Update:
		return cmd_update(&idx, &args)

	case .Query:
		return cmd_query(&idx, &args)

	case .Build:
		return cmd_build(&idx, &args)

	case .Clone:
		return cmd_clone()

	case .Src:
		return cmd_src(&args)

	case .None:
		// Packages specified without command = install
		return cmd_install(&idx, &args)
	}

	return 0
}

// --- Command implementations ---

cmd_search :: proc(idx: ^Index, args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("search requires a query argument")
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
		log_error("install requires at least one package name")
		return 1
	}

	exit_code := 0

	for pkg_name in args.packages {
		// Resolve dependencies
		res, ok := resolve_deps(pkg_name, idx, args.build_source)
		if !ok {
			log_error("Failed to resolve dependencies for %s", pkg_name)
			exit_code = 1
			continue
		}
		defer resolution_free(&res)

		// Check for missing packages
		if len(res.missing) > 0 {
			log_error("Cannot resolve: %s", strings.join(res.missing[:], ", ", context.temp_allocator))
			exit_code = 1
			continue
		}

		// Show what will happen
		if args.show_deps {
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
		log_error("remove requires at least one package name")
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

cmd_query :: proc(idx: ^Index, args: ^Args) -> int {
	if len(args.packages) == 0 {
		log_error("query requires a package name")
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
		log_error("build requires a package name")
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

	argv := os.args[1:] // Skip program name

	i := 0
	for i < len(argv) {
		arg := argv[i]

		if arg == "-h" || arg == "--help" {
			print_help()
			os.exit(0)
		} else if arg == "-v" || arg == "--version" {
			fmt.printf("vuru %s\n", VERSION)
			os.exit(0)
		} else if arg == "-S" || arg == "--sync" {
			args.sync = true
		} else if arg == "-u" || arg == "--update" {
			args.command = .Update
		} else if arg == "-y" || arg == "--yes" {
			args.yes = true
		} else if arg == "-d" || arg == "--deps" {
			args.show_deps = true
		} else if arg == "-b" || arg == "--build" {
			args.build_source = true
		} else if arg == "-a" || arg == "--all" {
			args.all_repos = true
		} else if arg == "--vup-only" {
			args.vup_only = true
		} else if strings.has_prefix(arg, "-") {
			// Handle combined flags like -Sy
			for c in arg[1:] {
				switch c {
				case 'S':
					args.sync = true
				case 'u':
					args.command = .Update
				case 'y':
					args.yes = true
				case 'd':
					args.show_deps = true
				case 'b':
					args.build_source = true
				case 'a':
					args.all_repos = true
				case:
					log_error(fmt.tprintf("Unknown option: -%c", c))
					os.exit(1)
				}
			}
		} else {
			// Positional argument
			if args.command == .None {
				switch arg {
				case "search", "s":
					args.command = .Search
				case "install", "i":
					args.command = .Install
				case "remove", "r":
					args.command = .Remove
				case "update", "u":
					args.command = .Update
				case "query", "q":
					args.command = .Query
				case "build", "b":
					args.command = .Build
				case "clone":
					args.command = .Clone
				case "src":
					args.command = .Src
					// For src, remaining args go straight to xbps-src
					if i + 1 < len(argv) {
						args.packages = argv[i + 1:]
					}
					return args
				case:
					// Not a command, treat as package name
					args.packages = argv[i:]
					return args
				}
			} else {
				// Remaining args are packages
				args.packages = argv[i:]
				return args
			}
		}
		i += 1
	}

	return args
}

print_help :: proc() {
	fmt.println("Usage: vuru [OPTIONS] [COMMAND] [ARGS...]")
	fmt.println()
	fmt.println("A paru/yay-like AUR helper for VUP (Void User Packages).")
	fmt.println()
	fmt.println("Commands:")
	fmt.println("  search, s  <query>    Search packages (VUP + official)")
	fmt.println("  install, i <pkgs...>  Install packages (resolves dependencies)")
	fmt.println("  remove, r  <pkgs...>  Remove packages")
	fmt.println("  update, u             Update all VUP packages")
	fmt.println("  query, q   <pkg>      Show package information")
	fmt.println("  build, b   <pkgs...>  Build packages from source")
	fmt.println("  clone                 Clone/update VUP repository")
	fmt.println("  src <cmd> [args]      Run xbps-src with VUP deps resolved")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -S, --sync       Force sync/refresh the package index")
	fmt.println("  -y, --yes        Assume yes to prompts")
	fmt.println("  -d, --deps       Show resolved dependencies (dry-run)")
	fmt.println("  -b, --build      Force build from source")
	fmt.println("  -a, --all        Search all repos (including official)")
	fmt.println("  --vup-only       Search VUP packages only")
	fmt.println("  -v, --version    Show version information")
	fmt.println("  -h, --help       Show this help message")
	fmt.println()
	fmt.println("Examples:")
	fmt.println("  vuru search code        # Search VUP + official repos")
	fmt.println("  vuru visual-studio-code # Install (implicit)")
	fmt.println("  vuru -Sy ferdium        # Sync index and install")
	fmt.println("  vuru -d ferdium         # Show what would be installed")
	fmt.println("  vuru build odin         # Build odin from source")
	fmt.println("  vuru clone              # Clone VUP repo for building")
	fmt.println("  vuru update             # Update all VUP packages")
	fmt.println("  vuru src pkg myapp      # Build template with VUP deps")
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

	if xbps_src_main(args.packages, &cfg) {
		return 0
	}
	return 1
}
