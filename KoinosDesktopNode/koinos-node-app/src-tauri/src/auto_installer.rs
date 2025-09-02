use std::process::Command;
use tokio::process::Command as AsyncCommand;
use crate::logger::{log_debug, log_info, log_warn, log_error};

pub struct AutoInstaller;

impl AutoInstaller {
    /// Automatically install all requirements
    pub async fn install_all_requirements() -> Result<String, String> {
        log_info("Starting automatic requirements installation", None);
        let mut installed_items = Vec::new();
        
        // Check and install each requirement
        #[cfg(target_os = "macos")]
        {
            // 1. Check/Install Homebrew
            log_debug("Checking for Homebrew installation", None);
            if !Self::is_homebrew_installed() {
                log_warn("Homebrew not found, attempting to install", None);
                println!("Installing Homebrew...");
                Self::install_homebrew().await?;
                installed_items.push("Homebrew");
            }
            
            // 2. Check/Install Docker
            log_debug("Checking for Docker installation", None);
            if !Self::is_docker_installed() {
                log_warn("Docker not found, attempting to install", None);
                println!("Installing Docker Desktop...");
                Self::install_docker_mac().await?;
                installed_items.push("Docker Desktop");
            }
            
            // 3. Start Docker if not running
            log_debug("Checking if Docker is running", None);
            if !Self::is_docker_running() {
                log_warn("Docker not running, attempting to start", None);
                println!("Starting Docker...");
                Self::start_docker_mac().await?;
                installed_items.push("Docker (started)");
            }
        }
        
        #[cfg(target_os = "linux")]
        {
            // Install Docker on Linux
            if !Self::is_docker_installed() {
                Self::install_docker_linux().await?;
                installed_items.push("Docker");
            }
        }
        
        #[cfg(target_os = "windows")]
        {
            // Check for Docker on Windows
            if !Self::is_docker_installed() {
                return Err("Docker Desktop must be installed manually on Windows. Please download from docker.com".to_string());
            }
        }
        
        if installed_items.is_empty() {
            Ok("All requirements already installed".to_string())
        } else {
            Ok(format!("Successfully installed: {}", installed_items.join(", ")))
        }
    }
    
