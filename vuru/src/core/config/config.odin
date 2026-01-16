package config

import "core:os"
import "core:strings"
import "core:sys/linux"

// Get the current system architecture name
get_arch :: proc() -> (string, bool) {
	uts: linux.UTS_Name
	if linux.uname(&uts) != nil {
		return "", false
	}

	machine_name := string(cstring(&uts.machine[0]))
	machine := strings.trim_space(machine_name)

	arch: string
	switch machine {
	case "x86_64":
		arch = "x86_64"
	case "aarch64":
		arch = "aarch64"
	case "armv7l":
		arch = "armv7l"
	case "i686", "i386":
		arch = "i686"
	case:
		arch = "x86_64"
		if machine != "" do arch = machine
	}

	return strings.clone(arch), true
}

// Get cache directory path
get_cache_dir :: proc(allocator := context.allocator) -> (string, bool) {
	xdg_cache := os.get_env("XDG_CACHE_HOME", context.temp_allocator)
	if len(xdg_cache) > 0 && xdg_cache[0] == '/' {
		return strings.concatenate({xdg_cache, "/vup"}, allocator), true
	}

	home := os.get_env("HOME", context.temp_allocator)
	if len(home) == 0 || home[0] != '/' {
		return "", false
	}

	return strings.concatenate({home, "/.cache/vup"}, allocator), true
}

// Get temporary directory path
get_tmpdir :: proc() -> string {
	tmpdir := os.get_env("TMPDIR", context.temp_allocator)
	if len(tmpdir) > 0 && tmpdir[0] == '/' {
		return tmpdir
	}
	return "/tmp"
}
