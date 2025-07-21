import { NextRequest, NextResponse } from "next/server";
import { db } from "../../../../lib/firebase";
import { collection, getDocs, query, orderBy } from "firebase/firestore";

interface MemoryDoc {
  id: string;
  title: string;
  content: string;
  [key: string]: unknown;
}

export async function OPTIONS() {
  return new NextResponse(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}

export async function POST(req: NextRequest) {
  const { userId, prompt } = await req.json();
  if (!userId || !prompt) return NextResponse.json({ error: "Missing userId or prompt" }, { status: 400 });

  // Fetch recent memories (top 5 by updatedAt)
  const q = query(collection(db, "memory", userId, "items"), orderBy("updatedAt", "desc"));
  const snapshot = await getDocs(q);
  const memories: MemoryDoc[] = snapshot.docs.slice(0, 5).map(doc => {
    const data = doc.data() || {};
    return {
      id: doc.id,
      title: typeof data.title === "string" ? data.title : "",
      content: typeof data.content === "string" ? data.content : "",
      ...data,
    };
  });
  const memorySummaries = memories.map(m => `${m.title}: ${m.content}`);

  // Build context string
  const context = memorySummaries.join("\n\n");

  // Call OpenAI API
  const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: "gpt-4",
      messages: [
        { role: "system", content: "You’re an AI that personalizes prompts using personal memory." },
        { role: "user", content: `User's memory: ${context}\n\nOriginal prompt: ${prompt}\n\nRewrite the prompt using memory context.` },
      ],
      max_tokens: 512,
    }),
  });
  const openaiData = await openaiRes.json();
  const enhancedPrompt = openaiData.choices?.[0]?.message?.content || prompt;

  return new NextResponse(JSON.stringify({ enhancedPrompt, memoryIds: memories.map(m => m.id) }), {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Content-Type": "application/json"
    }
  });
} 