"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, MotionConfig, motion } from "framer-motion";
import { X } from "lucide-react";
import { SMOOTH } from "@/lib/motion";
import { cn } from "@/lib/utils";

type Ctx = { open: () => void; close: () => void; isOpen: boolean };

const WaitlistContext = createContext<Ctx | null>(null);

export function useWaitlist() {
  const ctx = useContext(WaitlistContext);
  if (!ctx) throw new Error("useWaitlist must be used inside WaitlistModalProvider");
  return ctx;
}

const ROLES = ["Homeowner", "Electrician", "Builder", "Investor", "Other"] as const;
type Role = (typeof ROLES)[number];

export function WaitlistModalProvider({ children }: { children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const open = useCallback(() => setIsOpen(true), []);
  const close = useCallback(() => setIsOpen(false), []);

  // Wire up data-waitlist-trigger globally
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      const target = (e.target as HTMLElement)?.closest("[data-waitlist-trigger]");
      if (target) {
        e.preventDefault();
        setIsOpen(true);
      }
    };
    document.addEventListener("click", handler);
    return () => document.removeEventListener("click", handler);
  }, []);

  // Escape to close + lock body scroll
  useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setIsOpen(false);
    };
    document.addEventListener("keydown", onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [isOpen]);

  return (
    <MotionConfig reducedMotion="user">
      <WaitlistContext.Provider value={{ open, close, isOpen }}>
        {children}
        {mounted &&
          createPortal(
            <AnimatePresence>
              {isOpen && <WaitlistModal onClose={close} />}
            </AnimatePresence>,
            document.body,
          )}
      </WaitlistContext.Provider>
    </MotionConfig>
  );
}

function WaitlistModal({ onClose }: { onClose: () => void }) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("Homeowner");
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Focus trap setup: capture the element that opened us, restore on close
  useEffect(() => {
    triggerRef.current = document.activeElement as HTMLElement | null;
    const firstFocusable = dialogRef.current?.querySelector<HTMLElement>(
      'input, button, [tabindex]:not([tabindex="-1"])',
    );
    firstFocusable?.focus();
    return () => {
      triggerRef.current?.focus();
    };
  }, []);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, role }),
      });
      if (!res.ok) throw new Error("Submission failed");
      setSubmitted(true);
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <motion.div
      role="presentation"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.8, ease: SMOOTH }}
      className="fixed inset-0 z-[100] flex items-center justify-center p-6 bg-bg/70 backdrop-blur-md"
    >
      <motion.div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="waitlist-title"
        initial={{ opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.96 }}
        transition={{ duration: 0.5, ease: SMOOTH }}
        className="relative w-full max-w-lg bg-bg-elevated border border-fg-faint/60 p-10"
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="absolute top-4 right-4 size-9 flex items-center justify-center text-fg-muted hover:text-fg transition-colors"
        >
          <X size={18} />
        </button>

        <AnimatePresence mode="wait">
          {submitted ? (
            <motion.div
              key="confirm"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.6, ease: SMOOTH }}
              className="text-center py-8"
            >
              <svg
                width="56"
                height="56"
                viewBox="0 0 56 56"
                className="mx-auto mb-6 text-accent"
                aria-hidden
              >
                <motion.circle
                  cx="28"
                  cy="28"
                  r="25"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1"
                  initial={{ pathLength: 0 }}
                  animate={{ pathLength: 1 }}
                  transition={{ duration: 0.8, ease: SMOOTH }}
                />
                <motion.path
                  d="M 18 29 L 25 36 L 38 22"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  initial={{ pathLength: 0 }}
                  animate={{ pathLength: 1 }}
                  transition={{ duration: 0.6, delay: 0.5, ease: SMOOTH }}
                />
              </svg>
              <h2
                id="waitlist-title"
                className="font-display text-h2 mb-4"
              >
                Thank you.
              </h2>
              <p className="text-fg-muted leading-relaxed max-w-sm mx-auto">
                We&apos;ll be in touch when there&apos;s something worth saying.
              </p>
            </motion.div>
          ) : (
            <motion.form
              key="form"
              onSubmit={onSubmit}
              initial={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.3 }}
            >
              <div className="eyebrow mb-3">Early access</div>
              <h2
                id="waitlist-title"
                className="font-display text-h2 mb-8 leading-display"
              >
                Leave us a way to reach you.
              </h2>

              <FloatingInput
                label="Email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />

              <fieldset className="mt-8">
                <legend className="eyebrow mb-4">I&apos;m a…</legend>
                <div className="flex flex-wrap gap-x-6 gap-y-3">
                  {ROLES.map((r) => (
                    <label
                      key={r}
                      className={cn(
                        "inline-flex items-center gap-2 cursor-pointer text-sm",
                        role === r ? "text-fg" : "text-fg-muted",
                      )}
                    >
                      <input
                        type="radio"
                        name="role"
                        value={r}
                        checked={role === r}
                        onChange={() => setRole(r)}
                        className="sr-only"
                      />
                      <span
                        aria-hidden
                        className={cn(
                          "size-3 rounded-full border transition-colors",
                          role === r
                            ? "border-accent bg-accent"
                            : "border-fg-faint",
                        )}
                      />
                      {r}
                    </label>
                  ))}
                </div>
              </fieldset>

              {error && (
                <div className="mt-6 text-sm text-accent" role="alert">
                  {error}
                </div>
              )}

              <div className="mt-10">
                <button
                  type="submit"
                  disabled={submitting}
                  className="group relative overflow-hidden inline-flex items-center justify-center px-7 py-4 border border-fg-faint text-sm font-mono tracking-eyebrow uppercase transition-[color,border-color,transform] duration-300 ease-smooth hover:border-accent active:scale-[0.97] disabled:opacity-60 disabled:pointer-events-none"
                >
                  <span
                    aria-hidden
                    className="absolute inset-0 bg-accent origin-left scale-x-0 group-hover:scale-x-100 transition-transform duration-500 ease-smooth"
                  />
                  <span className="relative z-10 group-hover:text-bg transition-colors duration-300">
                    {submitting ? "Sending…" : "Request early access"}
                  </span>
                </button>
              </div>
            </motion.form>
          )}
        </AnimatePresence>
      </motion.div>
    </motion.div>
  );
}

function FloatingInput({
  label,
  ...rest
}: { label: string } & React.InputHTMLAttributes<HTMLInputElement>) {
  const [focused, setFocused] = useState(false);
  const hasValue = Boolean(rest.value);
  const floated = focused || hasValue;
  return (
    <label className="relative block">
      <span
        className={cn(
          "absolute left-0 transition-all duration-300 ease-smooth pointer-events-none",
          floated
            ? "top-0 text-xs font-mono tracking-eyebrow uppercase text-fg-muted"
            : "top-6 text-base text-fg-muted",
        )}
      >
        {label}
      </span>
      <input
        {...rest}
        onFocus={(e) => {
          setFocused(true);
          rest.onFocus?.(e);
        }}
        onBlur={(e) => {
          setFocused(false);
          rest.onBlur?.(e);
        }}
        className="w-full pt-6 pb-2 bg-transparent border-b border-fg-faint focus:border-accent transition-colors outline-none"
      />
    </label>
  );
}
