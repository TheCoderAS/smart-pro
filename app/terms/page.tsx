// TODO: replace with content reviewed by counsel before public launch
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms — Unisync",
};

export default function TermsPage() {
  return (
    <div className="pt-40 pb-24">
      <div className="max-w-3xl mx-auto px-6 lg:px-24">
        <div className="eyebrow mb-6">Legal</div>
        <h1 className="font-display text-h1 mb-12">Terms.</h1>

        <div className="space-y-6 text-fg/90 leading-relaxed">
          <p>
            These terms govern use of this website. They are a placeholder
            template. The final version will be reviewed by counsel before
            public launch.
          </p>
          <h2 className="font-display text-h2 mt-12">Use of the site</h2>
          <p>
            This website is provided for informational purposes. Nothing on this
            page constitutes a product offer, a warranty, or a binding
            commitment. Specifications and timelines are subject to change.
          </p>
          <h2 className="font-display text-h2 mt-12">Intellectual property</h2>
          <p>
            All content on this site, including the Unisync name and wordmark,
            is the property of Unisync and its respective owners.
          </p>
          <h2 className="font-display text-h2 mt-12">Contact</h2>
          <p>
            Questions about these terms can be sent to{" "}
            <a
              href="mailto:aalokmamtasah@gmail.com"
              className="link-underline hover:text-accent transition-colors"
            >
              aalokmamtasah@gmail.com
            </a>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
