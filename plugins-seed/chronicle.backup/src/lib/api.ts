/**
 * Authenticated fetch against the Chronicle server.
 *
 * Plugins run inside the app, so they reach the same API the app does. The
 * bearer token (present only in token/OIDC auth modes) lives in localStorage
 * exactly as the app stores it.
 */
export async function authFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  try {
    const token = localStorage.getItem('chronicle_token');
    if (token) headers.set('Authorization', `Bearer ${token}`);
  } catch {
    /* private mode: no token, same-origin cookie/none-mode still works */
  }
  return fetch(input, { ...init, headers });
}
