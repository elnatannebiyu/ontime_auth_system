import axios from "axios";

// Use relative base to leverage Vite proxy in dev (see vite.config.ts)
const apiBase = "/api";
const TENANT_ID: string = (import.meta as any).env?.VITE_TENANT_ID || "ontime";

const api = axios.create({
  baseURL: apiBase,
  withCredentials: true,
});

const ACCESS_KEY = "admin_fe_access";
let accessToken: string | null = sessionStorage.getItem(ACCESS_KEY);
export const setAccessToken = (t: string | null) => {
  accessToken = t;
  if (t) sessionStorage.setItem(ACCESS_KEY, t);
  else sessionStorage.removeItem(ACCESS_KEY);
};
export const getAccessToken = () => accessToken;

api.interceptors.request.use((config) => {
  config.headers = config.headers || {};
  // Always send tenant header (required by backend middleware)
  (config.headers as any)["X-Tenant-Id"] = TENANT_ID;
  if (accessToken) {
    (config.headers as any)["Authorization"] = `Bearer ${accessToken}`;
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
    
    if (err.response?.status === 401 && !orig._retry && !isAuthEndpoint) {
      orig._retry = true;
      try {
        const t = await refresh();
        orig.headers = orig.headers || {};
        orig.headers["Authorization"] = `Bearer ${t}`;
        // Ensure tenant header remains present on retried request
        orig.headers["X-Tenant-Id"] = TENANT_ID;
        return api(orig);
      } catch {
        // Refresh failed, don't retry
      }
    }
    return Promise.reject(err);
  }
);

export default api;
