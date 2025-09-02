import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Play, Square, RefreshCw, Settings, Terminal, Activity, Info } from 'lucide-react';
import clsx from 'clsx';
import { NodeStatus } from './StatusIndicator';

interface NodeControlsProps {
  status: NodeStatus;
  onStart: () => void;
  onStop: () => void;
  onRestart: () => void;
  onOpenSettings?: () => void;
  onOpenLogs?: () => void;
  onOpenMetrics?: () => void;
  onShowStatus?: () => void;
}

const NodeControls: React.FC<NodeControlsProps> = ({
  status,
  onStart,
  onStop,
  onRestart,
  onOpenSettings,
  onOpenLogs,
  onOpenMetrics,
  onShowStatus,
}) => {
  const [isLoading, setIsLoading] = useState(false);

  const handleAction = async (action: () => void) => {
    setIsLoading(true);
    try {
      await action();
    } finally {
      setTimeout(() => setIsLoading(false), 1000);
    }
  };

  const canStart = status === 'stopped' || status === 'error';
  const canStop = status === 'running' || status === 'syncing' || status === 'starting';
  const canRestart = status === 'running' || status === 'syncing';

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-semibold">Node Controls</h3>
        <div className="flex space-x-2">
          {onOpenLogs && (
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={onOpenLogs}
              className="p-2 rounded-lg bg-koinos-dark-800 hover:bg-koinos-dark-700 transition-colors"
              title="View Logs"
            >
              <Terminal className="w-4 h-4" />
            </motion.button>
          )}
          {onOpenMetrics && (
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={onOpenMetrics}
              className="p-2 rounded-lg bg-koinos-dark-800 hover:bg-koinos-dark-700 transition-colors"
              title="View Metrics"
            >
              <Activity className="w-4 h-4" />
            </motion.button>
          )}
          {onOpenSettings && (
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={onOpenSettings}
              className="p-2 rounded-lg bg-koinos-dark-800 hover:bg-koinos-dark-700 transition-colors"
              title="Settings"
            >
              <Settings className="w-4 h-4" />
            </motion.button>
          )}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4">
        {/* Start Button */}
        <motion.button
          whileHover={canStart ? { scale: 1.05 } : {}}
          whileTap={canStart ? { scale: 0.95 } : {}}
          onClick={() => handleAction(onStart)}
          disabled={!canStart || isLoading}
          className={clsx(
            'relative overflow-hidden rounded-lg p-4 transition-all duration-300',
            canStart && !isLoading
              ? 'bg-green-500/20 hover:bg-green-500/30 text-green-400 cursor-pointer'
              : 'bg-koinos-dark-800/50 text-koinos-dark-600 cursor-not-allowed'
          )}
        >
          <div className="flex flex-col items-center space-y-2">
            <Play className="w-8 h-8" />
            <span className="font-semibold">Start</span>
          </div>
          {canStart && !isLoading && (
            <motion.div
              className="absolute inset-0 bg-gradient-to-r from-transparent via-green-500/20 to-transparent"
              initial={{ x: '-100%' }}
              animate={{ x: '100%' }}
              transition={{ repeat: Infinity, duration: 3, ease: 'linear' }}
            />
          )}
        </motion.button>

        {/* Stop Button */}
        <motion.button
          whileHover={canStop ? { scale: 1.05 } : {}}
          whileTap={canStop ? { scale: 0.95 } : {}}
          onClick={() => handleAction(onStop)}
          disabled={!canStop || isLoading}
          className={clsx(
            'relative overflow-hidden rounded-lg p-4 transition-all duration-300',
            canStop && !isLoading
              ? 'bg-red-500/20 hover:bg-red-500/30 text-red-400 cursor-pointer'
              : 'bg-koinos-dark-800/50 text-koinos-dark-600 cursor-not-allowed'
          )}
        >
          <div className="flex flex-col items-center space-y-2">
            <Square className="w-8 h-8" />
            <span className="font-semibold">Stop</span>
          </div>
        </motion.button>

        {/* Restart Button */}
        <motion.button
          whileHover={canRestart ? { scale: 1.05 } : {}}
          whileTap={canRestart ? { scale: 0.95 } : {}}
          onClick={() => handleAction(onRestart)}
          disabled={!canRestart || isLoading}
          className={clsx(
            'relative overflow-hidden rounded-lg p-4 transition-all duration-300',
            canRestart && !isLoading
              ? 'bg-blue-500/20 hover:bg-blue-500/30 text-blue-400 cursor-pointer'
              : 'bg-koinos-dark-800/50 text-koinos-dark-600 cursor-not-allowed'
          )}
        >
          <div className="flex flex-col items-center space-y-2">
            <RefreshCw className={clsx('w-8 h-8', isLoading && 'animate-spin')} />
            <span className="font-semibold">Restart</span>
          </div>
        </motion.button>
      </div>

      {/* Quick Actions */}
      <div className="mt-6 pt-6 border-t border-koinos-dark-800">
        <p className="text-sm text-koinos-dark-500 mb-3">Quick Actions</p>
        <div className="flex flex-wrap gap-2">
          {onShowStatus && (
            <button 
              onClick={onShowStatus}
              className="px-3 py-1.5 text-xs bg-koinos-purple-600/20 hover:bg-koinos-purple-600/30 text-koinos-purple-400 rounded-lg transition-colors flex items-center gap-1"
            >
              <Info className="w-3 h-3" />
              Node Status
            </button>
          )}
          <button className="px-3 py-1.5 text-xs bg-koinos-dark-800 hover:bg-koinos-dark-700 rounded-lg transition-colors">
            Clear Cache
          </button>
          <button className="px-3 py-1.5 text-xs bg-koinos-dark-800 hover:bg-koinos-dark-700 rounded-lg transition-colors">
            Check Updates
          </button>
          <button className="px-3 py-1.5 text-xs bg-koinos-dark-800 hover:bg-koinos-dark-700 rounded-lg transition-colors">
            Export Logs
          </button>
          <button className="px-3 py-1.5 text-xs bg-koinos-dark-800 hover:bg-koinos-dark-700 rounded-lg transition-colors">
            Backup Config
          </button>
        </div>
      </div>
    </div>
  );
};

export default NodeControls;