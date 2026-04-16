const MIN_PASSWORD_LENGTH = 8;
const SPECIAL_CHAR_REGEX = /(\d|[^\w\s])/;

export function validatePassword(
  password: string,
  errorMessagePrefix?: string
): { status: "ok" } | { status: "error"; errors: string[] } {
  const format = (msg: string) =>
    errorMessagePrefix
      ? `${errorMessagePrefix} ${msg.charAt(0).toLowerCase()}${msg.slice(1)}`
      : msg;

  const errors: string[] = [];

  if (password.length < MIN_PASSWORD_LENGTH) {
    errors.push(format(`At least ${MIN_PASSWORD_LENGTH} characters.`));
  }

  if (!SPECIAL_CHAR_REGEX.test(password)) {
    errors.push(format("At least one number or special character."));
  }

  if (errors.length > 0) {
    return { status: "error", errors };
  }

  return { status: "ok" };
}
