import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, CheckCircle, XCircle, AlertCircle, HardDrive, Wifi, Server, Activity, RefreshCw } from 'lucide-react';
import { invoke } from '@tauri-apps/api/core';

interface StatusData {
  containers: { [key: string]: boolean };
  sync: {
    current_block: number;
    target_block: number;
    percentage: number;
    time_remaining: string;
  };
  network: {
    connected_peers: number;
    jsonrpc_available: boolean;
    grpc_available: boolean;
    p2p_available: boolean;
  };
  disk: {
    blockchain_size: string;
  };
  activity: {
    error_count: number;
    last_error: string;
  };
}

interface StatusModalProps {
  isOpen: boolean;
  onClose: () => void;
  statusData: StatusData | null;
}

const StatusModal: React.FC<StatusModalProps> = ({ isOpen, onClose, statusData: initialData }) => {
  const [statusData, setStatusData] = useState<StatusData | null>(initialData);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const formatNumber = (num: number) => num.toLocaleString();

  // Update local state when prop changes
  useEffect(() => {
    setStatusData(initialData);
  }, [initialData]);

  // Auto-refresh every 10 seconds while modal is open
  useEffect(() => {
    if (!isOpen) return;
    
    const refreshStatus = async () => {
      try {
        const status = await invoke<any>('get_detailed_status');
        setStatusData(status);
      } catch (err) {
        console.error('Failed to refresh status:', err);
      }
    };

    const interval = setInterval(refreshStatus, 10000);
    return () => clearInterval(interval);
  }, [isOpen]);

  const handleManualRefresh = async () => {
    setIsRefreshing(true);
    try {
      const status = await invoke<any>('get_detailed_status');
      setStatusData(status);
    } catch (err) {
      console.error('Failed to refresh status:', err);
    } finally {
      setTimeout(() => setIsRefreshing(false), 500);
    }
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50"
            onClick={onClose}
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.9, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20 }}
            className="fixed inset-x-4 top-[5%] md:inset-x-auto md:left-1/2 md:-translate-x-1/2 md:w-[700px] max-h-[90vh] bg-koinos-dark-900 rounded-xl shadow-xl z-50 overflow-hidden"
          >
            {/* Header */}
            <div className="bg-gradient-to-r from-koinos-purple-600/20 to-koinos-purple-800/20 border-b border-koinos-dark-800">
              <div className="flex items-center justify-between p-6">
                <div>
                  <h2 className="text-xl font-bold">KOINOS NODE STATUS</h2>
                  <p className="text-sm text-koinos-dark-400 mt-1">Comprehensive System Overview</p>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={handleManualRefresh}
                    className={`p-2 rounded-lg hover:bg-koinos-dark-800 transition-all ${
                      isRefreshing ? 'animate-spin' : ''
                    }`}
                    title="Refresh Status"
                  >
                    <RefreshCw className="w-5 h-5" />
                  </button>
                  <button
                    onClick={onClose}
                    className="p-2 rounded-lg hover:bg-koinos-dark-800 transition-colors"
                  >
                    <X className="w-5 h-5" />
                  </button>
                </div>
              </div>
            </div>

            {statusData ? (
              <div className="p-6 overflow-y-auto max-h-[75vh] space-y-6">
                {/* Container Status */}
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold text-koinos-purple-400 flex items-center gap-2">
                    <Server className="w-4 h-4" />
                    CONTAINER STATUS
                  </h3>
                  <div className="bg-koinos-dark-800 rounded-lg p-4">
                    <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                      {Object.entries(statusData.containers).map(([service, running]) => (
                        <div key={service} className="flex items-center gap-2 text-sm">
                          {running ? (
                            <CheckCircle className="w-4 h-4 text-green-400" />
                          ) : (
                            <XCircle className="w-4 h-4 text-red-400" />
                          )}
                          <span className={running ? 'text-green-400' : 'text-red-400'}>
                            {service}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>

                {/* Sync Status */}
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold text-koinos-purple-400 flex items-center gap-2">
                    <Activity className="w-4 h-4" />
                    SYNC STATUS
                  </h3>
                  <div className="bg-koinos-dark-800 rounded-lg p-4 space-y-3">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-koinos-dark-400">Current Block:</span>
                      <span className="font-mono text-green-400">{formatNumber(statusData.sync.current_block)}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-koinos-dark-400">Target Block:</span>
                      <span className="font-mono text-blue-400">{formatNumber(statusData.sync.target_block)}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-koinos-dark-400">Progress:</span>
                      <span className="font-mono text-yellow-400">{statusData.sync.percentage.toFixed(2)}%</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-koinos-dark-400">Time Remaining:</span>
                      <span className="font-mono text-yellow-400">{statusData.sync.time_remaining}</span>
                    </div>
                    {/* Progress Bar */}
                    <div className="mt-3">
                      <div className="w-full bg-koinos-dark-700 rounded-full h-2">
                        <div 
                          className="bg-gradient-to-r from-koinos-purple-600 to-koinos-purple-400 h-2 rounded-full transition-all duration-500"
                          style={{ width: `${statusData.sync.percentage}%` }}
                        />
                      </div>
                    </div>
                  </div>
                </div>

                {/* Network Status */}
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold text-koinos-purple-400 flex items-center gap-2">
                    <Wifi className="w-4 h-4" />
                    NETWORK STATUS
                  </h3>
                  <div className="bg-koinos-dark-800 rounded-lg p-4 space-y-3">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-koinos-dark-400">Connected Peers:</span>
                      <span className="font-mono text-green-400">{statusData.network.connected_peers}</span>
                    </div>
                    <div className="grid grid-cols-3 gap-3 mt-4">
                      <div className="text-center p-3 bg-koinos-dark-700 rounded-lg">
                        <div className={`text-lg mb-1 ${statusData.network.jsonrpc_available ? 'text-green-400' : 'text-red-400'}`}>
                          {statusData.network.jsonrpc_available ? '✓' : '✗'}
                        </div>
                        <div className="text-xs text-koinos-dark-400">JSON-RPC</div>
                        <div className="text-xs text-koinos-dark-500">port 8080</div>
                      </div>
                      <div className="text-center p-3 bg-koinos-dark-700 rounded-lg">
                        <div className={`text-lg mb-1 ${statusData.network.grpc_available ? 'text-green-400' : 'text-red-400'}`}>
                          {statusData.network.grpc_available ? '✓' : '✗'}
                        </div>
                        <div className="text-xs text-koinos-dark-400">gRPC</div>
                        <div className="text-xs text-koinos-dark-500">port 50051</div>
                      </div>
                      <div className="text-center p-3 bg-koinos-dark-700 rounded-lg">
                        <div className={`text-lg mb-1 ${statusData.network.p2p_available ? 'text-green-400' : 'text-red-400'}`}>
                          {statusData.network.p2p_available ? '✓' : '✗'}
                        </div>
                        <div className="text-xs text-koinos-dark-400">P2P</div>
                        <div className="text-xs text-koinos-dark-500">port 8888</div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Disk Usage */}
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold text-koinos-purple-400 flex items-center gap-2">
                    <HardDrive className="w-4 h-4" />
                    DISK USAGE
                  </h3>
                  <div className="bg-koinos-dark-800 rounded-lg p-4">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-koinos-dark-400">Blockchain Data:</span>
                      <span className="font-mono text-yellow-400">{statusData.disk.blockchain_size}</span>
                    </div>
                  </div>
                </div>

                {/* Recent Activity */}
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold text-koinos-purple-400 flex items-center gap-2">
                    <AlertCircle className="w-4 h-4" />
                    RECENT ACTIVITY
                  </h3>
                  <div className="bg-koinos-dark-800 rounded-lg p-4">
                    {statusData.activity.error_count > 0 ? (
                      <>
                        <div className="flex items-center gap-2 text-yellow-400 mb-3">
                          <AlertCircle className="w-4 h-4" />
                          <span className="text-sm">Found {statusData.activity.error_count} error(s) in recent logs</span>
                        </div>
                        <div className="bg-koinos-dark-700 rounded p-3">
                          <p className="text-xs font-mono text-koinos-dark-400 break-all">
                            {statusData.activity.last_error}
                          </p>
                        </div>
                      </>
                    ) : (
                      <div className="flex items-center gap-2 text-green-400">
                        <CheckCircle className="w-4 h-4" />
                        <span className="text-sm">No errors in recent logs</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Quick Commands */}
                <div className="border-t border-koinos-dark-800 pt-4">
                  <div className="flex justify-between items-center mb-3">
                    <p className="text-xs text-koinos-dark-400">QUICK COMMANDS</p>
                    <p className="text-xs text-koinos-dark-500">Auto-refreshes every 10s</p>
                  </div>
                  <div className="space-y-2">
                    <code className="block text-xs bg-koinos-dark-800 p-2 rounded text-koinos-purple-400">
                      docker logs -f koinos-chain-1
                    </code>
                    <code className="block text-xs bg-koinos-dark-800 p-2 rounded text-koinos-purple-400">
                      docker compose logs -f
                    </code>
                    <code className="block text-xs bg-koinos-dark-800 p-2 rounded text-koinos-purple-400">
                      ~/koinos/koinos-status.sh
                    </code>
                  </div>
                </div>
              </div>
            ) : (
              <div className="p-8 text-center">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-koinos-purple-400 mx-auto mb-4"></div>
                <p className="text-koinos-dark-400">Loading status information...</p>
              </div>
            )}
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

export default StatusModal;