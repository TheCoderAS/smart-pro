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
        side === "left" ? "-left-12 lg:-left-24" : "-right-12 lg:-right-24",
        className,
      )}
    >
      <motion.div
        style={{ y }}
        className="font-display font-light text-fg-faint/30 leading-none"
      >
        <span
          style={{ fontSize: "clamp(12rem, 25vw, 24rem)" }}
          className="block"
        >
          {number}
        </span>
      </motion.div>
    </div>
  );
}
