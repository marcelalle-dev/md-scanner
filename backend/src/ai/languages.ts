/**
 * Language codes accepted by the API. The values are the names inserted into
 * the system prompt: they come from this closed list, never from the client.
 */

export const OUTPUT_LANGUAGES = {
  fr: "French",
  en: "English",
} as const;
export type OutputLanguage = keyof typeof OUTPUT_LANGUAGES;
export const OUTPUT_LANGUAGE_CODES = Object.keys(OUTPUT_LANGUAGES) as [OutputLanguage, ...OutputLanguage[]];

export const TARGET_LANGUAGES = {
  fr: "French",
  en: "English",
  es: "Spanish",
  de: "German",
  it: "Italian",
  pt: "Portuguese",
  nl: "Dutch",
  pl: "Polish",
  ro: "Romanian",
  sv: "Swedish",
  cs: "Czech",
  hu: "Hungarian",
  el: "Greek",
  tr: "Turkish",
  ru: "Russian",
  uk: "Ukrainian",
  ar: "Arabic",
  sw: "Swahili",
  hi: "Hindi",
  id: "Indonesian",
  vi: "Vietnamese",
  zh: "Simplified Chinese",
  ja: "Japanese",
  ko: "Korean",
} as const;
export type TargetLanguage = keyof typeof TARGET_LANGUAGES;
export const TARGET_LANGUAGE_CODES = Object.keys(TARGET_LANGUAGES) as [TargetLanguage, ...TargetLanguage[]];
