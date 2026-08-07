"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { SMOOTH } from "@/lib/motion";

const NAV_LINKS = [
  { href: "/#problem", label: "Problem" },
  { href: "/#product", label: "Product" },
  { href: "/#approach", label: "Approach" },
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <motion.header
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.2, duration: 0.8, ease: SMOOTH }}
      className={cn(
        "fixed top-0 inset-x-0 z-50 transition-[background-color,backdrop-filter,border-color] duration-500 ease-smooth",
        scrolled
          ? "bg-bg-elevated/70 backdrop-blur-md border-b border-fg-faint/40"
          : "bg-transparent border-b border-transparent",
      )}
    >
      <div className="max-w-content mx-auto px-6 lg:px-24 h-16 flex items-center justify-between">
        <Link
          href="/"
          className="font-display text-lg tracking-tight"
          aria-label="Unisync home"
        >
          Unisync
        </Link>

        <nav className="hidden md:flex items-center gap-10">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="group relative text-sm text-fg-muted hover:text-fg transition-colors duration-300"
            >
              <span className="relative">
                {link.label}
                <span
                  className="absolute -left-3 top-1/2 -translate-y-1/2 size-1 rounded-full bg-accent scale-0 group-hover:scale-100 transition-transform duration-300 ease-smooth"
                  aria-hidden
                />
              </span>
            </Link>
          ))}
        </nav>

        <Link
          href="/#waitlist"
          className="text-xs font-mono tracking-eyebrow uppercase px-4 py-2 border border-fg-faint hover:border-accent hover:text-accent transition-colors duration-300"
        >
          Get Early Access
        </Link>
      </div>
    </motion.header>
  );
}
