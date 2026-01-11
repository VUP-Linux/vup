use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,

    /// Sync remote repository index
    #[arg(short = 'S', long)]
    pub sync: bool,

    /// Update target package(s) or all packages if none specified
    #[arg(short = 'u', long)]
    pub update: bool,

    /// Assume yes to all questions
    #[arg(short = 'y', long)]
    pub yes: bool,

    /// Packages to install/update
    pub packages: Vec<String>,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Search for packages in VUR
    Search {
        /// Package name to search for
        query: String,
    },
    /// Remove a package
    Remove {
        /// Package name to remove
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
