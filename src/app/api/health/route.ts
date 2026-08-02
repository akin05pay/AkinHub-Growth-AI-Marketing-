import { hasSupabaseConfig } from "@/lib/env";

export function GET() {
  return Response.json({
    ok: true,
    service: "akinhub-growth-ai",
    version: "0.1.0",
    supabaseConfigured: hasSupabaseConfig(),
    checkedAt: new Date().toISOString(),
  });
}
