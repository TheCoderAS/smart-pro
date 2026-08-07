"use client";

import { MotionConfig } from "framer-motion";

/**
 * Wraps the app in MotionConfig so all Framer Motion animations
 * automatically respect prefers-reduced-motion.
 */
export function ReducedMotionProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
