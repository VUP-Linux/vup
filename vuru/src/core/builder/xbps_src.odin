package builder

import "core:fmt"
import "core:os"
import "core:strings"

import errors "../../core/errors"
import index "../../core/index"
import template "../../core/template"
import utils "../../utils"

// xbps-src wrapper that intercepts builds and installs VUP dependencies first
// Usage: vuru src <xbps-src-command> [args...]
// Examples:
//   vuru src pkg mypackage
//   vuru src fetch mypackage
//   vuru src configure mypackage

// Config for the src command
Config :: struct {
	index_url: string,
	repo_url:  string,
}

// Commands that operate on a package template and need dependency resolution
PACKAGE_COMMANDS :: []string{"build", "check", "configure", "extract", "fetch", "install", "pkg"}

is_package_command :: proc(cmd: string) -> bool {
	for c in PACKAGE_COMMANDS {
		if c == cmd {
			return true
		}
	}
	return false
}

// Find xbps-src in current directory or parent directories
find_xbps_src :: proc() -> (string, bool) {
	// Check current directory first
	if os.exists("./xbps-src") {
		return "./xbps-src", true
	}

	// Check parent directory (in case we're in srcpkgs/ or similar)
	if os.exists("../xbps-src") {
		return "../xbps-src", true
	}

	return "", false
}

// Get the srcpkgs directory relative to xbps-src location
get_srcpkgs_dir :: proc(xbps_src_path: string, allocator := context.allocator) -> string {
	// xbps-src is at void-packages/xbps-src
	// srcpkgs is at void-packages/srcpkgs
	if strings.has_suffix(xbps_src_path, "/xbps-src") {
		base := xbps_src_path[:len(xbps_src_path) - len("/xbps-src")]
		return strings.concatenate({base, "/srcpkgs"}, allocator)
	}
	if xbps_src_path == "./xbps-src" {
		return strings.clone("./srcpkgs", allocator)
	}
	if xbps_src_path == "../xbps-src" {
		return strings.clone("../srcpkgs", allocator)
	}
	return strings.clone("srcpkgs", allocator)
}

// Get hostdir/binpkgs path relative to xbps-src
get_binpkgs_dir :: proc(xbps_src_path: string, allocator := context.allocator) -> string {
	if strings.has_suffix(xbps_src_path, "/xbps-src") {
		base := xbps_src_path[:len(xbps_src_path) - len("/xbps-src")]
		return strings.concatenate({base, "/hostdir/binpkgs"}, allocator)
	}
	if xbps_src_path == "./xbps-src" {
		return strings.clone("./hostdir/binpkgs", allocator)
	}
	if xbps_src_path == "../xbps-src" {
		return strings.clone("../hostdir/binpkgs", allocator)
	}
	return strings.clone("hostdir/binpkgs", allocator)
}

// Download VUP package to hostdir/binpkgs for xbps-src to find
download_vup_pkg_to_binpkgs :: proc(
	idx: ^index.Index,
	pkg_name: string,
	binpkgs_dir: string,
) -> (
	bool,
	errors.Error,
) {
	pkg, ok := index.index_get_package(idx, pkg_name)
	if !ok {
		return false, errors.make_error(.Package_Not_Found, pkg_name)
	}

	// Get architecture
	arch, arch_ok := utils.get_arch()
	defer delete(arch)
	if !arch_ok {
		return false, errors.make_error(.Arch_Detection_Failed)
	}

	// Get repo URL for this arch
	repo_url, url_ok := pkg.repo_urls[arch]
	if !url_ok {
		return false, errors.make_error(
			.Arch_Not_Supported,
			fmt.tprintf("%s for %s", pkg_name, arch),
		)
	}

	// Build the .xbps filename (pkgname-version.arch.xbps)
	// e.g. vlang-0.4.11_1.x86_64.xbps
	xbps_filename := fmt.tprintf("%s-%s.%s.xbps", pkg_name, pkg.version, arch)

	// Full URL to the .xbps file
	full_url := fmt.tprintf("%s/%s", repo_url, xbps_filename)

	// Destination path
	dest_path := utils.path_join(binpkgs_dir, xbps_filename, allocator = context.temp_allocator)

	// Check if already exists
	if os.exists(dest_path) {
		errors.log_info("%s already in binpkgs", pkg_name)
		return true, {}
	}

	// Create binpkgs dir if needed
	if !utils.mkdir_p(binpkgs_dir) {
		return false, errors.make_error(.Cache_Dir_Failed, binpkgs_dir)
	}

	// Download the package
	errors.log_info("Downloading %s to hostdir/binpkgs...", pkg_name)

	// Use curl to download (-L to follow redirects)
	curl_args := []string{"curl", "-fsSL", "-o", dest_path, full_url}
	if utils.run_command(curl_args) != 0 {
		return false, errors.make_error(
			.Download_Failed,
			fmt.tprintf("%s from %s", pkg_name, full_url),
		)
	}

	return true, {}
}

