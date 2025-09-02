import React from 'react';
import { motion } from 'framer-motion';

interface ProgressBarProps {
  progress: number;
  label?: string;
  showPercentage?: boolean;
  size?: 'sm' | 'md' | 'lg';
  color?: 'purple' | 'green' | 'blue' | 'amber';
  animate?: boolean;
  details?: string;
}

const ProgressBar: React.FC<ProgressBarProps> = ({
  progress,
  label,
  showPercentage = true,
  size = 'md',
  color = 'purple',
  animate = true,
  details
}) => {
  const sizeClasses = {
    sm: 'h-2',
    md: 'h-3',
    lg: 'h-4'
  };

  const colorClasses = {
    purple: 'bg-gradient-to-r from-koinos-purple-600 to-koinos-purple-500',
    green: 'bg-gradient-to-r from-green-600 to-green-500',
    blue: 'bg-gradient-to-r from-blue-600 to-blue-500',
    amber: 'bg-gradient-to-r from-amber-600 to-amber-500'
  };

  const glowClasses = {
    purple: 'shadow-[0_0_20px_rgba(139,92,246,0.5)]',
    green: 'shadow-[0_0_20px_rgba(34,197,94,0.5)]',
    blue: 'shadow-[0_0_20px_rgba(59,130,246,0.5)]',
    amber: 'shadow-[0_0_20px_rgba(245,158,11,0.5)]'
  };

  return (
    <div className="w-full">
      {(label || showPercentage) && (
        <div className="flex items-center justify-between mb-2">
          {label && (
            <span className="text-sm font-medium text-koinos-dark-200">
              {label}
            </span>
          )}
          {showPercentage && (
            <span className="text-sm font-bold text-koinos-dark-100">
              {Math.round(progress)}%
            </span>
          )}
        </div>
      )}
      
      <div className={`relative w-full bg-koinos-dark-800 rounded-full overflow-hidden ${sizeClasses[size]}`}>
        <motion.div
          className={`h-full ${colorClasses[color]} ${animate ? glowClasses[color] : ''} relative overflow-hidden`}
          initial={{ width: 0 }}
          animate={{ width: `${progress}%` }}
          transition={{ duration: 0.5, ease: "easeOut" }}
        >
          {animate && (
            <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent animate-shimmer" />
          )}
        </motion.div>
        
        {/* Progress markers */}
        <div className="absolute inset-0 flex">
          {[25, 50, 75].map((marker) => (
            <div
              key={marker}
              className="absolute top-0 bottom-0 w-px bg-koinos-dark-900/50"
              style={{ left: `${marker}%` }}
            />
          ))}
        </div>
      </div>

      {details && (
        <p className="text-xs text-koinos-dark-400 mt-1">{details}</p>
      )}
    </div>
  );
};

export default ProgressBar;