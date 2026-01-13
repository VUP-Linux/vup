package main

import "xbps"

// Remove a package using xbps-remove
xbps_uninstall :: proc(pkg_name: string, yes: bool) -> int {
	if len(pkg_name) == 0 {
		log_error("Invalid package name")
		return -1
	}

	log_info("Removing %s...", pkg_name)

	if xbps.remove_package(pkg_name, yes, run_command) == 0 {
		log_info("Successfully removed %s", pkg_name)
		return 0
	}

	log_error("xbps-remove failed for %s", pkg_name)
	return -1
}
