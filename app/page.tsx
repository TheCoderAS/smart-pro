import { Hero } from "@/components/sections/Hero";
import { Problem } from "@/components/sections/Problem";
import { Approach } from "@/components/sections/Approach";
import { Audiences } from "@/components/sections/Audiences";
import { Team } from "@/components/sections/Team";

export default function HomePage() {
  return (
    <>
      <Hero />
      <Problem />
      <Approach />
      <Audiences />
      <Team />
    </>
  );
}
