package common

import "core:fmt"
import "core:os"
import "core:strings"
import "core:c"
import "core:sys/posix"

// ANSI color codes
Color :: enum {
    Reset,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    Bold,
}

color_code :: proc(color: Color) -> string {
    if !is_tty() {
        return ""
    }
    
    switch color {
    case .Reset:   return "\x1b[0m"
    case .Red:     return "\x1b[31m"
    case .Green:   return "\x1b[32m"
    case .Yellow:  return "\x1b[33m"
    case .Blue:    return "\x1b[34m"
    case .Magenta: return "\x1b[35m"
    case .Cyan:    return "\x1b[36m"
    case .Bold:    return "\x1b[1m"
    }
    return ""
}

@(private="file")
_is_tty: Maybe(bool) = nil

is_tty :: proc() -> bool {
    if cached, ok := _is_tty.?; ok {
        return cached
    }
    result := posix.isatty(posix.STDOUT_FILENO)
    _is_tty = bool(result)
    return bool(result)
}

log_info :: proc(format: string, args: ..any) {
    fmt.eprintf("%s[INFO]%s ", color_code(.Cyan), color_code(.Reset))
    fmt.eprintfln(format, ..args)
}

log_warn :: proc(format: string, args: ..any) {
    fmt.eprintf("%s[WARN]%s ", color_code(.Yellow), color_code(.Reset))
    fmt.eprintfln(format, ..args)
}

log_error :: proc(format: string, args: ..any) {
    fmt.eprintf("%s[ERROR]%s ", color_code(.Red), color_code(.Reset))
    fmt.eprintfln(format, ..args)
}

log_success :: proc(format: string, args: ..any) {
    fmt.eprintf("%s[OK]%s ", color_code(.Green), color_code(.Reset))
    fmt.eprintfln(format, ..args)
}

// Prompt user for yes/no confirmation
prompt_yes_no :: proc(message: string) -> bool {
    fmt.eprintf("%s [y/N]: ", message)
    
    buf: [256]byte
    n, err := os.read(os.stdin, buf[:])
    if err != nil || n == 0 {
        return false
    }
    
    response := strings.trim_space(string(buf[:n]))
    return response == "y" || response == "Y" || response == "yes" || response == "Yes"
}

// Execute a command and wait for completion
exec_command :: proc(args: []string, use_sudo: bool = false) -> (success: bool) {
    if len(args) == 0 {
        return false
    }
    
    // Build command array
    cmd_args: [dynamic]cstring
    defer delete(cmd_args)
    
    if use_sudo {
        append(&cmd_args, "sudo")
    }
    
    for arg in args {
        append(&cmd_args, strings.clone_to_cstring(arg))
    }
    append(&cmd_args, nil)
    
    defer {
        start := 1 if use_sudo else 0
        for i := start; i < len(cmd_args) - 1; i += 1 {
            delete(cmd_args[i])
        }
    }
    
    pid := posix.fork()
    
    if pid < 0 {
        log_error("fork() failed")
        return false
    }
    
    if pid == 0 {
        // Child process
        program := cmd_args[0]
        posix.execvp(program, raw_data(cmd_args[:]))
        posix._exit(127)
    }
    
    // Parent process - wait for child
    status: c.int
    result := posix.waitpid(pid, &status, {})
    
    if result == -1 {
        return false
    }
    
    return posix.WIFEXITED(status) && posix.WEXITSTATUS(status) == 0
}

// Check if a file exists
file_exists :: proc(path: string) -> bool {
    return os.exists(path)
}

// Read entire file to string
read_file :: proc(path: string, allocator := context.allocator) -> (content: string, ok: bool) {
    data, success := os.read_entire_file(path, allocator)
    if !success {
        return "", false
    }
    return string(data), true
}

// Write string to file
write_file :: proc(path: string, content: string) -> bool {
    return os.write_entire_file(path, transmute([]byte)content)
}

// Get environment variable with fallback
getenv :: proc(key: string, fallback: string = "") -> string {
    if val, ok := os.lookup_env(key); ok {
        return val
    }
    return fallback
}
