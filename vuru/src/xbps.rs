use std::process::Command;
use anyhow::{Context, Result};
use crate::index::Index;

pub fn install(package: &str, index: &Index) -> Result<()> {
    // 1. Look up package in index
    let info = index.get(package)
        .ok_or_else(|| anyhow::anyhow!("Package '{}' not found in VUP index", package))?;

    println!("Found {} in category '{}'", package, info.category);
    println!("Installing from: {}", info.repo_url);

    // 2. Execute xbps-install with the repository URL
    let status = Command::new("sudo")
        .arg("xbps-install")
        .arg("-R")
        .arg(&info.repo_url)
        .arg("-S") // Sync repository
        .arg(package)
        .status()
        .context("Failed to execute xbps-install")?;

    if !status.success() {
        return Err(anyhow::anyhow!("xbps-install failed"));
    }
    Ok(())
}

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
