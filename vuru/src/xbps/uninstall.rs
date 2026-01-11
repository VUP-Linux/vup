use anyhow::Result;

pub fn uninstall(package: &str) -> Result<()> {
    // Placeholder: In the future, this could wrap xbps-remove
    println!("Uninstalling {} (placeholder)", package);
    Ok(())
}
