import 'next-auth';
import NextAuth from "next-auth"

declare module 'next-auth' {
  interface Session {
    accessToken: string;
    error?: 'RefreshAccessTokenError' | undefined;
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    accessToken: string;
    refreshToken?: string;
    accessTokenExpires: number;
    error?: 'RefreshAccessTokenError';
  }
} 