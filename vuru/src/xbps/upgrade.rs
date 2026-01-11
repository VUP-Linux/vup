use crate::index::Index;
use anyhow::{Context, Result};
use std::process::Command;

pub fn upgrade(index: &Index) -> Result<()> {
    println!("Checking for updates...");

    // xbps-query -l format: "ii <pkgname>-<version> <desc>"
    let output = Command::new("xbps-query")
        .arg("-l")
        .output()
        .context("Failed to run xbps-query")?;

    let stdout = String::from_utf8_lossy(&output.stdout);

    let mut updates = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 2 {
            continue;
        }

        let pkg_full = parts[1];
        if let Some(idx) = pkg_full.rfind('-') {
            let name = &pkg_full[0..idx];
            let ver = &pkg_full[idx + 1..];

            if let Some(info) = index.get(name) {
                if version_gt(&info.version, ver)? {
                    println!("Update available for {}: {} -> {}", name, ver, info.version);
                    updates.push((name, &info.repo_url));
                }
            }
        }
    }

    if updates.is_empty() {
        println!("All VUP packages are up to date.");
        return Ok(());
    }

    println!("Found {} updates.", updates.len());

    for (pkg, repo) in updates {
        println!("Updating {}...", pkg);
        let status = Command::new("sudo")
            .arg("xbps-install")
            .arg("-R")
            .arg(repo)
            .arg("-y")
            .arg(pkg)
            .status()
            .context("Failed to update package")?;

        if !status.success() {
            eprintln!("Failed to update {}", pkg);
        }
    }

    Ok(())
}

fn version_gt(v1: &str, v2: &str) -> Result<bool> {
    let status = Command::new("xbps-uhelper")
        .arg("cmpver")
        .arg(v1)
        .arg(v2)
        .status()
        .context("Failed to run xbps-uhelper")?;

    match status.code() {
        Some(1) => Ok(true),
        _ => Ok(false),
    }
}
