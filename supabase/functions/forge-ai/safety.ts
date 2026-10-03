// What Ask Forge will not do, decided twice: once before the model is asked,
// and once on what it answered.
//
// # Why a screen in code as well as rules in the prompt
//
// The prompt (`COACH_RULES` in prompts.ts) is the main line, because a model
// reads intent far better than a pattern does. But a prompt is a request, not
// a guarantee, and two outcomes must not depend on a model choosing to follow
// one:
//
//   * **A message that suggests self-harm or a crisis never reaches coaching.**
//     It is answered here, with a fixed caring line and the 988 Suicide &
//     Crisis Lifeline, before any model is asked and before any quota is
//     spent. The app runs the same screen first (`CoachSafety` in Swift), so
//     such a message normally never leaves the phone; this is the second lock.
//   * **The unambiguous cases of the declined topics** — a steroid cycle, a
//     supplement dose, a water fast, an explicit request, a request to harass
//     somebody — are declined in one fixed sentence, again without a model.
//
// The patterns are deliberately narrow. A false positive here costs somebody a
// useful answer ("help me quit porn" is a habit, not sexual content; "I was
// bullied" is not a request to bully), so anything a pattern cannot decide is
// left to the model and its rules.
//
// Nothing in this file logs, stores or returns the text it reads.

export type ScreenRule = "crisis" | "medical" | "drugs" | "diet" | "sexual" | "harassment";

/// Every rule, in the order they are checked. Crisis is first and wins.
export const SCREEN_RULES: readonly ScreenRule[] = [
  "crisis",
  "medical",
  "drugs",
  "diet",
  "sexual",
  "harassment",
];

/// The 988 line, exactly. The app recognises it (`CoachSafety.mentionsLifeline`)
/// and offers Call and Text under the reply.
export const LIFELINE_LINE =
  "Call or text 988 to reach the 988 Suicide & Crisis Lifeline, free and any time, in the US.";

/// The whole reply to a message that suggests self-harm or a crisis. A short
/// caring line and the lifeline; no coaching, no question, no proposal.
export const CRISIS_REPLY = `That sounds like a lot to carry, and you don't have to carry it alone. ${LIFELINE_LINE}`;

/// One sentence per declined topic: what Forge does not do, and what it does.
export const DECLINE_REPLIES: Record<Exclude<ScreenRule, "crisis">, string> = {
  medical:
    "Forge can't diagnose or treat anything, and nothing here is medical advice; a doctor can help with that. Forge can help with the habits around it: sleep, training and the activities you keep.",
  drugs:
    "Forge doesn't advise on drugs, PEDs or supplement doses. It can help you plan the training, sleep and habits that do the work.",
  diet:
    "Forge doesn't give diets or fasting protocols. It can help you fit training, sleep and the activities you keep into your week.",
  sexual: "Forge doesn't write that. Ask about your training, your week or your Arc.",
  harassment: "Forge won't help with that. It can help with what you do with your own week.",
};

export function replyFor(rule: ScreenRule): string {
  return rule === "crisis" ? CRISIS_REPLY : DECLINE_REPLIES[rule];
}

// ---------------------------------------------------------------------------
// The patterns
// ---------------------------------------------------------------------------

