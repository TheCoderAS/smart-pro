"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { ArchitectureDiagram } from "@/components/illustrations/ArchitectureDiagram";
import { SMOOTH, VIEWPORT_REPEAT } from "@/lib/motion";

const PARAGRAPHS = [
  "A single Master unit fits a standard switchboard. It has the Wi-Fi, the brains, and the radios.",
  "Up to five Extension units snap onto a low-voltage bus next to it — adding two switches each, with no extra radios and no extra setup. Twelve switches per master, controlled from one place.",
  "Multiple masters across your home form a single mesh — so any switch is reachable from any room. Even when your internet is down.",
];

const SUB_BULLETS = [
  {
    title: "One radio across twelve channels.",
    body: "Costs less, breaks less.",
  },
  {
    title: "Snap-in extensions.",
    body: "No re-wiring, no re-pairing.",
  },
  {
    title: "Mesh across the home.",
    body: "No range issues. No cloud dependency.",
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
              One master. A few extensions. Your whole house, networked.
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

        {/* The architecture diagram — the single most important visual on the page */}
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={VIEWPORT_REPEAT}
          transition={{ duration: 1.2, ease: SMOOTH, delay: 0.3 }}
          className="mt-20 lg:mt-28 max-w-5xl mx-auto"
        >
          <ArchitectureDiagram />
        </motion.div>

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
