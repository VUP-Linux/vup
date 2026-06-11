package commands

import "core:fmt"
import "core:strings"

import builder "../core/builder"
import errors "../core/errors"
import index "../core/index"
import resolve "../core/resolve"
import transaction "../core/transaction"
import xbps "../core/xbps"
import utils "../utils"

// Install command implementation
install_run :: proc(args: []string, config: ^Config) -> int {
	// Sync repos if -S flag
	if config.sync {
		errors.log_info("Syncing repository index...")
		if xbps.sync_repos(utils.run_command) != 0 {
			errors.log_error("Failed to sync repositories")
			return 1
		}
	}

	// Update mode: -u (system upgrade)
	if config.update_system {
		return install_update(config)
	}

	if len(args) == 0 {
		fmt.println("Usage: vuru install <package> [packages...]")
		fmt.println("       vuru install -S       (sync repos)")
		fmt.println("       vuru install -Su      (full system update)")
		return 1
	}

	// Load index
	idx, ok := index.index_load_or_fetch(config.index_url, false)
	if !ok {
		errors.log_error("Failed to load package index")
		return 1
	}

	// Resolve dependencies for all packages at once
	res, res_ok := resolve.resolve_deps(args, &idx, config.force_build)
	if !res_ok {
		if len(res.errors) > 0 {
			for err in res.errors {
				errors.print_error(err)
			}
		} else {
			errors.log_error("Failed to resolve dependencies")
		}
		return 1
	}

	// Check for missing packages
	if len(res.missing) > 0 {
		if len(res.errors) > 0 {
			for err in res.errors {
				errors.print_error(err)
			}
		} else {
			errors.log_error(
				"Cannot resolve: %s",
				strings.join(res.missing[:], ", ", context.temp_allocator),
			)
		}
		return 1
	}

	// Dry run - just show what would happen
	if config.dry_run {
		resolve.resolution_print(&res)
		return 0
	}

	// Create transaction
	tx := transaction.transaction_from_resolution(&res)

	transaction.transaction_print(&tx)

	// Confirm unless -y
	if !config.yes && !transaction.transaction_confirm(&tx) {
		errors.log_info("Installation cancelled")
		return 0
	}

	// Get build config if needed
	build_cfg: builder.Build_Config
	has_build := false
	for item in tx.items {
		if item.op == .Build_Install {
			has_build = true
			break
		}
	}

	if has_build {
		cfg_result, cfg_ok := builder.default_build_config()
		if !cfg_ok {
			errors.log_error("VUP repository not found. Run 'vuru clone' first.")
			return 1
		}
		build_cfg = cfg_result
	}

	// Execute
	if !transaction.transaction_execute(&tx, &build_cfg, config.yes) {
		return 1
	}

	return 0
}

// System upgrade (xbps-install -u)
install_update :: proc(config: ^Config) -> int {
	cmd: [dynamic; 16]string
	append(&cmd, "sudo", "xbps-install", "-u")

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

	errors.log_info("Updating system packages...")
	sys_ret := utils.run_command(cmd[:])

	if sys_ret != 0 {
		return sys_ret
	}

	// Also update VUP packages
	return update_run(nil, config)
}
