import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AkinHub Growth AI",
  description:
    "Conteúdo multilíngue, inteligência de relacionamento, SDR e reuniões.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
