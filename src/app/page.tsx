'use client';

import { useState, useEffect } from 'react';
import { Music, Sparkles, Instagram, Download } from 'lucide-react';
import { Button } from '@/components/ui/button';
import LoadingScreen from '@/components/LoadingScreen';
import ArtistPoster from '@/components/ArtistPoster';
import { useSession, signIn } from 'next-auth/react';
import { GeneratedProfile } from '@/types/artist';

export default function HomePage() {
  const { data: session, status } = useSession();
  const [currentStep, setCurrentStep] = useState<'landing' | 'loading' | 'poster'>('landing');
  const [profile, setProfile] = useState<GeneratedProfile | null>(null);
  const [error, setError] = useState<string | null>(null);

  const generateProfile = async () => {
    try {
      setCurrentStep('loading');
      const response = await fetch('/api/generate', {
        method: 'POST',
      });

      if (!response.ok) {
        const errorData = await response.json();
        if (errorData.error?.includes('access token expired')) {
          await signIn('spotify');
          return;
        }
        throw new Error(errorData.error || 'Failed to generate profile');
      }

      const data = await response.json();
      setProfile(data);
      setCurrentStep('poster');
    } catch (error) {
      console.error('Error:', error);
      setError(error instanceof Error ? error.message : 'Something went wrong');
      setCurrentStep('landing');
    }
  };

  useEffect(() => {
    if (session?.error === 'RefreshAccessTokenError') {
      signIn('spotify');
    }
  }, [session]);

  if (currentStep === 'loading') {
    return <LoadingScreen />;
  }

  if (currentStep === 'poster' && profile) {
    return (
      <ArtistPoster
        artistIdentity={profile.profile}
        onBack={() => setCurrentStep('landing')}
        onRegenerate={generateProfile}
      />
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 relative overflow-hidden">
      {/* Top Rectangle Section */}
      <div className="relative z-20 w-full flex justify-center px-4">
        <div className="glass mt-6 p-4 rounded-lg w-full max-w-4xl">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-md bg-purple-500/20">
                <Music className="w-5 h-5 text-purple-300" />
              </div>
              <span className="text-sm font-medium text-purple-200">If I Were an Artist</span>
            </div>
            <div className="text-xs text-purple-300">✨ AI-Powered Artist Identity Generator</div>
          </div>
        </div>
      </div>

      {/* Top Notification Banner */}
      <div className="relative z-20 w-full flex justify-center">
        <div className="glass mt-4 px-6 py-3 rounded-full flex items-center gap-2 animate-float hover:scale-105 transition-transform cursor-pointer">
          <Sparkles className="w-4 h-4 text-pink-400" />
          <span className="text-sm font-medium">Transform your music taste into art ✨</span>
        </div>
      </div>

      {/* Background Effects */}
      <div className="absolute inset-0 opacity-20">
        <div
          className="absolute inset-0"
          style={{
            backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fillRule='evenodd'%3E%3Cg fill='%239C92AC' fillOpacity='0.1'%3E%3Ccircle cx='30' cy='30' r='2'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
          }}
        ></div>
      </div>

      <div className="relative z-10 flex flex-col items-center justify-center min-h-screen px-6 text-center pt-24">
        {/* Header */}
        <div className="mb-8">
          <div className="flex items-center justify-center mb-4">
            <div className="p-3 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 shadow-lg shadow-purple-500/25">
              <Music className="w-8 h-8 text-white" />
            </div>
          </div>
          <h1 className="text-5xl md:text-7xl font-bold text-gradient mb-4">
            If I Were an Artist
          </h1>
          <p className="text-xl md:text-2xl text-gray-300 max-w-2xl mx-auto leading-relaxed">
            Discover your musical alter ego through AI magic ✨
          </p>
        </div>

        {error && (
          <div className="mb-8 w-full max-w-md">
            <div className="bg-red-500/20 border border-red-500/50 text-white p-4 rounded-lg text-center">
              {error}
            </div>
          </div>
        )}

        {/* Features */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12 max-w-4xl">
          <div className="card">
            <Sparkles className="w-8 h-8 text-pink-400 mb-3 mx-auto" />
            <h3 className="text-lg font-semibold text-white mb-2">AI-Generated Identity</h3>
            <p className="text-gray-300 text-sm">
              Get a unique artist name, genre fusion, and album based on your Spotify taste
            </p>
          </div>
          <div className="card">
            <Instagram className="w-8 h-8 text-purple-400 mb-3 mx-auto" />
            <h3 className="text-lg font-semibold text-white mb-2">Story-Ready Poster</h3>
            <p className="text-gray-300 text-sm">Beautiful 1080x1920 poster perfect for Instagram Stories</p>
          </div>
          <div className="card">
            <Download className="w-8 h-8 text-blue-400 mb-3 mx-auto" />
            <h3 className="text-lg font-semibold text-white mb-2">Download & Share</h3>
            <p className="text-gray-300 text-sm">Export your artist identity and share with the world</p>
          </div>
        </div>

        {/* CTA Button */}
        {!session ? (
          <button
            onClick={() => signIn('spotify')}
            className="btn-spotify"
          >
            <Music className="w-5 h-5 mr-2" />
            Start with Spotify Login
          </button>
        ) : (
          <button
            onClick={generateProfile}
            className="btn-gradient"
          >
            <Sparkles className="w-5 h-5 mr-2" />
            Generate My Artist Profile
          </button>
        )}

        <p className="text-gray-400 text-sm mt-4 max-w-md">
          We'll analyze your top artists, songs, and genres to create your perfect musical persona
        </p>
      </div>
    </div>
  );
}
