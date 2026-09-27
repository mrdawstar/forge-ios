// The model provider, and the only file that knows which one it is.
//
// The handler speaks to `ModelProvider` and receives a `ModelResult`: some JSON
// text, a refusal, nothing, or a failure. Nothing about OpenAI's wire format —
// output items, content parts, `incomplete_details` — leaves this file, so the
// provider can change without the request logic noticing.
//
// # The key
//
// `OPENAI_API_KEY` is a Supabase server secret, read once in `index.ts` and
// handed to `createOpenAIProvider`. It is never logged, never echoed in an
// error, never sent anywhere but `api.openai.com`, and never exists in the app.

export interface ModelRequest {
  model: string;
  /// The system-level instructions: Forge's voice and the task's rules.
  instructions: string;
  /// The one user turn: the brief, and for a plan the person's own request.
  input: string;
  schemaName: string;
  schema: Record<string, unknown>;
  maxOutputTokens: number;
}

export type ModelResult =
  /// A complete answer, already checked to be a JSON object.
  | { kind: "json"; text: string }
  /// The model declined, or the answer was filtered.
  | { kind: "refused" }
  /// Nothing usable came back: no text, or it was cut off.
  | { kind: "empty" }
  /// Text came back, but not a JSON object.
  | { kind: "malformed" }
  /// The call itself failed: HTTP error, network, timeout, unreadable body.
  | { kind: "failed"; status?: number };

export interface ModelProvider {
  generate(request: ModelRequest): Promise<ModelResult>;
}

export interface OpenAIOptions {
  apiKey: string;
  /// Injected in tests. Production uses the global `fetch`.
  fetch?: typeof fetch;
  baseURL?: string;
  timeoutMs?: number;
}

export const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

/// The OpenAI Responses API.
///
/// `store: false` so OpenAI does not keep the response for later retrieval —
/// there is no conversation to continue, and nothing about a person's week
/// needs to outlive the one sentence it produced.
export function createOpenAIProvider(options: OpenAIOptions): ModelProvider {
  const send = options.fetch ?? fetch;
  const url = options.baseURL ? `${options.baseURL.replace(/\/$/, "")}/responses` : OPENAI_RESPONSES_URL;
  const timeoutMs = options.timeoutMs ?? 30_000;

  return {
    async generate(request: ModelRequest): Promise<ModelResult> {
      const body = {
        model: request.model,
        instructions: request.instructions,
        input: request.input,
        max_output_tokens: request.maxOutputTokens,
        store: false,
        text: {
          format: {
            type: "json_schema",
            name: request.schemaName,
            schema: request.schema,
            strict: true,
          },
        },
      };

      let response: Response;
      try {
        response = await send(url, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${options.apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch {
        // Network, DNS, TLS or timeout. The error itself is not surfaced: it
        // can carry the request, and the request carries a person's week.
        return { kind: "failed" };
      }

      if (!response.ok) {
        // Drain without reading into anything that could be logged.
        await response.body?.cancel().catch(() => {});
        return { kind: "failed", status: response.status };
      }

      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        return { kind: "failed", status: response.status };
      }
      return interpretResponse(payload);
    },
  };
}

// ---------------------------------------------------------------------------
// Reading a Responses API object
// ---------------------------------------------------------------------------

interface ContentPart {
  type?: string;
  text?: string;
  refusal?: string;
}

interface OutputItem {
  type?: string;
  content?: ContentPart[];
}

interface ResponsesObject {
  status?: string;
  error?: unknown;
  incomplete_details?: { reason?: string } | null;
  output?: OutputItem[];
}

/// A Responses API object, reduced to the four outcomes the handler cares
/// about. Exported for the tests.
export function interpretResponse(payload: unknown): ModelResult {
  if (!payload || typeof payload !== "object") return { kind: "failed" };
  const response = payload as ResponsesObject;

  if (response.error) return { kind: "failed" };

  if (response.status === "incomplete") {
    // Filtered is a refusal in all but name; cut off at the token ceiling is
    // half a JSON object, which is nothing.
    return response.incomplete_details?.reason === "content_filter"
      ? { kind: "refused" }
      : { kind: "empty" };
  }
  if (response.status && response.status !== "completed") return { kind: "failed" };

  let text = "";
  for (const item of response.output ?? []) {
    if (item.type !== "message") continue;
    for (const part of item.content ?? []) {
      if (part.type === "refusal") return { kind: "refused" };
      if (part.type === "output_text" && typeof part.text === "string") text += part.text;
    }
  }

  if (!text.trim()) return { kind: "empty" };

  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { kind: "malformed" };
    }
  } catch {
    return { kind: "malformed" };
  }
  return { kind: "json", text };
}
