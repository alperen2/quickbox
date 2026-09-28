/** Stable task ids persisted as an `id:` token. Mirrors `TaskIdentifier.swift`. */

export const TASK_ID_KEY = "id";
export const TASK_ID_LENGTH = 8;

const ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789";
const VALID_PATTERN = /^[A-Za-z0-9_-]+$/;

export function generateTaskId(random: (size: number) => Uint8Array = randomBytes): string {
  // Rejection sampling keeps every character equally likely (256 is not a multiple of 36).
  const limit = 256 - (256 % ALPHABET.length);
  let id = "";
  while (id.length < TASK_ID_LENGTH) {
    for (const byte of random(TASK_ID_LENGTH)) {
      if (byte < limit && id.length < TASK_ID_LENGTH) id += ALPHABET[byte % ALPHABET.length];
    }
  }
  return id;
}

export function isValidTaskId(value: string): boolean {
  return VALID_PATTERN.test(value);
}

function randomBytes(size: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(size));
}
