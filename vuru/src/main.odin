package main

import "core:fmt"
import "core:os"
import "core:strings"

import commands "commands"
import errors "core/errors"

VERSION :: "0.5.1"
INDEX_URL :: "https://vup-linux.github.io/vup/index.json"

main :: proc() {
	exit_code := run()
	os.exit(exit_code)
}

run :: proc() -> int {
	if len(os.args) < 2 {
		print_help()
		return 1
	}

	// Parse global flags and find command
	args := os.args[1:]
	config := commands.Config {
		index_url = INDEX_URL,
	}

	command_name := ""
	command_args: [dynamic]string
	defer delete(command_args)

	// Flag parsing loop
	skip_next := false
	src_cmd_index := -1 // Track where 'src' command appears
	for arg, i in args {
		if skip_next {
			skip_next = false
			continue
		}

		// Special case: 'src' command should receive raw args (for xbps-src flags)
		if arg == "src" {
			src_cmd_index = i
			command_name = "src"
			break
		}

		if strings.has_prefix(arg, "-") {
			if arg == "-h" || arg == "--help" {
				if command_name == "" {
					print_help()
					return 0
				}
				print_help()
				return 0
			} else if arg == "-V" || arg == "--version" {
				fmt.printf("vuru %s\n", VERSION)
				return 0
			} else if arg == "-y" || arg == "--yes" {
				config.yes = true
			} else if arg == "-n" || arg == "--dry-run" {
				config.dry_run = true
			} else if arg == "-b" || arg == "--build" {
				config.force_build = true
			} else if arg == "--vup-only" {
				config.vup_only = true
			} else if arg == "-d" || arg == "--desc" {
				config.description_search = true
			} else if arg == "-v" || arg == "--verbose" {
				config.verbose = true
			} else if arg == "-S" || arg == "--sync" {
				config.sync = true
			} else if arg == "-u" || arg == "--update" {
				config.update_system = true
			} else if arg == "-R" || arg == "--recursive" {
				config.recursive = true
			} else if arg == "-o" || arg == "--orphans" {
				config.orphans = true
			} else if arg == "-O" || arg == "--clean-cache" {
				config.clean_cache = true
			} else if arg == "-l" || arg == "--list" {
				config.list_pkgs = true
			} else if arg == "-f" || arg == "--files" {
				config.show_files = true
			} else if arg == "-x" || arg == "--deps" {
				config.show_deps = true
			} else if arg == "--ownedby" {
				config.ownedby = true
			} else if arg == "-r" || arg == "--rootdir" {
				if i + 1 < len(args) {
					config.rootdir = args[i + 1]
					skip_next = true
				}
			} else if strings.has_prefix(arg, "-") && len(arg) > 1 && arg[1] != '-' {
				// Short flags combined (e.g., -Sy, -Ryn)
				for c in arg[1:] {
					switch c {
					case 'y':
						config.yes = true
					case 'n':
						config.dry_run = true
					case 'b':
						config.force_build = true
					case 'd':
						config.description_search = true
					case 'v':
						config.verbose = true
					case 'S':
						config.sync = true
					case 'u':
						config.update_system = true
					case 'R':
						config.recursive = true
					case 'o':
						config.orphans = true
					case 'O':
						config.clean_cache = true
					case 'l':
						config.list_pkgs = true
					case 'f':
						config.show_files = true
					case 'x':
						config.show_deps = true
					case 'h':
						print_help()
						return 0
					case:
						errors.log_error("Unknown option: -%c", c)
						return 1
					}
				}
			}
		} else {
			if command_name == "" {
				command_name = arg
			} else {
				append(&command_args, arg)
			}
		}
	}

	// Dispatch
	switch command_name {
	case "query", "q", "info", "show":
		return commands.query_run(command_args[:], &config)
	case "search", "s":
		return commands.search_run(command_args[:], &config)
	case "install", "i":
		return commands.install_run(command_args[:], &config)
	case "remove", "r", "uninstall":
		return commands.remove_run(command_args[:], &config)
	case "update", "upgrade", "u":
		return commands.update_run(command_args[:], &config)
	case "build":
		return commands.build_run(command_args[:], &config)
	case "clone":
		return commands.clone_run(command_args[:], &config)
	case "sync":
		return commands.sync_run(command_args[:], &config)
	case "fetch":
		return commands.fetch_run(command_args[:], &config)
	case "src":
		// Pass raw args after 'src' command (bypass vuru's flag parsing)
		if src_cmd_index >= 0 && src_cmd_index + 1 < len(args) {
			return commands.src_run(args[src_cmd_index + 1:], &config)
		}
		return commands.src_run([]string{}, &config)
	case "help":
		print_help()
		return 0
	case "":
		// Check if user passed flags that require a command
		if config.recursive {
			errors.print_flag_error("-R/--recursive", "remove", "vuru remove -R <pkg>")
			return 1
		}
		if config.clean_cache {
			errors.print_flag_error("-O/--clean-cache", "remove", "vuru remove -O")
			return 1
		}
		if config.orphans {
			errors.print_flag_error("-o/--orphans", "remove", "vuru remove -o")
			return 1
		}
		if config.sync && !config.update_system {
			errors.print_flag_error("-S/--sync", "install", "vuru install -S")
			return 1
		}
		if config.update_system {
			errors.print_flag_error("-u/--update", "install", "vuru install -Su")
			return 1
		}
		if config.list_pkgs {
			errors.print_flag_error("-l/--list", "query", "vuru query -l")
			return 1
		}
		if config.show_files {
			errors.print_flag_error("-f/--files", "query", "vuru query -f <pkg>")
			return 1
		}
		if config.show_deps {
			errors.print_flag_error("-x/--deps", "query", "vuru query -x <pkg>")
			return 1
		}
		if config.verbose {
			errors.print_flag_error("-v/--verbose", "a command", "vuru query -v <pkg>")
			return 1
		}
		print_help()
		return 1
	case:
		errors.print_error(errors.make_error(.Unknown_Command, command_name))
		return 1
	}

	return 0
}

