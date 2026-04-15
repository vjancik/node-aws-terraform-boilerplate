"use client"

import { useEffect, useState } from "react"

export function useDebouncedState<T>(
  initial: T,
  debounceMs: number
): [T, T, React.Dispatch<React.SetStateAction<T>>] {
  const [value, setValue] = useState<T>(initial)
  const [debounced, setDebounced] = useState<T>(initial)

  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), debounceMs)
    return () => clearTimeout(t)
  }, [value, debounceMs])

  return [value, debounced, setValue]
}
