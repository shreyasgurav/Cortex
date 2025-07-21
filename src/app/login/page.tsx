"use client";
import { useAuth } from "../../../hooks/useAuth";
import React from "react";

export default function LoginPage() {
  const { user, signIn, loading } = useAuth();

  // Async redirect logic
  React.useEffect(() => {
    async function handleLogin() {
      if (user) {
        // Store userId in chrome.storage.sync if available (for extension integration)
        const win = window as Window & typeof globalThis & { chrome?: unknown };
        if (
          typeof win !== "undefined" &&
          typeof win.chrome !== "undefined" &&
          typeof (win.chrome as Record<string, unknown>).storage !== "undefined" &&
          typeof ((win.chrome as Record<string, unknown>).storage as Record<string, unknown>).sync !== "undefined" &&
          typeof (((win.chrome as Record<string, unknown>).storage as Record<string, unknown>).sync as Record<string, unknown>).set === "function"
        ) {
          console.log("Setting userId in chrome.storage.sync", user.uid);
          await new Promise<void>(resolve => {
            function callback(): void { resolve(); }
            (
              ((win.chrome as Record<string, unknown>).storage as Record<string, unknown>).sync as {
                set: (items: Record<string, unknown>, callback: () => void) => void;
              }
            ).set({ userId: user.uid }, callback);
          });
        }
        if (typeof window !== "undefined") window.location.href = "/dashboard";
      }
    }
    handleLogin();
  }, [user]);

  if (loading) return <div>Loading...</div>;
  if (user) {
    return <div>Redirecting...</div>;
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <h1 className="text-2xl font-bold mb-4">Open Memory</h1>
      <button
        onClick={signIn}
        className="bg-blue-500 text-white px-4 py-2 rounded shadow"
      >
        Sign in with Google
      </button>
    </div>
  );
} 