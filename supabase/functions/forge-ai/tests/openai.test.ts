// The OpenAI Responses API boundary, against a mocked `fetch`. No request in
// this file reaches OpenAI, and the key used is a placeholder.

import { assertEquals, assertExists } from "jsr:@std/assert@1";
import { createOpenAIProvider, interpretResponse, type ModelRequest, OPENAI_RESPONSES_URL } from "../openai.ts";

const PLACEHOLDER_KEY = "test-placeholder-not-a-key";

const request: ModelRequest = {
  model: "gpt-6-sol",
  instructions: "voice + rules",
  input: "Here is what Forge knows about this person:\n{}",
  schemaName: "forge_reading",
  schema: { type: "object" },
  maxOutputTokens: 400,
};

interface Captured {
  url: string;
  init: RequestInit;
}

function mockFetch(respond: () => Response | Promise<Response>, captured: Captured[] = []): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    captured.push({ url: String(input), init: init ?? {} });
    return Promise.resolve(respond());
  }) as typeof fetch;
}

function completed(text: string, extra: Record<string, unknown> = {}) {
  return {
    id: "resp_test",
    object: "response",
    status: "completed",
    output: [
      { type: "reasoning", id: "rs_1", summary: [] },
      { type: "message", role: "assistant", content: [{ type: "output_text", text, annotations: [] }] },
    ],
    ...extra,
  };
}

const ok = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });

// --- The request -------------------------------------------------------------

Deno.test("posts one Responses API call with strict JSON output and nothing stored", async () => {
  const captured: Captured[] = [];
  const provider = createOpenAIProvider({
    apiKey: PLACEHOLDER_KEY,
    fetch: mockFetch(() => ok(completed('{"observation":"Four of five Mondays."}')), captured),
  });
  await provider.generate(request);

  assertEquals(captured.length, 1);
  const { url, init } = captured[0];
  assertEquals(url, OPENAI_RESPONSES_URL);
  assertEquals(url, "https://api.openai.com/v1/responses");
  assertEquals(init.method, "POST");
  const headers = new Headers(init.headers);
  assertEquals(headers.get("Authorization"), `Bearer ${PLACEHOLDER_KEY}`);
  assertEquals(headers.get("Content-Type"), "application/json");
  assertExists(init.signal, "every call has a timeout");

  const body = JSON.parse(String(init.body));
  assertEquals(body.model, "gpt-6-sol");
  assertEquals(body.instructions, "voice + rules");
  assertEquals(body.input, request.input);
  assertEquals(body.max_output_tokens, 400);
  assertEquals(body.store, false);
  assertEquals(body.text.format, {
    type: "json_schema",
    name: "forge_reading",
    schema: { type: "object" },
    strict: true,
  });
  // Not a chat: one input, no conversation, no tools.
  assertEquals(body.tools, undefined);
  assertEquals(body.previous_response_id, undefined);
});

// --- Reading the answer ------------------------------------------------------

Deno.test("a completed response with a JSON object is the answer", async () => {
  const provider = createOpenAIProvider({
    apiKey: PLACEHOLDER_KEY,
    fetch: mockFetch(() => ok(completed('{"observation":"Four of five Mondays."}'))),
  });
  assertEquals(await provider.generate(request), {
    kind: "json",
    text: '{"observation":"Four of five Mondays."}',
  });
});

Deno.test("a refusal part is a refusal", () => {
  assertEquals(
    interpretResponse({
      status: "completed",
      output: [{ type: "message", content: [{ type: "refusal", refusal: "I can't help with that." }] }],
    }),
    { kind: "refused" },
  );
});

Deno.test("an answer filtered for content is a refusal; one cut off is empty", () => {
  assertEquals(
    interpretResponse({ status: "incomplete", incomplete_details: { reason: "content_filter" }, output: [] }),
    { kind: "refused" },
  );
  assertEquals(
    interpretResponse({
      status: "incomplete",
      incomplete_details: { reason: "max_output_tokens" },
      output: [{ type: "message", content: [{ type: "output_text", text: '{"observ' }] }],
    }),
    { kind: "empty" },
  );
});

Deno.test("no text is empty", () => {
  assertEquals(interpretResponse(completed("")), { kind: "empty" });
  assertEquals(interpretResponse({ status: "completed", output: [] }), { kind: "empty" });
});

Deno.test("text that is not a JSON object is malformed", () => {
  assertEquals(interpretResponse(completed("Four of five Mondays.")), { kind: "malformed" });
  assertEquals(interpretResponse(completed("[1,2,3]")), { kind: "malformed" });
  assertEquals(interpretResponse(completed("null")), { kind: "malformed" });
});

Deno.test("a failed or errored response is a failure", () => {
  assertEquals(interpretResponse({ status: "failed", error: { code: "server_error" } }), { kind: "failed" });
  assertEquals(interpretResponse({ error: { message: "x" } }), { kind: "failed" });
  assertEquals(interpretResponse("nope"), { kind: "failed" });
});

Deno.test("an HTTP error from OpenAI is a failure carrying only its status", async () => {
  for (const status of [400, 401, 429, 500, 503]) {
    const provider = createOpenAIProvider({
      apiKey: PLACEHOLDER_KEY,
      fetch: mockFetch(() => new Response('{"error":{"message":"no"}}', { status })),
    });
    assertEquals(await provider.generate(request), { kind: "failed", status });
  }
});

Deno.test("an unreadable body is a failure", async () => {
  const provider = createOpenAIProvider({
    apiKey: PLACEHOLDER_KEY,
    fetch: mockFetch(() => new Response("<html>gateway</html>", { status: 200 })),
  });
  assertEquals(await provider.generate(request), { kind: "failed", status: 200 });
});

Deno.test("a network error is a failure, not a thrown exception", async () => {
  const provider = createOpenAIProvider({
    apiKey: PLACEHOLDER_KEY,
    fetch: (() => Promise.reject(new TypeError("connection reset"))) as typeof fetch,
  });
  assertEquals(await provider.generate(request), { kind: "failed" });
});
