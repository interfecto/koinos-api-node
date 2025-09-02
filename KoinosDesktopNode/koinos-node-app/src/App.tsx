import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import WelcomeScreen from "./components/WelcomeScreen";
import Dashboard from "./components/Dashboard";
import InitializationProgress from "./components/InitializationProgress";
import DebugConsole from "./components/DebugConsole";
import StatusModal from "./components/StatusModal";
import { NodeStatus } from "./components/StatusIndicator";

interface BackendNodeStatus {
  status: string;
  sync_progress: number;
  current_block: number;
  target_block: number;
  peers_count: number;
  error_message?: string;
}

interface ResourceUsage {
  cpu_percent: number;
  memory_mb: number;
  memory_total_mb: number;
  disk_used_gb: number;
  disk_total_gb: number;
}

const APP_VERSION = '0.4.0';

function App() {
  const [showWelcome, setShowWelcome] = useState(true);
  const [nodeStatus, setNodeStatus] = useState<NodeStatus>('stopped');
  const [syncProgress, setSyncProgress] = useState(0);
  const [currentBlock, setCurrentBlock] = useState(0);
  const [targetBlock, setTargetBlock] = useState(0);
  const [peersCount, setPeersCount] = useState(0);
  const [resourceUsage, setResourceUsage] = useState<ResourceUsage | null>(null);
  const [isInitializing, setIsInitializing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [initStep, setInitStep] = useState<string>('');
  const [initProgress, setInitProgress] = useState(0);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [downloadSpeed, setDownloadSpeed] = useState<string>('');
  const [estimatedTime, setEstimatedTime] = useState<string>('');
  const [showDebugConsole, setShowDebugConsole] = useState(false);
  const [showStatusModal, setShowStatusModal] = useState(false);
  const [statusData, setStatusData] = useState<any>(null);

  useEffect(() => {
    // Check if this is first launch AND if setup is complete
    const checkInitialization = async () => {
      const hasLaunched = localStorage.getItem('koinos-node-launched');
      if (hasLaunched) {
        // Verify that the node is actually set up
        try {
          const initialized = await invoke<boolean>('is_initialized');
          if (initialized) {
            setShowWelcome(false);
          } else {
            // Clear the flag if setup is incomplete
            console.log('Node not initialized, showing welcome screen');
            localStorage.removeItem('koinos-node-launched');
          }
        } catch (err) {
          console.log('Setup check failed, showing welcome screen');
          localStorage.removeItem('koinos-node-launched');
        }
      }
    };
    
    checkInitialization();

    // Listen for node status updates from backend
    const unsubscribeStatus = listen<BackendNodeStatus>('node_status_update', (event) => {
      const status = event.payload;
      setNodeStatus(status.status as NodeStatus);
      setSyncProgress(status.sync_progress);
      setCurrentBlock(status.current_block);
      setTargetBlock(status.target_block);
      setPeersCount(status.peers_count);
      
      if (status.error_message) {
        setError(status.error_message);
      }
    });

    // Listen for download progress
    const unsubscribeDownload = listen<number>('download_progress', (event) => {
      const progress = event.payload;
      setDownloadProgress(progress);
      
      // Calculate download speed (mock for now)
      const mbPerSec = 5 + Math.random() * 10;
      setDownloadSpeed(`${mbPerSec.toFixed(1)} MB/s`);
      
      // Calculate estimated time
      const remainingGB = 30 * (1 - progress / 100);
      const remainingSeconds = (remainingGB * 1024) / mbPerSec;
      const minutes = Math.floor(remainingSeconds / 60);
      const hours = Math.floor(minutes / 60);
      
      if (hours > 0) {
        setEstimatedTime(`${hours}h ${minutes % 60}m`);
      } else {
        setEstimatedTime(`${minutes}m`);
      }
    });

    // Get initial status
    invoke<BackendNodeStatus>('get_node_status')
      .then((status) => {
        setNodeStatus(status.status as NodeStatus);
        setSyncProgress(status.sync_progress);
        setCurrentBlock(status.current_block);
        setTargetBlock(status.target_block);
        setPeersCount(status.peers_count);
      })
      .catch(err => {
        console.error('Failed to get initial status:', err);
        setError('Failed to connect to backend');
      });

    // Update resource usage periodically
    const resourceInterval = setInterval(() => {
      invoke<ResourceUsage>('get_resource_usage')
        .then(setResourceUsage)
        .catch(err => console.error('Failed to get resource usage:', err));
    }, 5000);

    return () => {
      unsubscribeStatus.then(fn => fn());
      unsubscribeDownload.then(fn => fn());
      clearInterval(resourceInterval);
    };
  }, []);

  const handleGetStarted = async () => {
    setIsInitializing(true);
    setError(null);
    setInitProgress(0);
    
    try {
      // Step 1: Check and auto-install requirements
      setInitStep('requirements');
      setInitProgress(5);
      
      const requirements = await invoke<any>('check_system_requirements');
      
      if (!requirements.is_sufficient) {
        // Automatically install missing requirements
        setInitProgress(10);
        console.log('Installing missing requirements...');
        
        try {
          const installResult = await invoke<string>('auto_install_requirements');
          console.log('Installation result:', installResult);
          
          // Check if the message indicates manual action needed
          if (installResult.includes('Terminal') || installResult.includes('manually')) {
            setError(installResult);
            setIsInitializing(false);
            // Show a retry button by setting a special flag
            return;
          }
          
          // Wait a bit for services to start
          await new Promise(resolve => setTimeout(resolve, 3000));
          
          // Re-check requirements
          const newRequirements = await invoke<any>('check_system_requirements');
          if (!newRequirements.is_sufficient) {
            setError(`Some requirements could not be installed automatically: ${newRequirements.missing_requirements.join(', ')}`);
            setIsInitializing(false);
            return;
          }
        } catch (installErr) {
          const errorMsg = installErr as string;
          console.error('Auto-install failed:', errorMsg);
          
          // If it's a guided error message, show it as-is
          if (errorMsg.includes('Please') || errorMsg.includes('Terminal')) {
            setError(errorMsg);
          } else {
            setError(`Failed to install requirements: ${errorMsg}`);
          }
          setIsInitializing(false);
          return;
        }
      }
      setInitProgress(25);

      // Step 2: Setup Docker
      setInitStep('docker');
      await invoke('setup_node');
      setInitProgress(40);
      
      // Step 3: Download snapshot if needed
      const hasSnapshot = currentBlock > 0;
      if (!hasSnapshot) {
        setInitStep('download');
        setInitProgress(50);
        await invoke('download_snapshot');
      }
      setInitProgress(90);
      
      // Step 4: Finalize
      setInitStep('finalize');
      localStorage.setItem('koinos-node-launched', 'true');
      setInitProgress(100);
      
      // Wait a moment for the progress to show 100%
      await new Promise(resolve => setTimeout(resolve, 500));
      setShowWelcome(false);
      
      // Automatically start the node after successful setup
      console.log('Setup complete, starting node...');
      try {
        await invoke('start_node');
        console.log('Node started successfully');
      } catch (startErr) {
        console.error('Failed to auto-start node:', startErr);
        // Don't show error here, let the Dashboard handle it
      }
    } catch (err) {
      setError(err as string);
      console.error('Initialization error:', err);
    } finally {
      setIsInitializing(false);
    }
  };

  const handleStartNode = async () => {
    try {
      setError(null);
      await invoke('start_node');
    } catch (err) {
      const errorMsg = err as string;
      setError(errorMsg);
      console.error('Failed to start node:', errorMsg);
      
      // If not initialized, prompt to go through setup
      if (errorMsg.includes('not initialized') || errorMsg.includes('Please run setup')) {
        const shouldReset = window.confirm('Node is not initialized. Would you like to run the setup process?');
        if (shouldReset) {
          localStorage.removeItem('koinos-node-launched');
          setShowWelcome(true);
        }
      }
    }
  };

  const handleStopNode = async () => {
    try {
      setError(null);
      await invoke('stop_node');
    } catch (err) {
      setError(err as string);
      console.error('Failed to stop node:', err);
    }
  };

  const handleRestartNode = async () => {
    try {
      setError(null);
      await invoke('restart_node');
    } catch (err) {
      setError(err as string);
      console.error('Failed to restart node:', err);
    }
  };

  const handleShowStatus = async () => {
    try {
      setStatusData(null); // Clear old data to show loading
      setShowStatusModal(true);
      const status = await invoke<any>('get_detailed_status');
      setStatusData(status);
    } catch (err) {
      console.error('Failed to get status:', err);
      setStatusData(null);
    }
  };

  if (showWelcome) {
    return (
      <div>
        <WelcomeScreen onGetStarted={handleGetStarted} />
        {isInitializing && (
          <InitializationProgress
            currentStep={initStep}
            overallProgress={initProgress}
            downloadProgress={downloadProgress}
            downloadSpeed={downloadSpeed}
            estimatedTime={estimatedTime}
            steps={[
              {
                id: 'requirements',
                label: 'Installing system requirements',
                status: initStep === 'requirements' ? 'active' : 
                        initProgress > 25 ? 'completed' : 'pending',
                progress: initStep === 'requirements' ? Math.min(100, initProgress * 4) : undefined,
                details: 'Auto-installing Docker if needed'
              },
              {
                id: 'docker',
                label: 'Setting up Docker containers',
                status: initStep === 'docker' ? 'active' : 
                        initProgress > 40 ? 'completed' : 'pending',
                progress: initStep === 'docker' ? 100 : undefined,
                details: 'Creating Koinos node containers'
              },
              {
                id: 'download',
                label: 'Downloading blockchain snapshot',
                status: initStep === 'download' ? 'active' : 
                        initProgress > 90 ? 'completed' : 'pending',
                progress: initStep === 'download' ? downloadProgress : undefined,
                details: 'Downloading ~30GB blockchain data'
              },
              {
                id: 'finalize',
                label: 'Finalizing setup',
                status: initStep === 'finalize' ? 'active' : 
                        initProgress === 100 ? 'completed' : 'pending',
                progress: initStep === 'finalize' ? 100 : undefined,
                details: 'Preparing node for first start'
              }
            ]}
          />
        )}
        {error && (
          <div className="fixed bottom-4 right-4 bg-red-500/20 border border-red-500 text-red-400 p-4 rounded-lg max-w-md">
            <p className="font-semibold">Action Required</p>
            <p className="text-sm whitespace-pre-line">{error}</p>
            {error.includes('Check Again') && (
              <button 
                onClick={handleGetStarted}
                className="mt-3 w-full btn-primary text-sm"
              >
                Check Again
              </button>
            )}
          </div>
        )}
      </div>
    );
  }

  return (
    <>
      {/* Version Display */}
      <div className="fixed top-4 right-4 text-xs text-gray-500 font-mono z-40">
        v{APP_VERSION}
      </div>
      
      {/* Debug Console Toggle Button */}
      <button
        onClick={() => setShowDebugConsole(!showDebugConsole)}
        className="fixed bottom-4 left-4 px-3 py-2 bg-gray-800 text-gray-400 rounded-lg hover:bg-gray-700 text-xs font-mono z-40"
      >
        {showDebugConsole ? 'Hide' : 'Show'} Debug Console
      </button>
      
      <Dashboard
        nodeStatus={nodeStatus}
        syncProgress={syncProgress}
        currentBlock={currentBlock}
        targetBlock={targetBlock}
        peersCount={peersCount}
        onStartNode={handleStartNode}
        onStopNode={handleStopNode}
        onRestartNode={handleRestartNode}
        onShowStatus={handleShowStatus}
        resourceUsage={resourceUsage || undefined}
      />
      {error && (
        <div className="fixed bottom-4 right-4 bg-red-500/20 border border-red-500 text-red-400 p-4 rounded-lg max-w-md z-50">
          <p className="font-semibold">Error</p>
          <p className="text-sm">{error}</p>
        </div>
      )}
      
      <DebugConsole 
        isOpen={showDebugConsole} 
        onClose={() => setShowDebugConsole(false)} 
      />
      
      <StatusModal
        isOpen={showStatusModal}
        onClose={() => setShowStatusModal(false)}
        statusData={statusData}
      />
    </>
  );
}

export default App;