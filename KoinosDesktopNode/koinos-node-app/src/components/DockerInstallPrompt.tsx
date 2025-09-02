import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { AlertCircle, Download, ExternalLink, Loader2, CheckCircle } from 'lucide-react';
import { invoke } from '@tauri-apps/api/core';

interface DockerInstallPromptProps {
  onClose: () => void;
  onRetry: () => void;
}

const DockerInstallPrompt: React.FC<DockerInstallPromptProps> = ({ onClose, onRetry }) => {
  const [isInstalling, setIsInstalling] = useState(false);
  const [installStatus, setInstallStatus] = useState<'idle' | 'installing' | 'success' | 'error'>('idle');
  const [installError, setInstallError] = useState<string>('');
  const handleDownloadDocker = () => {
    // Open Docker download page
    window.open('https://www.docker.com/products/docker-desktop/', '_blank');
  };

  const handleBrewInstall = async () => {
    // Copy brew command to clipboard
    const command = 'brew install --cask docker';
    await navigator.clipboard.writeText(command);
    alert(`Command copied to clipboard:\n\n${command}\n\nPaste this in your terminal to install Docker.`);
  };

  const handleAutoInstall = async () => {
    setIsInstalling(true);
    setInstallStatus('installing');
    setInstallError('');
    
    try {
      await invoke('install_docker');
      setInstallStatus('success');
      // Wait a bit for Docker to start
      setTimeout(() => {
        onRetry();
      }, 5000);
    } catch (err) {
      setInstallStatus('error');
      setInstallError(err as string);
      setIsInstalling(false);
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50"
    >
      <motion.div
        initial={{ scale: 0.9, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        className="bg-koinos-dark-900 border border-koinos-dark-800 rounded-2xl p-8 max-w-2xl w-full mx-4 shadow-2xl"
      >
        {/* Icon and Title */}
        <div className="flex items-center space-x-4 mb-6">
          <div className="p-3 bg-amber-500/20 rounded-full">
            <AlertCircle className="w-8 h-8 text-amber-500" />
          </div>
          <div>
            <h2 className="text-2xl font-bold">Docker Desktop Required</h2>
            <p className="text-koinos-dark-400">Docker is needed to run the Koinos node</p>
          </div>
        </div>

        {/* Installation Options */}
        <div className="space-y-4 mb-8">
          <div className="bg-koinos-dark-800/50 rounded-lg p-6">
            <h3 className="font-semibold mb-4">Installation Options:</h3>
            
            {/* Option 1: Direct Download */}
            <div className="mb-6">
              <h4 className="text-sm font-medium text-koinos-purple-400 mb-2">Option 1: Download from Docker</h4>
              <button
                onClick={handleDownloadDocker}
                className="w-full btn-primary flex items-center justify-center space-x-2"
              >
                <Download className="w-5 h-5" />
                <span>Download Docker Desktop</span>
                <ExternalLink className="w-4 h-4" />
              </button>
              <p className="text-xs text-koinos-dark-500 mt-2">
                Download the official Docker Desktop installer (recommended)
              </p>
            </div>

            {/* Option 2: Auto Install */}
            <div className="mb-6">
              <h4 className="text-sm font-medium text-koinos-purple-400 mb-2">Option 2: One-Click Install (Homebrew)</h4>
              <button
                onClick={handleAutoInstall}
                disabled={isInstalling}
                className="w-full btn-primary flex items-center justify-center space-x-2 disabled:opacity-50"
              >
                {isInstalling ? (
                  <>
                    <Loader2 className="w-5 h-5 animate-spin" />
                    <span>Installing Docker...</span>
                  </>
                ) : installStatus === 'success' ? (
                  <>
                    <CheckCircle className="w-5 h-5 text-green-500" />
                    <span>Docker Installed!</span>
                  </>
                ) : (
                  <>
                    <Download className="w-5 h-5" />
                    <span>Install Docker Now</span>
                  </>
                )}
              </button>
              {installStatus === 'error' && (
                <p className="text-xs text-red-400 mt-2">{installError}</p>
              )}
              <p className="text-xs text-koinos-dark-500 mt-2">
                Automatically installs Docker using Homebrew (requires Homebrew)
              </p>
            </div>

            {/* Option 3: Manual Homebrew */}
            <div>
              <h4 className="text-sm font-medium text-koinos-purple-400 mb-2">Option 3: Manual Terminal Install</h4>
              <button
                onClick={handleBrewInstall}
                className="w-full btn-secondary flex items-center justify-center space-x-2"
              >
                <span className="font-mono text-sm">brew install --cask docker</span>
              </button>
              <p className="text-xs text-koinos-dark-500 mt-2">
                Click to copy the command, then paste in Terminal
              </p>
            </div>
          </div>

          {/* Installation Steps */}
          <div className="bg-koinos-dark-800/50 rounded-lg p-6">
            <h3 className="font-semibold mb-3">After Installing Docker:</h3>
            <ol className="space-y-2 text-sm text-koinos-dark-300">
              <li className="flex items-start">
                <span className="text-koinos-purple-400 mr-2">1.</span>
                <span>Open Docker Desktop from your Applications folder</span>
              </li>
              <li className="flex items-start">
                <span className="text-koinos-purple-400 mr-2">2.</span>
                <span>Complete the Docker setup wizard</span>
              </li>
              <li className="flex items-start">
                <span className="text-koinos-purple-400 mr-2">3.</span>
                <span>Wait for Docker to start (icon appears in menu bar)</span>
              </li>
              <li className="flex items-start">
                <span className="text-koinos-purple-400 mr-2">4.</span>
                <span>Click "Check Again" below to continue</span>
              </li>
            </ol>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex space-x-4">
          <button
            onClick={onClose}
            disabled={isInstalling}
            className="flex-1 btn-secondary disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={onRetry}
            disabled={isInstalling}
            className="flex-1 btn-primary disabled:opacity-50"
          >
            {installStatus === 'success' ? 'Continue Setup' : 'Check Again'}
          </button>
        </div>

        {/* Help Text */}
        <p className="text-xs text-koinos-dark-500 text-center mt-4">
          Docker Desktop is free for personal use. It manages containers that run the Koinos node.
        </p>
      </motion.div>
    </motion.div>
  );
};

export default DockerInstallPrompt;