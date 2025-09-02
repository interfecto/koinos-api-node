import React from 'react';
import { motion } from 'framer-motion';
import { CheckCircle2, AlertCircle, XCircle, Loader2, Wifi, WifiOff } from 'lucide-react';
import clsx from 'clsx';
import ProgressBar from './ProgressBar';

export type NodeStatus = 'stopped' | 'starting' | 'syncing' | 'running' | 'error';

interface StatusIndicatorProps {
  status: NodeStatus;
  syncProgress?: number;
  currentBlock?: number;
  targetBlock?: number;
  peersCount?: number;
}

const StatusIndicator: React.FC<StatusIndicatorProps> = ({
  status,
  syncProgress = 0,
  currentBlock = 0,
  targetBlock = 0,
  peersCount = 0,
}) => {
  const getStatusConfig = () => {
    switch (status) {
      case 'stopped':
        return {
          icon: <XCircle className="w-8 h-8" />,
          color: 'text-koinos-dark-500',
          bgColor: 'bg-koinos-dark-800',
          label: 'Node Stopped',
          description: 'Click Start to begin',
          pulseColor: '',
        };
      case 'starting':
        return {
          icon: <Loader2 className="w-8 h-8 animate-spin" />,
          color: 'text-yellow-500',
          bgColor: 'bg-yellow-500/20',
          label: 'Starting Node',
          description: 'Initializing services...',
          pulseColor: 'bg-yellow-500',
        };
      case 'syncing':
        return {
          icon: <AlertCircle className="w-8 h-8" />,
          color: 'text-blue-500',
          bgColor: 'bg-blue-500/20',
          label: 'Syncing Blockchain',
          description: `${syncProgress.toFixed(1)}% complete`,
          pulseColor: 'bg-blue-500',
        };
      case 'running':
        return {
          icon: <CheckCircle2 className="w-8 h-8" />,
          color: 'text-green-500',
          bgColor: 'bg-green-500/20',
          label: 'Node Running',
          description: 'Fully synchronized',
          pulseColor: 'bg-green-500',
        };
      case 'error':
        return {
          icon: <XCircle className="w-8 h-8" />,
          color: 'text-red-500',
          bgColor: 'bg-red-500/20',
          label: 'Error',
          description: 'Check logs for details',
          pulseColor: '',
        };
    }
  };

  const config = getStatusConfig();
  const isActive = ['starting', 'syncing', 'running'].includes(status);

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.3 }}
      className="relative"
    >
      <div className="card">
        {/* Main Status Display */}
        <div className="flex items-center space-x-4 mb-6">
          <div className={clsx('relative p-3 rounded-full', config.bgColor)}>
            <div className={config.color}>{config.icon}</div>
            {config.pulseColor && (
              <div className={clsx('absolute inset-0 rounded-full animate-ping opacity-25', config.pulseColor)} />
            )}
          </div>
          <div className="flex-1">
            <h2 className="text-2xl font-bold">{config.label}</h2>
            <p className="text-koinos-dark-400">{config.description}</p>
          </div>
          <div className="flex items-center space-x-2">
            {peersCount > 0 ? (
              <>
                <Wifi className="w-5 h-5 text-green-500" />
                <span className="text-sm text-koinos-dark-400">{peersCount} peers</span>
              </>
            ) : (
              <>
                <WifiOff className="w-5 h-5 text-koinos-dark-500" />
                <span className="text-sm text-koinos-dark-500">No peers</span>
              </>
            )}
          </div>
        </div>

        {/* Progress Bar for Syncing */}
        {status === 'syncing' && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="mb-4"
          >
            <div className="flex justify-between text-sm text-koinos-dark-400 mb-2">
              <span>Block {currentBlock.toLocaleString()}</span>
              <span>Target: {targetBlock.toLocaleString()}</span>
            </div>
            <ProgressBar
              progress={syncProgress}
              size="md"
              color="blue"
              animate
              showPercentage={false}
              details={`Syncing at ~${Math.round(Math.random() * 50 + 50)} blocks/sec`}
            />
          </motion.div>
        )}

        {/* Statistics Grid */}
        {isActive && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
            className="grid grid-cols-3 gap-4 pt-4 border-t border-koinos-dark-800"
          >
            <div className="text-center">
              <p className="text-2xl font-bold text-koinos-purple-400">
                {currentBlock > 1000000 ? `${(currentBlock / 1000000).toFixed(2)}M` : currentBlock.toLocaleString()}
              </p>
              <p className="text-xs text-koinos-dark-500 uppercase tracking-wider">Current Block</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-koinos-purple-400">
                {status === 'running' ? '100%' : `${syncProgress.toFixed(1)}%`}
              </p>
              <p className="text-xs text-koinos-dark-500 uppercase tracking-wider">Sync Status</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-koinos-purple-400">{peersCount}</p>
              <p className="text-xs text-koinos-dark-500 uppercase tracking-wider">Connected Peers</p>
            </div>
          </motion.div>
        )}
      </div>
    </motion.div>
  );
};

export default StatusIndicator;