// Update the local repo index after adding packages
update_binpkgs_index :: proc(binpkgs_dir: string) -> (bool, errors.Error) {
	errors.log_info("Updating local repository index...")

	// xbps-rindex -a <path>/*.xbps doesn't work directly
	// Weneed to pass individual .xbps files or use a glob in shell
	// Better: use xbps-rindex -fa with glob

	pattern := fmt.tprintf("%s/*.xbps", binpkgs_dir)
	args := []string{"sh", "-c", fmt.tprintf("xbps-rindex -fa %s", pattern)}
	if utils.run_command(args) != 0 {
		return false, errors.make_error(.Command_Failed, "xbps-rindex -fa")
	}

	return true, {}
}

// Install VUP dependencies for a package before building
install_vup_deps_for_pkg :: proc(
	pkg_name: string,
	xbps_src_path: string,
	idx: ^index.Index,
) -> (
	bool,
	errors.Error,
) {
	srcpkgs := get_srcpkgs_dir(xbps_src_path, context.temp_allocator)

	template_path := utils.path_join(
		srcpkgs,
		pkg_name,
		"template",
		allocator = context.temp_allocator,
	)

	if !os.exists(template_path) {
		return false, errors.make_error(.Template_Not_Found, template_path)
	}

	// Parse the template
	tmpl, ok := template.template_parse_file(template_path)
	if !ok {
		errors.log_warning("Could not parse template for %s", pkg_name)
		return true, {} // Continue anyway, let xbps-src handle the error
	}
	defer template.template_free(&tmpl)

	// Collect all dependencies using a map to deduplicate
	all_deps: map[string]bool
	defer delete(all_deps)

	for dep in tmpl.depends {
		all_deps[dep] = true
	}
	for dep in tmpl.makedepends {
		all_deps[dep] = true
	}
	for dep in tmpl.hostmakedeps {
		all_deps[dep] = true
	}

	if len(all_deps) == 0 {
		errors.log_info("No dependencies in template")
		return true, {}
	}

	// Find VUP dependencies
	vup_deps: [dynamic]string
	defer delete(vup_deps)

	for dep in all_deps {
		// Check if it's in VUP index
		if dep in idx.packages {
			append(&vup_deps, dep)
		}
	}

	if len(vup_deps) == 0 {
		errors.log_info("No VUP dependencies found")
		return true, {}
	}

	fmt.printf(
		"\n%s:: VUP dependencies detected for '%s':%s\n",
		errors.COLOR_INFO,
		pkg_name,
		errors.COLOR_RESET,
	)
	for dep in vup_deps {
		pkg_info := idx.packages[dep]
		fmt.printf(
			"   %s%s%s (%s)\n",
			errors.COLOR_INFO,
			dep,
			errors.COLOR_RESET,
			pkg_info.version,
		)
	}
	fmt.println()

	// Download VUP deps to hostdir/binpkgs
	binpkgs := get_binpkgs_dir(xbps_src_path, context.temp_allocator)
	errors.log_info("Downloading VUP dependencies to %s...", binpkgs)

	for dep in vup_deps {
		dl_ok, dl_err := download_vup_pkg_to_binpkgs(idx, dep, binpkgs)
		if !dl_ok {
			return false, dl_err
		}
	}

	// Update the local repo index so xbps-src can find them
	idx_ok, idx_err := update_binpkgs_index(binpkgs)
	if !idx_ok {
		return false, idx_err
	}

	errors.log_info("VUP dependencies ready in hostdir/binpkgs")
	return true, {}
}

