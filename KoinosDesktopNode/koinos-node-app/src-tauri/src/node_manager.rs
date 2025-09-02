use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tokio::process::Command as AsyncCommand;
use crate::state_manager::StateManager;
use crate::logger::{log_debug, log_info, log_warn, log_error};

// Helper function to get directory size
fn get_dir_size(path: &Path) -> u64 {
    let mut size = 0;
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    size += metadata.len();
                } else if metadata.is_dir() {
                    size += get_dir_size(&entry.path());
                }
            }
        }
    }
    size
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeStatus {
    pub status: String, // "stopped", "starting", "syncing", "running", "error"
    pub sync_progress: f32,
    pub current_block: u64,
    pub target_block: u64,
    pub peers_count: u32,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemRequirements {
    pub has_docker: bool,
    pub docker_running: bool,
    pub ram_gb: u32,
    pub available_disk_gb: u64,
    pub is_sufficient: bool,
    pub missing_requirements: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceUsage {
    pub cpu_percent: f32,
    pub memory_mb: u32,
    pub memory_total_mb: u32,
    pub disk_used_gb: f32,
    pub disk_total_gb: f32,
}

pub struct NodeManager {
    pub status: Arc<Mutex<NodeStatus>>,
    pub koinos_path: PathBuf,
    pub data_path: PathBuf,
    pub state_manager: Arc<Mutex<StateManager>>,
}

impl NodeManager {
    pub fn new() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let koinos_path = home.join("koinos");
        let data_path = home.join(".koinos");
        
        let mut state_manager = StateManager::new();
        let _ = state_manager.load();
        
        // Initialize status from saved state
        let saved_state = state_manager.get_state();
        let initial_status = NodeStatus {
            status: "stopped".to_string(),
            sync_progress: saved_state.last_sync_progress,
            current_block: saved_state.last_block,
            target_block: 0,
            peers_count: 0,
            error_message: None,
        };

        Self {
            status: Arc::new(Mutex::new(initial_status)),
            koinos_path,
            data_path,
            state_manager: Arc::new(Mutex::new(state_manager)),
        }
    }

    pub fn is_initialized(&self) -> bool {
        self.koinos_path.exists() && 
        self.koinos_path.join("docker-compose.yml").exists()
    }

    pub async fn check_system_requirements(&self) -> Result<SystemRequirements, String> {
        log_info("Starting system requirements check", None);
        
        let mut requirements = SystemRequirements {
            has_docker: false,
            docker_running: false,
            ram_gb: 0,
            available_disk_gb: 0,
            is_sufficient: false,
            missing_requirements: Vec::new(),
        };

        // Check Docker - try multiple methods
        log_debug("Checking for Docker installation", None);
        
        // First try the docker command directly
        let docker_check = Command::new("docker")
            .arg("--version")
            .output();
        
        if let Ok(output) = docker_check {
            if output.status.success() {
                requirements.has_docker = true;
                let version = String::from_utf8_lossy(&output.stdout);
                log_info("Docker found", Some(&version.trim()));
            } else {
                // Command exists but failed - try with full path
                let docker_paths = vec![
                    "/usr/local/bin/docker",
                    "/opt/homebrew/bin/docker",
                    "/usr/bin/docker",
                ];
                
                for path in docker_paths {
                    if let Ok(output) = Command::new(path).arg("--version").output() {
                        if output.status.success() {
                            requirements.has_docker = true;
                            let version = String::from_utf8_lossy(&output.stdout);
                            log_info("Docker found at", Some(&format!("{}: {}", path, version.trim())));
                            break;
                        }
                    }
                }
            }
        }
        
        // Also check if Docker Desktop is installed on macOS
        #[cfg(target_os = "macos")]
        if !requirements.has_docker && std::path::Path::new("/Applications/Docker.app").exists() {
            requirements.has_docker = true;
            log_info("Docker Desktop found", Some("Located at /Applications/Docker.app"));
        }
        
        if !requirements.has_docker {
            log_warn("Docker not found", Some("Docker is not installed"));
        }
        
        if requirements.has_docker {
            log_debug("Checking if Docker daemon is running", None);
            
            // Try docker info with different paths
            let docker_paths = vec![
                "docker",
                "/usr/local/bin/docker", 
                "/opt/homebrew/bin/docker",
                "/usr/bin/docker",
            ];
            
            let mut docker_found = false;
            for path in docker_paths {
                if let Ok(output) = Command::new(path).arg("info").output() {
                    docker_found = true;
                    if output.status.success() {
                        requirements.docker_running = true;
                        log_info("Docker daemon is running", None);
                        break;
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        log_warn("Docker daemon not running", Some(&stderr));
                    }
                }
            }
            
            if !docker_found {
                requirements.docker_running = false;
                log_error("Failed to check Docker daemon status", None);
                requirements.missing_requirements.push("Docker is not running".to_string());
            } else if !requirements.docker_running {
                requirements.missing_requirements.push("Docker is not running".to_string());
            }
        } else {
            requirements.missing_requirements.push("Docker is not installed".to_string());
            log_error("Docker is not installed", Some("Please install Docker Desktop"));
        }

        // Check RAM
        let ram_info = sys_info::mem_info().map_err(|e| e.to_string())?;
        requirements.ram_gb = (ram_info.total / 1024 / 1024) as u32; // Convert KB to GB
        
        if requirements.ram_gb < 4 {
            requirements.missing_requirements.push(format!("Insufficient RAM: {}GB (minimum 4GB required)", requirements.ram_gb));
        }

        // Check disk space
        let available_space = fs2::available_space(&self.data_path.parent().unwrap_or(&PathBuf::from("/")))
            .unwrap_or(0) / (1024 * 1024 * 1024); // Convert to GB
        
        requirements.available_disk_gb = available_space;
        
        if requirements.available_disk_gb < 60 {
            requirements.missing_requirements.push(format!(
                "Insufficient disk space: {}GB (minimum 60GB required)", 
                requirements.available_disk_gb
            ));
        }

        requirements.is_sufficient = requirements.missing_requirements.is_empty();
        
        log_info("System requirements check complete", 
            Some(&format!("Sufficient: {}, Missing: {:?}", 
                requirements.is_sufficient, 
                requirements.missing_requirements)));
        
        Ok(requirements)
    }

    pub async fn install_docker(&self) -> Result<(), String> {
        #[cfg(target_os = "macos")]
        {
            // Check if Homebrew is installed
            let brew_check = std::process::Command::new("which")
                .arg("brew")
                .output()
                .map_err(|e| format!("Failed to check for Homebrew: {}", e))?;
            
            if !brew_check.status.success() {
                return Err("Homebrew not installed. Please install Homebrew first or download Docker Desktop manually.".to_string());
            }
            
            // Install Docker using Homebrew
            let output = AsyncCommand::new("brew")
                .args(&["install", "--cask", "docker"])
                .output()
                .await
                .map_err(|e| format!("Failed to install Docker: {}", e))?;
            
            if !output.status.success() {
                let error = String::from_utf8_lossy(&output.stderr);
                if error.contains("already installed") {
                    // Docker is already installed, try to open it
                    std::process::Command::new("open")
                        .arg("/Applications/Docker.app")
                        .spawn()
                        .ok();
                    return Ok(());
                }
                return Err(format!("Docker installation failed: {}", error));
            }
            
            // Try to open Docker after installation
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            std::process::Command::new("open")
                .arg("/Applications/Docker.app")
                .spawn()
                .ok();
            
            Ok(())
        }

        #[cfg(target_os = "linux")]
        {
            // Install Docker on Linux
            let script = r#"
                curl -fsSL https://get.docker.com | sh
                sudo usermod -aG docker $USER
            "#;
            
            let output = AsyncCommand::new("sh")
                .arg("-c")
                .arg(script)
                .output()
                .await
                .map_err(|e| e.to_string())?;
            
            if !output.status.success() {
                Err("Failed to install Docker".to_string())
            } else {
                Ok(())
            }
        }

        #[cfg(target_os = "windows")]
        {
            Err("Please install Docker Desktop from https://www.docker.com/products/docker-desktop/".to_string())
        }
    }

    pub async fn setup_koinos(&self) -> Result<(), String> {
        log_info("Starting Koinos setup", None);
        
        // Create koinos directory
        log_debug("Creating koinos directory", Some(self.koinos_path.to_str().unwrap_or("unknown")));
        fs::create_dir_all(&self.koinos_path)
            .map_err(|e| format!("Failed to create koinos directory: {}", e))?;

        // Clone Koinos repository if not exists
        if !self.koinos_path.join("docker-compose.yml").exists() {
            log_info("docker-compose.yml not found, cloning repository", None);
            // First check if directory is empty (might exist from failed clone)
            if self.koinos_path.exists() && fs::read_dir(&self.koinos_path).map(|mut d| d.next().is_none()).unwrap_or(false) {
                fs::remove_dir(&self.koinos_path).ok();
            }

            log_info("Cloning Koinos repository", Some("https://github.com/koinos/koinos"));
            let output = AsyncCommand::new("git")
                .arg("clone")
                .arg("--depth")
                .arg("1")  // Shallow clone for faster download
                .arg("https://github.com/koinos/koinos")
                .arg(&self.koinos_path)
                .output()
                .await
                .map_err(|e| {
                    log_error("Failed to execute git clone", Some(&e.to_string()));
                    format!("Failed to clone repository: {}", e)
                })?;

            if !output.status.success() {
                let error = String::from_utf8_lossy(&output.stderr);
                log_error("Git clone failed", Some(&error));
                return Err(format!("Failed to clone Koinos repository: {}", error));
            }
            log_info("Repository cloned successfully", None);
        } else {
            log_info("docker-compose.yml already exists, skipping clone", None);
        }

        // Setup configuration
        self.setup_configuration().await?;
        
        // Pre-pull Docker images for smoother startup
        println!("Pulling Docker images (this may take a few minutes)...");
        let pull_output = AsyncCommand::new("docker")
            .arg("compose")
            .arg("pull")
            .current_dir(&self.koinos_path)
            .output()
            .await;
        
        if let Ok(output) = pull_output {
            if !output.status.success() {
                println!("Warning: Could not pre-pull Docker images. They will be downloaded on first start.");
            } else {
                println!("Docker images ready");
            }
        }

        Ok(())
    }

    // Resolve a working docker binary path (handles PATH issues on macOS)
    fn find_docker_path(&self) -> Option<String> {
        let candidates = vec![
            "docker",
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/usr/bin/docker",
        ];
        for c in candidates {
            if let Ok(output) = Command::new(c).arg("--version").output() {
                if output.status.success() {
                    return Some(c.to_string());
                }
            }
        }
        None
    }

    fn docker_info_ok(&self) -> bool {
        if let Some(docker) = self.find_docker_path() {
            if let Ok(output) = Command::new(&docker).arg("info").output() {
                if output.status.success() {
                    return true;
                }
                // Check if Docker Desktop is starting
                let stderr = String::from_utf8_lossy(&output.stderr);
                if stderr.contains("Docker Desktop is starting") {
                    log_info("Docker Desktop is starting, waiting...", None);
                    // Return false but don't treat as error
                    return false;
                }
            }
        }
        false
    }

    fn compose_invocation(&self) -> Option<(String, Vec<String>)> {
        if let Some(docker) = self.find_docker_path() {
            // Prefer 'docker compose' if supported
            if Command::new(&docker)
                .arg("compose")
                .arg("version")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
            {
                return Some((docker, vec!["compose".into()]));
            }
        }
        // Fallback to docker-compose binary
        for c in [
            "docker-compose",
            "/opt/homebrew/bin/docker-compose",
            "/usr/local/bin/docker-compose",
            "/usr/bin/docker-compose",
        ] {
            if Command::new(c)
                .arg("--version")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
            {
                return Some((c.to_string(), vec![]));
            }
        }
        None
    }

    async fn setup_configuration(&self) -> Result<(), String> {
        log_info("Setting up Koinos configuration", None);
        
        let config_path = self.koinos_path.join("config");
        let config_example = self.koinos_path.join("config-example");
        
        // Check if config directory needs to be created
        if !config_path.exists() {
            if config_example.exists() {
                log_debug("Copying config-example to config", None);
                // Use fs_extra with proper options to copy directory contents
                let mut options = fs_extra::dir::CopyOptions::new();
                options.overwrite = false;
                options.copy_inside = true;
                
                // Create the config directory first
                fs::create_dir_all(&config_path)
                    .map_err(|e| format!("Failed to create config directory: {}", e))?;
                
                // Copy all files from config-example to config
                let entries = fs::read_dir(&config_example)
                    .map_err(|e| format!("Failed to read config-example: {}", e))?;
                
                for entry in entries {
                    if let Ok(entry) = entry {
                        let from = entry.path();
                        let file_name = entry.file_name();
                        let to = config_path.join(file_name);
                        
                        if from.is_file() {
                            fs::copy(&from, &to)
                                .map_err(|e| format!("Failed to copy config file: {}", e))?;
                        }
                    }
                }
                log_info("Config files copied successfully", None);
            } else {
                log_warn("config-example not found, config may need manual setup", None);
            }
        } else {
            log_debug("Config directory already exists", None);
        }

        // Setup .env file
        let env_file = self.koinos_path.join(".env");
        let env_example = self.koinos_path.join("env.example");
        
        if !env_file.exists() && env_example.exists() {
            fs::copy(&env_example, &env_file)
                .map_err(|e| format!("Failed to copy env file: {}", e))?;
        }

        // Configure .env for desktop app (keep APIs on localhost for security)
        if env_file.exists() {
            let env_content = fs::read_to_string(&env_file)
                .map_err(|e| format!("Failed to read env file: {}", e))?;
            
            let mut new_content = env_content;
            
            // Keep interfaces on localhost for desktop app security
            new_content = new_content.replace("JSONRPC_INTERFACE=127.0.0.1", "JSONRPC_INTERFACE=127.0.0.1");
            new_content = new_content.replace("GRPC_INTERFACE=127.0.0.1", "GRPC_INTERFACE=127.0.0.1");
            new_content = new_content.replace("REST_INTERFACE=127.0.0.1", "REST_INTERFACE=127.0.0.1");
            
            // Enable required profiles (ensure COMPOSE_PROFILES is set)
            if !new_content.contains("COMPOSE_PROFILES=") {
                new_content.push_str("\nCOMPOSE_PROFILES=all\n");
            } else {
                // Un-comment if present as commented key
                new_content = new_content.replace("#COMPOSE_PROFILES", "COMPOSE_PROFILES");
            }
            
            // Add performance optimizations and restart policy
            if !new_content.contains("KOINOS_LOG_LEVEL") {
                new_content.push_str("\n# Desktop Node Optimizations\n");
                new_content.push_str("KOINOS_LOG_LEVEL=warn\n");
                new_content.push_str("KOINOS_LOG_JSON=false\n");
                new_content.push_str("# Auto-restart on system reboot\n");
                new_content.push_str("COMPOSE_RESTART_POLICY=unless-stopped\n");
            }
            
            fs::write(&env_file, new_content)
                .map_err(|e| format!("Failed to write env file: {}", e))?;
        }

        Ok(())
    }

    pub async fn download_snapshot(&self, progress_callback: impl Fn(f32)) -> Result<(), String> {
        log_info("Starting snapshot download with resume support", None);
        
        // Check if blockchain data already exists and is valid
        let chain_path = self.data_path.join("chain");
        let block_store_path = self.data_path.join("block_store");
        
        if chain_path.exists() && block_store_path.exists() {
            // Check if data is substantial (not just empty directories)
            let chain_size = get_dir_size(&chain_path);
            let block_size = get_dir_size(&block_store_path);
            
            if chain_size > 1_000_000_000 { // At least 1GB
                log_info("Blockchain data already exists", 
                    Some(&format!("Chain: {}GB, BlockStore: {}GB", 
                        chain_size / 1_000_000_000, 
                        block_size / 1_000_000_000)));
                progress_callback(100.0);
                return Ok(());
            }
        }

        // Get latest snapshot URL
        let snapshot_url = self.get_latest_snapshot_url().await?;
        let snapshot_name = snapshot_url.split('/').last().unwrap_or("snapshot.tar.gz");
        
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let snapshot_path = home.join(snapshot_name);
        
        // Also check for common snapshot filename
        let common_snapshot_path = home.join("koinos_snapshot.tar.gz");
        let actual_snapshot_path = if common_snapshot_path.exists() && !snapshot_path.exists() {
            // Rename to expected name
            fs::rename(&common_snapshot_path, &snapshot_path)
                .map_err(|e| format!("Failed to rename snapshot: {}", e))?;
            log_info("Renamed existing snapshot to expected filename", 
                Some(&format!("koinos_snapshot.tar.gz -> {}", snapshot_name)));
            snapshot_path.clone()
        } else {
            snapshot_path.clone()
        };
        
        // Check for existing partial download
        let mut resume_from = 0u64;
        if actual_snapshot_path.exists() {
            let existing_size = fs::metadata(&actual_snapshot_path)
                .map(|m| m.len())
                .unwrap_or(0);
            
            if existing_size > 100_000_000 { // More than 100MB
                resume_from = existing_size;
                log_info("Found partial download", 
                    Some(&format!("Resuming from {:.1}GB ({}MB)", 
                        existing_size as f64 / 1_000_000_000.0, 
                        existing_size / 1_000_000)));
                
                // Report initial progress
                let estimated_total = 36_872_000_000u64; // ~36.8GB
                let initial_progress = (existing_size as f32 / estimated_total as f32) * 100.0;
                progress_callback(initial_progress);
            } else if existing_size > 0 {
                // Small partial file, delete and start fresh
                fs::remove_file(&actual_snapshot_path).ok();
                log_info("Removing small partial download", 
                    Some(&format!("{}MB is too small", existing_size / 1_000_000)));
            }
        }
        
        // Download with resume support - very long timeout for large downloads
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(86400)) // 24 hour timeout for 30GB download
            .connect_timeout(std::time::Duration::from_secs(30)) // 30 second connection timeout
            .build()
            .map_err(|e| format!("Failed to create HTTP client: {}", e))?;
        
        let mut request = client.get(&snapshot_url);
        
        // Add Range header for resume
        if resume_from > 0 {
            request = request.header("Range", format!("bytes={}-", resume_from));
        }
        
        let response = request.send()
            .await
            .map_err(|e| format!("Failed to download snapshot: {}", e))?;
        
        // Check if server supports resume
        let status = response.status();
        if resume_from > 0 && status != reqwest::StatusCode::PARTIAL_CONTENT {
            log_warn("Server doesn't support resume, starting fresh download", None);
            resume_from = 0;
            fs::remove_file(&snapshot_path).ok();
        }
        
        let total_size = response.content_length()
            .map(|s| s + resume_from)
            .unwrap_or(30_000_000_000); // ~30GB
        
        // Open file for append if resuming, create if new
        let mut file = if resume_from > 0 {
            tokio::fs::OpenOptions::new()
                .append(true)
                .open(&actual_snapshot_path)
                .await
                .map_err(|e| format!("Failed to open snapshot file for resume: {}", e))?
        } else {
            tokio::fs::File::create(&actual_snapshot_path)
                .await
                .map_err(|e| format!("Failed to create snapshot file: {}", e))?
        };
        
        let mut downloaded = resume_from;
        let mut stream = response.bytes_stream();
        let mut last_checkpoint = downloaded;
        let checkpoint_interval = 100_000_000; // Save progress every 100MB
        
        use tokio::io::AsyncWriteExt;
        use futures_util::StreamExt;
        
        // Download with periodic checkpoints
        let start_time = std::time::Instant::now();
        let mut last_progress_time = std::time::Instant::now();
        
        while let Some(chunk_result) = stream.next().await {
            let chunk = match chunk_result {
                Ok(chunk) => chunk,
                Err(e) => {
                    // Save progress before failing
                    file.flush().await.ok();
                    log_warn("Download interrupted - will resume on retry", 
                        Some(&format!("Downloaded {:.1}GB so far. Error: {}", 
                            downloaded as f64 / 1_000_000_000.0, e)));
                    
                    return Err(format!(
                        "Download interrupted at {:.1}GB of {:.1}GB. Will resume on next attempt. Error: {}", 
                        downloaded as f64 / 1_000_000_000.0,
                        total_size as f64 / 1_000_000_000.0,
                        e
                    ));
                }
            };
            
            file.write_all(&chunk)
                .await
                .map_err(|e| format!("Write error: {}", e))?;
            
            downloaded += chunk.len() as u64;
            
            // Save checkpoint periodically
            if downloaded - last_checkpoint >= checkpoint_interval {
                file.flush().await.ok();
                last_checkpoint = downloaded;
                log_debug("Download checkpoint saved", 
                    Some(&format!("{:.1}GB of {:.1}GB", 
                        downloaded as f64 / 1_000_000_000.0, 
                        total_size as f64 / 1_000_000_000.0)));
            }
            
            // Report progress every 5 seconds to avoid UI spam
            if last_progress_time.elapsed() >= std::time::Duration::from_secs(5) {
                let progress = (downloaded as f32 / total_size as f32) * 100.0;
                let elapsed = start_time.elapsed().as_secs_f64();
                let mb_per_sec = ((downloaded - resume_from) as f64 / 1_000_000.0) / elapsed;
                let remaining_bytes = total_size - downloaded;
                let eta_seconds = (remaining_bytes as f64 / 1_000_000.0) / mb_per_sec;
                
                log_info("Download progress", 
                    Some(&format!("{:.1}% - {:.1}GB/{:.1}GB - {:.1} MB/s - ETA: {} min", 
                        progress,
                        downloaded as f64 / 1_000_000_000.0,
                        total_size as f64 / 1_000_000_000.0,
                        mb_per_sec,
                        (eta_seconds / 60.0) as u32)));
                
                progress_callback(progress);
                last_progress_time = std::time::Instant::now();
            }
        }
        
        // Final flush
        file.flush().await
            .map_err(|e| format!("Failed to flush file: {}", e))?;
        
        log_info("Download completed", 
            Some(&format!("Total: {}GB", downloaded / 1_000_000_000)));

        // Extract snapshot
        self.extract_snapshot(&actual_snapshot_path).await?;
        
        // Clean up
        fs::remove_file(&actual_snapshot_path).ok();
        
        Ok(())
    }

    async fn get_latest_snapshot_url(&self) -> Result<String, String> {
        let response = reqwest::get("https://backup.koinosblocks.com/")
            .await
            .map_err(|e| format!("Failed to fetch snapshot list: {}", e))?
            .text()
            .await
            .map_err(|e| format!("Failed to read snapshot list: {}", e))?;
        
        // Parse HTML to find latest backup file
        let re = regex::Regex::new(r"backup_\d{4}-\d{2}-\d{2}\.tar\.gz")
            .map_err(|e| format!("Regex error: {}", e))?;
        
        let mut snapshots: Vec<String> = re.find_iter(&response)
            .map(|m| m.as_str().to_string())
            .collect();
        
        snapshots.sort();
        
        let latest = snapshots.last()
            .ok_or_else(|| "No snapshots found".to_string())?;
        
        Ok(format!("https://backup.koinosblocks.com/{}", latest))
    }

    async fn extract_snapshot(&self, snapshot_path: &Path) -> Result<(), String> {
        log_info("Starting snapshot extraction", 
            Some(&format!("File: {}", snapshot_path.display())));
        
        let output = AsyncCommand::new("tar")
            .arg("-xzf")
            .arg(snapshot_path)
            .arg("-C")
            .arg(dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")))
            .output()
            .await
            .map_err(|e| format!("Failed to extract snapshot: {}", e))?;
        
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            log_error("Snapshot extraction failed", Some(&stderr));
            return Err(format!("Failed to extract snapshot: {}", stderr));
        }
        
        log_info("Snapshot extracted successfully", None);

        // Move extracted data to .koinos
        fs::create_dir_all(&self.data_path)
            .map_err(|e| format!("Failed to create data directory: {}", e))?;
        
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        log_info("Moving extracted directories to koinos data path", 
            Some(&format!("From: {} To: {}", home.display(), self.data_path.display())));
        
        for dir in &[
            "chain",
            "block_store",
            "account_history",
            "contract_meta_store",
            "transaction_store",
            "mempool",
            "p2p",
            "grpc",
            "jsonrpc",
        ] {
            let src = home.join(dir);
            let dst = self.data_path.join(dir);
            if src.exists() {
                log_debug("Moving directory", Some(&format!("{} -> {}", src.display(), dst.display())));
                
                // If destination exists, remove it first
                if dst.exists() {
                    fs::remove_dir_all(&dst).ok();
                }
                
                fs::rename(&src, &dst)
                    .map_err(|e| format!("Failed to move {}: {}", dir, e))?;
                log_info("Moved directory", Some(dir));
            } else {
                log_warn("Directory not found in extracted data", Some(dir));
            }
        }
        
        log_info("All blockchain data moved successfully", None);
        Ok(())
    }

    pub async fn resume_sync_if_needed(&self) -> Result<(), String> {
        // Load saved state to resume from last position
        let state_manager = self.state_manager.lock().unwrap();
        let saved_state = state_manager.get_state();
        
        if saved_state.last_block > 0 {
            log_info("Resuming sync from saved state", 
                Some(&format!("Block: {}, Progress: {:.2}%", 
                    saved_state.last_block, 
                    saved_state.last_sync_progress)));
            
            // Update current status with saved state
            let mut status = self.status.lock().unwrap();
            status.current_block = saved_state.last_block;
            status.sync_progress = saved_state.last_sync_progress;
            
            // If sync was incomplete, mark as syncing
            if !saved_state.first_sync_completed {
                status.status = "syncing".to_string();
            }
        }
        
        Ok(())
    }
    
    pub async fn start_node(&self) -> Result<(), String> {
        // Check if koinos directory exists
        if !self.koinos_path.exists() {
            return Err("Koinos not initialized. Please run setup first.".to_string());
        }

        // Check if docker-compose.yml exists
        if !self.koinos_path.join("docker-compose.yml").exists() {
            return Err("docker-compose.yml not found. Please run setup first.".to_string());
        }

        // Check if Docker daemon is running (resolve docker path robustly)
        if !self.docker_info_ok() {
            // Try to start Docker Desktop on macOS
            #[cfg(target_os = "macos")]
            {
                if std::path::Path::new("/Applications/Docker.app").exists() {
                    Command::new("open")
                        .arg("/Applications/Docker.app")
                        .spawn()
                        .ok();
                    
                    // Wait for Docker to start (up to 60 seconds)
                    log_info("Waiting for Docker Desktop to start...", None);
                    for i in 0..30 {
                        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                        
                        // Check Docker status
                        if let Some(docker) = self.find_docker_path() {
                            if let Ok(output) = Command::new(&docker).arg("info").output() {
                                if output.status.success() {
                                    log_info("Docker Desktop started successfully", None);
                                    break;
                                }
                                let stderr = String::from_utf8_lossy(&output.stderr);
                                if stderr.contains("Docker Desktop is starting") {
                                    log_debug(&format!("Docker Desktop still starting... ({}/30)", i + 1), None);
                                    continue;
                                }
                            }
                        }
                        
                        if i == 29 {
                            return Err("Docker Desktop is taking too long to start. Please ensure Docker is fully started and try again.".to_string());
                        }
                    }
                } else {
                    return Err("Docker is not running. Please start Docker Desktop and try again.".to_string());
                }
            }
            
            #[cfg(not(target_os = "macos"))]
            return Err("Docker daemon is not running. Please start Docker and try again.".to_string());
        }

        // Update status
        {
            let mut status = self.status.lock().unwrap();
            status.status = "starting".to_string();
        }

        // Start Docker containers using the 'all' profile with robust compose detection
        let (program, mut base_args) = self
            .compose_invocation()
            .ok_or_else(|| "Neither 'docker compose' nor 'docker-compose' is available".to_string())?;
        base_args.extend(vec!["--profile".into(), "all".into(), "up".into(), "-d".into()]);
        let output = AsyncCommand::new(program)
            .args(base_args)
            .current_dir(&self.koinos_path)
            .output()
            .await
            .map_err(|e| format!("Failed to start node: {}", e))?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Failed to start node: {}", error));
        }

        // Resume from saved checkpoint
        self.resume_sync_if_needed().await?;
        
        // Update status
        {
            let mut status = self.status.lock().unwrap();
            let state_manager = self.state_manager.lock().unwrap();
            let saved_state = state_manager.get_state();
            
            status.status = if saved_state.first_sync_completed {
                "running".to_string()
            } else {
                "syncing".to_string()
            };
            
            log_info("Node started", 
                Some(&format!("Resuming from block {}", saved_state.last_block)));
        }

        Ok(())
    }

    pub async fn stop_node(&self) -> Result<(), String> {
        let (program, mut base_args) = self
            .compose_invocation()
            .ok_or_else(|| "Neither 'docker compose' nor 'docker-compose' is available".to_string())?;
        base_args.extend(vec!["--profile".into(), "all".into(), "down".into()]);
        let output = AsyncCommand::new(program)
            .args(base_args)
            .current_dir(&self.koinos_path)
            .output()
            .await
            .map_err(|e| format!("Failed to stop node: {}", e))?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Failed to stop node: {}", error));
        }

        // Update status
        {
            let mut status = self.status.lock().unwrap();
            status.status = "stopped".to_string();
            status.sync_progress = 0.0;
            status.peers_count = 0;
        }

        Ok(())
    }

    pub async fn get_node_status(&self) -> NodeStatus {
        let mut status = self.status.lock().unwrap().clone();
        
        // Check if containers are actually running
        if status.status != "stopped" {
            let compose = self.compose_invocation();
            let check = if let Some((program, mut args)) = compose {
                args.extend(vec!["ps".into(), "--format".into(), "json".into()]);
                Command::new(program)
                    .args(args)
                    .current_dir(&self.koinos_path)
                    .output()
            } else {
                // Fallback attempt with default docker compose
                Command::new("docker")
                    .arg("compose")
                    .arg("ps")
                    .arg("--format")
                    .arg("json")
                    .current_dir(&self.koinos_path)
                    .output()
            };
            
            if let Ok(output) = check {
                if output.status.success() {
                    let output_str = String::from_utf8_lossy(&output.stdout);
                    // Check if koinos containers are running
                    if output_str.contains("koinos") && output_str.contains("running") {
                        // Try to get actual blockchain height from JSON-RPC
                        if let Ok(height) = self.get_blockchain_height().await {
                            status.current_block = height;
                            
                            // Get actual target height from Koinos mainnet API
                            let mut target_block = 43_000_000u64; // Fallback estimate
                            
                            // Try to get real mainnet height from Koinos API
                            if let Ok(mainnet_height) = self.get_mainnet_height().await {
                                target_block = mainnet_height;
                                log_debug(&format!("Got mainnet height from API: {}", mainnet_height), None);
                            } else {
                                // Fallback: Try to estimate from sync logs
                                if let Ok(logs_output) = AsyncCommand::new("docker")
                                    .arg("logs")
                                    .arg("--tail")
                                    .arg("5")
                                    .arg("koinos-chain-1")
                                    .output()
                                    .await
                                {
                                    let chain_logs = String::from_utf8_lossy(&logs_output.stdout);
                                    if let Some(line) = chain_logs.lines().filter(|l| l.contains("block time remaining")).last() {
                                        // Parse days remaining like "122d, 09h, 25m, 09s"
                                        if let Some(start) = line.find("(") {
                                            if let Some(end) = line.find("d,") {
                                                if let Ok(days) = line[start + 1..end].trim().parse::<f32>() {
                                                    // Koinos averages ~1000 blocks per day
                                                    let blocks_remaining = (days * 1000.0) as u64;
                                                    target_block = height + blocks_remaining;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            status.target_block = target_block;
                            
                            if height > 0 {
                                status.sync_progress = if status.target_block > 0 {
                                    ((height as f32 / status.target_block as f32) * 100.0).min(100.0)
                                } else {
                                    0.0
                                };
                                
                                status.status = if status.sync_progress >= 99.9 {
                                    "running".to_string()
                                } else {
                                    "syncing".to_string()
                                };
                            }
                            
                            // Save state
                            let mut state_manager = self.state_manager.lock().unwrap();
                            state_manager.update_sync_progress(height, status.sync_progress);
                        }
                    } else {
                        status.status = "stopped".to_string();
                    }
                } else {
                    // Docker compose command failed - likely containers not running
                    status.status = "stopped".to_string();
                }
            }
        }
        
        status
    }
    
    async fn get_mainnet_height(&self) -> Result<u64, String> {
        // Get current mainnet height from public Koinos API
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()
            .map_err(|e| format!("Failed to create HTTP client: {}", e))?;
        
        let body = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "chain.get_head_info",
            "params": {},
            "id": 1
        });
        
        let response = client
            .post("https://api.koinos.io")
            .header("Content-Type", "application/json")
            .body(body.to_string())
            .send()
            .await;
        
        if let Ok(resp) = response {
            if let Ok(text) = resp.text().await {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(result) = json.get("result") {
                        if let Some(head_topology) = result.get("head_topology") {
                            if let Some(height) = head_topology.get("height") {
                                if let Some(height_str) = height.as_str() {
                                    return height_str.parse::<u64>()
                                        .map_err(|e| format!("Failed to parse mainnet height: {}", e));
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Err("Failed to get mainnet height".to_string())
    }
    
    async fn get_blockchain_height(&self) -> Result<u64, String> {
        // Call Koinos JSON-RPC to get current height  
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(2))
            .build()
            .map_err(|e| format!("Failed to create HTTP client: {}", e))?;
        
        let body = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "chain.get_head_info",
            "params": {},
            "id": 1
        });
        
        let response = client
            .post("http://127.0.0.1:8080")
            .header("Content-Type", "application/json")
            .body(body.to_string())
            .send()
            .await;
        
        if let Ok(resp) = response {
            if let Ok(text) = resp.text().await {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                if let Some(result) = json.get("result") {
                    if let Some(head_topology) = result.get("head_topology") {
                        if let Some(height) = head_topology.get("height") {
                            if let Some(height_str) = height.as_str() {
                                return height_str.parse::<u64>()
                                    .map_err(|e| format!("Failed to parse height: {}", e));
                            }
                        }
                    }
                }
            }
            }
        }
        
        Err("Failed to get blockchain height".to_string())
    }

    pub async fn get_detailed_status(&self) -> Result<serde_json::Value, String> {
        // Run docker compose ps to get container status
        let ps_output = AsyncCommand::new("docker")
            .arg("compose")
            .arg("ps")
            .current_dir(&self.koinos_path)
            .output()
            .await
            .map_err(|e| format!("Failed to get container status: {}", e))?;
        
        let containers_status = String::from_utf8_lossy(&ps_output.stdout);
        
        // Get current block height from the node's JSON-RPC (same as main status)
        let mut current_block = 0u64;
        let mut sync_time_remaining = String::from("Unknown");
        
        // Try to get actual blockchain height from local node
        if let Ok(height) = self.get_blockchain_height().await {
            current_block = height;
        }
        
        // Get chain logs for sync time remaining
        let logs_output = AsyncCommand::new("docker")
            .arg("logs")
            .arg("--tail")
            .arg("10")
            .arg("koinos-chain-1")
            .output()
            .await
            .map_err(|e| format!("Failed to get chain logs: {}", e))?;
        
        let chain_logs = String::from_utf8_lossy(&logs_output.stdout);
        
        // Parse time remaining from logs
        for line in chain_logs.lines().rev() {
            if line.contains("Sync progress") && line.contains("block time remaining") {
                // Parse time remaining
                if let Some(start) = line.find("(") {
                    if let Some(end) = line.find(" block time remaining") {
                        sync_time_remaining = line[start + 1..end].to_string();
                        break;
                    }
                }
            }
        }
        
        // Check P2P peers
        let p2p_logs = AsyncCommand::new("docker")
            .arg("logs")
            .arg("--tail")
            .arg("20")
            .arg("koinos-p2p-1")
            .output()
            .await
            .map_err(|e| format!("Failed to get P2P logs: {}", e))?;
        
        let p2p_status = String::from_utf8_lossy(&p2p_logs.stdout);
        let peer_count = p2p_status.matches("Connected to peer").count();
        
        // Get disk usage
        let disk_usage = AsyncCommand::new("docker")
            .arg("exec")
            .arg("koinos-chain-1")
            .arg("du")
            .arg("-sh")
            .arg("/koinos")
            .output()
            .await
            .map_err(|e| format!("Failed to get disk usage: {}", e))?;
        
        let disk_size = String::from_utf8_lossy(&disk_usage.stdout);
        
        // Get mainnet height for comparison
        let mainnet_height = self.get_mainnet_height().await.unwrap_or(0);
        let sync_percentage = if mainnet_height > 0 && current_block > 0 {
            ((current_block as f32 / mainnet_height as f32) * 100.0).min(100.0)
        } else {
            0.0
        };
        
        // Check each container status individually using docker ps
        let services = vec![
            "chain", "p2p", "block_store", "mempool", "jsonrpc", "grpc", "rest",
            "account_history", "transaction_store", "contract_meta_store", "block_producer", "amqp"
        ];
        
        // Get actual running containers
        let running_containers = AsyncCommand::new("docker")
            .arg("ps")
            .arg("--format")
            .arg("{{.Names}}")
            .output()
            .await
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();
        
        let mut container_statuses = serde_json::Map::new();
        for service in services {
            let container_name = format!("koinos-{}-1", service);
            let is_running = running_containers.contains(&container_name);
            container_statuses.insert(service.to_string(), serde_json::Value::Bool(is_running));
        }
        
        // Check network ports
        let jsonrpc_available = AsyncCommand::new("nc")
            .arg("-z")
            .arg("localhost")
            .arg("8080")
            .output()
            .await
            .map(|o| o.status.success())
            .unwrap_or(false);
        
        let grpc_available = AsyncCommand::new("nc")
            .arg("-z")
            .arg("localhost")
            .arg("50051")
            .output()
            .await
            .map(|o| o.status.success())
            .unwrap_or(false);
        
        let p2p_available = AsyncCommand::new("nc")
            .arg("-z")
            .arg("localhost")
            .arg("8888")
            .output()
            .await
            .map(|o| o.status.success())
            .unwrap_or(false);
        
        // Get recent errors
        let error_logs = AsyncCommand::new("docker")
            .arg("compose")
            .arg("logs")
            .arg("--tail")
            .arg("100")
            .current_dir(&self.koinos_path)
            .output()
            .await
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();
        
        let error_count = error_logs.matches("error").count();
        let last_error = error_logs
            .lines()
            .filter(|l| l.to_lowercase().contains("error"))
            .last()
            .unwrap_or("No recent errors")
            .to_string();
        
        // Build comprehensive status report as JSON
        let status_report = serde_json::json!({
            "containers": container_statuses,
            "sync": {
                "current_block": current_block,
                "target_block": mainnet_height,
                "percentage": sync_percentage,
                "time_remaining": sync_time_remaining,
            },
            "network": {
                "connected_peers": peer_count,
                "jsonrpc_available": jsonrpc_available,
                "grpc_available": grpc_available,
                "p2p_available": p2p_available,
            },
            "disk": {
                "blockchain_size": disk_size.trim(),
            },
            "activity": {
                "error_count": error_count,
                "last_error": last_error,
            },
        });
        
        Ok(status_report)
    }

    pub async fn get_resource_usage(&self) -> Result<ResourceUsage, String> {
        let mem_info = sys_info::mem_info().map_err(|e| e.to_string())?;
        let load_avg = sys_info::loadavg().map_err(|e| e.to_string())?;
        
        let disk_usage = fs2::available_space(&self.data_path)
            .unwrap_or(0) / (1024 * 1024 * 1024);
        
        let total_disk = fs2::total_space(&self.data_path)
            .unwrap_or(0) / (1024 * 1024 * 1024);

        Ok(ResourceUsage {
            // Approximate CPU % normalized by number of cores
            cpu_percent: {
                let cores = num_cpus::get() as f64;
                let val = (load_avg.one / cores) * 100.0;
                val.clamp(0.0, 100.0) as f32
            },
            memory_mb: ((mem_info.total - mem_info.avail) / 1024) as u32,
            memory_total_mb: (mem_info.total / 1024) as u32,
            disk_used_gb: (total_disk - disk_usage) as f32,
            disk_total_gb: total_disk as f32,
        })
    }
}
