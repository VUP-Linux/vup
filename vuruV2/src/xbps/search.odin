package xbps

import "core:fmt"
import "core:strings"
import vuru ".."

// Search for packages matching query
search :: proc(idx: ^vuru.Index, query: string) {
    if idx == nil || len(query) == 0 {
        return
    }
    
    query_lower := strings.to_lower(query, context.temp_allocator)
    
    found_count := 0
    
    // Print header
    fmt.println()
    fmt.printf("%s%-30s %-15s %-12s %s%s\n",
        vuru.color_code(.Bold),
        "Package",
        "Version",
        "Category",
        "Description",
        vuru.color_code(.Reset))
    fmt.println(strings.repeat("-", 80))
    
    for name, pkg in idx.packages {
        name_lower := strings.to_lower(name, context.temp_allocator)
        desc_lower := strings.to_lower(pkg.description, context.temp_allocator)
        
        // Match against name or description
        if strings.contains(name_lower, query_lower) || strings.contains(desc_lower, query_lower) {
            // Truncate description if too long
            desc := pkg.description
            if len(desc) > 35 {
                desc = strings.concatenate({desc[:32], "..."}, context.temp_allocator)
            }
            
            // Highlight matching name
            if strings.contains(name_lower, query_lower) {
                fmt.printf("%s%-30s%s %-15s %-12s %s\n",
                    vuru.color_code(.Green),
                    name,
                    vuru.color_code(.Reset),
                    pkg.version,
                    pkg.category,
                    desc)
            } else {
                fmt.printf("%-30s %-15s %-12s %s\n",
                    name,
                    pkg.version,
                    pkg.category,
                    desc)
            }
            
            found_count += 1
        }
    }
    
    fmt.println()
    if found_count == 0 {
        vuru.log_info("No packages found matching '%s'", query)
    } else {
        vuru.log_info("Found %d package(s)", found_count)
    }
}
