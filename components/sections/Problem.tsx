"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { SMOOTH, VIEWPORT_ONCE } from "@/lib/motion";

const PARAGRAPHS = [
  "The expensive ones cost as much as a phone, for a switch. The cheap ones stop working when a Chinese server goes dark.",
  "Both require an electrician for a day, a re-wiring of the board, and a bet that the company that sold it to you will still exist in three years.",
  "Most of them, in most homes, end up on a manual override within a month. Not because the technology failed. Because the product was never made for the way people actually live.",
];

export function Problem() {
  return (
    <section
      id="problem"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 overflow-hidden"
    >
      <SectionNumber number="01" side="right" />

      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>01 — The problem</EyebrowLabel>
            </motion.div>
          </div>

          <div className="lg:col-span-8">
            <RevealText
              as="h2"
              className="font-display text-h1 max-w-3xl"
            >
              Smart switches today are neither.
            </RevealText>

            <motion.div
              initial="hidden"
              whileInView="visible"
              viewport={VIEWPORT_ONCE}
              variants={{
                hidden: {},
                visible: { transition: { staggerChildren: 0.15, delayChildren: 0.2 } },
              }}
              className="mt-16 space-y-10 max-w-2xl"
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
      </div>
    </section>
  );
}
