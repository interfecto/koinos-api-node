import React from 'react';
import { motion } from 'framer-motion';
import { Cpu, HardDrive, Wifi, Clock, TrendingUp, Award } from 'lucide-react';
import StatusIndicator, { NodeStatus } from './StatusIndicator';
import NodeControls from './NodeControls';
import ProgressBar from './ProgressBar';

interface DashboardProps {
  nodeStatus: NodeStatus;
  syncProgress: number;
  currentBlock: number;
  targetBlock: number;
  peersCount: number;
  onStartNode: () => void;
  onStopNode: () => void;
  onRestartNode: () => void;
  onShowStatus?: () => void;
  resourceUsage?: {
    cpu_percent: number;
    memory_mb: number;
    memory_total_mb: number;
    disk_used_gb: number;
    disk_total_gb: number;
  };
}

const Dashboard: React.FC<DashboardProps> = ({
  nodeStatus,
  syncProgress,
  currentBlock,
  targetBlock,
  peersCount,
  onStartNode,
  onStopNode,
  onRestartNode,
  onShowStatus,
  resourceUsage,
}) => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-koinos-dark-950 via-koinos-purple-900/10 to-koinos-dark-950">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="border-b border-koinos-dark-800 bg-koinos-dark-950/50 backdrop-blur-sm sticky top-0 z-50"
      >
        <div className="container mx-auto px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-xl font-bold">Koinos Node</h1>
              <p className="text-xs text-koinos-dark-400">Desktop Edition v0.4.0</p>
            </div>
            <div className="flex items-center space-x-4">
              <div className="text-right">
                <p className="text-sm text-koinos-dark-400">Network</p>
                <p className="font-semibold">Mainnet</p>
              </div>
            </div>
          </div>
        </div>
      </motion.header>

      {/* Main Content */}
      <div className="container mx-auto px-6 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Status and Controls */}
          <div className="lg:col-span-2 space-y-6">
            <StatusIndicator
              status={nodeStatus}
              syncProgress={syncProgress}
              currentBlock={currentBlock}
              targetBlock={targetBlock}
              peersCount={peersCount}
            />
            
            <NodeControls
              status={nodeStatus}
              onStart={onStartNode}
              onStop={onStopNode}
              onRestart={onRestartNode}
              onShowStatus={onShowStatus}
            />

            {/* Resource Usage */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.2 }}
              className="card"
            >
              <h3 className="text-lg font-semibold mb-4">System Resources</h3>
              <div className="space-y-4">
                <div>
                  <div className="flex items-center space-x-2 mb-2">
                    <Cpu className="w-4 h-4 text-koinos-purple-400" />
                    <span className="text-sm">CPU Usage</span>
                  </div>
                  <ProgressBar
                    progress={resourceUsage?.cpu_percent || 0}
                    size="sm"
                    color={resourceUsage && resourceUsage.cpu_percent > 80 ? 'amber' : 'purple'}
                    animate={false}
                  />
                </div>

                <div>
                  <div className="flex items-center space-x-2 mb-2">
                    <HardDrive className="w-4 h-4 text-koinos-purple-400" />
                    <span className="text-sm">Memory Usage</span>
                  </div>
                  <ProgressBar
                    progress={resourceUsage ? (resourceUsage.memory_mb / resourceUsage.memory_total_mb * 100) : 0}
                    size="sm"
                    color={resourceUsage && (resourceUsage.memory_mb / resourceUsage.memory_total_mb * 100) > 80 ? 'amber' : 'purple'}
                    animate={false}
                    details={resourceUsage ? `${resourceUsage.memory_mb} MB / ${(resourceUsage.memory_total_mb / 1024).toFixed(1)} GB` : '- / -'}
                  />
                </div>

                <div>
                  <div className="flex items-center space-x-2 mb-2">
                    <HardDrive className="w-4 h-4 text-koinos-purple-400" />
                    <span className="text-sm">Disk Usage</span>
                  </div>
                  <ProgressBar
                    progress={resourceUsage ? (resourceUsage.disk_used_gb / resourceUsage.disk_total_gb * 100) : 0}
                    size="sm"
                    color={resourceUsage && (resourceUsage.disk_used_gb / resourceUsage.disk_total_gb * 100) > 90 ? 'amber' : 'purple'}
                    animate={false}
                    details={resourceUsage ? `${resourceUsage.disk_used_gb.toFixed(1)} GB / ${resourceUsage.disk_total_gb.toFixed(0)} GB` : '- / -'}
                  />
                </div>
              </div>
            </motion.div>
          </div>

          {/* Right Column - Stats and Info */}
          <div className="space-y-6">
            {/* Network Contribution */}
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.1 }}
              className="card"
            >
              <h3 className="text-lg font-semibold mb-4">Your Contribution</h3>
              <div className="space-y-3">
                <div className="flex items-center justify-between p-3 bg-koinos-dark-800 rounded-lg">
                  <div className="flex items-center space-x-3">
                    <Clock className="w-5 h-5 text-koinos-purple-400" />
                    <span className="text-sm">Uptime</span>
                  </div>
                  <span className="font-semibold">{nodeStatus === 'running' ? 'Active' : 'Inactive'}</span>
                </div>
                <div className="flex items-center justify-between p-3 bg-koinos-dark-800 rounded-lg">
                  <div className="flex items-center space-x-3">
                    <TrendingUp className="w-5 h-5 text-koinos-purple-400" />
                    <span className="text-sm">Current Block</span>
                  </div>
                  <span className="font-semibold">{currentBlock.toLocaleString()}</span>
                </div>
                <div className="flex items-center justify-between p-3 bg-koinos-dark-800 rounded-lg">
                  <div className="flex items-center space-x-3">
                    <Wifi className="w-5 h-5 text-koinos-purple-400" />
                    <span className="text-sm">Connected Peers</span>
                  </div>
                  <span className="font-semibold">{peersCount}</span>
                </div>
              </div>
            </motion.div>

            {/* Achievements */}
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.2 }}
              className="card"
            >
              <h3 className="text-lg font-semibold mb-4">Achievements</h3>
              <div className="grid grid-cols-3 gap-3">
                <div className="text-center p-3 bg-koinos-dark-800 rounded-lg">
                  <Award className="w-8 h-8 mx-auto mb-2 text-yellow-500" />
                  <p className="text-xs">First Sync</p>
                </div>
                <div className="text-center p-3 bg-koinos-dark-800 rounded-lg opacity-50">
                  <Award className="w-8 h-8 mx-auto mb-2 text-koinos-dark-600" />
                  <p className="text-xs">7 Days</p>
                </div>
                <div className="text-center p-3 bg-koinos-dark-800 rounded-lg opacity-50">
                  <Award className="w-8 h-8 mx-auto mb-2 text-koinos-dark-600" />
                  <p className="text-xs">30 Days</p>
                </div>
              </div>
            </motion.div>

            {/* VHP Earnings */}
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.3 }}
              className="card bg-gradient-to-br from-koinos-purple-900/20 to-koinos-dark-900 border-koinos-purple-800"
            >
              <h3 className="text-lg font-semibold mb-4">VHP Earnings</h3>
              <div className="text-center py-4">
                <p className="text-3xl font-bold gradient-text mb-2">Coming Soon</p>
                <p className="text-sm text-koinos-dark-400 mb-4">VHP earning feature in development</p>
                <button className="btn-secondary text-sm opacity-50 cursor-not-allowed" disabled>
                  Learn More →
                </button>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;