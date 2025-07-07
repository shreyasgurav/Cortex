import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({
    spotify_id_set: !!process.env.SPOTIFY_CLIENT_ID,
    spotify_secret_set: !!process.env.SPOTIFY_CLIENT_SECRET,
    nextauth_url_set: !!process.env.NEXTAUTH_URL,
    nextauth_secret_set: !!process.env.NEXTAUTH_SECRET,
  }, { status: 200 });
} 