// Periop Signal "Ask": a small Cloudflare Worker that answers a clinician's question with Claude,
// grounded on the feed posts and quick references the app sends along. The Anthropic key lives here
// as a Worker secret, never in the app. Deployed by .github/workflows/worker-deploy.yml.
//
//   POST /ask   {question, context: [{id, headline, journal, date, summary, takeHome}], refs: [{id, title, society, excerpt}]}
//               → text/event-stream of {"t": "text delta"} lines, then {"done": true, "model": "..."}
//   GET  /health → {"ok": true, "model": "..."}

const MAX_QUESTION = 600;
const MAX_CONTEXT = 6;
const MAX_REFS = 4;
const MAX_TOKENS = 700;

const SYSTEM = `You are Periop Signal's reference assistant for anesthesiologists and perioperative clinicians. Answer the question directly and concisely (usually under 200 words), in plain prose or a short list, at the level of a colleague who is a specialist.

Ground the answer in the feed posts and quick references provided when they are relevant, and cite them inline as [1], [2] using the numbers given. If they do not cover the question, answer from established, widely accepted knowledge and say so in one short clause. Give numbers, doses and thresholds only when you are confident of them, name the source document when you can, and say plainly when something is uncertain or contested. Never invent citations, trial names or figures.

The reader is responsible for clinical decisions: do not add generic disclaimers, but do flag when an answer depends on patient-specific factors they must assess. If the question is not about anesthesiology, perioperative, critical care or related medicine, say that this assistant only covers those areas.`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: cors() });
    if (url.pathname === "/health") return json({ ok: true, model: model(env) });
    if (url.pathname !== "/ask" || request.method !== "POST") return json({ error: "not found" }, 404);
    if (!env.ANTHROPIC_API_KEY) return json({ error: "The ANTHROPIC_API_KEY secret is not set on this worker." }, 503);

    if (env.ASK_LIMIT) {
      const ip = request.headers.get("cf-connecting-ip") || "unknown";
      const { success } = await env.ASK_LIMIT.limit({ key: ip });
      if (!success) return json({ error: "Too many questions in a short time; try again in a minute." }, 429);
    }

    let body;
    try { body = await request.json(); } catch { return json({ error: "JSON body expected" }, 400); }
    const question = String(body.question || "").trim().slice(0, MAX_QUESTION);
    if (question.length < 3) return json({ error: "Ask a question." }, 400);

    const context = Array.isArray(body.context) ? body.context.slice(0, MAX_CONTEXT) : [];
    const refs = Array.isArray(body.refs) ? body.refs.slice(0, MAX_REFS) : [];
    const sources = [];
    let n = 0;
    for (const p of context) {
      n += 1;
      sources.push(`[${n}] Feed post — ${clip(p.headline, 200)} (${clip(p.journal, 60)}${p.date ? ", " + clip(p.date, 10) : ""})\n${clip(p.summary, 900)}${Array.isArray(p.takeHome) && p.takeHome.length ? "\nTake-home: " + p.takeHome.map(t => clip(t, 220)).join(" | ") : ""}`);
    }
    for (const r of refs) {
      n += 1;
      sources.push(`[${n}] Quick reference — ${clip(r.title, 160)} (${clip(r.society, 60)})\n${clip(r.excerpt, 1400)}`);
    }
    const user = sources.length
      ? `Question: ${question}\n\nMaterial from Periop Signal (cite by number when used):\n\n${sources.join("\n\n")}`
      : `Question: ${question}\n\n(No matching material in Periop Signal; answer from established knowledge and say so briefly.)`;

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: model(env),
        max_tokens: MAX_TOKENS,
        system: SYSTEM,
        messages: [{ role: "user", content: user }],
        stream: true,
      }),
    });
    if (!upstream.ok || !upstream.body) {
      const detail = await upstream.text().catch(() => "");
      return json({ error: `The model request failed (${upstream.status}).`, detail: detail.slice(0, 300) }, 502);
    }

    // Re-emit Anthropic's SSE as a simpler stream of {"t": "..."} lines the app can read.
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    let buffer = "";
    const transform = new TransformStream({
      transform(chunk, controller) {
        buffer += decoder.decode(chunk, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";
        for (const line of lines) {
          if (!line.startsWith("data:")) continue;
          let ev;
          try { ev = JSON.parse(line.slice(5).trim()); } catch { continue; }
          if (ev.type === "content_block_delta" && ev.delta && ev.delta.type === "text_delta") {
            controller.enqueue(encoder.encode(JSON.stringify({ t: ev.delta.text }) + "\n"));
          } else if (ev.type === "error") {
            controller.enqueue(encoder.encode(JSON.stringify({ error: (ev.error && ev.error.message) || "model error" }) + "\n"));
          }
        }
      },
      flush(controller) {
        controller.enqueue(encoder.encode(JSON.stringify({ done: true, model: model(env) }) + "\n"));
      },
    });
    return new Response(upstream.body.pipeThrough(transform), {
      headers: { ...cors(), "content-type": "application/x-ndjson; charset=utf-8", "cache-control": "no-store" },
    });
  },
};

function model(env) { return env.MODEL || "claude-sonnet-5-5"; }
function clip(s, n) { return String(s || "").replace(/\s+/g, " ").trim().slice(0, n); }
function cors() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST, GET, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors(), "content-type": "application/json; charset=utf-8" } });
}
