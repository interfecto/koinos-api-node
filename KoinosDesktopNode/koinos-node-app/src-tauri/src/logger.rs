use std::sync::Mutex;
use chrono::Local;
use serde::{Deserialize, Serialize};
use tauri::{Emitter, Window};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub timestamp: String,
    pub level: String,
    pub message: String,
    pub details: Option<String>,
}

pub struct Logger {
    entries: Mutex<Vec<LogEntry>>,
    window: Option<Window>,
}

impl Logger {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(Vec::new()),
            window: None,
        }
    }
    
    pub fn set_window(&mut self, window: Window) {
        self.window = Some(window);
    }
    
    pub fn log(&self, level: &str, message: &str, details: Option<&str>) {
        let entry = LogEntry {
            timestamp: Local::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string(),
            level: level.to_string(),
            message: message.to_string(),
            details: details.map(|s| s.to_string()),
        };
        
        // Print to console
        println!("[{}] [{}] {} {}", 
            entry.timestamp, 
            entry.level, 
            entry.message,
            entry.details.as_ref().map(|d| format!("- {}", d)).unwrap_or_default()
        );
        
        // Store in memory
        if let Ok(mut entries) = self.entries.lock() {
            entries.push(entry.clone());
            
            // Keep only last 1000 entries
            if entries.len() > 1000 {
                let drain_count = entries.len() - 1000;
                entries.drain(0..drain_count);
            }
        }
        
        // Emit to frontend
        if let Some(window) = &self.window {
            window.emit("log_entry", &entry).ok();
        }
    }
    
    pub fn debug(&self, message: &str, details: Option<&str>) {
        self.log("DEBUG", message, details);
    }
    
    pub fn info(&self, message: &str, details: Option<&str>) {
        self.log("INFO", message, details);
    }
    
    pub fn warn(&self, message: &str, details: Option<&str>) {
        self.log("WARN", message, details);
    }
    
    pub fn error(&self, message: &str, details: Option<&str>) {
        self.log("ERROR", message, details);
    }
    
    pub fn get_logs(&self) -> Vec<LogEntry> {
        self.entries.lock().unwrap_or_else(|_| panic!("Failed to lock entries")).clone()
    }
    
    pub fn clear_logs(&self) {
        if let Ok(mut entries) = self.entries.lock() {
            entries.clear();
        }
    }
}

// Global logger instance
lazy_static::lazy_static! {
    pub static ref LOGGER: Mutex<Logger> = Mutex::new(Logger::new());
}

pub fn log_debug(message: &str, details: Option<&str>) {
    if let Ok(logger) = LOGGER.lock() {
        logger.debug(message, details);
    }
}

pub fn log_info(message: &str, details: Option<&str>) {
    if let Ok(logger) = LOGGER.lock() {
        logger.info(message, details);
    }
}

pub fn log_warn(message: &str, details: Option<&str>) {
    if let Ok(logger) = LOGGER.lock() {
        logger.warn(message, details);
    }
}

pub fn log_error(message: &str, details: Option<&str>) {
    if let Ok(logger) = LOGGER.lock() {
        logger.error(message, details);
    }
}