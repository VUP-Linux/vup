package xbps

import common "../common"

import "core:fmt"
import "core:strings"


// Search for packages matching query
search :: proc(idx: ^common.Index, query: string) {
    if idx == nil || len(query) == 0 {
        return
    }
    
    query_lower := strings.to_lower(query, context.temp_allocator)
    system_arch := common.get_system_arch()
    
    found_count := 0
    
    // Print header
    fmt.println()
    fmt.printf("%s%-25s %-12s %-10s %-15s %s%s\n",
        common.color_code(.Bold),
        "Package",
        "Version",
        "Category",
        "Archs",
        "Available",
        common.color_code(.Reset))
    fmt.println(strings.repeat("-", 85))
    
    for name, &pkg in idx.packages {
        name_lower := strings.to_lower(name, context.temp_allocator)
        desc_lower := strings.to_lower(pkg.description, context.temp_allocator)
        
        // Match against name or description
        if strings.contains(name_lower, query_lower) || strings.contains(desc_lower, query_lower) {
            // Check if available for current arch
            _, available := common.get_repo_url_for_arch(&pkg, system_arch)
            avail_str := available ? "✓" : "✗"
            avail_color := available ? common.color_code(.Green) : common.color_code(.Red)
            
            // Format archs list
            archs_str := strings.join(pkg.archs[:], ",", context.temp_allocator)
            if len(archs_str) > 15 {
                archs_str = strings.concatenate({archs_str[:12], "..."}, context.temp_allocator)
            }
            
            // Highlight matching name
            name_color := strings.contains(name_lower, query_lower) ? common.color_code(.Green) : ""
            name_reset := strings.contains(name_lower, query_lower) ? common.color_code(.Reset) : ""
            
            fmt.printf("%s%-25s%s %-12s %-10s %-15s %s%s%s\n",
                name_color,
                name,
                name_reset,
                pkg.version,
                pkg.category,
                archs_str,
                avail_color,
                avail_str,
                common.color_code(.Reset))
            
            found_count += 1
        }
    }
    
    fmt.println()
    if found_count == 0 {
        common.log_info("No packages found matching '%s'", query)
    } else {
        common.log_info("Found %d package(s) (your arch: %s)", found_count, system_arch)
    }
}
