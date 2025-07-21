"use client";
import { useAuth } from "../../../../hooks/useAuth";
import { useEffect, useState } from "react";
import { db } from "../../../../lib/firebase";
import { doc, getDoc, updateDoc, deleteDoc } from "firebase/firestore";
import { useParams, useRouter } from "next/navigation";
import { Memory } from "../../../../types";

const memoryTypes = ["personal", "health", "work", "social", "preference"];

export default function MemoryDetailPage() {
  const { user, loading } = useAuth();
  const params = useParams();
  const router = useRouter();
  const memoryId = params?.id as string;
  const [memory, setMemory] = useState<Memory | null>(null);
  const [edit, setEdit] = useState(false);
  const [form, setForm] = useState<{ title: string; content: string; tags: string; type: string }>({ title: "", content: "", tags: "", type: "personal" });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!user || !memoryId) return;
    const fetchMemory = async () => {
      const ref = doc(db, "memory", user.uid, "items", memoryId);
      const snap = await getDoc(ref);
      if (snap.exists()) {
        const data = snap.data() as Omit<Memory, 'id'>;
        setMemory({ ...data, id: snap.id });
        setForm({
          title: data.title,
          content: data.content,
          tags: data.tags.join(", "),
          type: data.type,
        });
      }
    };
    fetchMemory();
  }, [user, memoryId]);

  if (loading) return <div>Loading...</div>;
  if (!user) {
    if (typeof window !== "undefined") window.location.href = "/login";
    return <div>Redirecting...</div>;
  }
  if (!memory) return <div>Loading memory...</div>;

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError("");
    try {
      const ref = doc(db, "memory", user.uid, "items", memoryId);
      await updateDoc(ref, {
        title: form.title,
        content: form.content,
        tags: form.tags.split(",").map(t => t.trim()).filter(Boolean),
        type: form.type,
        updatedAt: new Date(),
      });
      setEdit(false);
      router.refresh();
    } catch {
      setError("Failed to update memory.");
    }
    setSaving(false);
  };

  const handleDelete = async () => {
    if (!confirm("Delete this memory?")) return;
    try {
      const ref = doc(db, "memory", user.uid, "items", memoryId);
      await deleteDoc(ref);
      router.push("/dashboard");
    } catch {
      setError("Failed to delete memory.");
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <h1 className="text-2xl font-bold mb-4">Memory Details</h1>
      {edit ? (
        <form onSubmit={handleSave} className="w-full max-w-md space-y-4">
          <input
            className="w-full border rounded px-3 py-2"
            value={form.title}
            onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
            required
          />
          <textarea
            className="w-full border rounded px-3 py-2"
            value={form.content}
            onChange={e => setForm(f => ({ ...f, content: e.target.value }))}
            required
          />
          <input
            className="w-full border rounded px-3 py-2"
            value={form.tags}
            onChange={e => setForm(f => ({ ...f, tags: e.target.value }))}
            placeholder="Tags (comma separated)"
          />
          <select
            className="w-full border rounded px-3 py-2"
            value={form.type}
            onChange={e => setForm(f => ({ ...f, type: e.target.value }))}
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
            {saving ? "Saving..." : "Save"}
          </button>
          <button
            type="button"
            className="bg-gray-200 px-4 py-2 rounded shadow w-full"
            onClick={() => setEdit(false)}
          >
            Cancel
          </button>
          {error && <div className="text-red-500">{error}</div>}
        </form>
      ) : (
        <div className="w-full max-w-md border rounded p-4">
          <h2 className="text-lg font-semibold mb-2">{memory.title}</h2>
          <div className="mb-2 text-gray-600">{memory.content}</div>
          <div className="mb-2">
            <span className="text-xs bg-gray-200 rounded px-2 py-1 mr-2">{memory.type}</span>
            {memory.tags.map((tag: string) => (
              <span key={tag} className="text-xs bg-blue-100 text-blue-700 rounded px-2 py-0.5 mr-1">{tag}</span>
            ))}
          </div>
          <button
            className="bg-blue-500 text-white px-4 py-2 rounded shadow w-full mb-2"
            onClick={() => setEdit(true)}
          >
            Edit
          </button>
          <button
            className="bg-red-500 text-white px-4 py-2 rounded shadow w-full"
            onClick={handleDelete}
          >
            Delete
          </button>
          {error && <div className="text-red-500 mt-2">{error}</div>}
        </div>
      )}
    </div>
  );
} 