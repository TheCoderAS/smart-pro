import { NextResponse } from "next/server";

// TODO: connect to real backend (Resend, Loops, Airtable, Tally, Google Forms, etc.)
// Accepts { email: string, city?: string, role?: string }
export async function POST(request: Request) {
  try {
    const body = await request.json();
    if (!body?.email || typeof body.email !== "string") {
      return NextResponse.json(
        { ok: false, error: "Email required" },
        { status: 400 },
      );
    }
    console.log("[waitlist] submission:", {
      email: body.email,
      city: body.city ?? null,
      role: body.role ?? null,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("[waitlist] error:", err);
    return NextResponse.json({ ok: false }, { status: 400 });
  }
}
