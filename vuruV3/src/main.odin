package main

import "core:fmt"
import "core:os"
import "core:strings"

VERSION :: "0.3.7"
INDEX_URL :: "https://vup-linux.github.io/vup/index.json"

Command :: enum {
	None,
	Search,
	Install,
	Remove,
	Update,
}

Args :: struct {
	command:  Command,
	packages: []string,
	sync:     bool,
	yes:      bool,
}

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}

run :: proc() -> int {
	args := parse_args()

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
			xbps_upgrade_all(&idx, args.yes)
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

	exit_code := 0

	switch args.command {
	case .Search:
		if len(args.packages) == 0 {
			log_error("search requires a query argument")
			exit_code = 1
		} else {
			// Iterate efficiently: `for val, idx in slice`
			for query, i in args.packages {
				if i > 0 {fmt.println()}
				fmt.printf("Searching for '%s':\n", query)
				xbps_search(&idx, query)
			}
		}

	case .Install:
		if len(args.packages) == 0 {
			log_error("install requires at least one package name")
			exit_code = 1
		} else {
			for pkg in args.packages {
				if xbps_install_pkg(&idx, pkg, args.yes) != 0 {
					exit_code = 1
				}
			}
		}

	case .Remove:
		if len(args.packages) == 0 {
			log_error("remove requires at least one package name")
			exit_code = 1
		} else {
			for pkg in args.packages {
				if xbps_uninstall(pkg, args.yes) != 0 {
					exit_code = 1
				}
			}
		}

	case .Update:
		xbps_upgrade_all(&idx, args.yes)

	case .None:
		// Packages specified without command = install
		for pkg in args.packages {
			if xbps_install_pkg(&idx, pkg, args.yes) != 0 {
				exit_code = 1
			}
		}
	}

	return exit_code
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
				case:
					log_error(fmt.tprintf("Unknown option: -%c", c))
					os.exit(1)
				}
			}
		} else {
			// Positional argument
			if args.command == .None {
				switch arg {
				case "search":
					args.command = .Search
				case "install":
					args.command = .Install
				case "remove":
					args.command = .Remove
				case "update":
					args.command = .Update
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
	fmt.println("A package manager frontend for VUP repository.")
	fmt.println()
	fmt.println("Commands:")
	fmt.println("  search  <query>     Search for packages")
	fmt.println("  install <pkgs...>   Install one or more packages")
	fmt.println("  remove  <pkgs...>   Remove one or more packages")
	fmt.println("  update              Update all installed packages")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -S, --sync          Force sync/refresh the package index")
	fmt.println("  -u, --update        Update all packages")
	fmt.println("  -y, --yes           Assume yes to prompts")
	fmt.println("  -v, --version       Show version information")
	fmt.println("  -h, --help          Show this help message")
	fmt.println()
	fmt.println("Examples:")
	fmt.println("  vuru search editor           Search for packages")
	fmt.println("  vuru install visual-studio-code")
	fmt.println("  vuru -Sy install ferdium     Sync and install")
	fmt.println("  vuru update                  Update all packages")
}