print_help :: proc() {
	fmt.println("Usage: vuru <command> [options] [arguments]")
	fmt.println()
	fmt.println("VUP package manager - AUR-like helper for Void Linux")
	fmt.println()
	fmt.println("Commands:")
	fmt.println("  query    <pkg>         Show package info (default), or use modes below")
	fmt.println("  install  <pkg...>      Install packages (VUP + official)")
	fmt.println("  remove   <pkg...>      Remove packages")
	fmt.println("  update                 Update all packages")
	fmt.println("  build    <pkg...>      Build packages from source")
	fmt.println("  sync                   Sync repository index")
	fmt.println("  fetch    <url...>      Download files from URLs")
	fmt.println("  clone                  Clone/update VUP repository")
	fmt.println("  src      <cmd> [args]  Run xbps-src with VUP deps")
	fmt.println("  help                   Show this help")
	fmt.println()
	fmt.println("Query modes:")
	fmt.println("  -s, --search     Search packages by name")
	fmt.println("  -l, --list       List installed packages")
	fmt.println("  -f, --files      Show package files")
	fmt.println("  -x, --deps       Show dependencies")
	fmt.println("  --ownedby        Find package owning a file")
	fmt.println()
	fmt.println("Install/Remove flags:")
	fmt.println("  -S, --sync       Sync repos before operation")
	fmt.println("  -u, --update     Update mode (system upgrade)")
	fmt.println("  -R, --recursive  Recursive remove/deps")
	fmt.println("  -o, --orphans    Remove orphan packages")
	fmt.println("  -O, --clean-cache  Clean package cache")
	fmt.println()
	fmt.println("General options:")
	fmt.println("  -y, --yes        Skip confirmations")
	fmt.println("  -n, --dry-run    Show what would be done")
	fmt.println("  -b, --build      Force build from source")
	fmt.println("  -d, --desc       Include descriptions in search")
	fmt.println("  -v, --verbose    Verbose output")
	fmt.println("  -r, --rootdir    Alternate root directory")
	fmt.println("  --vup-only       VUP packages only")
	fmt.println("  -V, --version    Show version")
	fmt.println("  -h, --help       Show help")
	fmt.println()
	fmt.println("Aliases: q=query, s=search, i=install, r=remove, u=update")
}
