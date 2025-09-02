use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tokio::process::Command as AsyncCommand;
use reqwest;
use futures_util::StreamExt;

pub struct NativeInstaller {
    koinos_path: PathBuf,
    data_path: PathBuf,
}

impl NativeInstaller {
    pub fn new() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let koinos_path = home.join(".koinos-node");
        let data_path = koinos_path.join("data");
        
        Self {
            koinos_path,
            data_path,
        }
    }
    
    /// Download pre-compiled Koinos binaries instead of using Docker
    pub async fn install_native_binaries(&self, progress_callback: impl Fn(f32)) -> Result<(), String> {
        // Create directories
        fs::create_dir_all(&self.koinos_path)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
        fs::create_dir_all(&self.data_path)
            .map_err(|e| format!("Failed to create data directory: {}", e))?;
        
        progress_callback(10.0);
        
        // Download Koinos binaries for macOS
        #[cfg(target_os = "macos")]
        {
            let urls = vec![
                ("koinos_chain", "https://github.com/koinos/koinos-chain/releases/latest/download/koinos_chain-macos-arm64"),
                ("koinos_p2p", "https://github.com/koinos/koinos-p2p/releases/latest/download/koinos_p2p-macos-arm64"),
                ("koinos_jsonrpc", "https://github.com/koinos/koinos-jsonrpc/releases/latest/download/koinos_jsonrpc-macos-arm64"),
                ("koinos_block_store", "https://github.com/koinos/koinos-block-store/releases/latest/download/koinos_block_store-macos-arm64"),
            ];
            
            let total = urls.len() as f32;
            for (index, (name, url)) in urls.iter().enumerate() {
                let binary_path = self.koinos_path.join(name);
                
                // Download binary
                self.download_file(url, &binary_path).await
                    .map_err(|e| format!("Failed to download {}: {}", name, e))?;
                
                // Make executable
                Command::new("chmod")
                    .arg("+x")
                    .arg(&binary_path)
                    .output()
                    .map_err(|e| format!("Failed to make {} executable: {}", name, e))?;
                
                let progress = 10.0 + ((index + 1) as f32 / total * 30.0);
                progress_callback(progress);
            }
        }
        
        progress_callback(40.0);
        
        // Download configuration files
        self.download_configs().await?;
        progress_callback(50.0);
        
        Ok(())
    }
    
    async fn download_file(&self, url: &str, dest: &Path) -> Result<(), String> {
        // Skip if already exists
        if dest.exists() {
            return Ok(());
        }
        
        let response = reqwest::get(url)
            .await
            .map_err(|e| format!("Failed to download: {}", e))?;
        
        if !response.status().is_success() {
            return Err(format!("Download failed with status: {}", response.status()));
        }
        
        let content = response.bytes()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;
        
        fs::write(dest, content)
            .map_err(|e| format!("Failed to write file: {}", e))?;
        
        Ok(())
    }
    
    async fn download_configs(&self) -> Result<(), String> {
        // Create basic config files
        let config_dir = self.koinos_path.join("config");
        fs::create_dir_all(&config_dir)
            .map_err(|e| format!("Failed to create config directory: {}", e))?;
        
        // Chain config
        let chain_config = r#"{
  "amqp": "amqp://guest:guest@127.0.0.1:5672/",
  "fork_algorithm": "pob",
  "block_store": "127.0.0.1:8080",
  "data_dir": "./data/chain",
  "initial_height": 0,
  "checkpoint_interval": 10000
}"#;
        fs::write(config_dir.join("chain.json"), chain_config)
            .map_err(|e| format!("Failed to write chain config: {}", e))?;
        
        // P2P config
        let p2p_config = r#"{
  "amqp": "amqp://guest:guest@127.0.0.1:5672/",
  "tcp_port": 8888,
  "seed_peers": [
    "13.236.140.170:8888",
    "35.161.211.35:8888",
    "34.219.87.158:8888",
    "18.188.78.64:8888",
    "3.8.187.216:8888"
  ]
}"#;
        fs::write(config_dir.join("p2p.json"), p2p_config)
            .map_err(|e| format!("Failed to write p2p config: {}", e))?;
        
        // JSONRPC config
        let jsonrpc_config = r#"{
  "amqp": "amqp://guest:guest@127.0.0.1:5672/",
  "http_port": 8080,
  "endpoint": "127.0.0.1:8080"
}"#;
        fs::write(config_dir.join("jsonrpc.json"), jsonrpc_config)
            .map_err(|e| format!("Failed to write jsonrpc config: {}", e))?;
        
        Ok(())
    }
    
    /// Download blockchain snapshot
    pub async fn download_snapshot(&self, progress_callback: impl Fn(f32)) -> Result<(), String> {
        // Check if data already exists
        if self.data_path.join("chain").exists() {
            progress_callback(100.0);
            return Ok(());
        }
        
        // Download snapshot (simplified version - in reality would download from backup.koinosblocks.com)
        let snapshot_url = "https://backup.koinosblocks.com/latest.tar.gz";
        let snapshot_path = self.koinos_path.join("snapshot.tar.gz");
        
        // For now, just create empty data directories
        fs::create_dir_all(self.data_path.join("chain"))
            .map_err(|e| format!("Failed to create chain directory: {}", e))?;
        fs::create_dir_all(self.data_path.join("block_store"))
            .map_err(|e| format!("Failed to create block_store directory: {}", e))?;
        
        progress_callback(100.0);
        Ok(())
    }
    
    /// Start the node using native binaries
    pub async fn start_node(&self) -> Result<(), String> {
        // Start each service
        let services = vec![
            ("koinos_block_store", vec!["--config", "config/block_store.json"]),
            ("koinos_chain", vec!["--config", "config/chain.json"]),
            ("koinos_p2p", vec!["--config", "config/p2p.json"]),
            ("koinos_jsonrpc", vec!["--config", "config/jsonrpc.json"]),
        ];
        
        for (service, args) in services {
            let binary = self.koinos_path.join(service);
            if !binary.exists() {
                return Err(format!("{} not found. Please run setup first.", service));
            }
            
            AsyncCommand::new(&binary)
                .args(&args)
                .current_dir(&self.koinos_path)
                .spawn()
                .map_err(|e| format!("Failed to start {}: {}", service, e))?;
        }
        
        Ok(())
    }
    
    /// Stop all node processes
    pub async fn stop_node(&self) -> Result<(), String> {
        // Kill all koinos processes
        let _ = Command::new("pkill")
            .arg("-f")
            .arg("koinos_")
            .output();
        
        Ok(())
    }
    
    /// Check if node is running
    pub fn is_running(&self) -> bool {
        Command::new("pgrep")
            .arg("-f")
            .arg("koinos_chain")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
}