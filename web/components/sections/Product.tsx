"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { SMOOTH, VIEWPORT_REPEAT } from "@/lib/motion";

const PARAGRAPHS = [
  "One unit sits in your switchboard and quietly runs it. Your switches stay where they have always been — on the wall, and now also in your pocket.",
  "As your home grows, it grows with you: add on to a board, add more boards, and everything still behaves as one home in one app.",
  "And none of it depends on the internet. Everything your switches need lives inside your own four walls.",
];

const SUB_BULLETS = [
  {
    title: "Feels like a switch.",
    body: "Because it still is one. Nothing to learn, nothing to babysit.",
  },
  {
    title: "Grows with the home.",
    body: "Start with one board. Add more whenever. Still one app.",
  },
  {
    title: "No internet required.",
    body: "No cloud dependency, no outages that aren't yours.",
  },
  {
    title: "Standard modular form factor.",
    body: "Fits Anchor Roma, Legrand Myrius, Schneider Livia plates.",
  },
];

export function Product() {
  return (
    <section
      id="product"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 overflow-hidden"
    >
      <SectionNumber number="02" side="left" />

      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_REPEAT}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>02 — The product</EyebrowLabel>
            </motion.div>
          </div>

          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              Your whole house, one system.
            </RevealText>

            <motion.div
              initial="hidden"
              whileInView="visible"
              viewport={VIEWPORT_REPEAT}
              variants={{
                hidden: {},
                visible: {
                  transition: { staggerChildren: 0.15, delayChildren: 0.2 },
                },
              }}
              className="mt-16 space-y-8 max-w-2xl"
            >
              {PARAGRAPHS.map((p, i) => (
                <motion.p
                  key={i}
                  variants={{
                    hidden: { opacity: 0, y: 16 },
                    visible: {
                      opacity: 1,
                      y: 0,
                      transition: { duration: 0.8, ease: SMOOTH },
                    },
                  }}
                  className="text-body-lg leading-relaxed text-fg/90"
                >
                  {p}
                </motion.p>
              ))}
            </motion.div>
          </div>
        </div>

        {/* Sub-bullets that add concrete differentiation */}
        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={VIEWPORT_REPEAT}
          variants={{
            hidden: {},
            visible: {
              transition: { staggerChildren: 0.1, delayChildren: 0.3 },
            },
          }}
          className="mt-20 lg:mt-28 grid grid-cols-1 sm:grid-cols-2 gap-x-12 gap-y-10 max-w-4xl mx-auto"
        >
          {SUB_BULLETS.map((b) => (
            <motion.div
              key={b.title}
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
                {b.title}
              </h3>
              <p className="text-fg-muted leading-relaxed">{b.body}</p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
