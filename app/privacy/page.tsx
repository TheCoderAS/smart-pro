// TODO: replace with content reviewed by counsel before public launch
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy — [BRAND]",
};

export default function PrivacyPage() {
  return (
    <div className="pt-40 pb-24">
      <div className="max-w-3xl mx-auto px-6 lg:px-24">
        <div className="eyebrow mb-6">Legal</div>
        <h1 className="font-display text-h1 mb-12">Privacy.</h1>

        <div className="prose-custom space-y-6 text-fg/90 leading-relaxed">
          <p>
            This page describes how [BRAND] collects, uses, and protects
            information when you visit this website or sign up for early access.
            It is a placeholder template. The final version of this policy will
            be reviewed by counsel before public launch.
          </p>
          <h2 className="font-display text-h2 mt-12">What we collect</h2>
          <p>
            If you submit your email through one of our forms, we store that
            email so we can contact you about [BRAND]. We do not sell your
            data, ever.
          </p>
          <h2 className="font-display text-h2 mt-12">Cookies</h2>
          <p>
            This website does not use third-party tracking cookies. If we add
            basic analytics in the future, we will update this notice.
          </p>
          <h2 className="font-display text-h2 mt-12">Contact</h2>
          <p>
            For any privacy-related questions, write to{" "}
            <a
              href="mailto:privacy@brand.com"
              className="link-underline hover:text-accent transition-colors"
            >
              privacy@brand.com
            </a>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
