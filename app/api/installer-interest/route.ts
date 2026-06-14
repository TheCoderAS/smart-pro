import { NextResponse } from "next/server";

// TODO: connect to real backend
export async function POST(request: Request) {
  try {
    const body = await request.json();
    console.log("[installer-interest] submission:", body);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("[installer-interest] error:", err);
    return NextResponse.json({ ok: false }, { status: 400 });
  }
}
