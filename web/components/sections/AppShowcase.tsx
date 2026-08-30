"use client";

import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { SMOOTH, VIEWPORT_REPEAT } from "@/lib/motion";
import { cn } from "@/lib/utils";

/*
 * Everything here is described at the level a visitor experiences it —
 * what the app does, never how. No protocols, no parts, no internals.
 */
const FEATURES = [
  {
    title: "Tap. It's on.",
    body: "The app talks straight to the wall inside your own home. No round trip to a server on another continent — a tap lands as fast as your finger does.",
  },
  {
    title: "No cloud. No account.",
    body: "There is nothing to sign up for and nothing to leak. Your home's data never leaves your home — we couldn't read it if we wanted to.",
  },
  {
    title: "Internet down? Nothing happens.",
    body: "Your switches don't live in the sky. Wi-Fi or Bluetooth, whichever you prefer — your lights answer either way.",
  },
  {
    title: "Make it yours.",
    body: "Name every switch what your family actually calls it. Hold and drag to arrange the room the way you think about it.",
  },
  {
    title: "One home, shared simply.",
    body: "One household password. Everyone you trust gets full control — and one reset locks out everyone you no longer do.",
  },
  {
    title: "Goodnight is one tap.",
    body: "Everything off — the whole home, one button, on your way out or from under the blanket.",
  },
];

/* The demo panel: names are generic on purpose. */
const DEMO_SWITCHES = [
  { name: "Ceiling light", on: true },
  { name: "Fan", on: true },
  { name: "Bedside lamp", on: false },
  { name: "TV", on: false },
  { name: "Geyser", on: false },
  { name: "Balcony", on: true },
];

function PowerGlyph({ on }: { on: boolean }) {
  return (
    <span
      className={cn(
        "flex items-center justify-center size-7 rounded-full border transition-all duration-500",
        on
          ? "bg-accent border-accent text-bg"
          : "bg-bg-subtle border-fg-faint text-fg-muted",
      )}
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden>
        <path
          d="M12 3v8m5.66-6.16a8 8 0 1 1-11.32 0"
          stroke="currentColor"
          strokeWidth="2.4"
          strokeLinecap="round"
        />
      </svg>
    </span>
  );
}

