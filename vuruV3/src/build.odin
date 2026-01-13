package main

import "core:fmt"
import "core:os"
import "core:strings"

// Configuration for the build system
Build_Config :: struct {
	vup_dir:       string, // Path to VUP repository clone
	masterdir:     string, // xbps-src masterdir
	hostdir:       string, // xbps-src hostdir
	clean_after:   bool,   // Clean build dir after successful build
}

// Default build configuration
default_build_config :: proc(allocator := context.allocator) -> (Build_Config, bool) {
	// Try to find VUP directory
	home := os.get_env("HOME", context.temp_allocator)
	if len(home) == 0 {
		return {}, false
	}

	// Check common locations
	candidates := []string{
		path_join(home, ".local/share/vup", allocator = context.temp_allocator),
		path_join(home, "vup", allocator = context.temp_allocator),
		"/opt/vup",
	}

	for path in candidates {
		xbps_src := path_join(path, "xbps-src", allocator = context.temp_allocator)
		if os.exists(xbps_src) {
			return Build_Config{
				vup_dir = strings.clone(path, allocator),
				masterdir = path_join(path, "masterdir", allocator = allocator),
				hostdir = path_join(path, "hostdir", allocator = allocator),
				clean_after = true,
			}, true
		}
	}

	return {}, false
}

// Clone or update VUP repository
vup_clone_or_update :: proc(target_dir: string) -> bool {
	VUP_REPO :: "https://github.com/VUP-Linux/vup.git"

	if os.exists(path_join(target_dir, ".git", allocator = context.temp_allocator)) {
		// Update existing
		log_info("Updating VUP repository...")
		return run_command({"git", "-C", target_dir, "pull", "--ff-only"}) == 0
	}

	// Clone fresh
	log_info("Cloning VUP repository...")
	return run_command({"git", "clone", "--depth=1", VUP_REPO, target_dir}) == 0
}

// Initialize xbps-src masterdir if needed
xbps_src_bootstrap :: proc(cfg: ^Build_Config) -> bool {
	masterdir := path_join(cfg.vup_dir, "masterdir", allocator = context.temp_allocator)

	if os.exists(masterdir) {
		return true
	}

	log_info("Bootstrapping xbps-src (this may take a while)...")

	xbps_src := path_join(cfg.vup_dir, "xbps-src", allocator = context.temp_allocator)
	return run_command({xbps_src, "binary-bootstrap"}) == 0
}

// Build a package using xbps-src
build_package :: proc(cfg: ^Build_Config, pkg_name: string, category: string) -> bool {
	if !is_valid_identifier(pkg_name) || !is_valid_identifier(category) {
		log_error("Invalid package name or category")
		return false
	}

	xbps_src := path_join(cfg.vup_dir, "xbps-src", allocator = context.temp_allocator)

	// Ensure template exists
	template_path := path_join(
		cfg.vup_dir,
		"srcpkgs",
		category,
		pkg_name,
		"template",
		allocator = context.temp_allocator,
	)

	if !os.exists(template_path) {
		log_error("Template not found: %s", template_path)
		return false
	}

	log_info("Building %s...", pkg_name)

	// Run xbps-src pkg <pkgname>
	// Note: xbps-src expects to be run from its directory
	result := run_command({
		"sh", "-c",
		fmt.tprintf("cd %s && ./xbps-src pkg %s/%s", cfg.vup_dir, category, pkg_name),
	})

	if result != 0 {
		log_error("Build failed for %s", pkg_name)
		return false
	}

	if cfg.clean_after {
		run_command({xbps_src, "clean", pkg_name})
	}

	return true
}

// Install a locally built package
install_local_package :: proc(cfg: ^Build_Config, pkg_name: string, yes: bool) -> bool {
	// Find the built package in hostdir/binpkgs
	binpkgs := path_join(cfg.vup_dir, "hostdir/binpkgs", allocator = context.temp_allocator)

	arch, ok := get_arch()
	if !ok {
		return false
	}
	defer delete(arch)

	// xbps-install from local repository
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "sudo", "xbps-install", "-R", binpkgs)

	if yes {
		append(&args, "-y")
	}
	append(&args, pkg_name)

	return run_command(args[:]) == 0
}

// Get the output package path after build
get_built_package_path :: proc(
	cfg: ^Build_Config,
	pkg_name: string,
	allocator := context.allocator,
) -> (string, bool) {
	binpkgs := path_join(cfg.vup_dir, "hostdir/binpkgs", allocator = context.temp_allocator)

	arch, ok := get_arch()
	if !ok {
		return "", false
	}
	defer delete(arch)

	// Check for package file
	// Format: pkgname-version_revision.arch.xbps
	output, cmd_ok := run_command_output(
		{"find", binpkgs, "-name", fmt.tprintf("%s-*.%s.xbps", pkg_name, arch), "-type", "f"},
		context.temp_allocator,
	)

	if !cmd_ok || len(output) == 0 {
		return "", false
	}

	// Get first result
	first_line := strings.split_lines(output, context.temp_allocator)[0]
	return strings.clone(strings.trim_space(first_line), allocator), true
}

// Show xbps-src build log
show_build_log :: proc(cfg: ^Build_Config, pkg_name: string) {
	log_path := path_join(
		cfg.vup_dir,
		"masterdir/builddir",
		fmt.tprintf("%s.log", pkg_name),
		allocator = context.temp_allocator,
	)

	if os.exists(log_path) {
		run_command({"less", "+G", log_path})
	} else {
		log_error("Build log not found")
	}
}
