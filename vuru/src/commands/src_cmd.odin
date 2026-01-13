package commands

import builder "../core/builder"
import errors "../core/errors"

// Src command implementation (wrapper for xbps-src)
src_run :: proc(args: []string, config: ^Config) -> int {
	// packages slice contains all args after 'src'
	if len(args) == 0 {
		builder.xbps_src_usage()
		return 1
	}

	// Build config for builder
	// Note: builder.Config is for xbps_src wrapper, distinct from commands.Config?
	// commands.Config has index_url. builder.Config has index_url, repo_url.

	src_cfg := builder.Config {
		index_url = config.index_url,
		repo_url  = "https://github.com/VUP-Linux/vup/releases/download", // TODO: Configurable?
	}

	ok, err := builder.xbps_src_main(args, &src_cfg)
	if !ok {
		if err.kind != nil {
			errors.print_error(err)
		}
		return 1
	}
	return 0
}
