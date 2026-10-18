import { useEffect, useState } from 'react';

type Entry = { etag: string; data: unknown };
const STORAGE_KEY = 'srez-api-cache';
const build = import.meta.url;
const cache = new Map<string, Entry>();
try {
  const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
  if (saved?.build === build && Array.isArray(saved.entries)) {
    for (const [url, entry] of saved.entries.slice(-40)) {
      if (typeof url === 'string' && typeof entry?.etag === 'string' && entry.data) cache.set(url, entry);
    }
  }
} catch {}

export function cachedJSON<T>(url: string): T | null {
  return (cache.get(url)?.data as T) ?? null;
}

function remember(url: string, entry: Entry) {
  cache.delete(url);
  cache.set(url, entry);
  while (cache.size > 40) cache.delete(cache.keys().next().value!);
  while (cache.size) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ build, entries: [...cache] }));
      break;
    } catch {
      if (cache.size === 1) break;
      cache.delete(cache.keys().next().value!);
    }
  }
}

export function useJSON<T>(url: string | null, revision = 0) {
  const [result, setResult] = useState<{ url: string | null; data: T | null }>({ url, data: url ? cachedJSON<T>(url) : null });
  const [error, setError] = useState('');
  const [pending, setPending] = useState(false);
  const data = result.url === url ? result.data : url ? cachedJSON<T>(url) : null;
  useEffect(() => {
    if (!url) return;
    const controller = new AbortController();
    const saved = cache.get(url);
    setResult({ url, data: (saved?.data as T) ?? null });
    setPending(true); setError('');
    fetch(url, {
      signal: controller.signal,
      cache: 'no-store',
      headers: saved ? { 'If-None-Match': saved.etag } : {},
    }).then(async response => {
      if (response.status === 304 && saved) return saved.data as T;
      const value = await response.json();
      if (!response.ok) throw new Error(typeof value.detail === 'string' ? value.detail : 'Не удалось получить данные.');
      const etag = response.headers.get('ETag');
      if (!controller.signal.aborted && etag) remember(url, { etag, data: value });
      return value as T;
    }).then(value => { if (!controller.signal.aborted) setResult({ url, data: value }); }).catch(e => {
      if (!controller.signal.aborted) setError(e instanceof Error ? e.message : 'Ошибка соединения.');
    }).finally(() => { if (!controller.signal.aborted) setPending(false); });
    return () => controller.abort();
  }, [url, revision]);
  return { data, error, loading: pending && !data };
}
