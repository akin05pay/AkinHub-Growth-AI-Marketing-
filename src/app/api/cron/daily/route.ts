import type { NextRequest } from "next/server";

export function GET(request: NextRequest) {
  const secret = process.env.CRON_SECRET;
  const authorization = request.headers.get("authorization");

  if (!secret || authorization !== `Bearer ${secret}`) {
    return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });
  }

  // Bootstrap only: future workers will enqueue source monitoring and drafts.
  return Response.json({
    ok: true,
    queued: [],
    mode: "bootstrap",
    executedAt: new Date().toISOString(),
  });
}
