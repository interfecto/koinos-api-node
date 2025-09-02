import React from 'react';
import { motion } from 'framer-motion';

interface WelcomeScreenProps {
  onGetStarted: () => void;
}

const WelcomeScreen: React.FC<WelcomeScreenProps> = ({ onGetStarted }) => {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-br from-koinos-dark-950 via-koinos-purple-900/20 to-koinos-dark-950 relative overflow-hidden">
      {/* Animated background elements */}
      <div className="absolute inset-0">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-koinos-purple-600/20 rounded-full blur-3xl animate-pulse-slow" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-koinos-purple-500/20 rounded-full blur-3xl animate-pulse-slow animation-delay-400" />
      </div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.8 }}
        className="relative z-10 text-center px-8 max-w-3xl"
      >
        {/* Title */}
        <motion.h1
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="text-5xl font-bold mb-4"
        >
          <span className="gradient-text">Koinos Node</span>
        </motion.h1>

        {/* Subtitle */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="text-xl text-koinos-dark-300 mb-12"
        >
          Run a Koinos node in one click. Support the network. Be part of the revolution.
        </motion.p>

        {/* Features */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4 }}
          className="grid grid-cols-3 gap-6 mb-12"
        >
          <div className="glass rounded-lg p-4">
            <h3 className="font-semibold text-sm text-koinos-purple-400 mb-1">One Click</h3>
            <p className="text-xs text-koinos-dark-400">No technical knowledge needed</p>
          </div>

          <div className="glass rounded-lg p-4">
            <h3 className="font-semibold text-sm text-koinos-purple-400 mb-1">Earn VHP</h3>
            <p className="text-xs text-koinos-dark-400">Optional rewards for running</p>
          </div>

          <div className="glass rounded-lg p-4">
            <h3 className="font-semibold text-sm text-koinos-purple-400 mb-1">Decentralized</h3>
            <p className="text-xs text-koinos-dark-400">Every node strengthens the network</p>
          </div>
        </motion.div>

        {/* CTA Button */}
        <motion.button
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.5, type: "spring", stiffness: 200 }}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={onGetStarted}
          className="btn-primary text-lg px-10 py-4 rounded-full"
        >
          Get Started →
        </motion.button>

        {/* Footer text */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.6 }}
          className="text-sm text-koinos-dark-500 mt-8"
        >
          No registration required • Free forever • Open source
        </motion.p>
      </motion.div>
    </div>
  );
};

export default WelcomeScreen;