package xbps

import "core:fmt"
import "core:strings"
import vuru ".."

// Show a simple diff between old and new content
show_diff :: proc(old_content: string, new_content: string) {
    old_lines := strings.split_lines(old_content)
    new_lines := strings.split_lines(new_content)
    defer {
        delete(old_lines)
        delete(new_lines)
    }
    
    fmt.println()
    fmt.printf("%s--- old%s\n", vuru.color_code(.Red), vuru.color_code(.Reset))
    fmt.printf("%s+++ new%s\n", vuru.color_code(.Green), vuru.color_code(.Reset))
    fmt.println()
    
    // Simple line-by-line diff
    max_lines := max(len(old_lines), len(new_lines))
    
    context_lines :: 3
    changes: [dynamic]int
    defer delete(changes)
    
    // Find changed lines
    for i in 0 ..< max_lines {
        old_line := old_lines[i] if i < len(old_lines) else ""
        new_line := new_lines[i] if i < len(new_lines) else ""
        
        if old_line != new_line {
            append(&changes, i)
        }
    }
    
    if len(changes) == 0 {
        fmt.println("No differences")
        return
    }
    
    // Print changes with context
    printed := make(map[int]bool)
    defer delete(printed)
    
    for change_idx in changes {
        // Print context before
        start := max(0, change_idx - context_lines)
        end := min(max_lines, change_idx + context_lines + 1)
        
        for i in start ..< end {
            if i in printed {
                continue
            }
            printed[i] = true
            
            old_line := old_lines[i] if i < len(old_lines) else ""
            new_line := new_lines[i] if i < len(new_lines) else ""
            
            if old_line == new_line {
                // Context line
                fmt.printf(" %4d | %s\n", i + 1, old_line)
            } else {
                // Changed line
                if i < len(old_lines) && len(old_line) > 0 {
                    fmt.printf("%s-%4d | %s%s\n",
                        vuru.color_code(.Red),
                        i + 1,
                        old_line,
                        vuru.color_code(.Reset))
                }
                if i < len(new_lines) && len(new_line) > 0 {
                    fmt.printf("%s+%4d | %s%s\n",
                        vuru.color_code(.Green),
                        i + 1,
                        new_line,
                        vuru.color_code(.Reset))
                }
            }
        }
        
        // Print separator if there's a gap
        if change_idx + context_lines + 1 < max_lines {
            next_change := max_lines
            for other in changes {
                if other > change_idx && other < next_change {
                    next_change = other
                }
            }
            
            if next_change - change_idx > 2 * context_lines + 1 {
                fmt.println("...")
            }
        }
    }
    
    fmt.println()
}
