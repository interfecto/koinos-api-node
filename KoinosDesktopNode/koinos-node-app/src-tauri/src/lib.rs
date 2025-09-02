mod node_manager;
mod state_manager;
mod auto_installer;
mod logger;

use node_manager::{NodeManager, NodeStatus, SystemRequirements, ResourceUsage};
use auto_installer::AutoInstaller;
use std::sync::Arc;
use tauri::{Emitter, Manager, State};
use tokio::sync::Mutex;

struct AppState {
    node_manager: Arc<Mutex<NodeManager>>,
}

#[tauri::command]
async fn is_initialized(state: State<'_, AppState>) -> Result<bool, String> {
    let manager = state.node_manager.lock().await;
    Ok(manager.is_initialized())
}

#[tauri::command]
async fn check_system_requirements(state: State<'_, AppState>) -> Result<SystemRequirements, String> {
    let manager = state.node_manager.lock().await;
    manager.check_system_requirements().await
}

#[tauri::command]
async fn install_docker(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    manager.install_docker().await
}

#[tauri::command]
async fn auto_install_requirements() -> Result<String, String> {
    AutoInstaller::install_all_requirements().await
}

#[tauri::command]
async fn setup_node(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    manager.setup_koinos().await
}

#[tauri::command]
async fn download_snapshot(
    state: State<'_, AppState>,
    window: tauri::Window,
) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    
    manager.download_snapshot(move |progress| {
        window.emit("download_progress", progress).ok();
    }).await
}

#[tauri::command]
async fn start_node(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    manager.start_node().await
}

#[tauri::command]
async fn stop_node(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    manager.stop_node().await
}

#[tauri::command]
async fn restart_node(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    manager.stop_node().await?;
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    manager.start_node().await
}

#[tauri::command]
async fn get_node_status(state: State<'_, AppState>) -> Result<NodeStatus, String> {
    let manager = state.node_manager.lock().await;
    Ok(manager.get_node_status().await)
}

#[tauri::command]
async fn get_logs() -> Result<Vec<logger::LogEntry>, String> {
    if let Ok(logger) = logger::LOGGER.lock() {
        Ok(logger.get_logs())
    } else {
        Err("Failed to access logger".to_string())
    }
}

#[tauri::command]
async fn clear_logs() -> Result<(), String> {
    if let Ok(logger) = logger::LOGGER.lock() {
        logger.clear_logs();
        Ok(())
    } else {
        Err("Failed to access logger".to_string())
    }
}

#[tauri::command]
async fn get_resource_usage(state: State<'_, AppState>) -> Result<ResourceUsage, String> {
    let manager = state.node_manager.lock().await;
    manager.get_resource_usage().await
}

#[tauri::command]
async fn check_docker_installed() -> Result<bool, String> {
    let output = std::process::Command::new("docker")
        .arg("--version")
        .output();
    
    Ok(output.is_ok())
}

#[tauri::command]
async fn get_detailed_status(state: State<'_, AppState>) -> Result<serde_json::Value, String> {
    let manager = state.node_manager.lock().await;
    manager.get_detailed_status().await
}

#[tauri::command]
async fn open_logs_folder(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.node_manager.lock().await;
    let logs_path = manager.koinos_path.join("logs");
    
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(logs_path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(logs_path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(logs_path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let node_manager = Arc::new(Mutex::new(NodeManager::new()));
            
            app.manage(AppState {
                node_manager: node_manager.clone(),
            });
            
            // Start background task to monitor node status
            let app_handle = app.handle().clone();
            let manager = node_manager.clone();
            
            tauri::async_runtime::spawn(async move {
                loop {
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                    
                    let manager = manager.lock().await;
                    let status = manager.get_node_status().await;
                    
                    // Emit status update to frontend
                    app_handle.emit("node_status_update", &status).ok();
                }
            });
            
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            is_initialized,
            check_system_requirements,
            install_docker,
            auto_install_requirements,
            setup_node,
            download_snapshot,
            start_node,
            stop_node,
            restart_node,
            get_node_status,
            get_resource_usage,
            check_docker_installed,
            get_detailed_status,
            open_logs_folder,
            get_logs,
            clear_logs,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}