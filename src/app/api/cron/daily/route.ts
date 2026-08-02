import type { NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: NextRequest) {
  const cronSecret = process.env.CRON_SECRET;
  const orchestratorSecret = process.env.ORCHESTRATOR_SECRET;
  const authorization = request.headers.get("authorization");

  if (!cronSecret || authorization !== `Bearer ${cronSecret}`) {
    return Response.json(
      { ok: false, error: "unauthorized" },
      { status: 401 },
    );
  }

  if (!orchestratorSecret) {
    return Response.json(
      { ok: false, error: "orchestrator_not_configured" },
      { status: 503 },
    );
  }

  try {
    const supabase = createAdminClient();
    const { data, error } = await supabase.functions.invoke(
      "agent-orchestrator",
      {
        body: {
          source: "vercel-cron",
          requestedAt: new Date().toISOString(),
        },
        headers: {
          "x-orchestrator-secret": orchestratorSecret,
        },
      },
    );

    if (error) {
      return Response.json(
        {
          ok: false,
          error: "orchestrator_invocation_failed",
        },
        { status: 502 },
      );
    }

    return Response.json({
      ok: true,
      data,
      executedAt: new Date().toISOString(),
    });
  } catch {
    return Response.json(
      { ok: false, error: "orchestrator_not_available" },
      { status: 503 },
    );
  }
}
