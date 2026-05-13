"use client";

import { useRef } from "react";
import { motion, useScroll, useTransform } from "framer-motion";
import { SMOOTH } from "@/lib/motion";

/**
 * Abstract switchboard schematic. Reads as architectural drafting, not a literal switch.
 * Single master tile (top-left) + three extension tiles connected via traces.
 * One filled accent circle = pulsing LED.
 */
export function HeroSchematic() {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start start", "end start"],
  });
  // ~0.15x scroll parallax (negative because we want it to lag upward)
  const y = useTransform(scrollYProgress, [0, 1], [0, -120]);

  // Order paths outermost → inward; LED last
  const paths: Array<{
    d: string;
    duration: number;
    delay: number;
  }> = [
    // Outer enclosure
    { d: "M 60 80 L 540 80 L 540 380 L 60 380 Z", duration: 1.4, delay: 0 },
    // Inner frame
    { d: "M 90 110 L 510 110 L 510 350 L 90 350 Z", duration: 1.2, delay: 0.25 },
    // Horizontal divider
    { d: "M 90 230 L 510 230", duration: 0.8, delay: 0.5 },
    // Master tile (top-left)
    { d: "M 120 140 L 260 140 L 260 210 L 120 210 Z", duration: 0.9, delay: 0.7 },
    // Extension tile 1 (top-right)
    { d: "M 300 140 L 480 140 L 480 210 L 300 210 Z", duration: 0.9, delay: 0.85 },
    // Extension tile 2 (bottom-left)
    { d: "M 120 260 L 260 260 L 260 330 L 120 330 Z", duration: 0.9, delay: 1.0 },
    // Extension tile 3 (bottom-right)
    { d: "M 300 260 L 480 260 L 480 330 L 300 330 Z", duration: 0.9, delay: 1.15 },
    // Trace: master → extension 1
    { d: "M 260 175 L 300 175", duration: 0.5, delay: 1.3 },
    // Trace: master → bottom-left
    { d: "M 190 210 L 190 260", duration: 0.5, delay: 1.4 },
    // Trace: extension 1 → bottom-right
    { d: "M 390 210 L 390 260", duration: 0.5, delay: 1.5 },
    // Small detail line top
    { d: "M 90 95 L 510 95", duration: 0.5, delay: 1.6 },
    // Small detail line bottom
    { d: "M 90 365 L 510 365", duration: 0.5, delay: 1.7 },
    // Mounting dots top
    { d: "M 70 90 L 80 90", duration: 0.3, delay: 1.8 },
    { d: "M 520 90 L 530 90", duration: 0.3, delay: 1.85 },
  ];

  return (
    <motion.div
      ref={ref}
      style={{ y }}
      className="w-full max-w-2xl mx-auto"
      role="img"
      aria-label="Abstract schematic of a switchboard with a master tile and three extension tiles"
    >
      <svg
        viewBox="0 0 600 460"
        fill="none"
        stroke="currentColor"
        strokeWidth="1"
        strokeLinecap="square"
        className="w-full h-auto text-fg-muted"
      >
        {paths.map((p, i) => (
          <motion.path
            key={i}
            d={p.d}
            initial={{ pathLength: 0, opacity: 0 }}
            animate={{ pathLength: 1, opacity: 1 }}
            transition={{
              pathLength: {
                duration: p.duration,
                delay: 2.2 + p.delay,
                ease: SMOOTH,
              },
              opacity: {
                duration: 0.3,
                delay: 2.2 + p.delay,
              },
            }}
          />
        ))}
        {/* LED — the single colored element. Pulses 1.0 → 0.5 → 1.0 over 3s */}
        <motion.circle
          cx="230"
          cy="175"
          r="4"
          fill="var(--accent)"
          stroke="none"
          initial={{ opacity: 0 }}
          animate={{ opacity: [1, 0.5, 1] }}
          transition={{
            opacity: {
              duration: 3,
              delay: 4,
              repeat: Infinity,
              repeatType: "loop",
              ease: "easeInOut",
            },
          }}
        />
      </svg>
    </motion.div>
  );
}
