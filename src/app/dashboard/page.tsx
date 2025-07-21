"use client";
import { useAuth } from "../../../hooks/useAuth";
import { useEffect, useState } from "react";
import { db } from "../../../lib/firebase";
import { collection, query, getDocs, orderBy } from "firebase/firestore";
import MemoryCard from "../../../components/MemoryCard";
import { Memory } from "../../../types";

export default function Dashboard() {
  const { user, loading, signOut } = useAuth();
  const [memories, setMemories] = useState<Memory[]>([]);
  const [loadingMemories, setLoadingMemories] = useState(true);

  useEffect(() => {
    if (!user) return;
    const fetchMemories = async () => {
      setLoadingMemories(true);
      const q = query(
        collection(db, "memory", user.uid, "items"),
        orderBy("createdAt", "desc")
      );
      const snapshot = await getDocs(q);
      const data = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Memory));
      setMemories(data);
      setLoadingMemories(false);
    };
    fetchMemories();
  }, [user]);

  if (loading) return <div>Loading...</div>;
  if (!user) {
    if (typeof window !== "undefined") window.location.href = "/login";
    return <div>Redirecting...</div>;
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <h1 className="text-2xl font-bold mb-4">Welcome, {user.displayName}</h1>
      <div className="mb-2 text-xs text-gray-500">Your User ID: <span className="font-mono select-all">{user.uid}</span></div>
      <button
        onClick={signOut}
        className="bg-gray-200 px-4 py-2 rounded shadow mb-4"
      >
        Sign out
      </button>
      <button
        onClick={() => (window.location.href = "/add")}
        className="bg-blue-500 text-white px-4 py-2 rounded shadow mb-4"
      >
        + Add New Memory
      </button>
      {loadingMemories ? (
        <div>Loading memories...</div>
      ) : (
        <div className="w-full max-w-xl">
          {memories.length === 0 ? (
            <div className="text-gray-500">No memories yet.</div>
          ) : (
            memories.map(memory => (
              <MemoryCard
                key={memory.id}
                memory={memory}
                onClick={() => (window.location.href = `/memory/${memory.id}`)}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
} 