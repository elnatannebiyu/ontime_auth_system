import api, { setAccessToken, setLoggedOut } from "./api";

export interface User {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  roles: string[];
  permissions: string[];
}

export const login = async (username: string, password: string) => {
  const { data } = await api.post(
    "/token/",
    { username, password },
    { headers: { "X-Admin-Login": "1" } }
  );
  setAccessToken(data.access);
  setLoggedOut(false);
  return data;
};

export const logout = async () => {
  try {
    await api.post("/logout/");
  } catch (err) {
    // Ignore logout errors - we're logging out anyway
  }
  setAccessToken(null);
  // Notify app to update auth state
  window.dispatchEvent(new Event('admin_fe_logout'));
  setLoggedOut(true);
};

export const getCurrentUser = async (): Promise<User> => {
  const { data } = await api.get("/me/");
  return data;
};

export const refreshToken = async () => {
  const { data } = await api.post("/token/refresh/");
  setAccessToken(data.access);
  return data.access;
};
