use clap::CommandFactory;
use clap_complete::{Shell, generate_to};
use std::env;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::Path;

include!("src/cli.rs");

fn main() -> std::io::Result<()> {
    let out_dir = env::var("OUT_DIR").unwrap();
    let mut cmd = Cli::command();
    let bin_name = "vuru";

    for shell in [Shell::Bash, Shell::Zsh, Shell::Fish] {
        let path = generate_to(shell, &mut cmd, bin_name, &out_dir)?;

        // Add dynamic completion logic for Fish
        if shell == Shell::Fish {
            let mut file = OpenOptions::new().append(true).open(&path)?;

            writeln!(file, "\n# Dynamic package completion for vuru")?;
            writeln!(
                file,
                "complete -c vuru -n \"__fish_seen_subcommand_from install update\" -f -a \"(vuru list-packages)\""
            )?;
            writeln!(
                file,
                "complete -c vuru -n \"not __fish_seen_subcommand_from search remove repo completion\" -f -a \"(vuru list-packages)\""
            )?;
        }

        println!("cargo:warning=Generated completion file: {:?}", path);
    }

    Ok(())
}
