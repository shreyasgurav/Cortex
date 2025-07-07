'use client';

import { Music, Sparkles } from 'lucide-react';

export default function LoadingScreen() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 relative overflow-hidden flex items-center justify-center">
      {/* Background Effects */}
      <div className="absolute inset-0 opacity-20">
        <div
          className="absolute inset-0"
          style={{
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fillRule='evenodd'%3E%3Cg fill='%239C92AC' fillOpacity='0.1'%3E%3Ccircle cx='30' cy='30' r='2'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
          }}
        ></div>
      </div>

      <div className="relative z-10 text-center">
        {/* Animated Logo */}
        <div className="mb-8">
          <div className="relative">
            <div className="p-6 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 shadow-lg shadow-purple-500/25 animate-pulse">
              <Music className="w-12 h-12 text-white" />
            </div>
            <div className="absolute -top-2 -right-2">
              <Sparkles className="w-6 h-6 text-yellow-400 animate-bounce" />
            </div>
          </div>
        </div>

        {/* Loading Text */}
        <h2 className="text-3xl md:text-4xl font-bold bg-gradient-to-r from-pink-400 via-purple-400 to-blue-400 bg-clip-text text-transparent mb-4">
          Creating Your Artist Identity
        </h2>

        {/* Loading Steps */}
        <div className="space-y-3 max-w-md mx-auto">
          <div className="flex items-center justify-between backdrop-blur-sm bg-white/10 rounded-lg p-3 border border-white/20">
            <span className="text-gray-300">Analyzing your music taste</span>
            <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
          </div>
          <div className="flex items-center justify-between backdrop-blur-sm bg-white/10 rounded-lg p-3 border border-white/20">
            <span className="text-gray-300">Generating artist persona</span>
            <div className="w-2 h-2 bg-yellow-400 rounded-full animate-pulse"></div>
          </div>
          <div className="flex items-center justify-between backdrop-blur-sm bg-white/10 rounded-lg p-3 border border-white/20">
            <span className="text-gray-300">Crafting your story</span>
            <div className="w-2 h-2 bg-purple-400 rounded-full animate-pulse"></div>
          </div>
        </div>

        {/* Progress Bar */}
        <div className="mt-8 max-w-xs mx-auto">
          <div className="w-full bg-white/20 rounded-full h-2">
            <div
              className="bg-gradient-to-r from-pink-500 to-purple-500 h-2 rounded-full animate-pulse"
              style={{ width: '75%' }}
            ></div>
          </div>
        </div>
      </div>
    </div>
  );
} 