// Run xbps-src with the given arguments
run_xbps_src :: proc(xbps_src_path: string, args: []string) -> bool {
	// Build the command as string array
	cmd_args: [dynamic]string
	defer delete(cmd_args)

	append(&cmd_args, xbps_src_path)

	for arg in args {
		append(&cmd_args, arg)
	}

	// Execute xbps-src
	return utils.run_command(cmd_args[:]) == 0
}

// Extract package name from xbps-src arguments
// Returns the package name if found, empty string otherwise
extract_pkg_name :: proc(cmd: string, args: []string) -> string {
	// For most commands, the package name is the last non-flag argument
	// Skip flags like -a, -j, etc.

	skip_next := false
	for arg in args {
		if skip_next {
			skip_next = false
			continue
		}

		if strings.has_prefix(arg, "-") {
			// Flags that take a value
			if arg == "-a" || arg == "-j" || arg == "-o" || arg == "-C" || arg == "-r" {
				skip_next = true
			}
			continue
		}

		// This should be the package name
		return arg
	}

	return ""
}

// Supported cross-compilation targets for -a flag
CROSS_TARGETS :: []string {
	"aarch64-musl",
	"aarch64",
	"armv5te-musl",
	"armv5te",
	"armv5tel-musl",
	"armv5tel",
	"armv6hf-musl",
	"armv6hf",
	"armv6l-musl",
	"armv6l",
	"armv7hf-musl",
	"armv7hf",
	"armv7l-musl",
	"armv7l",
	"i686-musl",
	"i686",
	"mips-musl",
	"mipsel-musl",
	"mipselhf-musl",
	"mipshf-musl",
	"ppc-musl",
	"ppc",
	"ppc64-musl",
	"ppc64",
	"ppc64le-musl",
	"ppc64le",
	"ppcle-musl",
	"ppcle",
	"riscv64-musl",
	"riscv64",
	"x86_64-musl",
	"x86_64",
}

is_valid_cross_target :: proc(target: string) -> bool {
	for t in CROSS_TARGETS {
		if t == target {
			return true
		}
	}
	return false
}

// Parse top-level flags from args, returning the cross target (if any), remaining args, and success status
parse_top_level_flags :: proc(
	args: []string,
) -> (
	cross_target: string,
	cmd_args: []string,
	ok: bool,
) {
	i := 0
	target := ""

	// Parse leading flags before the command
	for i < len(args) {
		arg := args[i]

		if arg == "-a" {
			// Cross-compile flag
			if i + 1 >= len(args) {
				errors.log_error("Option -a requires a target architecture")
				return "", nil, false
			}
			target = args[i + 1]
			if !is_valid_cross_target(target) {
				errors.log_error("Invalid cross-compile target: %s", target)
				errors.log_info("Run 'vuru src' to see supported targets")
				return "", nil, false
			}
			i += 2
		} else if strings.has_prefix(arg, "-") {
			// Other top-level flags we might add later
			errors.log_error("Unknown option: %s", arg)
			return "", nil, false
		} else {
			// Found the command, return remaining args
			break
		}
	}

	return target, args[i:], true
}

