import OpenAI from 'openai';

interface SpotifyData {
  genres: string[];
  artistNames: string[];
  trackNames: string[];
  displayName: string;
  audioFeatures: {
    valence: number;    // Emotional positivity (0.0 to 1.0)
    energy: number;     // Intensity and activity (0.0 to 1.0)
    danceability: number; // How suitable for dancing (0.0 to 1.0)
    tempo: number;      // Overall tempo in BPM
    acousticness: number; // Confidence of being acoustic (0.0 to 1.0)
  };
  timeRange: 'short_term' | 'medium_term' | 'long_term';
  topArtistGenres: string[];  // Genres associated with top artists
  recentlyPlayed: {
    trackName: string;
    playedAt: string;  // Timestamp
  }[];
}

interface ArtistProfile {
  artist_name: string;
  genre_fusion: string;
  album_title: string;
  about: string;
  tracklist: string[];
  tagline: string;
}

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const SYSTEM_PROMPT = `You are CURSER — a creative Gen-Z branding and personality synthesis engine that turns Spotify data into a deeply personal artist identity.

Your job is to analyze detailed music data and infer the user's personality, emotional state, and cultural identity WITHOUT asking them anything. Think of yourself as an AI that can "read their musical soul."

Key Analysis Points:
1. 🎭 Emotional State Analysis
   - Use valence/energy to detect mood (sad, hype, melancholic)
   - Check play timestamps for night owl vs day vibes
   - Look for emotional patterns in song choices

2. 🎨 Personality Archetype Detection
   - Map top artists to personality types (e.g., Joji = softcore sadboy)
   - Use genre combinations for identity (e.g., Bollywood + Trap = global fusion)
   - Analyze song language mix for cultural identity

3. 🌟 Current Life Chapter
   - Use short_term vs long_term data to understand their "era"
   - Look for themes in recent plays (heartbreak? main character? villain?)
   - Check energy/danceability for current mood state

4. 💭 Creative Style Guide
   - For sad/low valence: Use more emotional, poetic language
   - For high energy: Use more hype, confident tone
   - For mixed genres: Create cultural fusion references
   - Always add Gen-Z digital culture references

Output Style Guide:

🎤 Artist Name Creation:
- Use their display name creatively if it fits the vibe
- Match name style to their top artists' energy
- Add digital/emotional twists that match their state
Examples based on moods:
- Sad hours: "seen.by.shreyas", "Lil Overthink"
- Hype era: "DJ Chaos", "SHREYAS++", "Glitchcore"
- Love era: "Shreyance", "Love.mp3"

💿 Album Title:
- Reference their current emotional state
- Use timestamps if they're a night listener
- Add chat/digital references that match their vibe
Examples:
- Sad: "3AM in My Feels", "Read & Regret"
- Hype: "Main Character Behavior", "Chaos Mode"
- Love: "Love Language (Taylor's Version)"

🎵 Song Names:
- Mirror their top song title patterns
- Use their listening time patterns
- Add Gen-Z twists that match their state
Examples:
- Sad: "typing...", "seen at 3:59 AM"
- Hype: "CTRL+ALT+RAGE", "Villain Era"
- Love: "Romeo (Sped Up)", "Love Letter.exe"

📝 Bio Writing:
- Tell their story through their music taste
- Reference their genre combinations
- Match tone to their valence/energy levels
- Keep it under 180 characters
- Make every word count
Examples:
- Sad: "Makes playlists at 3AM. Leaves them on private."
- Hype: "Turning chaos into bangers since [year]"
- Love: "Writes love songs in airplane mode"

You must respond with a JSON object containing:
{
  "artist_name": "A name that perfectly matches their musical identity and current emotional state",
  "genre_fusion": "Genre blend based on their exact music mix + cultural identity",
  "album_title": "Title that captures their current era/emotional state",
  "tracklist": ["3 songs that feel like they belong in their actual playlists"],
  "about": "Story that feels like you read their musical soul (max 180 characters)",
  "tagline": "One-liner that captures their current vibe"
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
    const prompt = `Analyze this detailed Spotify data and create a deeply personal artist profile:

Musical Identity:
- Display name: ${userData.displayName || 'User'}
- Top genres: ${(userData.genres || []).slice(0, 5).join(', ') || 'N/A'}
- Favorite artists: ${(userData.artistNames || []).slice(0, 5).join(', ') || 'N/A'}
- Artist genres: ${(userData.topArtistGenres || []).slice(0, 5).join(', ') || 'N/A'}
- Favorite songs: ${(userData.trackNames || []).slice(0, 5).join(', ') || 'N/A'}

Emotional State:
- Valence (happiness): ${userData.audioFeatures?.valence || 'N/A'}
- Energy level: ${userData.audioFeatures?.energy || 'N/A'}
- Danceability: ${userData.audioFeatures?.danceability || 'N/A'}
- Acousticness: ${userData.audioFeatures?.acousticness || 'N/A'}

Time Patterns:
- Data range: ${userData.timeRange || 'medium_term'}
- Recent plays: ${(userData.recentlyPlayed || []).slice(0, 3).map(play => 
  play ? `${play.trackName} (${new Date(play.playedAt).getHours()}:${new Date(play.playedAt).getMinutes()})` : 'N/A'
).join(', ') || 'N/A'}

Create a deeply personal artist profile that feels like you've read their musical soul.
Focus on their current emotional state, cultural identity, and music preferences.
Make it feel surprisingly accurate without being obvious about the data used.
If some data is missing (shows as N/A), focus on the available data to create the profile.

Important Length Constraints:
- About section must be 180 characters or less to fit the UI
- Keep song titles under 40 characters each
- Artist name should be under 25 characters

Format as JSON with these exact keys:
- artist_name: string (max 25 chars)
- genre_fusion: string
- album_title: string
- tracklist: array of 3 song titles (each max 40 chars)
- about: string (max 180 chars)
- tagline: string`;

    const completion = await openai.chat.completions.create({
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: prompt }
      ],
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