use crate::index::Index;
use anyhow::Result;

pub fn search(query: &str, index: &Index) -> Result<()> {
    let results = index.search(query);

    if results.is_empty() {
        println!("No results found for '{}'", query);
        return Ok(());
    }

    println!("{:<20} {:<15} {:<20}", "PACKAGE", "VERSION", "CATEGORY");
    println!("{}", "-".repeat(55));

    for (name, info) in results {
        println!("{:<20} {:<15} {:<20}", name, info.version, info.category);
    }
    Ok(())
}
