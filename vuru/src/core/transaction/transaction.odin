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

	for &item in t.items {
		switch item.op {
		case .Install_Official:
			if !execute_install_official(&item, yes) {
				return false
			}

		case .Install_VUP:
			if !execute_install_vup(&item, yes) {
				return false
			}

		case .Build_Install:
			if !execute_build_install(&item, cfg, yes) {
				return false
			}

		case .Remove:
			if !execute_remove(&item, yes) {
				return false
			}

		case .Upgrade:
			// Handled by install with newer version
		}
	}

	return true
}

// Execute handlers for each operation type
@(private)
execute_install_official :: proc(item: ^Transaction_Item, yes: bool) -> bool {
	errors.log_info("Installing %s from official repos...", item.name)
	
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "sudo", "xbps-install", "-S")
	if yes {
		append(&args, "-y")
	}
	append(&args, item.name)

	if utils.run_command(args[:]) != 0 {
		errors.log_error("Failed to install %s", item.name)
		return false
	}
	return true
}

@(private)
execute_install_vup :: proc(item: ^Transaction_Item, yes: bool) -> bool {
	errors.log_info("Installing %s from VUP...", item.name)
	
	if xbps.install_from_repo(item.repo_url, item.name, yes, utils.run_command) != 0 {
		errors.log_error("Failed to install %s", item.name)
		return false
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

@(private)
execute_remove :: proc(item: ^Transaction_Item, yes: bool) -> bool {
	errors.log_info("Removing %s...", item.name)
	
	if xbps.remove_package(item.name, yes, utils.run_command) != 0 {
		errors.log_error("Failed to remove %s", item.name)
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
