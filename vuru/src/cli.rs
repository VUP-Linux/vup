use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Search for packages in VUR
    Search {
        /// Package name to search for
        query: String,
    },
    /// Install a package from VUR
    Install {
        /// Package name to install
        package: String,
    },
    /// Manage VUR repositories
    Repo {
        #[command(subcommand)]
        command: RepoCommands,
    },
}

#[derive(Subcommand)]
pub enum RepoCommands {
    /// List configured repositories
    List,
    /// Add a repository
    Add {
        /// Name of the repository
        name: String,
        /// URL of the repository
        url: String,
    },
    /// Remove a repository
    Remove {
        /// Name of the repository
        name: String,
    },
}
