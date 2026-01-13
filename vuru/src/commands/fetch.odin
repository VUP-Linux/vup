package commands

import utils "../utils"

// Fetch command - wrapper around xbps-fetch
fetch_run :: proc(args: []string, config: ^Config) -> int {
	if len(args) == 0 {
		utils.log_error("Usage: vuru fetch <url> [urls...]")
		utils.log_error("Options:")
		utils.log_error("  -v, --verbose   Verbose output")
		return 1
	}

	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "xbps-fetch")

	if config.verbose {
		append(&cmd, "-v")
	}

	for url in args {
		append(&cmd, url)
	}

	return utils.run_command(cmd[:])
}
