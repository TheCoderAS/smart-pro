"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SMOOTH, VIEWPORT_REPEAT } from "@/lib/motion";

export function InstallersProfile() {
  return (
    <section className="relative py-[clamp(4rem,10vw,8rem)] border-t border-fg-faint/40">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <EyebrowLabel>The partner profile</EyebrowLabel>
          </div>
          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              We&apos;re looking for the careful ones.
            </RevealText>

            <motion.p
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_REPEAT}
              transition={{ duration: 0.8, ease: SMOOTH, delay: 0.3 }}
              className="text-body-lg leading-relaxed text-fg/90 mt-12 max-w-2xl"
            >
              The professionals whose customers know them by first name. Who
              prefer to do a board once and well, rather than three times and
              cheap. We are starting with a small founding cohort, and we will
              build the next ten years of the company alongside them.
            </motion.p>
          </div>
        </div>
      </div>
    </section>
  );
}
