import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import SpotifyWebApi from 'spotify-web-api-node';
import { authOptions } from '../../auth/[...nextauth]/route';

export async function GET(req: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session?.accessToken) {
      return NextResponse.json(
        { error: 'Please sign in to access Spotify data' },
        { status: 401 }
      );
    }

    const spotify = new SpotifyWebApi({
      accessToken: session.accessToken
    });

    // Fetch all data in parallel
    const [topArtists, topTracks] = await Promise.all([
      spotify.getMyTopArtists({ limit: 5, time_range: 'medium_term' }),
      spotify.getMyTopTracks({ limit: 5, time_range: 'medium_term' })
    ]);

    // Process and return the data
    const userData = {
      topArtists: topArtists.body.items.map(artist => ({
        name: artist.name,
        image: artist.images[0]?.url || '',
        genres: artist.genres
      })),
      topTracks: topTracks.body.items.map(track => ({
        name: track.name,
        artist: track.artists[0].name,
        image: track.album.images[0]?.url || ''
      }))
    };

    return NextResponse.json(userData);
  } catch (error) {
    console.error('Error fetching Spotify data:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Failed to fetch Spotify data' },
      { status: 500 }
    );
  }
} 