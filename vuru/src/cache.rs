use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;

pub struct Cache {
    root: PathBuf,
}

impl Cache {
    pub fn new() -> Result<Self> {
        let base_dirs = dirs::cache_dir()
            .ok_or_else(|| anyhow::anyhow!("Could not determine cache directory"))?;

        let root = base_dirs.join("vup").join("templates");
        fs::create_dir_all(&root).context("Failed to create cache directory")?;

        Ok(Self { root })
    }

    /// Returns the path where a template should be stored
    pub fn template_path(&self, pkg_name: &str) -> PathBuf {
        self.root.join(pkg_name)
    }

    /// Reads a cached template if it exists
    pub fn get_template(&self, pkg_name: &str) -> Option<String> {
        let path = self.template_path(pkg_name);
        if path.exists() {
            fs::read_to_string(path).ok()
        } else {
            None
        }
    }

    /// Saves a template to the cache
    pub fn save_template(&self, pkg_name: &str, content: &str) -> Result<()> {
        let path = self.template_path(pkg_name);
        fs::write(path, content).context("Failed to write template to cache")
    }
}
