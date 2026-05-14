import { Hero } from "@/components/sections/Hero";
import { Problem } from "@/components/sections/Problem";
import { Product } from "@/components/sections/Product";
import { Approach } from "@/components/sections/Approach";
import { Audiences } from "@/components/sections/Audiences";
import { Waitlist } from "@/components/sections/Waitlist";

export default function HomePage() {
  return (
    <>
      <Hero />
      <Problem />
      <Product />
      <Approach />
      <Audiences />
      <Waitlist />
    </>
  );
}
