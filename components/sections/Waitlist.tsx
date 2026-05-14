"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SMOOTH, VIEWPORT_ONCE } from "@/lib/motion";
import { cn } from "@/lib/utils";

const CITIES = [
  "Bangalore",
  "Mumbai",
  "Delhi",
  "Pune",
  "Chennai",
  "Hyderabad",
  "Other",
] as const;

const ROLES = [
  "Homeowner",
  "Electrician",
  "Builder/Developer",
  "Investor",
  "Other",
] as const;

// Same address; subject lets visitors self-identify in their inbox.
// TODO: replace once a dedicated mailbox exists.
const CONTACT_LINKS = [
  { label: "For early access", subject: "Early access" },
  { label: "For investors", subject: "Investors" },
  { label: "For press", subject: "Press" },
];

export function Waitlist() {
  const [email, setEmail] = useState("");
  const [city, setCity] = useState<string>("");
  const [role, setRole] = useState<string>("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, city: city || undefined, role: role || undefined }),
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
    <section
      id="waitlist"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 scroll-mt-20"
    >
      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>Early access</EyebrowLabel>
            </motion.div>
          </div>

          <div className="lg:col-span-8 max-w-2xl">
            <RevealText as="h2" className="font-display text-h1">
              Get on the early access list.
            </RevealText>

            <motion.p
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_ONCE}
              transition={{ duration: 0.8, ease: SMOOTH, delay: 0.2 }}
              className="text-body-lg leading-relaxed text-fg-muted mt-8"
            >
              Pilot launching Bangalore, Q3 2026. We&apos;ll notify you when
              units are available in your city.
            </motion.p>

            <AnimatePresence mode="wait">
              {submitted ? (
                <motion.div
                  key="confirm"
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.6, ease: SMOOTH }}
                  className="mt-12 p-8 border border-fg-faint/60 flex items-start gap-5"
                >
                  <svg
                    width="40"
                    height="40"
                    viewBox="0 0 56 56"
                    className="shrink-0 text-accent"
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
                  <div>
                    <h3 className="font-display text-h2 mb-2">Thank you.</h3>
                    <p className="text-fg-muted leading-relaxed">
                      We&apos;ll be in touch when there&apos;s something worth
                      saying.
                    </p>
                  </div>
                </motion.div>
              ) : (
                <motion.form
                  key="form"
                  initial={{ opacity: 0, y: 16 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={VIEWPORT_ONCE}
                  transition={{ duration: 0.8, ease: SMOOTH, delay: 0.4 }}
                  onSubmit={onSubmit}
                  className="mt-12 space-y-8"
                >
                  <Field label="Email">
                    <input
                      type="email"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      className="w-full bg-transparent border-b border-fg-faint focus:border-accent transition-colors outline-none py-3 text-body-lg"
                      autoComplete="email"
                    />
                  </Field>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-8">
                    <Field label="City (optional)">
                      <Select
                        value={city}
                        onChange={(v) => setCity(v)}
                        options={CITIES as unknown as string[]}
                        placeholder="Select your city"
                      />
                    </Field>

                    <Field label="I am a (optional)">
                      <Select
                        value={role}
                        onChange={(v) => setRole(v)}
                        options={ROLES as unknown as string[]}
                        placeholder="Select"
                      />
                    </Field>
                  </div>

                  {error && (
                    <div className="text-sm text-accent" role="alert">
                      {error}
                    </div>
                  )}

                  <div>
                    <button
                      type="submit"
                      disabled={submitting}
                      className={cn(
                        "group relative overflow-hidden inline-flex items-center justify-center",
                        "px-7 py-4 border border-fg-faint",
                        "text-sm font-mono tracking-eyebrow uppercase",
                        "transition-[color,border-color,transform] duration-300 ease-smooth",
                        "hover:border-accent active:scale-[0.97]",
                        "disabled:opacity-60 disabled:pointer-events-none",
                      )}
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
          </div>
        </div>

        {/* Want to talk? — three labelled mailto links, all to the same address with a subject prefilled */}
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={VIEWPORT_ONCE}
          transition={{ duration: 0.8, ease: SMOOTH, delay: 0.2 }}
          className="mt-32 max-w-2xl"
        >
          <h3 className="font-display text-h2 mb-8">Or reach us directly.</h3>
          <ul className="space-y-4">
            {CONTACT_LINKS.map((c) => (
              <li
                key={c.label}
                className="flex flex-col sm:flex-row sm:items-baseline gap-2 sm:gap-6"
              >
                <span className="eyebrow min-w-[10rem]">{c.label}</span>
                <a
                  href={`mailto:aalokmamtasah@gmail.com?subject=${encodeURIComponent(c.subject)}`}
                  className="text-body-lg link-underline hover:text-accent transition-colors"
                >
                  aalokmamtasah@gmail.com
                </a>
              </li>
            ))}
          </ul>
        </motion.div>
      </div>
    </section>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="eyebrow block mb-3">{label}</span>
      {children}
    </label>
  );
}

function Select({
  value,
  onChange,
  options,
  placeholder,
}: {
  value: string;
  onChange: (v: string) => void;
  options: string[];
  placeholder: string;
}) {
  return (
    <div className="relative">
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className={cn(
          "w-full bg-transparent border-b border-fg-faint focus:border-accent transition-colors outline-none py-3 text-body-lg appearance-none cursor-pointer",
          value ? "text-fg" : "text-fg-muted",
        )}
      >
        <option value="" className="bg-bg text-fg-muted">
          {placeholder}
        </option>
        {options.map((o) => (
          <option key={o} value={o} className="bg-bg text-fg">
            {o}
          </option>
        ))}
      </select>
      <span
        aria-hidden
        className="pointer-events-none absolute right-1 top-1/2 -translate-y-1/2 text-fg-muted"
      >
        ▾
      </span>
    </div>
  );
}
