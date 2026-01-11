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
            Commands::ListPackages => {
                // Try to load index, but don't fetch if missing (fail silently/gracefully for completion speed)
                // Actually, for completion we want speed, so maybe just load cache.
                // Index::load_or_fetch handles cache checking.
                // If it fails, we just output nothing so completion doesn't break.
                if let Ok(index) = Index::load_or_fetch(INDEX_URL, false) {
                    for (pkg, _) in &index.0 {
                        println!("{}", pkg);
                    }
                }
            }
            Commands::Completion { shell } => {
                use clap::CommandFactory;
                let mut cmd = Cli::command();
                let bin_name = cmd.get_name().to_string();

                // Generate the completions
                clap_complete::generate(*shell, &mut cmd, &bin_name, &mut std::io::stdout());

                // Inject dynamic completion for Fish
                if *shell == clap_complete::Shell::Fish {
                    println!("\n# Dynamic package completion for vuru");
                    println!(
                        "complete -c vuru -n \"__fish_seen_subcommand_from install update\" -f -a \"(vuru list-packages)\""
                    );
                    // Also allow it for main arguments which map to install implicitly
                    println!(
                        "complete -c vuru -n \"not __fish_seen_subcommand_from search remove repo completion\" -f -a \"(vuru list-packages)\""
                    );
                }
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
