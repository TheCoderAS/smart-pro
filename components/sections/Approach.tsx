"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { SMOOTH, VIEWPORT_ONCE } from "@/lib/motion";

const PRINCIPLES = [
  {
    title: "Networked first",
    body: "Switches in different rooms talk to each other. Your whole home is one system, not four lonely switchboards.",
  },
  {
    title: "Local always",
    body: "Wi-Fi can go down. The cloud can go away. Your lights work either way — schedules, scenes, and physical switches all run on the wall, not in the sky.",
  },
  {
    title: "Open by default",
    body: "Your switches should work with whatever app, voice, or system you already use. Not just ours.",
  },
  {
    title: "Built for installers",
    body: "The person fitting it to your wall is our customer too. We design for the ladder, not just the couch.",
  },
];

export function Approach() {
  return (
    <section
      id="approach"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 overflow-hidden"
    >
      <SectionNumber number="03" side="left" />

      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>03 — Our approach</EyebrowLabel>
            </motion.div>
          </div>

          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              Built like infrastructure. Priced like a switch.
            </RevealText>

            <motion.p
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH, delay: 0.3 }}
              className="text-body-lg leading-relaxed text-fg/90 mt-12 max-w-2xl"
            >
              We started with a question no incumbent has answered: what if a
              smart switch felt exactly like a normal switch — and a normal
              switch was the smart one?
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
          className="mt-24 grid grid-cols-1 md:grid-cols-2 gap-x-16 gap-y-16"
        >
          {PRINCIPLES.map((p) => (
            <motion.div
              key={p.title}
              variants={{
                hidden: { opacity: 0, y: 20 },
                visible: {
                  opacity: 1,
                  y: 0,
                  transition: { duration: 0.8, ease: SMOOTH },
                },
              }}
            >
              <h3 className="font-display text-h2 mb-3">{p.title}</h3>
              <p className="text-fg-muted leading-relaxed max-w-md">
                {p.body}
              </p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
