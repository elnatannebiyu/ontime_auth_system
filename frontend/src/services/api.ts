import axios from "axios";

const api = axios.create({
  baseURL: "http://localhost:8000/api",
  withCredentials: true,
});

let accessToken: string | null = null;
export const setAccessToken = (t: string | null) => { accessToken = t; };
export const getAccessToken = () => accessToken;

api.interceptors.request.use((config) => {
  if (accessToken) {
    config.headers = config.headers || {};
    config.headers["Authorization"] = `Bearer ${accessToken}`;
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
        orig.headers["Authorization"] = `Bearer ${t}`;
        return api(orig);
      } catch {
        // Refresh failed, don't retry
      }
    }
    return Promise.reject(err);
  }
);

export default api;
