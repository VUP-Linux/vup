package commands

import index "../core/index"
import utils "../utils"

// Sync command implementation
sync_run :: proc(args: []string, config: ^Config) -> int {
	// Force sync
	_, ok := index.index_load_or_fetch(config.index_url, true)
	if !ok {
		utils.log_error("Failed to sync package index")
		return 1
	}
	utils.log_info("Package index synchronized")
	return 0
}
