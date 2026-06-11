package commands

import "core:mem"

// Free owned resources in Config
config_free :: proc(c: ^Config) {
	if c.allocator.procedure == nil {
		return
	}

	if len(c.index_url) > 0 {
		delete(c.index_url, c.allocator)
	}
	if len(c.vup_dir) > 0 {
		delete(c.vup_dir, c.allocator)
	}
	if len(c.arch) > 0 {
		delete(c.arch, c.allocator)
	}
	if len(c.rootdir) > 0 {
		delete(c.rootdir, c.allocator)
	}
}
