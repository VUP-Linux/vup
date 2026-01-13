package commands

import errors "../core/errors"
import utils "../utils"
import "core:fmt"

// Remove command implementation
remove_run :: proc(args: []string, config: ^Config) -> int {
	// Mode: clean cache (-O)
	if config.clean_cache {
		return remove_cache(config)
	}

	// Mode: remove orphans (-o)
	if config.orphans {
		return remove_orphans(config)
	}

	// Standard remove
	if len(args) == 0 {
		fmt.println("Usage: vuru remove <package> [packages...]")
		fmt.println("       vuru remove -o    (remove orphans)")
		fmt.println("       vuru remove -O    (clean cache)")
		return 1
	}

	exit_code := 0
	for pkg in args {
		if xbps_uninstall(pkg, config) != 0 {
			exit_code = 1
		}
	}

	return exit_code
}

// Remove orphan packages (xbps-remove -o)
remove_orphans :: proc(config: ^Config) -> int {
	cmd := make([dynamic]string, context.temp_allocator)

	// Need sudo for system operations (unless dry-run)
	if !config.dry_run {
		append(&cmd, "sudo")
	}
	append(&cmd, "xbps-remove", "-o")

	if config.dry_run {
		append(&cmd, "-n")
	}
	if config.yes {
		append(&cmd, "-y")
	}
	if config.verbose {
		append(&cmd, "-v")
	}
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}

	errors.log_info("Removing orphan packages...")
	return utils.run_command(cmd[:])
}

// Clean package cache (xbps-remove -O)
remove_cache :: proc(config: ^Config) -> int {
	cmd := make([dynamic]string, context.temp_allocator)

	// Need sudo for cache operations (unless dry-run)
	if !config.dry_run {
		append(&cmd, "sudo")
	}
	append(&cmd, "xbps-remove", "-O")

	if config.dry_run {
		append(&cmd, "-n")
	}
	if config.yes {
		append(&cmd, "-y")
	}
	if config.verbose {
		append(&cmd, "-v")
	}
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}

	errors.log_info("Cleaning package cache...")
	return utils.run_command(cmd[:])
}

// Remove a package using xbps-remove
xbps_uninstall :: proc(pkg_name: string, config: ^Config) -> int {
	if len(pkg_name) == 0 {
		errors.log_error("Invalid package name")
		return -1
	}

	errors.log_info("Removing %s...", pkg_name)

	cmd := make([dynamic]string, context.temp_allocator)

	// Need sudo for package removal (unless dry-run)
	if !config.dry_run {
		append(&cmd, "sudo")
	}
	append(&cmd, "xbps-remove", pkg_name)

	if config.dry_run {
		append(&cmd, "-n")
	}
	if config.yes {
		append(&cmd, "-y")
	}
	if config.recursive {
		append(&cmd, "-R")
	}
	if config.verbose {
		append(&cmd, "-v")
	}
	if len(config.rootdir) > 0 {
		append(&cmd, "-r", config.rootdir)
	}

	if utils.run_command(cmd[:]) == 0 {
		errors.log_info("Successfully removed %s", pkg_name)
		return 0
	}

	errors.log_error("xbps-remove failed for %s", pkg_name)
	return -1
}
