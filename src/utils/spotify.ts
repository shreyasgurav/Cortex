import SpotifyWebApi from 'spotify-web-api-node';
import { SpotifyUserData } from '../types/artist';

export async function getSpotifyUserData(accessToken: string): Promise<SpotifyUserData> {
  const spotify = new SpotifyWebApi({
    accessToken
  });

  try {
    const [
      userProfile,
      topArtists,
      topTracks
    ] = await Promise.all([
      spotify.getMe(),
      spotify.getMyTopArtists({ limit: 10, time_range: 'medium_term' }),
      spotify.getMyTopTracks({ limit: 10, time_range: 'medium_term' })
    ]);

    // Get all unique genres from top artists
    const allGenres = topArtists.body.items.flatMap(artist => artist.genres);
    const uniqueGenres = [...new Set(allGenres)];
    const topGenres = uniqueGenres.slice(0, 5); // Get top 5 unique genres

    const userData: SpotifyUserData = {
      USER_NAME: userProfile.body.display_name || 'User',
      // Top 3 artists with images for main influences
      ARTIST_1: {
        name: topArtists.body.items[0]?.name || '',
        image: topArtists.body.items[0]?.images[0]?.url || ''
      },
      ARTIST_2: {
        name: topArtists.body.items[1]?.name || '',
        image: topArtists.body.items[1]?.images[0]?.url || ''
      },
      ARTIST_3: {
        name: topArtists.body.items[2]?.name || '',
        image: topArtists.body.items[2]?.images[0]?.url || ''
      },
      // Top 3 songs with images for main influences
      SONG_1: {
        name: topTracks.body.items[0]?.name || '',
        image: topTracks.body.items[0]?.album.images[0]?.url || ''
      },
      SONG_2: {
        name: topTracks.body.items[1]?.name || '',
        image: topTracks.body.items[1]?.album.images[0]?.url || ''
      },
      SONG_3: {
        name: topTracks.body.items[2]?.name || '',
        image: topTracks.body.items[2]?.album.images[0]?.url || ''
      },
      // Top 3 genres for genre fusion
      GENRE_1: topGenres[0] || '',
      GENRE_2: topGenres[1] || '',
      GENRE_3: topGenres[2] || '',
      // Additional data for better context
      ADDITIONAL_ARTISTS: topArtists.body.items.slice(3, 10).map(artist => ({
        name: artist.name,
        image: artist.images[0]?.url || ''
      })),
      ADDITIONAL_SONGS: topTracks.body.items.slice(3, 10).map(track => ({
        name: track.name,
        image: track.album.images[0]?.url || '',
        artist: track.artists[0].name
      })),
      ADDITIONAL_GENRES: topGenres.slice(3),
      // Get some mood/tempo data from tracks
      MOOD_DATA: topTracks.body.items.slice(0, 5).map(track => ({
        name: track.name,
        artist: track.artists[0].name,
        popularity: track.popularity,
        image: track.album.images[0]?.url || ''
      }))
    };

    return userData;
  } catch (error) {
    console.error('Error fetching Spotify data:', error);
    throw error;
  }
} 