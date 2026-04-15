"use server";

import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { auth } from "@/lib/auth";
import { validatePassword } from "@/lib/validation";
import { APIError } from "better-auth/api";

export type AuthState = {
  errors?: string[];
  email?: string;
} | undefined;

export async function signIn(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = formData.get("email") as string;
  const password = formData.get("password") as string;

  try {
    await auth.api.signInEmail({
      body: { email, password },
      headers: await headers(),
    });
  } catch (e) {
    if (e instanceof APIError) {
      return { errors: [e.message], email };
    }
    return { errors: ["Something went wrong. Please try again."], email };
  }

  redirect("/");
}

export async function signUp(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = formData.get("email") as string;
  const password = formData.get("password") as string;
  const confirmPassword = formData.get("confirm-password") as string;

  const validation = validatePassword(password, "The password must have");
  if (validation.status === "error") {
    return { errors: validation.errors, email };
  }

  if (password !== confirmPassword) {
    return { errors: ["Passwords do not match."], email };
  }

  try {
    await auth.api.signUpEmail({
      body: { email, password, name: email },
      headers: await headers(),
    });
  } catch (e) {
    if (e instanceof APIError) {
      return { errors: [e.message], email };
    }
    return { errors: ["Something went wrong. Please try again."], email };
  }

  redirect("/");
}

export async function signOut(): Promise<void> {
  await auth.api.signOut({ headers: await headers() });
  redirect("/");
}
