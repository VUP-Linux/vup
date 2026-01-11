use anyhow::{Context, Result};
use std::io::{self, Write};
use std::process::{Command, Stdio};

// Fetch template content
pub fn fetch_template(category: &str, pkg: &str) -> Result<String> {
    let url = format!(
        "https://raw.githubusercontent.com/VUP-Linux/vup/main/vup/srcpkgs/{}/{}/template",
        category, pkg
    );
    let resp = reqwest::blocking::get(&url).context("Failed to fetch template")?;

    if !resp.status().is_success() {
        return Err(anyhow::anyhow!(
            "Failed to fetch template: {}",
            resp.status()
        ));
    }

    resp.text().context("Failed to read template text")
}

// Show content or diff
pub fn review_changes(pkg: &str, current: &str, previous: Option<String>) -> Result<bool> {
    if let Some(prev) = previous {
        if prev == current {
            println!(
                "Template for {} has not changed since last cached version.",
                pkg
            );
        } else {
            println!("Template for {} has changed. Showing diff:", pkg);
            println!("{}", "-".repeat(50));

            // Allow system diff if available, else simple print
            // Writing to temp files for diff command
            let dir = std::env::temp_dir();
            let p1 = dir.join(format!("{}.old", pkg));
            let p2 = dir.join(format!("{}.new", pkg));

            std::fs::write(&p1, &prev)?;
            std::fs::write(&p2, current)?;

            let _ = Command::new("diff")
                .arg("-u")
                .arg("--color=always")
                .arg(&p1)
                .arg(&p2)
                .status(); // Ignore exit code as diff returns 1 on diffs

            println!("{}", "-".repeat(50));

            // Clean up
            let _ = std::fs::remove_file(p1);
            let _ = std::fs::remove_file(p2);
        }
    } else {
        println!(
            "New installation of {}. Usage of 'less' to view template:",
            pkg
        );

        // Use less to show content
        let mut child = Command::new("less")
            .stdin(Stdio::piped())
            .spawn()
            .context("Failed to spawn less")?;

        if let Some(mut stdin) = child.stdin.take() {
            write!(stdin, "{}", current)?;
        }

        child.wait()?;
    }

    // Prompt
    print!("Proceed with installation? [Y/n] ");
    io::stdout().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    let input = input.trim().to_lowercase();

    Ok(input == "" || input == "y" || input == "yes")
}
