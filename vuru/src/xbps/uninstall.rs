use anyhow::{Context, Result};
use std::process::Command;

pub fn uninstall(package: &str) -> Result<()> {
    println!("Uninstalling {}...", package);

    let status = Command::new("sudo")
        .arg("xbps-remove")
        .arg("-R") // Recursive remove
        .arg(package)
        .status()
        .context("Failed to execute xbps-remove")?;

    if !status.success() {
        return Err(anyhow::anyhow!("xbps-remove failed"));
    }

    Ok(())
}
