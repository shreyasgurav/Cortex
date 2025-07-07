import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import SpotifyWebApi from 'spotify-web-api-node';
import { generateArtistProfile } from '@/utils/openai';
import { authOptions } from '../auth/[...nextauth]/route';

export async function POST(req: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session?.accessToken) {
      return NextResponse.json(
        { error: 'Please sign in to generate your artist profile' },
        { status: 401 }
      );
    }

    // Get Spotify data for AI generation
    const spotify = new SpotifyWebApi({
      accessToken: session.accessToken
    });

    const [topArtists, topTracks] = await Promise.all([
      spotify.getMyTopArtists({ limit: 5, time_range: 'medium_term' }),
      spotify.getMyTopTracks({ limit: 5, time_range: 'medium_term' })
    ]);

    // Prepare data for AI generation
    const userData = {
      genres: topArtists.body.items.flatMap(artist => artist.genres),
      artistNames: topArtists.body.items.map(artist => artist.name),
      trackNames: topTracks.body.items.map(track => track.name)
    };

    // Generate artist profile using AI
    const profile = await generateArtistProfile(userData);

    return NextResponse.json({ profile });
  } catch (error) {
    console.error('Error in generate route:', error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Failed to generate artist profile' },
      { status: 500 }
    );
  }
} 