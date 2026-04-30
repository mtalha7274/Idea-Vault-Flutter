import {onCall, HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions/v2";
import OpenAI from "openai";

/** Delays (ms) between retries after a failed OpenRouter request. */
const RETRY_BACKOFF_MS = [1000, 2000, 4000];

/** Per-attempt timeout for the chat completion HTTP request. */
const COMPLETION_TIMEOUT_MS = 30_000;

/** Lazily-built singleton so the same client is reused across warm
 *  invocations. */
let openaiClient: OpenAI | undefined;

const getClient = (): OpenAI => {
  if (!openaiClient) {
    openaiClient = new OpenAI({
      baseURL: "https://openrouter.ai/api/v1",
      apiKey: process.env.OPENROUTER_API_KEY,
      defaultHeaders: {
        "HTTP-Referer": "https://ideavault.app",
        "X-Title": "Idea Vault",
      },
    });
  }
  return openaiClient;
};

/**
 * Runs an async operation with exponential backoff (1s, 2s, 4s) after
 * failures. Up to 3 retries (4 attempts total).
 * @param {Function} fn Operation to run; must return the chat completion.
 * @return {Promise<OpenAI.Chat.Completions.ChatCompletion>} First success.
 */
async function withOpenRouterRetry(
  fn: () => Promise<OpenAI.Chat.ChatCompletion>,
): Promise<OpenAI.Chat.ChatCompletion> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= RETRY_BACKOFF_MS.length; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt === RETRY_BACKOFF_MS.length) {
        break;
      }
      await new Promise((resolve) => {
        setTimeout(resolve, RETRY_BACKOFF_MS[attempt]);
      });
    }
  }
  throw lastError;
}

/**
 * Normalizes chat completion message content to a plain string.
 * OpenRouter text-only chat models return `content` as a string, not a
 * multimodal parts array, so we only handle the string case.
 * @param {unknown} content Raw `message.content` from the completion API.
 * @return {string|undefined} Assistant text, or undefined if not a string.
 */
function extractAssistantText(
  content: unknown,
): string | undefined {
  if (typeof content === "string") {
    return content;
  }
  return undefined;
}

export const organizeSection = onCall(
  {secrets: ["OPENROUTER_API_KEY"]},
  async (request) => {
    const v = request.data?.sectionContent;
    if (typeof v !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Section content cannot be empty.",
      );
    }

    const sectionContent = v.trim();
    if (sectionContent === "") {
      throw new HttpsError(
        "invalid-argument",
        "Section content cannot be empty.",
      );
    }
    if (sectionContent.length > 2000) {
      throw new HttpsError(
        "invalid-argument",
        "Section content exceeds the maximum allowed length of " +
          "2000 characters.",
      );
    }

    try {
      const systemPrompt = [
        "You are an AI writing assistant for Idea Vault, a productivity app.",
        "",
        "Task: Reorganize and refine raw, unstructured markdown notes.",
        "",
        "Guidelines:",
        "- Fix grammar, spelling, and punctuation errors",
        "- Improve sentence clarity and flow",
        "- Group related ideas together logically",
        "- Use proper markdown formatting (headings, lists, emphasis)",
        "- Preserve all original ideas and key information",
        "- Maintain the user's voice, tone, and intent",
        "- Consolidate duplicate points if present",
        "- Break up run-on thoughts into clear, digestible points",
        "- Keep content concise and coherent - avoid over-explaining or " +
          "adding unnecessary elaboration",
        "",
        "Constraints:",
        "- Do NOT add new ideas, facts, or information",
        "- Do NOT remove meaningful content",
        "- Do NOT provide explanations or meta-commentary",
        "",
        "Output: Return ONLY the reorganized markdown content.",
      ].join("\n");

      const completion = await withOpenRouterRetry(async () => {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
          controller.abort();
        }, COMPLETION_TIMEOUT_MS);
        try {
          // OpenRouter-specific field; not in OpenAI TypeScript types.
          // maxRetries: 0 — only withOpenRouterRetry handles backoff.
          return await getClient().chat.completions.create(
            {
              model: "google/gemini-2.5-flash-lite",
              max_tokens: 500,
              temperature: 0.4,
              messages: [
                {
                  role: "system",
                  content: systemPrompt,
                },
                {
                  role: "user",
                  content: sectionContent,
                },
              ],
              thinking_mode: "non-thinking",
            } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming,
            {maxRetries: 0, signal: controller.signal},
          );
        } finally {
          clearTimeout(timeoutId);
        }
      });

      const organizedText = extractAssistantText(
        completion.choices[0]?.message?.content,
      );

      if (!organizedText || organizedText.trim() === "") {
        throw new HttpsError(
          "internal",
          "AI returned an empty response. Please try again.",
        );
      }

      return {organizedContent: organizedText};
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error("organizeSection error:", error);
      throw new HttpsError(
        "internal",
        "Something went wrong. Please try again.",
      );
    }
  },
);
