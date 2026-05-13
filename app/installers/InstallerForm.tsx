"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SMOOTH, VIEWPORT_ONCE } from "@/lib/motion";
import { cn } from "@/lib/utils";

type FormState = {
  name: string;
  city: string;
  experience: string;
  phone: string;
  message: string;
};

const INITIAL: FormState = {
  name: "",
  city: "",
  experience: "",
  phone: "",
  message: "",
};

export function InstallerForm() {
  const [data, setData] = useState<FormState>(INITIAL);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onChange =
    (k: keyof FormState) =>
    (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      setData((d) => ({ ...d, [k]: e.target.value }));

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch("/api/installer-interest", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
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
    <section className="relative py-[clamp(4rem,10vw,8rem)] border-t border-fg-faint/40">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <EyebrowLabel withMark>Become a partner</EyebrowLabel>
          </div>
          <div className="lg:col-span-8 max-w-xl">
            <RevealText as="h2" className="font-display text-h1">
              Tell us about your work.
            </RevealText>

            {submitted ? (
              <motion.div
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.6, ease: SMOOTH }}
                className="mt-12 p-8 border border-fg-faint"
              >
                <p className="text-body-lg leading-relaxed">
                  Received. We&apos;ll be in touch when there&apos;s something
                  worth saying.
                </p>
              </motion.div>
            ) : (
              <motion.form
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={VIEWPORT_ONCE}
                transition={{ duration: 0.8, ease: SMOOTH, delay: 0.3 }}
                onSubmit={onSubmit}
                className="mt-12 space-y-8"
              >
                <Field
                  label="Name"
                  required
                  value={data.name}
                  onChange={onChange("name")}
                />
                <Field
                  label="City"
                  required
                  value={data.city}
                  onChange={onChange("city")}
                />
                <Field
                  label="Years of experience"
                  type="number"
                  min={0}
                  value={data.experience}
                  onChange={onChange("experience")}
                />
                <Field
                  label="Phone"
                  type="tel"
                  required
                  value={data.phone}
                  onChange={onChange("phone")}
                />
                <Field
                  label="Tell us a little"
                  textarea
                  value={data.message}
                  onChange={onChange("message")}
                />

                {error && (
                  <div className="text-sm text-accent" role="alert">
                    {error}
                  </div>
                )}

                <button
                  type="submit"
                  disabled={submitting}
                  className={cn(
                    "group relative overflow-hidden inline-flex items-center justify-center",
                    "px-7 py-4 border border-fg-faint text-sm font-mono tracking-eyebrow uppercase",
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
                    {submitting ? "Sending…" : "Submit"}
                  </span>
                </button>
              </motion.form>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

type FieldProps = {
  label: string;
  textarea?: boolean;
} & React.InputHTMLAttributes<HTMLInputElement> &
  React.TextareaHTMLAttributes<HTMLTextAreaElement>;

function Field({ label, textarea, ...rest }: FieldProps) {
  return (
    <label className="block">
      <span className="eyebrow block mb-2">{label}</span>
      {textarea ? (
        <textarea
          {...(rest as React.TextareaHTMLAttributes<HTMLTextAreaElement>)}
          rows={4}
          className="w-full bg-transparent border-b border-fg-faint focus:border-accent transition-colors outline-none py-2 resize-none"
        />
      ) : (
        <input
          {...(rest as React.InputHTMLAttributes<HTMLInputElement>)}
          className="w-full bg-transparent border-b border-fg-faint focus:border-accent transition-colors outline-none py-2"
        />
      )}
    </label>
  );
}
