package commands

import "core:fmt"
import "core:strings"

import errors "../core/errors"
import xbps "../core/xbps"
import utils "../utils"

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

	cmd: [dynamic; 64]string

	if !config.dry_run {
		append(&cmd, "sudo")
	}
	append(&cmd, "xbps-remove")

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

	for pkg in args {
		append(&cmd, pkg)
	}

	errors.log_info("Removing %s...", strings.join(args[:], ", ", context.temp_allocator))

	if utils.run_command(cmd[:]) == 0 {
		errors.log_info("Successfully removed package(s)")
		return 0
	}

	errors.log_error("xbps-remove failed")
	return 1
}

// Remove orphan packages (xbps-remove -o)
remove_orphans :: proc(config: ^Config) -> int {
	cmd: [dynamic; 16]string

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
	return xbps.remove_orphans(config.yes, utils.run_command)
}

// Clean package cache (xbps-remove -O)
remove_cache :: proc(config: ^Config) -> int {
	cmd: [dynamic; 16]string

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
	return xbps.clean_cache(utils.run_command)
}
