package transaction

import "core:fmt"
import "core:os"
import "core:strings"

import builder "../../core/builder"
import errors "../../core/errors"
import resolve "../../core/resolve"
import xbps "../../core/xbps"
import utils "../../utils"

// Create a transaction from resolution result
transaction_from_resolution :: proc(
	res: ^resolve.Resolution,
	allocator := context.allocator,
) -> Transaction {
	tx := transaction_make(allocator)

	// Add packages to install (binary)
	for pkg in res.to_install {
		item := Transaction_Item {
			name        = strings.clone(pkg.name, allocator),
			new_version = strings.clone(pkg.version, allocator),
			reason      = strings.clone(pkg.depth == 0 ? "explicit" : "dependency", allocator),
		}

		if pkg.source == .VUP {
			item.op = .Install_VUP
			item.repo_url = strings.clone(pkg.repo_url, allocator)
			item.category = strings.clone(pkg.category, allocator)
		} else {
			item.op = .Install_Official
		}

		append(&tx.items, item)
	}

	// Add packages to build from source
	for pkg in res.to_build {
		append(&tx.items, Transaction_Item {
			op          = .Build_Install,
			name        = strings.clone(pkg.name, allocator),
			new_version = strings.clone(pkg.version, allocator),
			category    = strings.clone(pkg.category, allocator),
			reason      = strings.clone(pkg.depth == 0 ? "explicit" : "dependency", allocator),
		})
	}

	return tx
}

// Print transaction summary
transaction_print :: proc(t: ^Transaction) {
	if transaction_is_empty(t) {
		fmt.println("Nothing to do.")
		return
	}

	counts := transaction_count_by_op(t)

	fmt.println()
	fmt.println("Transaction Summary")
	fmt.println("===================")

	if counts.install_official > 0 {
		fmt.printf("\nInstall from official repos (%d):\n", counts.install_official)
		for item in t.items {
			if item.op == .Install_Official {
				fmt.printf("  %s-%s\n", item.name, item.new_version)
			}
		}
	}

	if counts.install_vup > 0 {
		fmt.printf("\nInstall from VUP (%d):\n", counts.install_vup)
		for item in t.items {
			if item.op == .Install_VUP {
				fmt.printf("  %s-%s [%s]\n", item.name, item.new_version, item.category)
			}
		}
	}

	if counts.build > 0 {
		fmt.printf("\nBuild from source (%d):\n", counts.build)
		for item in t.items {
			if item.op == .Build_Install {
				fmt.printf("  %s-%s\n", item.name, item.new_version)
			}
		}
	}

	if counts.remove > 0 {
		fmt.printf("\nRemove (%d):\n", counts.remove)
		for item in t.items {
			if item.op == .Remove {
				fmt.printf("  %s-%s\n", item.name, item.old_version)
			}
		}
	}

	fmt.println()
}

// Execute a transaction
transaction_execute :: proc(t: ^Transaction, cfg: ^builder.Build_Config, yes: bool) -> bool {
	if transaction_is_empty(t) {
		return true
	}

	// Group packages by operation type for batch execution
	VUP_Group :: struct {
		repo_url: string,
		pkgs:     [dynamic]string,
	}

	official_pkgs := make([dynamic]string, context.temp_allocator)
	vup_groups := make([dynamic]VUP_Group, context.temp_allocator)
	remove_pkgs := make([dynamic]string, context.temp_allocator)
	builds := make([dynamic]^Transaction_Item, context.temp_allocator)

	for &item in t.items {
		switch item.op {
		case .Install_Official:
			append(&official_pkgs, item.name)

		case .Install_VUP:
			found := false
			for &group in vup_groups {
				if group.repo_url == item.repo_url {
					append(&group.pkgs, item.name)
					found = true
					break
				}
			}
			if !found {
				append(&vup_groups, VUP_Group{
					repo_url = item.repo_url,
					pkgs     = make([dynamic]string, context.temp_allocator),
				})
				append(&vup_groups[len(vup_groups) - 1].pkgs, item.name)
			}

		case .Remove:
			append(&remove_pkgs, item.name)

		case .Build_Install:
			append(&builds, &item)

		case .Upgrade:
		}
	}

	// Execute official installs in one batch
	if len(official_pkgs) > 0 {
		errors.log_info("Installing %d package(s) from official repos...", len(official_pkgs))

		args: [dynamic; 64]string
		append(&args, "sudo", "xbps-install", "-S")
		if yes {
			append(&args, "-y")
		}
		for pkg in official_pkgs {
			append(&args, pkg)
		}

		if utils.run_command(args[:]) != 0 {
			errors.log_error("Failed to install official packages")
			return false
		}
	}

	// Execute VUP installs grouped by repo
	for group in vup_groups {
		errors.log_info("Installing %d package(s) from VUP...", len(group.pkgs))

		if xbps.install_packages_from_repo(group.repo_url, group.pkgs[:], yes, utils.run_command) != 0 {
			errors.log_error("Failed to install VUP packages")
			return false
		}
	}

	// Execute removes in one batch
	if len(remove_pkgs) > 0 {
		errors.log_info("Removing %d package(s)...", len(remove_pkgs))

		args: [dynamic; 64]string
		append(&args, "sudo", "xbps-remove", "-R")
		if yes {
			append(&args, "-y")
		}
		for pkg in remove_pkgs {
			append(&args, pkg)
		}

		if utils.run_command(args[:]) != 0 {
			errors.log_error("Failed to remove packages")
			return false
		}
	}

	// Execute builds individually
	for item in builds {
		if !execute_build_install(item, cfg, yes) {
			return false
		}
	}

	return true
}

@(private)
execute_build_install :: proc(item: ^Transaction_Item, cfg: ^builder.Build_Config, yes: bool) -> bool {
	errors.log_info("Building %s...", item.name)
	
	if !builder.build_package(cfg, item.name, item.category) {
		errors.log_error("Failed to build %s", item.name)
		return false
	}
	
	if !builder.install_local_package(cfg, item.name, yes) {
		errors.log_error("Failed to install built package %s", item.name)
		return false
	}
	return true
}

// Confirm transaction with user
transaction_confirm :: proc(t: ^Transaction) -> bool {
	if transaction_is_empty(t) {
		return true
	}

	fmt.print("Proceed? [Y/n] ")

	buf: [100]u8
	n, _ := os.read(os.stdin, buf[:])

	if n <= 0 {
		return false
	}

	input := strings.trim_space(string(buf[:n]))
	input_lower := strings.to_lower(input, context.temp_allocator)

	return len(input) == 0 || input_lower == "y" || input_lower == "yes"
}
