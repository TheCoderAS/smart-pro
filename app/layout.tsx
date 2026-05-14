import type { Metadata } from "next";
import { Fraunces, JetBrains_Mono } from "next/font/google";
import { GeistSans } from "geist/font/sans";
import "./globals.css";
import { Nav } from "@/components/layout/Nav";
import { Footer } from "@/components/layout/Footer";
import { ScrollProgress } from "@/components/layout/ScrollProgress";
import { ReducedMotionProvider } from "@/components/layout/ReducedMotionProvider";

const fraunces = Fraunces({
  subsets: ["latin"],
  variable: "--font-display",
  display: "swap",
  axes: ["opsz", "SOFT"],
});

const jetbrains = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Unisync — The wall should be smarter than the bulb.",
  description:
    "Unisync is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch — pilot launching Bangalore, Q3 2026.",
  metadataBase: new URL("https://unisync.in"),
  alternates: {
    canonical: "https://unisync.in",
  },
  robots: {
    index: true,
    follow: true,
  },
  openGraph: {
    title: "Unisync — The wall should be smarter than the bulb.",
    description:
      "Unisync is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch — pilot launching Bangalore, Q3 2026.",
    url: "https://unisync.in",
    siteName: "Unisync",
    // TODO: add og-image.jpg at /public/og-image.jpg
    images: [{ url: "/og-image.jpg", width: 1200, height: 630 }],
    locale: "en_IN",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Unisync — The wall should be smarter than the bulb.",
    description:
      "Unisync is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch — pilot launching Bangalore, Q3 2026.",
    // TODO: add og-image.jpg at /public/og-image.jpg
    images: ["/og-image.jpg"],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${fraunces.variable} ${GeistSans.variable} ${jetbrains.variable}`}
    >
      <body>
        <ReducedMotionProvider>
          <ScrollProgress />
          <Nav />
          <main>{children}</main>
          <Footer />
        </ReducedMotionProvider>
      </body>
    </html>
  );
}