const CRISIS: RegExp[] = [
  // "yourself" too: the same screen reads the model's reply (`checkAnswer`).
  /\b(kill|killing|hurt|hurting|harm|harming|cut|cutting|burn|burning)\s+(myself|yourself)\b/,
  /\bsuicid/,
  /\bself[\s-]?harm/,
  /\bend(ing)?\s+(my\s+life|it\s+all)\b/,
  /\btake\s+my\s+(own\s+)?life\b/,
  /\b(want|wanna|going|ready)\s+(to\s+)?die\b/,
  /\b(don'?t|do\s+not)\s+want\s+to\s+(live|be\s+alive|be\s+here|exist|wake\s+up)\b/,
  /\bno\s+(reason|point)\s+(to|in)\s+(live|living|go\s+on|going\s+on)\b/,
  /\bnot\s+worth\s+living\b/,
  /\bbetter\s+off\s+(dead|without\s+me)\b/,
  /\boverdos(e|ed|ing)\b/,
];

const MEDICAL: RegExp[] = [
  /\bdiagnos/,
  /\bprescri(be|bed|ption)/,
  /\b(what|which)\s+(meds|medication|medicine|pills?)\b/,
  /\b(antidepressants?|ssris?)\b/,
  /\bdo\s+i\s+have\s+(adhd|add|depression|anxiety|ocd|ptsd|bipolar|autism|cancer|diabetes|a\s+concussion|an?\s+(eating\s+)?disorder)\b/,
  /\bam\s+i\s+(depressed|bipolar|autistic)\b/,
];

const DRUGS: RegExp[] = [
  /\b(steroids?|anabolics?|sarms?|trenbolone|tren|anavar|oxandrolone|dianabol|dbol|winstrol|testosterone|trt|hgh|clenbuterol|clen|peptides?|ozempic|semaglutide|adderall|modafinil|cocaine|mdma|molly|ketamine|lsd|psilocybin|microdos\w*)\b/,
];

const SUPPLEMENT =
  /\b(creatine|caffeine|melatonin|ashwagandha|magnesium|zinc|vitamins?(\s+[a-z0-9]+)?|fish\s+oil|omega[\s-]?3|pre[\s-]?workout|protein\s+powder|whey|supplements?|nootropics?|beta[\s-]alanine|l[\s-]theanine)\b/;
const DOSE = /\b(how\s+much|how\s+many|doses?|dosage|dosing|stack|should\s+i\s+take|\d+(\.\d+)?\s*(mg|mcg|g|grams?|iu|scoops?))\b/;

const DIET: RegExp[] = [
  /\b(water|dry|juice)\s+fast/,
  /\b\d+[\s-]*(day|hour|hr)s?\s+fast\b/,
  /\bfasting\s+(protocol|plan|schedule|window)\b/,
  /\bintermittent\s+fasting\b/,
  /\bomad\b/,
  /\b(crash\s+diet|starve|starving|starvation|purg(e|ing)|laxatives?|diet\s+pills?|fat\s+burners?)\b/,
  // "Stop eating junk at night" is a habit; stopping eating altogether is not.
  /\bstop\s+eating\s+(entirely|completely|altogether|for\s+(a|\d+|two|three|four|five|several)\s+(days?|weeks?))\b/,
  /\b[1-9]\d{2}\s*(k?cal|kcals|calories)\b/,
];

const SEXUAL: RegExp[] = [
  /\b(sext|sexting|nudes?|erotica|erotic)\b/,
  /\b(sex|porn)\s+(story|scene|script|chat)\b/,
  /\bdirty\s+talk\b/,
  /\b(write|describe|roleplay|role-play)\b[^.?!]*\b(sex|sexual|sexy|naked|horny|explicit)\b/,
];

const HARASSMENT: RegExp[] = [
  /\b(harass|humiliate|bully|dox|stalk|threaten|blackmail|intimidate)\s+(him|her|them|my|someone|somebody|people|a|an|this|that|the)\b/,
  /\b(get|take)\s+revenge\b/,
  /\bget\s+back\s+at\b/,
  /\bmake\s+(him|her|them)\s+(suffer|pay|cry)\b/,
  /\bruin\s+(his|her|their)\s+(life|reputation)\b/,
];

/// Lower case, straight apostrophes, single spaces — so "Don’t" and "don't"
/// read the same.
export function normalise(text: string): string {
  return text.toLowerCase().replace(/[‘’ʼ]/g, "'").replace(/\s+/g, " ").trim();
}

/// The first rule a message breaks, or null. Crisis is checked first.
export function screen(message: string): ScreenRule | null {
  const text = normalise(message);
  if (CRISIS.some((p) => p.test(text))) return "crisis";
  if (MEDICAL.some((p) => p.test(text))) return "medical";
  if (DRUGS.some((p) => p.test(text))) return "drugs";
  if (SUPPLEMENT.test(text) && DOSE.test(text)) return "drugs";
  if (DIET.some((p) => p.test(text))) return "diet";
  if (SEXUAL.some((p) => p.test(text))) return "sexual";
  if (HARASSMENT.some((p) => p.test(text))) return "harassment";
  return null;
}

// ---------------------------------------------------------------------------
// The answer, checked
// ---------------------------------------------------------------------------

/// A dose with a unit, in what the model wrote. Forge never gives one.
const DOSE_IN_REPLY = /\b\d+(\.\d+)?\s?(mg|mcg|µg|iu|ml|cc)\b/i;

/// Pictographs (emoji) and the variation selector and joiner that build them.
const EMOJI = /[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu;

/// The voice, enforced where it can be by machine: no exclamation marks, no
/// emoji, no stray whitespace at the ends.
export function inVoice(text: string): string {
  return text
    .replace(EMOJI, "")
    .replace(/([?.])!+/g, "$1")
    .replace(/!+/g, ".")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

export function mentionsLifeline(text: string): boolean {
  return /\b988\b/.test(text);
}

export interface CoachAnswer {
  reply: string;
  proposal: unknown;
}

/// What the model answered, made safe to send to the phone, or null when
/// there is no usable reply.
///
/// * A reply naming a dose, or one the input screen would decline, is
///   replaced by the decline line, and its proposal dropped.
/// * A reply that mentions the 988 line is the crisis answer: its proposal is
///   dropped, because nothing is coached in that turn.
export function checkAnswer(answer: CoachAnswer): CoachAnswer | null {
  if (typeof answer.reply !== "string") return null;
  const reply = inVoice(answer.reply);
  // Punctuation alone is not a reply.
  if (!/[\p{L}\p{N}]/u.test(reply)) return null;

  if (mentionsLifeline(reply)) return { reply, proposal: null };
  if (DOSE_IN_REPLY.test(reply)) return { reply: DECLINE_REPLIES.drugs, proposal: null };

  const rule = screen(reply);
  if (rule === "crisis") return { reply: CRISIS_REPLY, proposal: null };
  if (rule === "drugs" || rule === "sexual") return { reply: replyFor(rule), proposal: null };

  const proposal = answer.proposal && typeof answer.proposal === "object" && !Array.isArray(answer.proposal)
    ? answer.proposal
    : null;
  return { reply, proposal };
}
