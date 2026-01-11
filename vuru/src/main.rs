mod cache;
mod cli;
mod index;
mod xbps;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Commands};
use index::Index;

// Hardcoded for now, as per design
const INDEX_URL: &str = "https://vup-linux.github.io/vup/index.json";

fn main() -> Result<()> {
    let cli = Cli::parse();

    if let Some(command) = &cli.command {
        match command {
            Commands::Search { query } => {
                let index = Index::load_or_fetch(INDEX_URL, false)?;
                xbps::search(query, &index)?;
            }
            Commands::Remove { package } => {
                xbps::uninstall(package)?;
            }
            Commands::Repo { command: _ } => {
                println!("Repo management is now handled automatically via the global index.");
            }
        }
        return Ok(());
    }

    let force_update = cli.sync;

    // Usage Check
    if !cli.sync && !cli.update && cli.packages.is_empty() {
        use clap::CommandFactory;
        Cli::command().print_help()?;
        return Ok(());
    }

    let index = Index::load_or_fetch(INDEX_URL, force_update).unwrap_or_else(|e| {
        eprintln!("Error loading index: {}", e);
        std::process::exit(1);
    });

    if cli.sync && !cli.update && cli.packages.is_empty() {
        println!("Index synchronized.");
        return Ok(());
    }

    if cli.update && cli.packages.is_empty() {
        xbps::upgrade(&index)?;
        return Ok(());
    }

    for pkg in &cli.packages {
        xbps::install(pkg, &index)?;
    }

    Ok(())
}
