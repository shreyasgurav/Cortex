"use client";
import { useAuth } from "../../../hooks/useAuth";
import { useState } from "react";
import { db } from "../../../lib/firebase";
import { collection, addDoc, serverTimestamp } from "firebase/firestore";

const memoryTypes = ["personal", "health", "work", "social", "preference"];

export default function AddMemoryPage() {
  const { user, loading } = useAuth();
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [tags, setTags] = useState("");
  const [type, setType] = useState("personal");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  if (loading) return <div>Loading...</div>;
  if (!user) {
    if (typeof window !== "undefined") window.location.href = "/login";
    return <div>Redirecting...</div>;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError("");
    try {
      await addDoc(collection(db, "memory", user.uid, "items"), {
        title,
        content,
        tags: tags.split(",").map(t => t.trim()).filter(Boolean),
        type,
        visibility: "private",
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      window.location.href = "/dashboard";
    } catch (err) {
      console.error("Error saving memory:", err);
      setError("Failed to save memory.");
      setSaving(false);
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <h1 className="text-2xl font-bold mb-4">Add New Memory</h1>
      <form onSubmit={handleSubmit} className="w-full max-w-md space-y-4">
        <input
          className="w-full border rounded px-3 py-2"
          placeholder="Title"
          value={title}
          onChange={e => setTitle(e.target.value)}
          required
        />
        <textarea
          className="w-full border rounded px-3 py-2"
          placeholder="Content"
          value={content}
          onChange={e => setContent(e.target.value)}
          required
        />
        <input
          className="w-full border rounded px-3 py-2"
          placeholder="Tags (comma separated)"
          value={tags}
          onChange={e => setTags(e.target.value)}
        />
        <select
          className="w-full border rounded px-3 py-2"
          value={type}
          onChange={e => setType(e.target.value)}
        >
          {memoryTypes.map(t => (
            <option key={t} value={t}>{t}</option>
          ))}
        </select>
        <button
          type="submit"
          className="bg-blue-500 text-white px-4 py-2 rounded shadow w-full"
          disabled={saving}
        >
          {saving ? "Saving..." : "Save Memory"}
        </button>
        {error && <div className="text-red-500">{error}</div>}
      </form>
    </div>
  );
} 