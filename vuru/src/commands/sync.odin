package commands

import errors "../core/errors"
import index "../core/index"

// Sync command implementation
sync_run :: proc(args: []string, config: ^Config) -> int {
	// Force sync
	_, ok := index.index_load_or_fetch(config.index_url, true)
	if !ok {
		errors.log_error("Failed to sync package index")
		return 1
	}
	errors.log_info("Package index synchronized")
	return 0
}
