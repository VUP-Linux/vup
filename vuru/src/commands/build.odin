package commands

import builder "../core/builder"
import index "../core/index"
import utils "../utils"

// Build command implementation
build_run :: proc(args: []string, config: ^Config) -> int {
	if len(args) == 0 {
		utils.log_error("Usage: vuru build <package> [packages...]")
		return 1
	}

	// Load index
	idx, ok := index.index_load_or_fetch(config.index_url, false)
	if !ok {
		utils.log_error("Failed to load package index")
		return 1
	}
	defer index.index_free(&idx)

	cfg, cfg_ok := builder.default_build_config()
	if !cfg_ok {
		utils.log_error("VUP repository not found. Run 'vuru clone' first.")
		return 1
	}

	exit_code := 0

	for pkg_name in args {
		pkg, ok := index.index_get_package(&idx, pkg_name)
		if !ok {
			utils.log_error("Package '%s' not found in VUP index", pkg_name)
			exit_code = 1
			continue
		}

		if !builder.build_package(&cfg, pkg_name, pkg.category) {
			exit_code = 1
		} else {
			utils.log_info("Successfully built %s", pkg_name)

			// Show where the package is
			if path, path_ok := builder.get_built_package_path(
				&cfg,
				pkg_name,
				context.temp_allocator,
			); path_ok {
				utils.log_info("Package file: %s", path)
			}
		}
	}

	return exit_code
}
