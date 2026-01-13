package commands

import "core:os"

import builder "../core/builder"
import errors "../core/errors"
import utils "../utils"

// Clone command implementation
clone_run :: proc(args: []string, config: ^Config) -> int {
	home := os.get_env("HOME", context.temp_allocator)
	if len(home) == 0 {
		errors.log_error("HOME not set")
		return 1
	}

	target := utils.path_join(home, ".local/share/vup", allocator = context.temp_allocator)

	if !utils.mkdir_p(utils.path_join(home, ".local/share", allocator = context.temp_allocator)) {
		errors.log_error("Failed to create directory")
		return 1
	}

	if builder.vup_clone_or_update(target) {
		errors.log_info("VUP repository ready at %s", target)
		return 0
	}

	errors.log_error("Failed to clone/update VUP repository")
	return 1
}
