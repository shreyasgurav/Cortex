import OpenAI from 'openai';

interface SpotifyData {
  genres: string[];
  artistNames: string[];
  trackNames: string[];
}

interface ArtistProfile {
  artist_name: string;
  genre_fusion: string;
  album_title: string;
  about: string;
  tracklist: string[];
}

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const SYSTEM_PROMPT = `You are CURSER — a creative Gen-Z branding and personality synthesis engine. You help build a web app called "If I Were an Artist" — a viral Instagram Story generator that turns a user's Spotify data into a fictional artist identity.

Your job is to analyze their music taste and generate a custom artist profile that reflects their personality, vibe, emotions, and music aesthetic — like a character that could exist in the real world, but is fictionalized based on their Spotify listening patterns.

Think like a creative director at a Gen-Z record label. Every word should feel aesthetic, bold, sad-happy, romanticized, or poetic. Song and album names should feel emotional or vibey, not random. About sections should tell a story or reflect a personality. Taglines should feel like something people would post on their IG bio.

Use the provided data to create a deeply personalized profile:
- Analyze their top artists and additional artists to understand their core influences
- Look at their top songs and additional songs to understand their musical storytelling preferences
- Use their genre data to create a unique genre fusion that captures their taste
- Consider the mood data to understand their vibe
- Create song titles that feel like they belong in their music library
- Write an "about" section that captures the emotional essence of their music taste
- Generate a tagline that their favorite artists might use

You must respond with a JSON object containing:
{
  "artist_name": "A creative stage name that reflects their musical identity",
  "genre_fusion": "Creative genre combo based on their top and additional genres",
  "album_title": "Fictional album title that matches their music's emotional tone",
  "tracklist": ["Track 1 - emotional/vibey", "Track 2 - based on their taste", "Track 3 - matches their style"],
  "about": "Short, poetic artist bio that captures their musical soul",
  "tagline": "Short, bold one-liner their favorite artists would use",
  "top_artists": ["Artist 1", "Artist 2", "Artist 3"],
  "top_songs": [
    { "name": "Song 1", "artist": "Artist 1" },
    { "name": "Song 2", "artist": "Artist 2" },
    { "name": "Song 3", "artist": "Artist 3" },
    { "name": "Song 4", "artist": "Artist 4" },
    { "name": "Song 5", "artist": "Artist 5" }
  ]
}`;

function handleOpenAIError(error: any): never {
  if (error?.response?.status === 429) {
    throw new Error('Our AI service is currently at capacity. Please try again in a few minutes.');
  } else if (error?.response?.status === 401) {
    throw new Error('AI service configuration error. Please contact support.');
  } else {
    throw new Error(error?.message || 'An error occurred while generating your artist profile.');
  }
}

export async function generateArtistProfile(userData: SpotifyData): Promise<ArtistProfile> {
  try {
    const prompt = `Based on this Spotify data:
- Top genres: ${userData.genres.slice(0, 5).join(', ')}
- Favorite artists: ${userData.artistNames.slice(0, 5).join(', ')}
- Favorite songs: ${userData.trackNames.slice(0, 5).join(', ')}

Create a fictional artist profile with:
1. A creative artist name that reflects these musical influences
2. A unique genre fusion description
3. An album title that captures the essence
4. A compelling artist bio (2-3 sentences)
5. A list of 4 fictional song titles that would be on their most popular EP

Format the response as JSON with these exact keys: 
- artist_name: string
- genre_fusion: string
- album_title: string
- about: string
- tracklist: array of 4 song titles`;

    const completion = await openai.chat.completions.create({
      messages: [{ role: "user", content: prompt }],
      model: "gpt-3.5-turbo",
      temperature: 0.9,
      response_format: { type: "json_object" }
    });

    const response = completion.choices[0].message.content;
    if (!response) throw new Error('No response from OpenAI');

    const profile: ArtistProfile = JSON.parse(response);
    return profile;
  } catch (error) {
    console.error('Error generating artist profile:', error);
    throw error;
  }
}

export async function generateArtistImage(profile: ArtistProfile): Promise<string> {
  try {
    const prompt = `Create a stylish, aesthetic profile photo for a music artist named "${profile.artist_name}". Style: ${profile.genre_fusion}. Vibe: ${profile.tagline}. Make it look like a professional artist photo that would appear on Spotify or Instagram.`;
    
    const response = await openai.images.generate({
      model: "dall-e-3",
      prompt,
      n: 1,
      size: "1024x1024",
      quality: "hd",
      style: "vivid"
    });

    if (!response.data?.[0]?.url) {
      throw new Error('Failed to generate artist image');
    }

    return response.data[0].url;
  } catch (error) {
    console.error('Error generating artist image:', error);
    handleOpenAIError(error);
  }
} 