use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeState {
    pub last_block: u64,
    pub last_sync_progress: f32,
    pub total_uptime_seconds: u64,
    pub blocks_validated: u64,
    pub data_relayed_gb: f32,
    pub first_sync_completed: bool,
    pub install_date: String,
    pub last_run_date: String,
}

impl Default for NodeState {
    fn default() -> Self {
        Self {
            last_block: 0,
            last_sync_progress: 0.0,
            total_uptime_seconds: 0,
            blocks_validated: 0,
            data_relayed_gb: 0.0,
            first_sync_completed: false,
            install_date: chrono::Local::now().to_rfc3339(),
            last_run_date: chrono::Local::now().to_rfc3339(),
        }
    }
}

pub struct StateManager {
    state_path: PathBuf,
    state: NodeState,
}

impl StateManager {
    pub fn new() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let state_path = home.join(".koinos").join("node_state.json");
        
        let state = if state_path.exists() {
            fs::read_to_string(&state_path)
                .ok()
                .and_then(|content| serde_json::from_str(&content).ok())
                .unwrap_or_default()
        } else {
            NodeState::default()
        };

        Self { state_path, state }
    }

    pub fn load(&mut self) -> Result<NodeState, String> {
        if self.state_path.exists() {
            let content = fs::read_to_string(&self.state_path)
                .map_err(|e| format!("Failed to read state file: {}", e))?;
            
            self.state = serde_json::from_str(&content)
                .map_err(|e| format!("Failed to parse state file: {}", e))?;
        }
        
        Ok(self.state.clone())
    }

    pub fn save(&self) -> Result<(), String> {
        // Ensure directory exists
        if let Some(parent) = self.state_path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create state directory: {}", e))?;
        }

        let json = serde_json::to_string_pretty(&self.state)
            .map_err(|e| format!("Failed to serialize state: {}", e))?;
        
        fs::write(&self.state_path, json)
            .map_err(|e| format!("Failed to write state file: {}", e))?;
        
        Ok(())
    }

    pub fn update_sync_progress(&mut self, block: u64, progress: f32) {
        let previous_block = self.state.last_block;
        let previous_progress = self.state.last_sync_progress;
        
        self.state.last_block = block;
        self.state.last_sync_progress = progress;
        self.state.last_run_date = chrono::Local::now().to_rfc3339();
        
        if progress >= 100.0 && !self.state.first_sync_completed {
            self.state.first_sync_completed = true;
        }
        
        // Save checkpoint every 100 blocks or 1% progress change
        let block_diff = if block > previous_block { 
            block - previous_block 
        } else { 
            0 
        };
        let progress_diff = (progress - previous_progress).abs();
        
        if block_diff >= 100 || progress_diff >= 1.0 {
            let _ = self.save();
        }
    }

    pub fn increment_uptime(&mut self, seconds: u64) {
        self.state.total_uptime_seconds += seconds;
        let _ = self.save();
    }

    pub fn increment_blocks_validated(&mut self, count: u64) {
        self.state.blocks_validated += count;
        let _ = self.save();
    }

    pub fn add_data_relayed(&mut self, gb: f32) {
        self.state.data_relayed_gb += gb;
        let _ = self.save();
    }

    pub fn get_state(&self) -> &NodeState {
        &self.state
    }

    pub fn get_formatted_uptime(&self) -> String {
        let total_seconds = self.state.total_uptime_seconds;
        let days = total_seconds / 86400;
        let hours = (total_seconds % 86400) / 3600;
        let minutes = (total_seconds % 3600) / 60;
        
        if days > 0 {
            format!("{}d {}h {}m", days, hours, minutes)
        } else if hours > 0 {
            format!("{}h {}m", hours, minutes)
        } else {
            format!("{}m", minutes)
        }
    }
}