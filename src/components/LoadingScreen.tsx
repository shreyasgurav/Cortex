'use client';

export default function LoadingScreen() {
  return (
    <div className="h-screen w-screen flex flex-col items-center justify-center bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900">
      <div className="relative">
        <div className="w-16 h-16 border-4 border-purple-200 border-t-purple-500 rounded-full animate-spin"></div>
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-8 h-8 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full animate-pulse"></div>
        </div>
      </div>
      <h2 className="mt-8 text-xl font-semibold text-transparent bg-clip-text bg-gradient-to-r from-white via-purple-200 to-pink-200 animate-pulse">
        Creating Your Artist Profile...
      </h2>
    </div>
  );
} 