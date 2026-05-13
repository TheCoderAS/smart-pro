"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { SMOOTH, VIEWPORT_ONCE } from "@/lib/motion";

const FOUNDERS = [
  {
    // TODO: replace with real founder details
    initial: "A",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "Hardware, firmware, and quiet decisions about the right way to build things.",
    tone: "var(--bg-subtle)",
  },
  {
    initial: "B",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "Design, brand, and the kind of taste that knows when to stop.",
    tone: "var(--bg-elevated)",
  },
  {
    initial: "C",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "Operations, factories, and the realities of getting things off a line.",
    tone: "var(--bg-subtle)",
  },
];

const CONTACTS = [
  // TODO: replace email domains
  { label: "For early access", email: "hello@brand.com" },
  { label: "For investors", email: "investors@brand.com" },
  { label: "For press", email: "press@brand.com" },
];

export function Team() {
  return (
    <section
      id="team"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 overflow-hidden"
    >
      <SectionNumber number="04" side="left" />

      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>04 — The team</EyebrowLabel>
            </motion.div>
          </div>

          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              Built by people who have done this before.
            </RevealText>

            <motion.p
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH, delay: 0.3 }}
              className="text-body-lg leading-relaxed text-fg/90 mt-12 max-w-2xl"
            >
              We are a small team of hardware, firmware, and design people based
              in [CITY]. We have shipped products to millions of homes, certified
              electronics in three regions, and spent more time than we will
              admit talking to electricians about why their last smart switch
              ended up in a drawer.
            </motion.p>
          </div>
        </div>

        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={VIEWPORT_ONCE}
          variants={{
            hidden: {},
            visible: { transition: { staggerChildren: 0.12, delayChildren: 0.4 } },
          }}
          className="mt-24 grid grid-cols-1 md:grid-cols-3 gap-12"
        >
          {FOUNDERS.map((f) => (
            <motion.div
              key={f.initial}
              variants={{
                hidden: { opacity: 0, y: 20 },
                visible: {
                  opacity: 1,
                  y: 0,
                  transition: { duration: 0.8, ease: SMOOTH },
                },
              }}
              className="flex flex-col"
            >
              <div
                className="size-20 rounded-full flex items-center justify-center mb-6"
                style={{ background: f.tone }}
              >
                <span className="font-display text-3xl text-fg-muted">
                  {f.initial}
                </span>
              </div>
              <div className="font-display text-h2 mb-1">{f.name}</div>
              <div className="eyebrow mb-4">{f.role}</div>
              <p className="text-fg-muted leading-relaxed text-sm max-w-xs">
                {f.bio}
              </p>
            </motion.div>
          ))}
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={VIEWPORT_ONCE}
          transition={{ duration: 0.8, ease: SMOOTH, delay: 0.2 }}
          className="mt-32 max-w-2xl"
        >
          <h3 className="font-display text-h1 mb-10">Want to talk?</h3>
          <ul className="space-y-5">
            {CONTACTS.map((c) => (
              <li
                key={c.label}
                className="flex flex-col sm:flex-row sm:items-baseline gap-2 sm:gap-6"
              >
                <span className="eyebrow min-w-[10rem]">{c.label}</span>
                <a
                  href={`mailto:${c.email}`}
                  className="text-body-lg link-underline hover:text-accent transition-colors"
                >
                  {c.email}
                </a>
              </li>
            ))}
          </ul>
        </motion.div>
      </div>
    </section>
  );
}
