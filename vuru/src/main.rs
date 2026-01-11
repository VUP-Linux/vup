mod cli;
mod index; // Renamed/Added
mod xbps;

use clap::Parser;
use cli::{Cli, Commands};
use index::Index;
use anyhow::Result;

// Hardcoded for now, as per design
const INDEX_URL: &str = "https://vup-linux.github.io/vup/index.json";

fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Load index relative to CWD for dev/testing, or fetch from URL
    // In production, we'd probably cache this in ~/.cache/vuru/
    let index = Index::load_or_fetch(INDEX_URL)
        .unwrap_or_else(|e| {
            eprintln!("Warning: Failed to load index: {}", e);
            // Return empty index if fetch fails, so at least we can try?
            // Or just exit.
            std::process::exit(1);
        });

    match &cli.command {
        Commands::Search { query } => {
            xbps::search(query, &index)?;
        }
        Commands::Install { package } => {
            xbps::install(package, &index)?;
        }
        Commands::Repo { command: _ } => {
           println!("Repo management is now handled automatically via the global index.");
        }
    }
    Ok(())
}
