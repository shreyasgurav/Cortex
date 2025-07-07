# If I Were an Artist 🎨

A viral Instagram Story generator that turns your Spotify data into a fictional artist identity. This app analyzes your music taste and generates a custom artist profile that reflects your personality, vibe, emotions, and music aesthetic.

## Features ✨

- 🎵 Connect with Spotify to analyze your music taste
- 🎨 Generate a unique artist identity with AI
- 📸 Create beautiful, shareable Instagram Story cards
- 🎭 Get a custom artist name, genre fusion, and fictional album
- 🖼️ Generate AI art for your artist profile
- 📱 Mobile-first, beautiful UI design

## Getting Started 🚀

### Prerequisites

- Node.js 18+ and npm
- Spotify Developer Account
- OpenAI API Key

### Environment Variables

Create a `.env` file in the root directory with the following variables:

```env
# Spotify API credentials
SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret

# OpenAI API key
OPENAI_API_KEY=your_openai_api_key

# NextAuth configuration
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=your_nextauth_secret # Generate with: openssl rand -base64 32
```

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/if-i-were-an-artist.git
cd if-i-were-an-artist
```

2. Install dependencies:
```bash
npm install
```

3. Run the development server:
```bash
npm run dev
```

4. Open [http://localhost:3000](http://localhost:3000) in your browser.

## How It Works 🎯

1. User logs in with Spotify
2. We fetch their top artists, tracks, and genres
3. AI generates a custom artist profile including:
   - Artist stage name
   - Genre fusion (2-3 genre mashup)
   - Imaginary album title
   - 2-3 fictional song names
   - An emotional "About" section
   - A short, iconic tagline
   - A list of "Inspired by" artists
4. DALL·E generates a unique artist photo
5. Users can share their profile to Instagram Stories

## Tech Stack 💻

- Next.js 13+ with App Router
- TypeScript
- TailwindCSS
- Framer Motion
- NextAuth.js
- OpenAI API (GPT-4 & DALL·E 3)
- Spotify Web API

## Contributing 🤝

Contributions are welcome! Please feel free to submit a Pull Request.

## License 📄

This project is licensed under the MIT License - see the LICENSE file for details.