// Main entry point for xbps-src wrapper
xbps_src_main :: proc(args: []string, config: ^Config) -> (bool, errors.Error) {
	if len(args) == 0 {
		xbps_src_usage()
		return false, {}
	}

	// Parse top-level flags like -a <target>
	cross_target, cmd_args, parse_ok := parse_top_level_flags(args)
	if !parse_ok {
		return false, {}
	}

	if len(cmd_args) == 0 {
		xbps_src_usage()
		return false, {}
	}

	cmd := cmd_args[0]
	remaining_args := cmd_args[1:] if len(cmd_args) > 1 else []string{}

	// Find xbps-src
	xbps_src_path, found := find_xbps_src()
	if !found {
		return false, errors.make_error(.Xbps_Src_Not_Found)
	}

	// If this is a package command, try to install VUP deps first
	if is_package_command(cmd) {
		pkg_name := extract_pkg_name(cmd, remaining_args)
		if pkg_name == "" {
			return false, errors.make_error(
				.Missing_Argument,
				fmt.tprintf("package name for '%s' command", cmd),
			)
		}

		errors.log_info("Checking VUP dependencies for '%s'...", pkg_name)

		// Load the index
		idx, idx_ok := index.index_load_or_fetch(config.index_url, false)
		if !idx_ok {
			errors.log_warning("Could not load VUP index, continuing without VUP dep resolution")
		} else {
			defer index.index_free(&idx)

			ok, err := install_vup_deps_for_pkg(pkg_name, xbps_src_path, &idx)
			if !ok {
				return false, err
			}
		}
	}

	// Build the full xbps-src args, including -a if specified
	xbps_args: [dynamic]string
	defer delete(xbps_args)

	if cross_target != "" {
		append(&xbps_args, "-a")
		append(&xbps_args, cross_target)
	}
	for arg in cmd_args {
		append(&xbps_args, arg)
	}

	// Run the actual xbps-src command
	joined_args := strings.join(xbps_args[:], " ", context.temp_allocator)
	errors.log_info("Running: xbps-src %s", joined_args)
	if !run_xbps_src(xbps_src_path, xbps_args[:]) {
		return false, errors.make_error(.Command_Failed, fmt.tprintf("xbps-src %s", joined_args))
	}
	return true, {}
}

xbps_src_usage :: proc() {
	fmt.println("Usage: vuru src [-a <target>] <command> [options] [package]")
	fmt.println()
	fmt.println("Wrapper for xbps-src that automatically installs VUP dependencies.")
	fmt.println("Run this from within a void-packages checkout.")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -a <target>  Cross compile packages for target architecture")
	fmt.println()
	fmt.println("Commands:")
	fmt.println("  pkg <pkgname>        Build binary package for <pkgname>")
	fmt.println("  fetch <pkgname>      Download source files for <pkgname>")
	fmt.println("  configure <pkgname>  Configure <pkgname>")
	fmt.println("  build <pkgname>      Build <pkgname>")
	fmt.println("  check <pkgname>      Run tests for <pkgname>")
	fmt.println("  install <pkgname>    Install <pkgname> into destdir")
	fmt.println("  clean <pkgname>      Clean up <pkgname> build directory")
	fmt.println("  show <pkgname>       Show info about <pkgname>")
	fmt.println("  ... and all other xbps-src commands")
	fmt.println()
	fmt.println("Supported cross-compile targets:")
	fmt.println("  aarch64-musl    aarch64       armv5te-musl   armv5te")
	fmt.println("  armv5tel-musl   armv5tel      armv6hf-musl   armv6hf")
	fmt.println("  armv6l-musl     armv6l        armv7hf-musl   armv7hf")
	fmt.println("  armv7l-musl     armv7l        i686-musl      i686")
	fmt.println("  mips-musl       mipsel-musl   mipselhf-musl  mipshf-musl")
	fmt.println("  ppc-musl        ppc           ppc64-musl     ppc64")
	fmt.println("  ppc64le-musl    ppc64le       ppcle-musl     ppcle")
	fmt.println("  riscv64-musl    riscv64       x86_64-musl    x86_64")
	fmt.println()
	fmt.println("Examples:")
	fmt.println("  # Build for native architecture:")
	fmt.println("  vuru src pkg antigravity")
	fmt.println()
	fmt.println("  # Cross-compile for ARM:")
	fmt.println("  vuru src -a armv7l pkg visual-studio-code")
	fmt.println()
	fmt.println("VUP dependencies are automatically installed before building.")
}