    fn is_homebrew_installed() -> bool {
        // Check common Homebrew installation locations
        // Apple Silicon location
        if std::path::Path::new("/opt/homebrew/bin/brew").exists() {
            log_debug("Found Homebrew at /opt/homebrew/bin/brew", None);
            return true;
        }
        // Intel Mac location
        if std::path::Path::new("/usr/local/bin/brew").exists() {
            log_debug("Found Homebrew at /usr/local/bin/brew", None);
            return true;
        }
        // Also check if it's in PATH (though it might not be in a new shell)
        Command::new("which")
            .arg("brew")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    
    fn is_docker_installed() -> bool {
        #[cfg(target_os = "macos")]
        {
            // Check if Docker.app exists
            if std::path::Path::new("/Applications/Docker.app").exists() {
                log_debug("Found Docker.app in Applications", None);
                return true;
            }
            // Or check if docker command exists
            let docker_cmd = Command::new("which")
                .arg("docker")
                .output()
                .map(|output| output.status.success())
                .unwrap_or(false);
            
            if docker_cmd {
                log_debug("Found docker command in PATH", None);
            } else {
                log_debug("Docker not found", None);
            }
            docker_cmd
        }
        
        #[cfg(not(target_os = "macos"))]
        {
            Command::new("which")
                .arg("docker")
                .output()
                .map(|output| output.status.success())
                .unwrap_or(false)
        }
    }
    
    fn is_docker_running() -> bool {
        Command::new("docker")
            .arg("info")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    
    async fn install_homebrew() -> Result<(), String> {
        // Double-check if Homebrew is already installed
        if Self::is_homebrew_installed() {
            println!("Homebrew is already installed!");
            return Ok(());
        }
        
        // Open Terminal and run the Homebrew installation
        let applescript = r#"
tell application "Terminal"
    activate
    set newTab to do script "echo 'Installing Homebrew for Koinos Node...' && /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && echo 'Homebrew installation complete! You can close this window.'"
    delay 2
end tell
"#;
        
        let output = AsyncCommand::new("osascript")
            .arg("-e")
            .arg(applescript)
            .output()
            .await
            .map_err(|e| format!("Failed to open Terminal for Homebrew installation: {}", e))?;
        
        if !output.status.success() {
            // If Terminal approach fails, provide manual instructions
            return Err("Please install Homebrew manually:\n1. Open Terminal\n2. Run: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n3. Then click 'Check Again'".to_string());
        }
        
        // Wait for user to complete installation
        // Since we opened Terminal, we need to give the user time to complete it
        // Return a message asking them to wait
        Err("Homebrew installation started in Terminal. Please:\n1. Complete the installation in Terminal\n2. Enter your password when prompted\n3. Wait for it to finish\n4. Click 'Check Again' to continue".to_string())
    }
    
    async fn install_docker_mac() -> Result<(), String> {
        // First ensure Homebrew is available
        if !Self::is_homebrew_installed() {
            Self::install_homebrew().await?;
        }
        
        // Find the correct brew path
        let brew_path = if std::path::Path::new("/opt/homebrew/bin/brew").exists() {
            "/opt/homebrew/bin/brew"
        } else if std::path::Path::new("/usr/local/bin/brew").exists() {
            "/usr/local/bin/brew"
        } else {
            // Try to find brew in PATH
            "brew"
        };
        
        // Install Docker Desktop using Homebrew
        let output = AsyncCommand::new(brew_path)
            .args(&["install", "--cask", "docker"])
            .output()
            .await
            .map_err(|e| format!("Failed to install Docker: {}", e))?;
        
        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            
            // Check for various error conditions
            if error.contains("already installed") {
                return Ok(());
            }
            
            if error.contains("already locked") || error.contains("process has already locked") {
                // Kill any stuck brew processes and retry
                let _ = Command::new("pkill")
                    .args(&["-f", "brew install --cask docker"])
                    .output();
                
                return Err("Another installation was in progress. It has been stopped.\nClick 'Check Again' to retry.".to_string());
            }
            
            if error.contains("sudo") || error.contains("password") {
                return Err("Docker installation needs admin privileges.\nClick 'Check Again' and enter your password when prompted.".to_string());
            }
            
            return Err(format!("Docker installation failed: {}", error));
        }
        
        // Wait a moment for installation to complete
        tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
        
        Ok(())
    }
    
    async fn start_docker_mac() -> Result<(), String> {
        // Open Docker Desktop
        Command::new("open")
            .arg("/Applications/Docker.app")
            .spawn()
            .map_err(|e| format!("Failed to open Docker: {}", e))?;
        
        // Wait for Docker to start (check every 2 seconds for up to 30 seconds)
        for _ in 0..15 {
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            if Self::is_docker_running() {
                return Ok(());
            }
        }
        
        // Docker is starting but not ready yet, that's okay
        Ok(())
    }
    
    async fn install_docker_linux() -> Result<(), String> {
        // Use the official Docker installation script
        let install_script = r#"
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
            rm get-docker.sh
        "#;
        
        let output = AsyncCommand::new("bash")
            .arg("-c")
            .arg(install_script)
            .output()
            .await
            .map_err(|e| format!("Failed to install Docker: {}", e))?;
        
        if !output.status.success() {
            return Err("Docker installation failed".to_string());
        }
        
        Ok(())
    }
    
    /// Check if all requirements are met
    pub fn check_requirements() -> (bool, Vec<String>) {
        let mut missing = Vec::new();
        
        #[cfg(target_os = "macos")]
        {
            if !Self::is_docker_installed() {
                missing.push("Docker Desktop".to_string());
            } else if !Self::is_docker_running() {
                missing.push("Docker (not running)".to_string());
            }
        }
        
        #[cfg(not(target_os = "macos"))]
        {
            if !Self::is_docker_installed() {
                missing.push("Docker".to_string());
            } else if !Self::is_docker_running() {
                missing.push("Docker (not running)".to_string());
            }
        }
        
        (missing.is_empty(), missing)
    }
}