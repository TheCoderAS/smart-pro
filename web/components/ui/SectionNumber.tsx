"use client";

import { useRef } from "react";
import { motion, useScroll, useTransform } from "framer-motion";
import { cn } from "@/lib/utils";

type Props = {
  number: string;
  side?: "left" | "right";
  className?: string;
};

export function SectionNumber({ number, side = "right", className }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  // Parallax: number translates slower (0.3x) than scroll
  const y = useTransform(scrollYProgress, [0, 1], [120, -120]);

  return (
    <div
      ref={ref}
      aria-hidden
      className={cn(
        "pointer-events-none absolute top-1/2 -translate-y-1/2 select-none",
        // Mobile: positive offset so the full number is visible inside the section.
        // md+: negative offset for the brief's "partially clipped by the section edge" feel,
        // which only reads as intentional when the viewport is wide enough that the clip is subtle.
        side === "left"
          ? "left-4 md:-left-12 lg:-left-24"
          : "right-4 md:-right-12 lg:-right-24",
        className,
      )}
    >
      <motion.div
        style={{ y }}
        className="font-display font-light text-fg-faint/20 leading-none"
      >
        <span
          // Min sized so the "01" fits inside the content area on a 375px viewport,
          // not pushing past the right edge.
          style={{ fontSize: "clamp(4.5rem, 20vw, 24rem)" }}
          className="block"
        >
          {number}
        </span>
      </motion.div>
    </div>
  );
}
