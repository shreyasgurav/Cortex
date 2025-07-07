'use client';

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Download, ArrowLeft, RefreshCw, Play, Shuffle, MoreHorizontal, Sparkles, Music } from 'lucide-react';
import html2canvas from 'html2canvas';

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
  onBack: () => void;
  onRegenerate?: () => void;
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
        const canvas = await html2canvas(element, {
          width: 1080,
          height: 1920,
          scale: 2,
          backgroundColor: '#121212',
          allowTaint: true,
          useCORS: true,
          logging: false,
          onclone: (clonedDoc) => {
            // Ensure all images are loaded before capture
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

        // Create a high-quality download
        const link = document.createElement('a');
        link.download = `${artistIdentity.artist_name.replace(/\s+/g, '_')}_artist_profile.png`;
        link.href = canvas.toDataURL('image/png', 1.0);
        link.click();
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
          <Button onClick={onBack} variant="ghost" className="text-white hover:bg-white/20">
            <ArrowLeft className="w-4 h-4 mr-1 sm:mr-2" />
            <span className="text-sm sm:text-base">Back</span>
          </Button>

          <div className="flex gap-2 sm:gap-3">
            {onRegenerate && (
              <Button onClick={onRegenerate} variant="ghost" className="text-white hover:bg-white/20">
                <RefreshCw className="w-4 h-4 mr-1 sm:mr-2" />
                <span className="text-sm sm:text-base">Regenerate</span>
              </Button>
            )}
            <Button
              onClick={handleDownload}
              disabled={isExporting}
              className="bg-gradient-to-r from-pink-500 to-purple-500 hover:from-pink-600 hover:to-purple-600 text-white"
            >
              <Download className="w-4 h-4 mr-1 sm:mr-2" />
              <span className="text-sm sm:text-base">{isExporting ? 'Exporting...' : 'Download'}</span>
            </Button>
          </div>
        </div>
      </div>

      {/* Story Preview */}
      <div className="flex justify-center">
        <div className="relative w-full max-w-[360px] sm:max-w-[390px] md:max-w-[420px]">
          <div
            id="spotify-poster"
            className="w-full aspect-[9/16] bg-[#121212] relative overflow-hidden rounded-2xl sm:rounded-3xl shadow-2xl"
          >
            {/* "If I Were an Artist?" Header Section */}
            <div className="relative h-16 bg-gradient-to-r from-purple-600 via-pink-500 to-orange-500 flex items-center justify-center overflow-hidden">
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
                  <br />
                  <span className="text-xl bg-gradient-to-r from-yellow-300 via-pink-300 to-white bg-clip-text text-transparent animate-pulse">
                    Artist?
                  </span>
                </h1>
              </div>

              {/* Decorative border */}
              <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-gradient-to-r from-transparent via-white/50 to-transparent"></div>
            </div>

            {/* Banner Section */}
            <div className="relative h-[20%] overflow-hidden">
              <div className="absolute inset-0 bg-gradient-to-br from-purple-500 via-pink-500 to-purple-600">
                <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-black/30 to-transparent"></div>
                <div className="absolute top-[15%] right-[15%] w-16 h-16 bg-white/20 rounded-full blur-2xl"></div>
                <div className="absolute bottom-[20%] left-[15%] w-12 h-12 bg-pink-400/30 rounded-full blur-xl"></div>
              </div>

              <div className="absolute bottom-0 left-0 right-0 p-3">
                <h1 className="text-2xl font-black tracking-tight text-white mb-0.5">{artistIdentity.artist_name}</h1>
                <p className="text-xs text-gray-300">{formattedListeners} monthly listeners</p>
              </div>
            </div>

            {/* Main Content */}
            <div className="px-4 pt-3 pb-4 flex flex-col">
              {/* Controls Section */}
              <div className="flex items-center gap-2 h-[8%]">
                <div className="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center">
                  <Play className="w-3 h-3 text-black fill-current ml-0.5" />
                </div>
                <Shuffle className="w-4 h-4 text-gray-400" />
                <MoreHorizontal className="w-4 h-4 text-gray-400 ml-auto" />
              </div>

              {/* Popular Tracks */}
              <div className="h-[20%] mt-2">
                <h3 className="text-sm font-bold text-white mb-1.5">Popular</h3>
                <div className="space-y-1">
                  {artistIdentity.tracklist.slice(0, 4).map((track, index) => (
                    <div
                      key={index}
                      className="flex items-center group hover:bg-white/5 rounded p-1"
                    >
                      <div className="w-4 text-gray-400 text-xs font-medium">{index + 1}</div>
                      <div className="w-5 h-5 bg-gradient-to-br from-purple-500 to-pink-500 rounded mx-1.5"></div>
                      <div className="flex-1 min-w-0">
                        <div className="text-white text-xs font-medium truncate">{track}</div>
                      </div>
                      <div className="text-gray-400 text-xs">{['3:42', '4:18', '3:56', '4:02'][index]}</div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Latest Release */}
              <div className="h-[12%] mt-2">
                <h3 className="text-sm font-bold text-white mb-1.5">Latest Release</h3>
                <div className="flex items-center gap-2 bg-white/5 rounded p-1.5">
                  <div className="w-8 h-8 bg-gradient-to-br from-purple-500 to-pink-500 rounded"></div>
                  <div className="flex-1 min-w-0">
                    <h4 className="text-xs text-white font-semibold truncate">{artistIdentity.album_title}</h4>
                    <p className="text-xs text-gray-400">Album • 2024</p>
                  </div>
                </div>
              </div>

              {/* About Section */}
              <div className="h-[20%] mt-4">
                <h3 className="text-sm font-bold text-white mb-0.5">About</h3>
                <p className="text-xs text-gray-300 leading-tight line-clamp-4">{artistIdentity.about}</p>
              </div>

              {/* Inspired By Section */}
              <div className="mt-2">
                <h3 className="text-sm font-bold text-white mb-2">
                  <span className="bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
                    Inspired By
                  </span>
                </h3>
                <div className="grid grid-cols-2 gap-2">
                  {/* Top Artists */}
                  <div className="bg-white/5 rounded-lg p-2">
                    <h4 className="text-xs text-white font-semibold mb-1.5">Top Artists</h4>
                    <div className="space-y-1">
                      {spotifyData?.topArtists.map((artist, index) => (
                        <div 
                          key={index}
                          className="flex items-center gap-1.5"
                        >
                          <div className="w-4 h-4 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full overflow-hidden">
                            {artist.image && (
                              <img 
                                src={artist.image} 
                                alt={artist.name}
                                className="w-full h-full object-cover"
                              />
                            )}
                          </div>
                          <p className="text-xs text-gray-300 truncate flex-1">{artist.name}</p>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Top Songs */}
                  <div className="bg-white/5 rounded-lg p-2">
                    <h4 className="text-xs text-white font-semibold mb-1.5">Top Songs</h4>
                    <div className="space-y-1">
                      {spotifyData?.topTracks.map((track, index) => (
                        <div 
                          key={index}
                          className="flex items-center gap-1.5"
                        >
                          <div className="w-4 h-4 bg-gradient-to-br from-purple-500 to-pink-500 rounded overflow-hidden">
                            {track.image && (
                              <img 
                                src={track.image} 
                                alt={track.name}
                                className="w-full h-full object-cover"
                              />
                            )}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-xs text-gray-300 truncate">{track.name}</p>
                          </div>
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
  );
} 