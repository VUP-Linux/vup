use super::diff::{fetch_template, review_changes};
use crate::cache::Cache;
use crate::index::Index;
use anyhow::{Context, Result};
use std::process::Command;

pub fn install(package: &str, index: &Index) -> Result<()> {
    // 1. Look up package in index
    let info = index
        .get(package)
        .ok_or_else(|| anyhow::anyhow!("Package '{}' not found in VUP index", package))?;

    println!("Found {} in category '{}'", package, info.category);

    // 2. Fetch and Review
    let cache = Cache::new()?;

    println!("Fetching template for review...");
    let new_template = fetch_template(&info.category, package)?;

    // Check if we have a cached version
    let cached_template = cache.get_template(package);

    if !review_changes(package, &new_template, cached_template)? {
        println!("Aborted by user.");
        return Ok(());
    }

    // 3. Save to cache
    cache.save_template(package, &new_template)?;

    println!("Installing from: {}", info.repo_url);

    // 4. Execute xbps-install with the repository URL
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
