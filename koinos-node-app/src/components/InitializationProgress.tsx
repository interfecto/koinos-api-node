import React from 'react';
import { motion } from 'framer-motion';
import { CheckCircle, Circle, Loader2 } from 'lucide-react';
import ProgressBar from './ProgressBar';

interface Step {
  id: string;
  label: string;
  status: 'pending' | 'active' | 'completed';
  progress?: number;
  details?: string;
}

interface InitializationProgressProps {
  currentStep: string;
  steps: Step[];
  overallProgress: number;
  downloadProgress?: number;
  downloadSpeed?: string;
  estimatedTime?: string;
}

const InitializationProgress: React.FC<InitializationProgressProps> = ({
  currentStep,
  steps,
  overallProgress,
  downloadProgress,
  downloadSpeed,
  estimatedTime
}) => {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      className="fixed inset-0 bg-koinos-dark-950/95 backdrop-blur-sm flex items-center justify-center z-50"
    >
      <div className="bg-koinos-dark-900 border border-koinos-dark-800 rounded-2xl p-8 max-w-2xl w-full mx-4 shadow-2xl">
        {/* Header */}
        <div className="text-center mb-8">
          <h2 className="text-2xl font-bold mb-2">Initializing Koinos Node</h2>
          <p className="text-koinos-dark-400">Setting up your node for the first time</p>
        </div>

        {/* Overall Progress */}
        <div className="mb-8">
          <ProgressBar
            progress={overallProgress}
            label="Overall Progress"
            size="lg"
            color="purple"
            animate
          />
        </div>

        {/* Steps */}
        <div className="space-y-4 mb-6">
          {steps.map((step, index) => (
            <motion.div
              key={step.id}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: index * 0.1 }}
              className={`flex items-start space-x-3 ${
                step.status === 'pending' ? 'opacity-50' : ''
              }`}
            >
              <div className="flex-shrink-0 mt-0.5">
                {step.status === 'completed' ? (
                  <CheckCircle className="w-5 h-5 text-green-500" />
                ) : step.status === 'active' ? (
                  <Loader2 className="w-5 h-5 text-koinos-purple-500 animate-spin" />
                ) : (
                  <Circle className="w-5 h-5 text-koinos-dark-600" />
                )}
              </div>
              <div className="flex-1">
                <div className="flex items-center justify-between">
                  <p className={`font-medium ${
                    step.status === 'active' ? 'text-koinos-purple-400' : 'text-koinos-dark-200'
                  }`}>
                    {step.label}
                  </p>
                  {step.progress !== undefined && step.status === 'active' && (
                    <span className="text-sm text-koinos-dark-400">
                      {Math.round(step.progress)}%
                    </span>
                  )}
                </div>
                {step.details && step.status === 'active' && (
                  <p className="text-xs text-koinos-dark-500 mt-1">{step.details}</p>
                )}
                {step.status === 'active' && step.progress !== undefined && (
                  <div className="mt-2">
                    <ProgressBar
                      progress={step.progress}
                      size="sm"
                      color="purple"
                      showPercentage={false}
                      animate
                    />
                  </div>
                )}
              </div>
            </motion.div>
          ))}
        </div>

        {/* Download Details */}
        {currentStep === 'download' && downloadProgress !== undefined && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-koinos-dark-800/50 rounded-lg p-4 space-y-3"
          >
            <div className="text-sm font-medium text-koinos-dark-200">
              Downloading Blockchain Snapshot (~30GB)
            </div>
            
            <ProgressBar
              progress={downloadProgress}
              size="md"
              color="blue"
              animate
              details={`${(downloadProgress * 0.3).toFixed(1)} GB / 30 GB`}
            />

            <div className="flex justify-between text-xs text-koinos-dark-400">
              {downloadSpeed && (
                <span>Speed: {downloadSpeed}</span>
              )}
              {estimatedTime && (
                <span>Est. time remaining: {estimatedTime}</span>
              )}
            </div>
          </motion.div>
        )}

        {/* Status Message */}
        <div className="mt-6 text-center">
          <p className="text-sm text-koinos-dark-400">
            This may take a few minutes. Please keep this window open.
          </p>
        </div>
      </div>
    </motion.div>
  );
};

export default InitializationProgress;