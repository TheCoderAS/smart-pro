import { NextResponse } from "next/server";

// TODO: connect to real backend
export async function POST(request: Request) {
  try {
    const body = await request.json();
    console.log("[waitlist] submission:", body);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("[waitlist] error:", err);
    return NextResponse.json({ ok: false }, { status: 400 });
  }
}
