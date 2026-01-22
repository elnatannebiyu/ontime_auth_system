import axios from "axios";

// Use relative base to leverage Vite proxy in dev (see vite.config.ts)
const apiBase = "/api";
const TENANT_ID: string = (import.meta as any).env?.VITE_TENANT_ID || "ontime";

const api = axios.create({
  baseURL: apiBase,
  withCredentials: true,
});

let accessToken: string | null = null; // Keep access token in memory only
let loggedOut = false;
export const setLoggedOut = (v: boolean) => { loggedOut = v; };
export const isLoggedOut = () => loggedOut;
export const setAccessToken = (t: string | null) => {
  accessToken = t;
};
export const getAccessToken = () => accessToken;

// Stable per-device identifier (safe to persist)
const DEVICE_KEY = "ontime_device_id";
const getDeviceId = (): string => {
  try {
    let d = localStorage.getItem(DEVICE_KEY);
    if (!d) {
      const id = (typeof crypto !== 'undefined' && (crypto as any).randomUUID)
        ? (crypto as any).randomUUID()
        : Math.random().toString(36).slice(2) + Date.now().toString(36);
      d = `WEB-${id}`;
      localStorage.setItem(DEVICE_KEY, d);
    }
    return d;
  } catch {
    return `WEB-${(navigator?.userAgent || 'UA')}`;
  }
};

// AUDIT FIX #5: CSRF Token Helper
const getCsrfToken = (): string | null => {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; csrftoken=`);
  if (parts.length === 2) {
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
};

api.interceptors.request.use((config) => {
  config.headers = config.headers || {};
  // Always send tenant header (required by backend middleware)
  (config.headers as any)["X-Tenant-Id"] = TENANT_ID;
  // Send stable device identifier
  (config.headers as any)["X-Device-Id"] = getDeviceId();
  if (accessToken) {
    (config.headers as any)["Authorization"] = `Bearer ${accessToken}`;
  }
  
  // AUDIT FIX #5: Include CSRF token for state-changing requests
  const method = config.method?.toUpperCase();
  if (method && ['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
    const csrfToken = getCsrfToken();
    if (csrfToken) {
      (config.headers as any)["X-CSRFToken"] = csrfToken;
    }
  }
  
  return config;
});

let refreshPromise: Promise<string> | null = null;
const refresh = async () => {
  if (!refreshPromise) {
    refreshPromise = api.post("/token/refresh/")
      .then(res => {
        const t = res.data.access as string;
        setAccessToken(t);
        return t;
      })
      .catch((e) => {
        // Mark logged out on refresh failure so guards won't keep retrying
        try {
          setAccessToken(null);
          setLoggedOut(true);
          window.dispatchEvent(new Event('admin_fe_logout'));
        } catch {}
        throw e;
      })
      .finally(() => { refreshPromise = null; });
  }
  return refreshPromise;
};

api.interceptors.response.use(
  (r) => r,
  async (err) => {
    const orig = err.config;
    // Don't retry refresh for logout or refresh endpoints
    const isAuthEndpoint = orig.url?.includes('/logout') || orig.url?.includes('/token/refresh/');
    
    const respDetail: string | undefined = err.response?.data?.detail;
    const refreshMissing = respDetail && String(respDetail).toLowerCase().includes('refresh token not found');
    const shouldAttemptRefresh = (
      err.response?.status === 401 &&
      !orig._retry &&
      !isAuthEndpoint &&
      !loggedOut &&
      !refreshMissing
    );
    

    if (shouldAttemptRefresh) {
      orig._retry = true;
      try {
        const t = await refresh();
        orig.headers = orig.headers || {};
        orig.headers["Authorization"] = `Bearer ${t}`;
        // Ensure tenant header remains present on retried request
        orig.headers["X-Tenant-Id"] = TENANT_ID;
        return api(orig);
      } catch {
        // Refresh failed, don't retry further. Already marked loggedOut in refresh().
      }
    }
    return Promise.reject(err);
  }
);

// Attempt silent bootstrap via refresh cookie to align FE-BE flow on cold loads
export const bootstrapAuth = async (): Promise<boolean> => {
  try {
    const res = await api.post("/token/refresh/", {});
    const t = res.data?.access as string | undefined;
    if (t) {
      setAccessToken(t);
      setLoggedOut(false);
      return true;
    }
  } catch {}
  return false;
};

export default api;
