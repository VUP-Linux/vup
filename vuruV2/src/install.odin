package main

import "xbps"

// Run xbps-install with the given repository and package
run_xbps_install :: proc(repo_url: string, pkg_name: string, yes: bool) -> int {
	return xbps.install_from_repo(repo_url, pkg_name, yes, run_command)
}

// Install a package from VUP repository
xbps_install_pkg :: proc(idx: ^Index, pkg_name: string, yes: bool) -> int {
	pkg, ok := index_get_package(idx, pkg_name)
	if !ok {
		log_error("Package '%s' not found in VUP index", pkg_name)
		return -1
	}

	if len(pkg.category) == 0 || len(pkg.repo_urls) == 0 {
		log_error("Invalid package metadata for '%s'", pkg_name)
		return -1
	}

	// Get architecture-specific repo URL
	arch, arch_ok := get_arch()
	defer delete(arch)

	if !arch_ok {
		log_error("Failed to detect system architecture")
		return -1
	}

	url, url_ok := pkg.repo_urls[arch]
	if !url_ok {
		log_error("Package '%s' is not available for architecture '%s'", pkg_name, arch)
		return -1
	}

	log_info("Found %s in category '%s' for %s", pkg_name, pkg.category, arch)

	// Fetch template for review
	log_info("Fetching template for review...")
	new_tmpl, tmpl_ok := fetch_template(pkg.category, pkg_name)
	defer delete(new_tmpl)

	if !tmpl_ok {
		log_error("Failed to fetch template")
		return -1
	}

	cached_tmpl, cached_ok := cache_get_template(pkg_name)
	defer if cached_ok {delete(cached_tmpl)}

	// Review unless --yes flag
	if !yes {
		prev := cached_tmpl if cached_ok else ""
		if !review_changes(pkg_name, new_tmpl, prev) {
			log_info("Installation aborted by user")
			return 0 // User cancelled, not an error
		}
	}

	// Cache the template for future comparisons
	if !cache_save_template(pkg_name, new_tmpl) {
		log_error("Warning: Failed to cache template")
		// Continue anyway
	}

	log_info("Installing from: %s", url)

	if run_xbps_install(url, pkg_name, yes) != 0 {
		log_error("xbps-install failed for %s", pkg_name)
		return -1
	}

	log_info("Successfully installed %s", pkg_name)
	return 0
}
