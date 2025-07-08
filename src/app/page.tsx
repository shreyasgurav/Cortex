'use client';

import { useState, useEffect } from 'react';
import { useSession, signIn } from 'next-auth/react';
import { Music, Sparkles, Play } from 'lucide-react';
import LoadingScreen from '@/components/LoadingScreen';
import ArtistPoster from '@/components/ArtistPoster';
import { Button } from '@/components/ui/button';
import { GeneratedProfile } from '@/types/artist';

export default function Home() {
  const [isHovered, setIsHovered] = useState(false);
  const { data: session, status } = useSession();
  const [profile, setProfile] = useState<GeneratedProfile | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const generateProfile = async () => {
    try {
      setIsLoading(true);
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
    } catch (error) {
      console.error('Error:', error);
      setError(error instanceof Error ? error.message : 'Something went wrong');
    } finally {
      setIsLoading(false);
    }
  };

  // Auto-generate profile when logged in
  useEffect(() => {
    if (session?.error === 'RefreshAccessTokenError') {
      signIn('spotify');
      return;
    }
    
    if (session && !profile && !isLoading) {
      generateProfile();
    }
  }, [session, profile, isLoading]);

  if (status === 'loading' || isLoading) {
    return <LoadingScreen />;
  }

  if (!session) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 relative overflow-hidden flex items-center justify-center">
        {/* Animated Background Elements */}
        <div className="absolute inset-0">
          {/* Floating Orbs */}
          <div className="absolute top-20 left-20 w-32 h-32 bg-purple-500/20 rounded-full blur-xl animate-pulse"></div>
          <div className="absolute top-40 right-32 w-24 h-24 bg-pink-500/20 rounded-full blur-lg animate-bounce"></div>
          <div className="absolute bottom-32 left-40 w-20 h-20 bg-blue-500/20 rounded-full blur-md animate-pulse"></div>
          <div className="absolute bottom-20 right-20 w-28 h-28 bg-indigo-500/20 rounded-full blur-xl animate-bounce"></div>

          {/* Subtle Grid Pattern */}
          <div
            className="absolute inset-0 opacity-5"
            style={{
              backgroundImage: `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='%23ffffff' fillOpacity='0.1'%3E%3Ccircle cx='20' cy='20' r='1'/%3E%3C/g%3E%3C/svg%3E")`,
            }}
          ></div>
        </div>

        {/* Main Content */}
        <div className="relative z-10 text-center max-w-4xl mx-auto px-6">
          {/* Logo/Icon */}
          <div className="mb-8 flex justify-center">
            <div className="relative">
              <div className="w-20 h-20 bg-gradient-to-r from-purple-500 to-pink-500 rounded-full flex items-center justify-center shadow-2xl shadow-purple-500/25 animate-pulse">
                <Music className="w-10 h-10 text-white" />
              </div>
            </div>
          </div>

          {/* Main Title */}
          <div className="mb-6">
            <h1 className="text-6xl md:text-8xl font-black mb-4">
              <span className="bg-gradient-to-r from-white via-purple-200 to-pink-200 bg-clip-text text-transparent animate-pulse">
                If I Were an
              </span>
              <br />
              <span className="bg-gradient-to-r from-purple-400 via-pink-400 to-blue-400 bg-clip-text text-transparent">
                Artist ?
              </span>
            </h1>
            <div className="w-32 h-1 bg-gradient-to-r from-purple-500 to-pink-500 mx-auto rounded-full animate-pulse"></div>
          </div>

          {/* Subtitle */}
          <p className="text-xl md:text-2xl text-gray-300 mb-12 max-w-2xl mx-auto leading-relaxed">
            Discover your musical alter ego
          </p>

          {/* Spotify Login Button */}
          <div className="mb-4">
            <button
              onClick={() => signIn('spotify')}
              onMouseEnter={() => setIsHovered(true)}
              onMouseLeave={() => setIsHovered(false)}
              className="group relative bg-gradient-to-r from-green-500 to-green-600 hover:from-green-400 hover:to-green-500 text-white font-bold py-4 px-6 sm:py-5 sm:px-8 md:py-6 md:px-12 rounded-full text-base sm:text-lg md:text-xl shadow-2xl shadow-green-500/25 transition-all duration-500 hover:scale-110 hover:shadow-green-400/40"
            >
              {/* Button Background Animation */}
              <div className="absolute inset-0 bg-gradient-to-r from-green-400 to-green-500 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-500"></div>

              {/* Button Content */}
              <div className="relative flex items-center gap-2 sm:gap-3 md:gap-4">
                <div className="w-6 h-6 sm:w-7 sm:h-7 md:w-8 md:h-8 bg-white rounded-full flex items-center justify-center">
                  <Play className="w-3 h-3 sm:w-3.5 sm:h-3.5 md:w-4 md:h-4 text-green-500 fill-current ml-0.5" />
                </div>
                <span>Connect with Spotify</span>
                {isHovered && <Sparkles className="hidden sm:block w-4 h-4 sm:w-4.5 sm:h-4.5 md:w-5 md:h-5 animate-spin" />}
              </div>
            </button>
          </div>

          {/* Description */}
          <p className="text-xs sm:text-sm md:text-base text-gray-400 max-w-xs sm:max-w-sm md:max-w-xl mx-auto leading-relaxed opacity-80 px-4">
            Connect with Spotify and let AI transform your music taste into a unique artist identity, complete with personalized aesthetics and vibes.
          </p>
        </div>

        {/* Floating Music Icons */}
        <div className="absolute top-1/4 left-12 text-white/20 animate-float">
          <Music className="w-5 h-5" />
        </div>
        <div className="absolute bottom-1/3 right-12 text-white/20 animate-pulse">
          <Music className="w-3 h-3" />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="h-screen w-screen flex items-center justify-center bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900">
        <div className="bg-red-500/20 border border-red-500/50 text-white p-4 rounded-lg text-center max-w-md mx-4">
          {error}
          <button
            onClick={generateProfile}
            className="mt-4 px-4 py-2 bg-white/20 rounded-lg hover:bg-white/30 transition-all"
          >
            Try Again
          </button>
        </div>
      </div>
    );
  }

  return profile ? (
    <ArtistPoster
      artistIdentity={profile.profile}
      onRegenerate={generateProfile}
    />
  ) : null;
}
