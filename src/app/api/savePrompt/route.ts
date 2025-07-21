import { NextRequest, NextResponse } from "next/server";
import { db } from "../../../../lib/firebase";
import { collection, addDoc, serverTimestamp } from "firebase/firestore";

export async function POST(req: NextRequest) {
  const { userId, originalPrompt, enhancedPrompt, memoryIdsUsed } = await req.json();
  if (!userId || !originalPrompt || !enhancedPrompt) return NextResponse.json({ error: "Missing fields" }, { status: 400 });

  await addDoc(collection(db, "prompts", userId, ""), {
    originalPrompt,
    enhancedPrompt,
    memoryUsed: memoryIdsUsed || [],
    timestamp: serverTimestamp(),
  });

  return NextResponse.json({ success: true });
} 