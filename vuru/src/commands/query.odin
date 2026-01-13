package commands

import "core:fmt"
import "core:strings"

import errors "../core/errors"
import index "../core/index"
import resolve "../core/resolve"
import template "../core/template"
import utils "../utils"

// Unified query command - maps to xbps-query patterns
query_run :: proc(args: []string, config: ^Config) -> int {
	// Mode: list installed packages (-l)
	if config.list_pkgs {
		return query_list(config)
	}

	// Mode: find file owner (--ownedby)
	if config.ownedby && len(args) > 0 {
		return query_ownedby(args[0], config)
	}

	// Mode: show package files (-f)
	if config.show_files && len(args) > 0 {
		return query_files(args[0], config)
	}

	// Mode: show dependencies (-x)
	if config.show_deps && len(args) > 0 {
		return query_deps(args[0], config)
	}

	// Mode: search packages (when no specific package given or -s flag implied)
	// Note: "search" and "s" aliases route here too
	if len(args) == 0 {
		query_help()
		return 1
	}

	// Default: show package info (like xbps-query <pkg>)
	return query_info(args, config)
}

// List installed packages (xbps-query -l)
query_list :: proc(config: ^Config) -> int {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "xbps-query", "-l")
	if config.verbose {
		append(&cmd, "-v")
	}
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}
	return utils.run_command(cmd[:])
}

// Find package owning a file (xbps-query -o)
query_ownedby :: proc(file: string, config: ^Config) -> int {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "xbps-query", "-o", file)
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}
	return utils.run_command(cmd[:])
}

// Show package files (xbps-query -f)
query_files :: proc(pkg: string, config: ^Config) -> int {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "xbps-query", "-f", pkg)
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}
	return utils.run_command(cmd[:])
}

// Show package dependencies (xbps-query -x)
query_deps :: proc(pkg: string, config: ^Config) -> int {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "xbps-query", "-x", pkg)
	if config.recursive {
		append(&cmd, "--fulldeptree")
	}
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}
	return utils.run_command(cmd[:])
}

// Show package info (default mode) - searches VUP first, then official
query_info :: proc(args: []string, config: ^Config) -> int {
	// Load VUP index
	idx, ok := index.index_load_or_fetch(config.index_url, false)
	if !ok {
		errors.log_error("Failed to load package index")
		return 1
	}
	defer index.index_free(&idx)

	for pkg_name in args {
		// Check VUP first
		if pkg, found := index.index_get_package(&idx, pkg_name); found {
			// Always fetch template for complete info
			tmpl, tmpl_ok := resolve.fetch_and_parse_template(
				pkg.category,
				pkg_name,
				context.temp_allocator,
			)
			if tmpl_ok {
				defer template.template_free(&tmpl)
			}

			// Use template description if index doesn't have it
			desc := pkg.short_desc
			if len(desc) == 0 && tmpl_ok && len(tmpl.short_desc) > 0 {
				desc = tmpl.short_desc
			}

			// Output in xbps-query style
			fmt.printf("pkgname: %s\n", pkg_name)
			fmt.printf("pkgver: %s-%s\n", pkg_name, pkg.version)
			fmt.printf("category: %s\n", pkg.category)
			fmt.printf("source: VUP\n")

			// Show architectures
			fmt.print("architectures: ")
			first := true
			for arch, _ in pkg.repo_urls {
				if !first {fmt.print(" ")}
				fmt.print(arch)
				first = false
			}
			fmt.println()

			// Show deps from template
			if tmpl_ok {
				if len(tmpl.homepage) > 0 {
					fmt.printf("homepage: %s\n", tmpl.homepage)
				}
				if len(tmpl.license) > 0 {
					fmt.printf("license: %s\n", tmpl.license)
				}
				if len(tmpl.maintainer) > 0 {
					fmt.printf("maintainer: %s\n", tmpl.maintainer)
				}
				if len(tmpl.depends) > 0 {
					fmt.println("run_depends:")
					for dep in tmpl.depends {
						fmt.printf("\t%s\n", dep)
					}
				}
				if len(tmpl.makedepends) > 0 {
					fmt.println("makedepends:")
					for dep in tmpl.makedepends {
						fmt.printf("\t%s\n", dep)
					}
				}
				if len(tmpl.hostmakedeps) > 0 {
					fmt.println("hostmakedepends:")
					for dep in tmpl.hostmakedeps {
						fmt.printf("\t%s\n", dep)
					}
				}
			}

			fmt.printf("short_desc: %s\n", desc)
			fmt.println()
		} else if !config.vup_only {
			// Check official repos
			cmd := make([dynamic]string, context.temp_allocator)
			append(&cmd, "xbps-query", "-R", pkg_name)
			if len(config.rootdir) > 0 {
				append(&cmd, "-r", config.rootdir)
			}
			if utils.run_command(cmd[:]) != 0 {
				errors.log_error("Package '%s' not found", pkg_name)
				return 1
			}
		} else {
			errors.log_error("VUP package '%s' not found", pkg_name)
			return 1
		}
	}

	return 0
}

// Print help for query command
query_help :: proc() {
	fmt.println("Usage: vuru query [options] <package>")
	fmt.println()
	fmt.println("Modes:")
	fmt.println("  <package>       Show package info (default)")
	fmt.println("  -l, --list      List installed packages")
	fmt.println("  -f, --files     Show package files")
	fmt.println("  -x, --deps      Show dependencies")
	fmt.println("  --ownedby       Find package owning a file")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -R, --recursive Show full dependency tree")
	fmt.println("  -v, --verbose   Verbose output")
	fmt.println("  -r, --rootdir   Alternate root directory")
	fmt.println("  --vup-only      VUP packages only")
}