function PhoneMock() {
  const [states, setStates] = useState(DEMO_SWITCHES.map((s) => s.on));

  // A quiet, ambient life: every few seconds one switch flips, like a
  // home being lived in.
  useEffect(() => {
    const id = setInterval(() => {
      setStates((prev) => {
        const i = Math.floor(Math.random() * prev.length);
        const next = [...prev];
        next[i] = !next[i];
        return next;
      });
    }, 2600);
    return () => clearInterval(id);
  }, []);

  const onCount = states.filter(Boolean).length;

  return (
    <div
      aria-hidden
      className="relative w-[280px] sm:w-[300px] rounded-[2.2rem] border border-fg-faint/70 bg-bg-elevated p-3 shadow-[0_40px_80px_-20px_rgba(0,0,0,0.8)]"
    >
      {/* screen */}
      <div className="rounded-[1.7rem] bg-bg overflow-hidden border border-fg-faint/40">
        {/* status row */}
        <div className="flex items-center justify-between px-4 pt-4">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-bg-subtle px-2.5 py-1 text-[10px] font-mono uppercase tracking-eyebrow text-fg-muted">
            <span className="relative flex size-1.5">
              <span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400/60" />
              <span className="relative inline-flex size-1.5 rounded-full bg-emerald-400" />
            </span>
            Connected
          </span>
          <span className="text-[10px] font-mono uppercase tracking-eyebrow text-fg-faint">
            Wi-Fi
          </span>
        </div>

        {/* header */}
        <div className="px-4 pt-4">
          <div className="font-display text-xl text-fg">Living room</div>
          <div className="text-[11px] text-fg-muted mt-0.5">
            {onCount} of {states.length} on
          </div>
        </div>

        {/* all off */}
        <div className="px-4 pt-3">
          <button
            type="button"
            tabIndex={-1}
            onClick={() => setStates(states.map(() => false))}
            className="w-full rounded-xl border border-fg-faint/60 py-2 text-[11px] font-mono uppercase tracking-eyebrow text-fg-muted hover:border-accent hover:text-accent transition-colors"
          >
            All off
          </button>
        </div>

        {/* grid */}
        <div className="grid grid-cols-2 gap-2.5 p-4">
          {DEMO_SWITCHES.map((sw, i) => {
            const on = states[i];
            return (
              <button
                key={sw.name}
                type="button"
                tabIndex={-1}
                onClick={() =>
                  setStates((prev) => {
                    const next = [...prev];
                    next[i] = !next[i];
                    return next;
                  })
                }
                className={cn(
                  "rounded-2xl border p-3 text-left transition-all duration-500",
                  on
                    ? "border-accent/60 bg-accent/10 shadow-[0_0_24px_-6px_var(--accent)]"
                    : "border-fg-faint/50 bg-bg-subtle/60",
                )}
              >
                <PowerGlyph on={on} />
                <div className="mt-3 text-[11px] text-fg leading-tight">
                  {sw.name}
                </div>
                <div
                  className={cn(
                    "text-[10px] mt-0.5 transition-colors duration-500",
                    on ? "text-accent" : "text-fg-faint",
                  )}
                >
                  {on ? "On" : "Off"}
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export function AppShowcase() {
  return (
    <section
      id="app"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 overflow-hidden"
    >
      <SectionNumber number="03" side="right" />

      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_REPEAT}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>03 — The app</EyebrowLabel>
            </motion.div>
          </div>

          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              Your whole home, on one screen.
            </RevealText>

            <motion.p
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_REPEAT}
              transition={{ duration: 0.8, ease: SMOOTH, delay: 0.2 }}
              className="text-body-lg leading-relaxed text-fg/90 mt-10 max-w-2xl"
            >
              The wall still works the way it always has. The app is the wall,
              carried with you — every switch, live, wherever you are in the
              house.
            </motion.p>
          </div>
        </div>

        <div className="mt-20 lg:mt-28 grid grid-cols-1 lg:grid-cols-12 gap-16 items-center">
          {/* phone */}
          <motion.div
            initial={{ opacity: 0, y: 32 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={VIEWPORT_REPEAT}
            transition={{ duration: 1, ease: SMOOTH }}
            className="lg:col-span-5 flex justify-center lg:justify-start"
          >
            <div className="relative">
              {/* soft glow behind the phone */}
              <div
                aria-hidden
                className="absolute -inset-12 rounded-full bg-accent/10 blur-3xl"
              />
              <PhoneMock />
              <div className="mt-6 text-center text-xs font-mono uppercase tracking-eyebrow text-fg-faint">
                Live preview — go on, tap one
              </div>
            </div>
          </motion.div>

          {/* features */}
          <motion.div
            initial="hidden"
            whileInView="visible"
            viewport={VIEWPORT_REPEAT}
            variants={{
              hidden: {},
              visible: {
                transition: { staggerChildren: 0.1, delayChildren: 0.2 },
              },
            }}
            className="lg:col-span-7 grid grid-cols-1 sm:grid-cols-2 gap-x-12 gap-y-12"
          >
            {FEATURES.map((f) => (
              <motion.div
                key={f.title}
                variants={{
                  hidden: { opacity: 0, y: 16 },
                  visible: {
                    opacity: 1,
                    y: 0,
                    transition: { duration: 0.8, ease: SMOOTH },
                  },
                }}
              >
                <h3 className="font-display text-h2 mb-2 leading-display">
                  {f.title}
                </h3>
                <p className="text-fg-muted leading-relaxed">{f.body}</p>
              </motion.div>
            ))}
          </motion.div>
        </div>

        <motion.div
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={VIEWPORT_REPEAT}
          transition={{ duration: 0.8, ease: SMOOTH, delay: 0.3 }}
          className="mt-16 inline-flex items-center gap-4 border border-fg-faint/60 px-5 py-3"
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/brand/app-icon.png"
            alt="The Unisync app icon"
            className="size-10 rounded-xl"
          />
          <span className="text-sm text-fg-muted font-mono uppercase tracking-eyebrow">
            The Unisync app — coming soon. Android first, iOS to follow.
          </span>
        </motion.div>
      </div>
    </section>
  );
}
