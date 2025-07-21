"use client";
import { useAuth } from "../../../hooks/useAuth";
import { useEffect, useState } from "react";
import { db } from "../../../lib/firebase";
import { collection, getDocs, orderBy, query, Timestamp } from "firebase/firestore";

interface PromptLog {
  id: string;
  originalPrompt: string;
  enhancedPrompt: string;
  memoryUsed: string[];
  timestamp: Timestamp | null;
}

export default function HistoryPage() {
  const { user, loading } = useAuth();
  const [logs, setLogs] = useState<PromptLog[]>([]);
  const [loadingLogs, setLoadingLogs] = useState(true);

  useEffect(() => {
    if (!user) return;
    const fetchLogs = async () => {
      setLoadingLogs(true);
      const q = query(
        collection(db, "prompts", user.uid, ""),
        orderBy("timestamp", "desc")
      );
      const snapshot = await getDocs(q);
      const data = snapshot.docs.map(doc => {
        const d = doc.data();
        return {
          id: doc.id,
          originalPrompt: d.originalPrompt,
          enhancedPrompt: d.enhancedPrompt,
          memoryUsed: d.memoryUsed,
          timestamp: d.timestamp ?? null,
        } as PromptLog;
      });
      setLogs(data);
      setLoadingLogs(false);
    };
    fetchLogs();
  }, [user]);

  if (loading) return <div>Loading...</div>;
  if (!user) {
    if (typeof window !== "undefined") window.location.href = "/login";
    return <div>Redirecting...</div>;
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      <h1 className="text-2xl font-bold mb-4">Prompt History</h1>
      {loadingLogs ? (
        <div>Loading history...</div>
      ) : (
        <div className="w-full max-w-2xl space-y-4">
          {logs.length === 0 ? (
            <div className="text-gray-500">No prompt logs yet.</div>
          ) : (
            logs.map(log => (
              <div key={log.id} className="border rounded p-4">
                <div className="mb-2">
                  <span className="font-semibold">Original:</span> {log.originalPrompt}
                </div>
                <div className="mb-2">
                  <span className="font-semibold">Enhanced:</span> {log.enhancedPrompt}
                </div>
                <div className="mb-2">
                  <span className="font-semibold">Memory IDs:</span> {log.memoryUsed?.join(", ")}
                </div>
                <div className="text-xs text-gray-500">
                  {log.timestamp && typeof log.timestamp.toDate === 'function' ? log.timestamp.toDate().toLocaleString() : ""}
                </div>
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
} 