import type { Metadata } from "next";
import { Fraunces, JetBrains_Mono } from "next/font/google";
import { GeistSans } from "geist/font/sans";
import "./globals.css";
import { Nav } from "@/components/layout/Nav";
import { Footer } from "@/components/layout/Footer";
import { ScrollProgress } from "@/components/layout/ScrollProgress";
import { WaitlistModalProvider } from "@/components/ui/WaitlistModal";

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
  title: "[BRAND] — The wall should be smarter than the bulb.",
  description:
    "[BRAND] is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch, coming to India in 2026.",
  metadataBase: new URL("https://brand.com"),
  alternates: {
    canonical: "https://brand.com",
  },
  robots: {
    index: true,
    follow: true,
  },
  openGraph: {
    title: "[BRAND] — The wall should be smarter than the bulb.",
    description:
      "[BRAND] is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch, coming to India in 2026.",
    url: "https://brand.com",
    siteName: "[BRAND]",
    // TODO: add og-image.jpg at /public/og-image.jpg
    images: [{ url: "/og-image.jpg", width: 1200, height: 630 }],
    locale: "en_IN",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "[BRAND] — The wall should be smarter than the bulb.",
    description:
      "[BRAND] is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch, coming to India in 2026.",
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
        <WaitlistModalProvider>
          <ScrollProgress />
          <Nav />
          <main>{children}</main>
          <Footer />
        </WaitlistModalProvider>
      </body>
    </html>
  );
}
