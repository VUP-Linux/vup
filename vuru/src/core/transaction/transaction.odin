package transaction

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

import builder "../../core/builder"
import resolve "../../core/resolve"
import xbps "../../core/xbps"
import utils "../../utils"

// Transaction operation type
Transaction_Op :: enum {
	Install_Official, // Install from official Void repos
	Install_VUP, // Install from VUP binary repo
	Build_Install, // Build from source then install
	Remove, // Remove package
	Upgrade, // Upgrade package
}

// Single transaction item
Transaction_Item :: struct {
	op:          Transaction_Op,
	name:        string,
	old_version: string, // For upgrades
	new_version: string,
	repo_url:    string, // For VUP binary installs
	category:    string, // For VUP packages
	reason:      string, // "explicit" or "dependency"
}

// Complete transaction plan
Transaction :: struct {
	items:     [dynamic]Transaction_Item,
	allocator: mem.Allocator,
}

transaction_free :: proc(t: ^Transaction) {
	for item in t.items {
		delete(item.name, t.allocator)
		delete(item.old_version, t.allocator)
		delete(item.new_version, t.allocator)
		delete(item.repo_url, t.allocator)
		delete(item.category, t.allocator)
		delete(item.reason, t.allocator)
	}
	delete(t.items)
}

// Create a transaction from resolution
transaction_from_resolution :: proc(
	res: ^resolve.Resolution,
	allocator := context.allocator,
) -> Transaction {
	tx := Transaction {
		items     = make([dynamic]Transaction_Item, allocator),
		allocator = allocator,
	}

	// Add items in dependency order (deps first)
	// Sort by depth descending so deps come first
	for pkg in res.to_install {
		item := Transaction_Item {
			name        = strings.clone(pkg.name, allocator),
			new_version = strings.clone(pkg.version, allocator),
			reason      = "explicit" if pkg.depth == 0 else "dependency",
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

	for pkg in res.to_build {
		append(
			&tx.items,
			Transaction_Item {
				op = .Build_Install,
				name = strings.clone(pkg.name, allocator),
				new_version = strings.clone(pkg.version, allocator),
				category = strings.clone(pkg.category, allocator),
				reason = "explicit" if pkg.depth == 0 else "dependency",
			},
		)
	}

	return tx
}

// Print transaction summary
transaction_print :: proc(t: ^Transaction) {
	if len(t.items) == 0 {
		fmt.println("Nothing to do.")
		return
	}

	// Count by operation type
	install_official := 0
	install_vup := 0
	build := 0

	for item in t.items {
		switch item.op {
		case .Install_Official:
			install_official += 1
		case .Install_VUP:
			install_vup += 1
		case .Build_Install:
			build += 1
		case .Remove, .Upgrade:
		// Count if needed
		}
	}

	fmt.println()
	fmt.println("Transaction Summary")
	fmt.println("===================")

	if install_official > 0 {
		fmt.printf("\nInstall from official repos (%d):\n", install_official)
		for item in t.items {
			if item.op == .Install_Official {
				fmt.printf("  %s-%s\n", item.name, item.new_version)
			}
		}
	}

	if install_vup > 0 {
		fmt.printf("\nInstall from VUP (%d):\n", install_vup)
		for item in t.items {
			if item.op == .Install_VUP {
				fmt.printf("  %s-%s [%s]\n", item.name, item.new_version, item.category)
			}
		}
	}

	if build > 0 {
		fmt.printf("\nBuild from source (%d):\n", build)
		for item in t.items {
			if item.op == .Build_Install {
				fmt.printf("  %s-%s\n", item.name, item.new_version)
			}
		}
	}

	fmt.println()
}

// Execute a transaction
transaction_execute :: proc(t: ^Transaction, cfg: ^builder.Build_Config, yes: bool) -> bool {
	if len(t.items) == 0 {
		return true
	}

	// Execute in order
	for item in t.items {
		switch item.op {
		case .Install_Official:
			utils.log_info("Installing %s from official repos...", item.name)
			if utils.run_command(build_official_install_args(item.name, yes)[:]) != 0 {
				utils.log_error("Failed to install %s", item.name)
				return false
			}

		case .Install_VUP:
			utils.log_info("Installing %s from VUP...", item.name)
			if xbps.install_from_repo(item.repo_url, item.name, yes, utils.run_command) != 0 {
				utils.log_error("Failed to install %s", item.name)
				return false
			}

		case .Build_Install:
			utils.log_info("Building %s...", item.name)
			if !builder.build_package(cfg, item.name, item.category) {
				utils.log_error("Failed to build %s", item.name)
				return false
			}
			if !builder.install_local_package(cfg, item.name, yes) {
				utils.log_error("Failed to install built package %s", item.name)
				return false
			}

		case .Remove:
			utils.log_info("Removing %s...", item.name)
			if xbps.remove_package(item.name, yes, utils.run_command) != 0 {
				utils.log_error("Failed to remove %s", item.name)
				return false
			}

		case .Upgrade:
		// Handled by install with newer version
		}
	}

	return true
}

// Build args for official repo install
build_official_install_args :: proc(
	pkg_name: string,
	yes: bool,
	allocator := context.allocator,
) -> [dynamic]string {
	args := make([dynamic]string, allocator)
	append(&args, "sudo", "xbps-install", "-S")

	if yes {
		append(&args, "-y")
	}
	append(&args, pkg_name)

	return args
}

// Confirm transaction with user
transaction_confirm :: proc(t: ^Transaction) -> bool {
	if len(t.items) == 0 {
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
