import type { Metadata } from "next";
import { InstallersHero } from "./InstallersHero";
import { InstallersValue } from "./InstallersValue";
import { InstallersProfile } from "./InstallersProfile";
import { InstallerForm } from "./InstallerForm";

export const metadata: Metadata = {
  title: "[BRAND] for Installers — The smart switch your customer won't return.",
  description:
    "A smart switch built around the professional on the ladder. Fits the boards you already install. Trains in a day.",
};

export default function InstallersPage() {
  return (
    <>
      <InstallersHero />
      <InstallersValue />
      <InstallersProfile />
      <InstallerForm />
    </>
  );
}
