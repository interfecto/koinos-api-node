import { useState, useEffect, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

interface LogEntry {
  timestamp: string;
  level: string;
  message: string;
  details?: string;
}

interface DebugConsoleProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function DebugConsole({ isOpen, onClose }: DebugConsoleProps) {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [filter, setFilter] = useState<string>('ALL');
  const logContainerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);

  useEffect(() => {
    if (!isOpen) return;

    // Load existing logs
    invoke<LogEntry[]>('get_logs')
      .then(setLogs)
      .catch(console.error);

    // Listen for new logs
    const unlisten = listen<LogEntry>('log_entry', (event) => {
      setLogs(prev => [...prev, event.payload]);
    });

    return () => {
      unlisten.then(fn => fn());
    };
  }, [isOpen]);

  useEffect(() => {
    if (autoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  const clearLogs = async () => {
    try {
      await invoke('clear_logs');
      setLogs([]);
    } catch (err) {
      console.error('Failed to clear logs:', err);
    }
  };

  const filteredLogs = logs.filter(log => 
    filter === 'ALL' || log.level === filter
  );

  const getLevelColor = (level: string) => {
    switch (level) {
      case 'ERROR': return 'text-red-400';
      case 'WARN': return 'text-yellow-400';
      case 'INFO': return 'text-blue-400';
      case 'DEBUG': return 'text-gray-400';
      default: return 'text-gray-300';
    }
  };

  const getLevelBg = (level: string) => {
    switch (level) {
      case 'ERROR': return 'bg-red-500/20';
      case 'WARN': return 'bg-yellow-500/20';
      case 'INFO': return 'bg-blue-500/20';
      case 'DEBUG': return 'bg-gray-500/20';
      default: return 'bg-gray-500/20';
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-end">
      <div className="bg-gray-900 border-t border-gray-800 w-full h-96 flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-800">
          <div className="flex items-center gap-4">
            <h3 className="text-lg font-semibold text-white">Debug Console</h3>
            <div className="flex gap-2">
              {['ALL', 'ERROR', 'WARN', 'INFO', 'DEBUG'].map(level => (
                <button
                  key={level}
                  onClick={() => setFilter(level)}
                  className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                    filter === level 
                      ? 'bg-blue-500 text-white' 
                      : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                  }`}
                >
                  {level}
                </button>
              ))}
            </div>
            <div className="text-sm text-gray-400">
              {filteredLogs.length} entries
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setAutoScroll(!autoScroll)}
              className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                autoScroll 
                  ? 'bg-green-500/20 text-green-400' 
                  : 'bg-gray-800 text-gray-400'
              }`}
            >
              Auto-scroll: {autoScroll ? 'ON' : 'OFF'}
            </button>
            <button
              onClick={clearLogs}
              className="px-3 py-1 bg-gray-800 text-gray-400 rounded hover:bg-gray-700 text-xs font-medium"
            >
              Clear
            </button>
            <button
              onClick={onClose}
              className="px-3 py-1 bg-gray-800 text-gray-400 rounded hover:bg-gray-700 text-xs font-medium"
            >
              Close
            </button>
          </div>
        </div>

        {/* Log Content */}
        <div 
          ref={logContainerRef}
          className="flex-1 overflow-y-auto p-4 font-mono text-xs space-y-1"
        >
          {filteredLogs.length === 0 ? (
            <div className="text-gray-500 text-center py-8">
              No logs to display
            </div>
          ) : (
            filteredLogs.map((log, index) => (
              <div 
                key={index} 
                className={`flex gap-2 py-1 px-2 rounded ${getLevelBg(log.level)}`}
              >
                <span className="text-gray-500 min-w-[180px]">
                  {log.timestamp}
                </span>
                <span className={`min-w-[60px] font-semibold ${getLevelColor(log.level)}`}>
                  [{log.level}]
                </span>
                <span className="text-gray-300 flex-1">
                  {log.message}
                  {log.details && (
                    <span className="text-gray-500 ml-2">
                      - {log.details}
                    </span>
                  )}
                </span>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}