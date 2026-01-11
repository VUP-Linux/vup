use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Deserialize, Debug, Clone)]
pub struct PackageInfo {
    pub category: String,
    pub version: String,
    pub repo_url: String,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Index(HashMap<String, PackageInfo>);

impl Index {
    pub fn fetch(url: &str) -> Result<Self> {
        println!("Fetching index from {}...", url);
        let response = reqwest::blocking::get(url)?;
        let index: Index = response.json()?;
        Ok(index)
    }

    pub fn load_or_fetch(url: &str) -> Result<Self> {
        // In a real app, check cache first. 
        // For now, always fetch or fallback to a local file if URL fails (for dev).
        match Self::fetch(url) {
            Ok(idx) => Ok(idx),
            Err(e) => {
                eprintln!("Failed to fetch index: {}. Trying local cache...", e);
                // Fallback to local dev file if exists
                let path = PathBuf::from("../index.json");
                if path.exists() {
                     let content = fs::read_to_string(path)?;
                     let index: HashMap<String, PackageInfo> = serde_json::from_str(&content)?;
                     Ok(Index(index))
                } else {
                    Err(e).context("Could not fetch index and no local cache found")
                }
            }
        }
    }

    pub fn search(&self, query: &str) -> Vec<(&String, &PackageInfo)> {
        self.0.iter()
            .filter(|(name, _)| name.contains(query))
            .collect()
    }

    pub fn get(&self, package: &str) -> Option<&PackageInfo> {
        self.0.get(package)
    }
}
