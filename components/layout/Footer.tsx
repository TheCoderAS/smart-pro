import Link from "next/link";

const COLUMNS = [
  {
    title: "Product",
    links: [
      { label: "Overview", href: "/" },
      { label: "Installers", href: "/installers" },
      { label: "Early access", href: "#waitlist" },
    ],
  },
  {
    title: "Company",
    links: [
      { label: "Team", href: "/#team" },
      { label: "Press", href: "/press" },
      // TODO: replace careers email domain
      { label: "Careers", href: "mailto:careers@brand.com" },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "FAQ", href: "/#faq" },
      { label: "Updates", href: "#waitlist" },
      // TODO: replace investors email domain
      { label: "Investors", href: "mailto:investors@brand.com" },
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

export function Footer() {
  return (
    <footer className="border-t border-fg-faint/50 mt-32">
      <div className="max-w-content mx-auto px-6 lg:px-24 py-20">
        <div className="grid grid-cols-1 md:grid-cols-12 gap-12">
          <div className="md:col-span-4">
            <div className="font-display text-2xl mb-3">[BRAND]</div>
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
                    const isWaitlist = link.href === "#waitlist";
                    if (isWaitlist) {
                      return (
                        <li key={link.label}>
                          <a
                            href="#waitlist"
                            data-waitlist-trigger
                            className="text-sm text-fg-muted hover:text-fg link-underline"
                          >
                            {link.label}
                          </a>
                        </li>
                      );
                    }
                    return (
                      <li key={link.label}>
                        <Link
                          href={link.href}
                          className="text-sm text-fg-muted hover:text-fg link-underline"
                        >
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
            © 2026 [BRAND]. Made in India
          </div>
          <div className="flex items-center gap-5 text-fg-muted">
            {/* TODO: replace with real social URLs */}
            <a
              href="https://x.com/brand"
              aria-label="X / Twitter"
              className="hover:text-fg transition-colors"
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden
              >
                <path d="M18.244 2H21l-6.52 7.452L22 22h-6.84l-4.74-6.214L4.8 22H2l7.02-8.02L2 2h6.94l4.29 5.692L18.244 2Zm-1.2 18h1.84L7.04 4H5.1l11.944 16Z" />
              </svg>
            </a>
            <a
              href="https://linkedin.com/company/brand"
              aria-label="LinkedIn"
              className="hover:text-fg transition-colors"
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden
              >
                <path d="M4.98 3.5a2.5 2.5 0 1 1 0 5.001 2.5 2.5 0 0 1 0-5ZM2.4 21h5.16V9.75H2.4V21Zm7.84-11.25H15.2v1.56h.07c.55-1.04 1.9-2.13 3.91-2.13 4.18 0 4.95 2.75 4.95 6.32V21h-5.16v-5.18c0-1.23-.02-2.82-1.72-2.82-1.72 0-1.99 1.34-1.99 2.73V21h-5.02V9.75Z" />
              </svg>
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
