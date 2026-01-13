package commands

import utils "../utils"
import "core:fmt"

// Fetch command - wrapper around xbps-fetch
fetch_run :: proc(args: []string, config: ^Config) -> int {
	if len(args) == 0 {
		fmt.println("Usage: vuru fetch <url> [urls...]")
		fmt.println("  -v, --verbose   Verbose output")
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
