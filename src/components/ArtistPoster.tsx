'use client';

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Download, ArrowLeft, RefreshCw, Play, Shuffle, MoreHorizontal, Sparkles, Music, LogOut } from 'lucide-react';
import html2canvas from 'html2canvas';
import { signOut } from 'next-auth/react';

interface SpotifyArtist {
  name: string;
  image: string;
  genres: string[];
}

interface SpotifyTrack {
  name: string;
  artist: string;
  image: string;
}

interface SpotifyData {
  topArtists: SpotifyArtist[];
  topTracks: SpotifyTrack[];
}

interface ArtistProfile {
  artist_name: string;
  genre_fusion: string;
  album_title: string;
  about: string;
  tracklist: string[];
}

interface ArtistPosterProps {
  artistIdentity: ArtistProfile;
  onRegenerate?: () => void;
  onBack?: () => void;
}

export default function ArtistPoster({ artistIdentity, onBack, onRegenerate }: ArtistPosterProps) {
  const [isExporting, setIsExporting] = useState(false);
  const [spotifyData, setSpotifyData] = useState<SpotifyData | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Generate random monthly listeners (between 100K - 1M)
  const monthlyListeners = Math.floor(Math.random() * 900000) + 100000;
  const formattedListeners = monthlyListeners.toLocaleString();

  useEffect(() => {
    const fetchSpotifyData = async () => {
      try {
        const response = await fetch('/api/spotify/user-data');
        if (!response.ok) {
          throw new Error('Failed to fetch Spotify data');
        }
        const data = await response.json();
        setSpotifyData(data);
      } catch (error) {
        console.error('Error:', error);
        setError(error instanceof Error ? error.message : 'Failed to fetch Spotify data');
      }
    };

    fetchSpotifyData();
  }, []);

  const handleDownload = async () => {
    setIsExporting(true);
    try {
      const element = document.getElementById('spotify-poster');
      if (element) {
        // Get the actual dimensions of the poster as displayed
        const rect = element.getBoundingClientRect();
        
        // Create a temporary container that matches the current display exactly
        const tempContainer = document.createElement('div');
        tempContainer.style.position = 'absolute';
        tempContainer.style.left = '-9999px';
        tempContainer.style.width = `${rect.width}px`;
        tempContainer.style.height = `${rect.height}px`;
        tempContainer.style.background = '#121212';
        document.body.appendChild(tempContainer);

        // Clone the poster and its styles
        const clone = element.cloneNode(true) as HTMLElement;
        clone.style.width = '100%';
        clone.style.height = '100%';
        clone.style.transform = 'none';
        
        // Ensure text is fully visible
        const style = document.createElement('style');
        style.textContent = `
          .text-transparent { opacity: 1 !important; }
          .text-white, .text-gray-300, .text-gray-400 { opacity: 1 !important; }
          .bg-clip-text { -webkit-background-clip: unset !important; background-clip: unset !important; }
          #spotify-poster * { line-height: 1.2 !important; }
        `;
        clone.appendChild(style);
        tempContainer.appendChild(clone);

        // Calculate the scale needed for high resolution while maintaining proportions
        const targetWidth = 1080;
        const scale = targetWidth / rect.width;

        // Render with exact proportions
        const canvas = await html2canvas(tempContainer, {
          width: rect.width,
          height: rect.height,
          scale: scale,
          backgroundColor: '#121212',
          allowTaint: true,
          useCORS: true,
          logging: false,
          onclone: (clonedDoc) => {
            // Fix text visibility in the cloned document
            const clonedStyle = document.createElement('style');
            clonedStyle.textContent = `
              .text-transparent { opacity: 1 !important; }
              .text-white, .text-gray-300, .text-gray-400 { opacity: 1 !important; }
              .bg-clip-text { -webkit-background-clip: unset !important; background-clip: unset !important; }
              #spotify-poster * { line-height: 1.2 !important; }
            `;
            clonedDoc.head.appendChild(clonedStyle);

            // Ensure all images are loaded
            const images = clonedDoc.getElementsByTagName('img');
            return Promise.all(Array.from(images).map(img => {
              if (img.complete) return Promise.resolve();
              return new Promise((resolve) => {
                img.onload = resolve;
                img.onerror = resolve;
              });
            }));
          }
        });

        // Create a high-quality PNG
        const link = document.createElement('a');
        link.download = `${artistIdentity.artist_name.replace(/[^a-zA-Z0-9]/g, '_')}_artist_profile.png`;
        link.href = canvas.toDataURL('image/png', 1.0);
        link.click();

        // Clean up
        document.body.removeChild(tempContainer);
      }
    } catch (error) {
      console.error('Error exporting image:', error);
    } finally {
      setIsExporting(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 p-2 sm:p-4">
      {/* Controls */}
      <div className="max-w-lg mx-auto mb-4 sm:mb-6">
        <div className="flex items-center justify-between backdrop-blur-sm bg-white/10 rounded-xl sm:rounded-2xl p-3 sm:p-4 border border-white/20">
          <button
            onClick={() => signOut()}
            className="text-white hover:bg-white/20 px-4 py-2 rounded-lg flex items-center gap-2 transition-all"
          >
            <LogOut className="w-4 h-4" />
            <span className="text-sm">Logout</span>
          </button>

          <div className="flex gap-2 sm:gap-3">
            <button
              onClick={onRegenerate}
              className="bg-gradient-to-r from-purple-500 to-pink-500 hover:from-purple-600 hover:to-pink-600 text-white px-4 py-2 rounded-lg flex items-center gap-2 transition-all"
            >
              <RefreshCw className="w-4 h-4" />
              <span className="text-sm">New Profile</span>
            </button>
            <button
              onClick={handleDownload}
              disabled={isExporting}
              className="bg-gradient-to-r from-pink-500 to-purple-500 hover:from-pink-600 hover:to-purple-600 text-white px-4 py-2 rounded-lg flex items-center gap-2 transition-all"
            >
              <Download className="w-4 h-4" />
              <span className="text-sm">{isExporting ? 'Exporting...' : 'Download'}</span>
            </button>
          </div>
        </div>
      </div>

      {/* Story Preview Container */}
      <div className="flex justify-center">
        <div className="relative w-full max-w-[360px]">
          {/* Fixed Aspect Ratio Container */}
          <div className="relative w-full pb-[177.777%]">
            <div
              id="spotify-poster"
              className="absolute inset-0 bg-[#121212] overflow-hidden rounded-2xl shadow-2xl"
            >
              {/* Content Container with Fixed Width */}
              <div className="w-[360px] h-[640px] relative">
                {/* Header Section - 48px */}
                <div className="h-[48px] bg-gradient-to-r from-purple-600 via-pink-500 to-orange-500 flex items-center justify-center relative overflow-hidden">
                  {/* Animated background elements */}
                  <div className="absolute inset-0">
                    <div className="absolute top-2 left-8 w-4 h-4 bg-white/20 rounded-full animate-pulse"></div>
                    <div className="absolute top-3 right-12 w-3 h-3 bg-yellow-300/30 rounded-full animate-bounce"></div>
                    <div className="absolute bottom-2 left-16 w-2 h-2 bg-pink-300/40 rounded-full animate-pulse"></div>
                    <div className="absolute bottom-2 right-20 w-3 h-3 bg-blue-300/25 rounded-full animate-bounce"></div>
                  </div>

                  {/* Sparkle icons */}
                  <Sparkles className="absolute top-2 left-4 w-3 h-3 text-yellow-300 animate-pulse" />
                  <Music className="absolute bottom-2 right-4 w-3 h-3 text-pink-300 animate-bounce" />
                  <Sparkles className="absolute top-3 right-6 w-2 h-2 text-blue-300 animate-pulse" />

                  {/* Main text */}
                  <div className="relative z-10 text-center">
                    <h1 className="text-lg font-black text-white tracking-wide">
                      <span className="bg-gradient-to-r from-white via-yellow-200 to-pink-200 bg-clip-text text-transparent">
                        If I Were an
                      </span>
                      <span className="bg-gradient-to-r from-yellow-300 via-pink-300 to-white bg-clip-text text-transparent animate-pulse ml-1">
                        Artist?
                      </span>
                    </h1>
                  </div>
                </div>

                {/* Banner Section - 120px */}
                <div className="h-[120px] relative overflow-hidden">
                  <div className="absolute inset-0 bg-gradient-to-br from-purple-500 via-pink-500 to-purple-600">
                    <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-black/30 to-transparent"></div>
                  </div>
                  <div className="absolute bottom-0 left-0 right-0 p-3">
                    <h1 className="text-2xl font-black tracking-tight text-white mb-0.5">{artistIdentity.artist_name}</h1>
                    <p className="text-xs text-gray-300">{formattedListeners} monthly listeners</p>
                  </div>
                </div>

                {/* Main Content Section - 456px */}
                <div className="h-[456px] px-4 py-3 flex flex-col">
                  {/* Controls Section - 32px */}
                  <div className="h-[32px] flex items-center gap-2">
                    <div className="w-6 h-6 bg-green-500 rounded-full flex items-center justify-center">
                      <Play className="w-2.5 h-2.5 text-black fill-current ml-0.5" />
                    </div>
                    <Shuffle className="w-4 h-4 text-gray-400" />
                    <MoreHorizontal className="w-4 h-4 text-gray-400 ml-auto" />
                  </div>

                  {/* Popular Section - 96px */}
                  <div className="h-[96px] mt-3">
                    <h3 className="text-xs font-bold text-white mb-1">Popular</h3>
                    <div className="space-y-1">
                      {artistIdentity.tracklist.slice(0, 3).map((track, index) => (
                        <div key={index} className="h-[24px] flex items-center group hover:bg-white/5 rounded py-1 px-1.5">
                          <div className="w-5 h-5 bg-gradient-to-br from-purple-500 to-pink-500 rounded flex-shrink-0"></div>
                          <div className="flex-1 min-w-0 ml-2">
                            <div className="text-white text-xs font-medium leading-normal">{track}</div>
                          </div>
                          <div className="text-gray-400 text-xs ml-1.5">{['3:42', '4:18', '3:56'][index]}</div>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Latest Release Section - 72px */}
                  <div className="h-[72px] mt-3">
                    <h3 className="text-xs font-bold text-white mb-1">Latest Release</h3>
                    <div className="flex items-center gap-2 bg-white/5 rounded p-1.5">
                      <div className="w-8 h-8 bg-gradient-to-br from-purple-500 to-pink-500 rounded flex-shrink-0"></div>
                      <div className="flex-1 min-w-0">
                        <h4 className="text-[11px] text-white font-semibold leading-normal">{artistIdentity.album_title}</h4>
                        <p className="text-[10px] text-gray-400 mt-0.5">Album • 2024</p>
                      </div>
                    </div>
                  </div>

                  {/* About Section - 96px */}
                  <div className="h-[96px] mt-3">
                    <h3 className="text-xs font-bold text-white mb-1">About</h3>
                    <p className="text-xs text-gray-300 leading-normal line-clamp-4">{artistIdentity.about}</p>
                  </div>

                  {/* Inspired By Section - 160px */}
                  <div className="h-[160px] mt-3">
                    <h3 className="text-xs font-bold text-white mb-1">
                      <span className="bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
                        Inspired By
                      </span>
                    </h3>
                    <div className="grid grid-cols-2 gap-2 h-[136px]">
                      {/* Top Artists */}
                      <div className="bg-white/5 rounded-lg p-2">
                        <h4 className="text-[11px] text-white font-semibold mb-1.5">Top Artists</h4>
                        <div className="space-y-1">
                          {spotifyData?.topArtists.slice(0, 5).map((artist, index) => (
                            <div key={index} className="h-[20px] flex items-center gap-1.5">
                              <div className="w-4 h-4 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full overflow-hidden flex-shrink-0">
                                {artist.image && (
                                  <img src={artist.image} alt={artist.name} className="w-full h-full object-cover" />
                                )}
                              </div>
                              <p className="text-[11px] text-gray-300 truncate flex-1 leading-normal">{artist.name}</p>
                            </div>
                          ))}
                        </div>
                      </div>

                      {/* Top Songs */}
                      <div className="bg-white/5 rounded-lg p-2">
                        <h4 className="text-[11px] text-white font-semibold mb-1.5">Top Songs</h4>
                        <div className="space-y-1">
                          {spotifyData?.topTracks.slice(0, 5).map((track, index) => (
                            <div key={index} className="h-[20px] flex items-center gap-1.5">
                              <div className="w-4 h-4 bg-gradient-to-br from-purple-500 to-pink-500 rounded overflow-hidden flex-shrink-0">
                                {track.image && (
                                  <img src={track.image} alt={track.name} className="w-full h-full object-cover" />
                                )}
                              </div>
                              <p className="text-[11px] text-gray-300 truncate leading-normal">{track.name}</p>
                            </div>
                          ))}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
} 