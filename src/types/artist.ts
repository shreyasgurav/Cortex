export interface SpotifyItem {
  name: string;
  image: string;
}

export interface SpotifyTrack extends SpotifyItem {
  artist: string;
}

export interface SpotifyUserData {
  USER_NAME: string;
  ARTIST_1: SpotifyItem;
  ARTIST_2: SpotifyItem;
  ARTIST_3: SpotifyItem;
  SONG_1: SpotifyItem;
  SONG_2: SpotifyItem;
  SONG_3: SpotifyItem;
  GENRE_1: string;
  GENRE_2: string;
  GENRE_3: string;
  ADDITIONAL_ARTISTS: SpotifyItem[];
  ADDITIONAL_SONGS: SpotifyTrack[];
  ADDITIONAL_GENRES: string[];
  MOOD_DATA: SpotifyTrack[];
}

export interface ArtistProfile {
  artist_name: string;
  genre_fusion: string;
  album_title: string;
  tracklist: string[];
  about: string;
  tagline: string;
  top_artists: SpotifyItem[];
  top_songs: SpotifyTrack[];
}

export interface GeneratedProfile {
  profile: ArtistProfile;
} 