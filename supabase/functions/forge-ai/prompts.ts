// What the model is asked to do, and what it may answer with.
//
// Two jobs, and only two. Forge is not a chat product: there is no
// conversation, no memory between calls, and no free-form answer. The model
// reads a week back to somebody in one sentence (`reading`), or proposes edits
// to a week they already keep (`plan`). Everything it returns is constrained by
// a JSON schema here and checked again on the phone before anybody sees it —
// `ReviewObservation.validate` for a reading, `AIWirePlan.resolved(against:)`
// for a plan — and anything that fails either check is discarded for the
// phone's own arithmetic.

export type Task = "reading" | "plan";

export const TASKS: readonly Task[] = ["reading", "plan"];

export function isTask(value: unknown): value is Task {
  return value === "reading" || value === "plan";
}

// ---------------------------------------------------------------------------
// The models — fixed per task, never shared, never chosen by the client.
//
// The reading is the request that makes a claim about somebody's own life,
// once a week, from counts it must not misread. Quality is the whole product
// there, so it gets the stronger model. A plan is structured interpretation of
// a sentence against a list the app already sent — ids, minutes, weekdays —
// and the phone re-checks every edit, so it gets the much cheaper one.
// ---------------------------------------------------------------------------

export const READING_MODEL = "gpt-6-sol";
export const PLAN_MODEL = "gpt-6-luna";

export function modelFor(task: Task): string {
  switch (task) {
    case "reading":
      return READING_MODEL;
    case "plan":
      return PLAN_MODEL;
  }
}

/// Output ceilings. A reading is at most two sentences and a plan is a short
/// list of edits; anything longer than this is already wrong.
export const MAX_OUTPUT_TOKENS: Record<Task, number> = {
  reading: 400,
  plan: 1200,
};

// ---------------------------------------------------------------------------
// The voice
//
// Forge's register is the product. Nothing congratulates, nothing diagnoses,
// nothing exclaims, and no sentence tells somebody what they are like.
// ---------------------------------------------------------------------------

export const VOICE = `You write for Forge, an app for keeping a daily practice.

The register, which is not negotiable:
- Flat, adult, unsentimental. State what the record shows and stop.
- Never congratulate, praise, encourage, or commiserate.
- Never diagnose the person. "You kept four of five Mondays" is a fact.
  "You struggle on Fridays" is a claim about who they are, and you have no
  standing to make it.
- No exclamation marks. No emoji. No second-person imperatives about effort
  ("keep going", "push harder", "you've got this").
- Counts are spelled out as words below one hundred: "four", not "4".
- Short. A sentence that could be shorter is wrong.`;

export const READING_RULES = `You are reading somebody's own week back to them.

HARD RULES — a sentence breaking any of these is thrown away unread:
1. Assert ONLY numbers that appear in the data you were given. Do not add,
   subtract, average, or round. If the data says four of five Mondays, you may
   say four of five Mondays and nothing else about Mondays.
2. Name ONLY activities and identity statements that appear in the data,
   spelled exactly as given.
3. At most two sentences.
4. Say one thing. Not a summary, not a list, not a conclusion — one
   observation the person could not easily have made themselves.
5. If the week does not clearly show anything, say what the week was, plainly.

HEALTH — this is a record of habits, not a medical record:
6. Never give medical advice of any kind.
7. Never diagnose, and never suggest or imply a condition, illness, disorder
   or injury — physical or mental.
8. If an activity or identity mentions sleep, pain, mood, eating, medication,
   illness, injury or any symptom, do not interpret it as a symptom or as
   evidence of a condition. Treat it only as an activity that was or was not
   done, and report the count.
9. Never recommend a treatment, a therapy, a medication, a supplement, a dose,
   a diet, or seeing (or not seeing) a doctor or any other professional.

Prefer, in this order: a split between two weekdays; a split between two named
activities; an identity with no evidence beside one with plenty; the plain
count.`;

export const PLAN_RULES = `You are rearranging a week somebody already keeps.

HARD RULES:
1. Only edit activities present in the brief, by their exact id. You may not
   invent an activity, and there is no way to add one — an activity nobody
   chose has no business in a routine somebody built by hand.
2. Never place anything inside an hour the person said they were busy.
3. Leave a time somebody already chose alone unless it collides with something.
4. Spread repeats across the week rather than stacking them on consecutive days.
5. Nothing before waking, nothing after 22:30.
6. The summary is one sentence about the shape of the change.
7. For each change, set only the field its kind uses — "minute" for time,
   "minutes" for duration, "weekdays" for days — and null for the other two.`;

const RULES: Record<Task, string> = {
  reading: READING_RULES,
  plan: PLAN_RULES,
};

export function instructionsFor(task: Task): string {
  return `${VOICE}\n\n${RULES[task]}`;
}

// ---------------------------------------------------------------------------
// The shapes
//
// Strict structured outputs: every property is listed in `required`, and the
// optional ones are nullable instead of absent. The app's decoders read a null
// exactly as they read a missing field (`decodeIfPresent`), so the wire shape
// the app already understands is unchanged.
// ---------------------------------------------------------------------------

export const SCHEMAS: Record<Task, Record<string, unknown>> = {
  reading: {
    type: "object",
    properties: { observation: { type: "string" } },
    required: ["observation"],
    additionalProperties: false,
  },
  plan: {
    type: "object",
    properties: {
      summary: { type: "string" },
      changes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            kind: { type: "string", enum: ["time", "duration", "days"] },
            id: { type: "string" },
            minute: { type: ["integer", "null"] },
            minutes: { type: ["integer", "null"] },
            weekdays: { type: ["array", "null"], items: { type: "integer" } },
          },
          required: ["kind", "id", "minute", "minutes", "weekdays"],
          additionalProperties: false,
        },
      },
    },
    required: ["summary", "changes"],
    additionalProperties: false,
  },
};

// ---------------------------------------------------------------------------
// The input
// ---------------------------------------------------------------------------

/// The request body, as far as this function reads it. Anything else in the
/// body — including any identifier a client puts there — is ignored.
export interface AIRequestBody {
  task?: unknown;
  brief?: unknown;
  request?: unknown;
}

/// How much of a free-text request is ever forwarded.
export const REQUEST_LIMIT = 500;

/// The user message: the brief the app built (the only thing it ever sends
/// about a person — see `AIBrief`), and for a plan, what they asked for.
export function inputFor(task: Task, body: AIRequestBody): string {
  const brief = JSON.stringify(body.brief ?? {});
  const parts = [`Here is what Forge knows about this person:\n${brief}`];
  if (task === "plan") {
    const asked = typeof body.request === "string" ? body.request.slice(0, REQUEST_LIMIT) : "";
    if (asked) parts.push(`They asked: ${asked}`);
  }
  return parts.join("\n\n");
}
