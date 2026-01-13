package main

import "core:fmt"
import "core:os"
import "core:strings"
import "xbps"

MAX_UPGRADES :: 64

Upgrade_Info :: struct {
	name:            string,
	installed_ver:   string,
	new_ver:         string,
	repo_url:        string,
	category:        string,
	new_template:    string,
	cached_template: string,
}

// Compare versions using xbps-uhelper
version_gt :: proc(v1: string, v2: string) -> bool {
	return xbps.version_greater_than(v1, v2, run_command)
}

// Get the currently installed version of a package
get_installed_version :: proc(pkg_name: string, allocator := context.allocator) -> (string, bool) {
	return xbps.get_installed_version(pkg_name, run_command_output, allocator)
}

// Run xbps-install for upgrade
run_xbps_upgrade :: proc(repo_url: string, pkg_name: string, yes: bool) -> int {
	return xbps.upgrade_from_repo(repo_url, pkg_name, yes, run_command)
}

// Parse installed package line from xbps-query -l
parse_installed_pkg :: proc(line: string) -> (name: string, version: string, ok: bool) {
	parts := strings.fields(line, context.temp_allocator)
	if len(parts) < 2 {
		return "", "", false
	}

	return xbps.parse_pkgver(parts[1])
}

// Show batched diffs in less pager
show_batch_review :: proc(upgrades: []Upgrade_Info) -> bool {
	builder := strings.builder_make(context.temp_allocator)

	strings.write_string(&builder, "VUP Package Upgrade Review\n")
	strings.write_string(&builder, "==========================\n\n")
	fmt.sbprintf(&builder, "%d package(s) to upgrade:\n\n", len(upgrades))

	for u, i in upgrades {
		fmt.sbprintf(&builder, "  [%d] %s: %s -> %s\n", i + 1, u.name, u.installed_ver, u.new_ver)
	}
	strings.write_string(&builder, "\n")

	for u, i in upgrades {
		strings.write_string(
			&builder,
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n",
		)
		fmt.sbprintf(
			&builder,
			"[%d/%d] %s: %s -> %s\n",
			i + 1,
			len(upgrades),
			u.name,
			u.installed_ver,
			u.new_ver,
		)
		strings.write_string(
			&builder,
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n",
		)

		if len(u.cached_template) > 0 {
			diff, diff_ok := diff_generate(
				u.cached_template,
				u.new_template,
				context.temp_allocator,
			)
			if diff_ok && len(diff) > 0 {
				strings.write_string(&builder, diff)
				strings.write_string(&builder, "\n")
			}
		} else {
			strings.write_string(&builder, "(New package - showing full template)\n\n")
			strings.write_string(&builder, u.new_template)
			strings.write_string(&builder, "\n")
		}
		strings.write_string(&builder, "\n")
	}

	content := strings.to_string(builder)
	review_path, path_ok := diff_write_temp_file(content, context.temp_allocator)
	if !path_ok {
		log_error("Failed to create review file")
		return false
	}
	defer os.remove(review_path)

	// Show in less
	diff_show_pager(review_path)

	// Prompt for confirmation
	fmt.printf("Proceed with %d upgrade(s)? [Y/n] ", len(upgrades))

	buf: [100]u8
	n, _ := os.read(os.stdin, buf[:])

	if n <= 0 {
		return false
	}

	input := strings.trim_space(string(buf[:n]))
	input_lower := strings.to_lower(input, context.temp_allocator)

	return len(input) == 0 || input_lower == "y" || input_lower == "yes"
}

// Upgrade all VUP packages
xbps_upgrade_all :: proc(idx: ^Index, yes: bool) -> int {
	log_info("Checking for VUP package updates...")

	output, ok := run_command_output({"xbps-query", "-l"})
	if !ok {
		log_error("Failed to run xbps-query")
		return -1
	}
	defer delete(output)

	upgrades: [dynamic]Upgrade_Info
	defer {
		for u in upgrades {
			delete(u.new_template)
			delete(u.cached_template)
		}
		delete(upgrades)
	}

	// Phase 1: Collect packages needing upgrade
	lines := output
	for line in strings.split_lines_iterator(&lines) {
		if len(upgrades) >= MAX_UPGRADES {
			break
		}

		name, installed_ver, parse_ok := parse_installed_pkg(line)
		if !parse_ok {continue}

		pkg, pkg_ok := index_get_package(idx, name)
		if !pkg_ok {continue}

		if len(pkg.version) == 0 || len(pkg.repo_urls) == 0 || len(pkg.category) == 0 {
			continue
		}

		// Get architecture-specific repo URL
		arch, arch_ok := get_arch()
		if !arch_ok {continue}
		defer delete(arch)

		repo_url, url_ok := pkg.repo_urls[arch]
		if !url_ok {continue}

		if version_gt(pkg.version, installed_ver) {
			append(
				&upgrades,
				Upgrade_Info {
					name = strings.clone(name),
					installed_ver = strings.clone(installed_ver),
					new_ver = strings.clone(pkg.version),
					repo_url = strings.clone(repo_url),
					category = strings.clone(pkg.category),
				},
			)
		}
	}

	if len(upgrades) == 0 {
		log_info("All VUP packages are up to date")
		return 0
	}

	// Print summary
	fmt.println()
	fmt.printf("%d package(s) to upgrade:\n", len(upgrades))
	for u in upgrades {
		fmt.printf("  %s: %s -> %s\n", u.name, u.installed_ver, u.new_ver)
	}
	fmt.println()

	// Phase 2: Fetch templates (unless --yes)
	if !yes {
		log_info("Fetching templates for review...")

		for &u in upgrades {
			new_tmpl, tmpl_ok := fetch_template(u.category, u.name)
			if !tmpl_ok {
				log_error("Failed to fetch template for %s", u.name)
				return -1
			}
			u.new_template = new_tmpl

			cached, cached_ok := cache_get_template(u.name)
			u.cached_template = cached if cached_ok else ""
		}

		// Phase 3: Show batch review
		if !show_batch_review(upgrades[:]) {
			log_info("Upgrade cancelled by user")
			return 0
		}
	}

	// Phase 4: Perform upgrades
	upgraded := 0
	errors := 0

	for u in upgrades {
		log_info("Upgrading %s...", u.name)

		if run_xbps_upgrade(u.repo_url, u.name, yes) != 0 {
			log_error("Failed to upgrade %s", u.name)
			errors += 1
		} else {
			// Verify upgrade happened
			new_ver, ver_ok := get_installed_version(u.name, context.temp_allocator)
			if ver_ok && new_ver != u.installed_ver {
				upgraded += 1
				// Update template cache
				if len(u.new_template) > 0 {
					cache_save_template(u.name, u.new_template)
				}
			}
		}
	}

	if upgraded > 0 {
		log_info("Upgraded %d package(s)", upgraded)
	} else if errors == 0 {
		log_info("All VUP packages are up to date")
	}

	return -1 if errors > 0 else 0
}
