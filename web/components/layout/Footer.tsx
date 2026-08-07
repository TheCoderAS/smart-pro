import Link from "next/link";

const COLUMNS = [
  {
    title: "Product",
    links: [
      { label: "Overview", href: "/" },
      { label: "Installers", href: "/installers" },
      { label: "Early access", href: "/#waitlist" },
    ],
  },
  {
    title: "Company",
    links: [
      { label: "Press", href: "/press" },
      {
        label: "Careers",
        href: "mailto:aalokmamtasah@gmail.com?subject=Careers",
      },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Early access", href: "/#waitlist" },
      { label: "Brochure (PDF)", href: "/Smart_Switch_Pitch_v1.pdf", download: true },
      {
        label: "Investors",
        href: "mailto:aalokmamtasah@gmail.com?subject=Investors",
      },
    ],
  },
  {
    title: "Legal",
    links: [
      { label: "Privacy", href: "/privacy" },
      { label: "Terms", href: "/terms" },
    ],
  },
];

// TODO: confirm real social handles before launch
const SOCIALS = [
  {
    label: "Instagram",
    href: "https://instagram.com/unisync.in",
    icon: (
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
        <path d="M12 2.16c3.2 0 3.58.01 4.85.07 1.17.05 1.8.25 2.23.41.56.22.96.48 1.38.9.42.42.68.82.9 1.38.16.42.36 1.06.41 2.23.06 1.27.07 1.65.07 4.85s-.01 3.58-.07 4.85c-.05 1.17-.25 1.8-.41 2.23a3.7 3.7 0 0 1-.9 1.38 3.7 3.7 0 0 1-1.38.9c-.42.16-1.06.36-2.23.41-1.27.06-1.65.07-4.85.07s-3.58-.01-4.85-.07c-1.17-.05-1.8-.25-2.23-.41a3.7 3.7 0 0 1-1.38-.9 3.7 3.7 0 0 1-.9-1.38c-.16-.42-.36-1.06-.41-2.23-.06-1.27-.07-1.65-.07-4.85s.01-3.58.07-4.85c.05-1.17.25-1.8.41-2.23.22-.56.48-.96.9-1.38.42-.42.82-.68 1.38-.9.42-.16 1.06-.36 2.23-.41 1.27-.06 1.65-.07 4.85-.07ZM12 0C8.74 0 8.33.01 7.05.07 5.78.13 4.9.34 4.14.63a5.9 5.9 0 0 0-2.13 1.39A5.9 5.9 0 0 0 .62 4.15C.34 4.9.13 5.78.07 7.05.01 8.33 0 8.74 0 12c0 3.26.01 3.67.07 4.95.06 1.27.27 2.15.55 2.91.3.79.69 1.46 1.39 2.13.67.7 1.34 1.09 2.13 1.39.76.28 1.64.49 2.91.55C8.33 23.99 8.74 24 12 24s3.67-.01 4.95-.07c1.27-.06 2.15-.27 2.91-.55a5.9 5.9 0 0 0 2.13-1.39 5.9 5.9 0 0 0 1.39-2.13c.28-.76.49-1.64.55-2.91.06-1.28.07-1.69.07-4.95s-.01-3.67-.07-4.95c-.06-1.27-.27-2.15-.55-2.91a5.9 5.9 0 0 0-1.39-2.13A5.9 5.9 0 0 0 19.86.63C19.1.34 18.22.13 16.95.07 15.67.01 15.26 0 12 0Zm0 5.84a6.16 6.16 0 1 0 0 12.32 6.16 6.16 0 0 0 0-12.32Zm0 10.16a4 4 0 1 1 0-8 4 4 0 0 1 0 8Zm6.41-11.85a1.44 1.44 0 1 0 0 2.88 1.44 1.44 0 0 0 0-2.88Z" />
      </svg>
    ),
  },
  {
    label: "YouTube",
    href: "https://youtube.com/@unisync",
    icon: (
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
        <path d="M23.5 6.2a3 3 0 0 0-2.1-2.1C19.5 3.5 12 3.5 12 3.5s-7.5 0-9.4.6A3 3 0 0 0 .5 6.2C0 8 0 12 0 12s0 4 .5 5.8a3 3 0 0 0 2.1 2.1c1.9.6 9.4.6 9.4.6s7.5 0 9.4-.6a3 3 0 0 0 2.1-2.1C24 16 24 12 24 12s0-4-.5-5.8ZM9.6 15.6V8.4L15.8 12l-6.2 3.6Z" />
      </svg>
    ),
  },
  {
    label: "LinkedIn",
    href: "https://linkedin.com/company/unisync",
    icon: (
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
        <path d="M4.98 3.5a2.5 2.5 0 1 1 0 5.001 2.5 2.5 0 0 1 0-5ZM2.4 21h5.16V9.75H2.4V21Zm7.84-11.25H15.2v1.56h.07c.55-1.04 1.9-2.13 3.91-2.13 4.18 0 4.95 2.75 4.95 6.32V21h-5.16v-5.18c0-1.23-.02-2.82-1.72-2.82-1.72 0-1.99 1.34-1.99 2.73V21h-5.02V9.75Z" />
      </svg>
    ),
  },
];

export function Footer() {
  return (
    <footer className="bg-black border-t border-fg-faint/50 mt-32">
      <div className="max-w-content mx-auto px-6 lg:px-24 py-20">
        <div className="grid grid-cols-1 md:grid-cols-12 gap-12">
          <div className="md:col-span-4">
            <div className="font-display text-2xl mb-3">Unisync</div>
            <p className="text-fg-muted text-sm max-w-xs leading-relaxed">
              The wall should be smarter than the bulb.
            </p>
          </div>

          <div className="md:col-span-8 grid grid-cols-2 md:grid-cols-4 gap-10">
            {COLUMNS.map((col) => (
              <div key={col.title}>
                <div className="eyebrow mb-4">{col.title}</div>
                <ul className="space-y-3">
                  {col.links.map((link) => {
                    const linkClass =
                      "text-sm text-fg-muted hover:text-fg link-underline";
                    // Use a plain <a> for in-page anchors, mailto, and downloadable static files;
                    // Next <Link> for in-app route navigation.
                    const isPlainAnchor =
                      link.href.startsWith("#") ||
                      link.href.startsWith("/#") ||
                      link.href.startsWith("mailto:") ||
                      "download" in link;
                    if (isPlainAnchor) {
                      return (
                        <li key={link.label}>
                          <a
                            href={link.href}
                            className={linkClass}
                            {...("download" in link && link.download
                              ? { download: true }
                              : {})}
                          >
                            {link.label}
                          </a>
                        </li>
                      );
                    }
                    return (
                      <li key={link.label}>
                        <Link href={link.href} className={linkClass}>
                          {link.label}
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </div>
        </div>

        <div className="mt-20 pt-8 border-t border-fg-faint/30 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="text-xs text-fg-muted font-mono tracking-eyebrow uppercase">
            © 2026 Unisync. Made in India
          </div>
          <div className="flex items-center gap-5 text-fg-muted">
            {SOCIALS.map((s) => (
              <a
                key={s.label}
                href={s.href}
                aria-label={s.label}
                className="hover:text-fg transition-colors"
              >
                {s.icon}
              </a>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
}
