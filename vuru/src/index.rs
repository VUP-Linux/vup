use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json;
use std::collections::HashMap;
use std::fs;

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct PackageInfo {
    pub category: String,
    pub version: String,
    pub repo_url: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Index(pub HashMap<String, PackageInfo>);

impl Index {
    pub fn fetch(url: &str, etag: Option<String>) -> Result<(Self, Option<String>, bool)> {
        // bool return = true if updated (200), false if not modified (304)
        println!("Fetching index from {}...", url);

        let client = reqwest::blocking::Client::new();
        let mut request = client.get(url);

        if let Some(e) = etag {
            request = request.header("If-None-Match", e);
        }

        let response = request.send()?;

        if response.status() == 304 {
            println!("Index not modified.");
            // Return dummy empty index, but indicate not modified
            // Caller should use cache
            return Ok((Index(HashMap::new()), None, false));
        }

        // Check for new ETag
        let new_etag = response
            .headers()
            .get("etag")
            .and_then(|h| h.to_str().ok())
            .map(|s| s.to_string());

        let index: Index = response.json()?;
        Ok((index, new_etag, true))
    }

    pub fn load_or_fetch(url: &str, force_update: bool) -> Result<Self> {
        let cache = crate::cache::Cache::new()?;
        let path = cache.index_path();
        let etag_path = path.with_extension("json.etag");

        let cached_etag = if path.exists() && etag_path.exists() {
            fs::read_to_string(&etag_path).ok()
        } else {
            None
        };

        if !force_update && path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(index_map) = serde_json::from_str(&content) {
                    return Ok(Index(index_map));
                }
            }
        }

        match Self::fetch(url, cached_etag) {
            Ok((idx, new_etag, updated)) => {
                if !updated {
                    let content = fs::read_to_string(&path)?;
                    let index_map: HashMap<String, PackageInfo> = serde_json::from_str(&content)?;
                    return Ok(Index(index_map));
                }

                let content = serde_json::to_string(&idx.0)?;
                fs::write(&path, content).context("Failed to cache index")?;

                if let Some(e) = new_etag {
                    fs::write(&etag_path, e).ok();
                }

                Ok(idx)
            }
            Err(e) => {
                if path.exists() {
                    let content = fs::read_to_string(&path)?;
                    let index_map: HashMap<String, PackageInfo> = serde_json::from_str(&content)?;
                    Ok(Index(index_map))
                } else {
                    Err(e).context("Failed to fetch index and no cache available")
                }
            }
        }
    }

    pub fn search(&self, query: &str) -> Vec<(&String, &PackageInfo)> {
        self.0
            .iter()
            .filter(|(name, _)| name.contains(query))
            .collect()
    }

    pub fn get(&self, package: &str) -> Option<&PackageInfo> {
        self.0.get(package)
    }
}
