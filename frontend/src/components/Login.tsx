import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useThemeMode } from '../theme';
import { login } from '../services/auth';
import '../style.css';

interface LoginProps { onLogin: () => void }

const Login: React.FC<LoginProps> = ({ onLogin }) => {
  const navigate = useNavigate();
  const { mode, toggle } = useThemeMode();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [failedCount, setFailedCount] = useState(0);
  const [lockUntil, setLockUntil] = useState<number | null>(null);
  const [now, setNow] = useState(Date.now());
  const [showPassword, setShowPassword] = useState(false);

  const LOCK_KEY = 'auth:loginLockUntil';
  const FAIL_KEY = 'auth:loginFailCount';
  const MAX_ATTEMPTS = 5;
  const LOCK_DURATION_MS = 5 * 60 * 1000;

  useEffect(() => {
    try {
      const saved = localStorage.getItem('auth:lastUser');
      if (saved) setUsername(saved);
      const rawLock = localStorage.getItem(LOCK_KEY);
      const rawFail = localStorage.getItem(FAIL_KEY);
      if (rawFail) setFailedCount(Number(rawFail) || 0);
      if (rawLock) {
        const ts = Number(rawLock) || 0;
        if (ts > Date.now()) setLockUntil(ts);
        else localStorage.removeItem(LOCK_KEY);
      }
    } catch {}
  }, []);

  useEffect(() => {
    if (!lockUntil) return;
    const id = window.setInterval(() => {
      setNow(Date.now());
      if (lockUntil <= Date.now()) {
        setLockUntil(null);
        setFailedCount(0);
        try {
          localStorage.removeItem(LOCK_KEY);
          localStorage.removeItem(FAIL_KEY);
        } catch {}
      }
    }, 1000);
    return () => window.clearInterval(id);
  }, [lockUntil]);

  const remainingLockSeconds = lockUntil ? Math.max(0, Math.ceil((lockUntil - now) / 1000)) : 0;
  const isLocked = !!lockUntil && remainingLockSeconds > 0;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isLocked) return;
    setError('');
    setLoading(true);
    try {
      await login(username, password);
      if (remember) {
        try { localStorage.setItem('auth:lastUser', username); } catch {}
      }
      try {
        localStorage.removeItem(LOCK_KEY);
        localStorage.removeItem(FAIL_KEY);
      } catch {}
      setFailedCount(0);
      setLockUntil(null);
      onLogin();
      navigate('/dashboard');
    } catch (err: any) {
      let message = err?.response?.data?.detail || 'Invalid credentials';
      const status = err?.response?.status;

      if (status === 429) {
        message = typeof message === 'string' ? message : 'Too many attempts, please try again later.';
      } else {
        const nextFailed = failedCount + 1;
        setFailedCount(nextFailed);
        try { localStorage.setItem(FAIL_KEY, String(nextFailed)); } catch {}
        if (nextFailed >= MAX_ATTEMPTS) {
          const until = Date.now() + LOCK_DURATION_MS;
          setLockUntil(until);
          try { localStorage.setItem(LOCK_KEY, String(until)); } catch {}
          message = `Too many failed attempts. Please wait a few minutes before trying again.`;
        } else {
          const remaining = MAX_ATTEMPTS - nextFailed;
          if (remaining <= 2) {
            message = `${message} (${remaining} attempt${remaining === 1 ? '' : 's'} remaining before temporary lockout.)`;
          }
        }
      }

      setError(message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-shell">
      <button
        className="mode-toggle top-right"
        onClick={toggle}
        aria-pressed={mode === 'dark'}
        title={mode === 'dark' ? 'Switch to light' : 'Switch to dark'}
      >
        {mode !== 'dark' ? (
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" fill="currentColor" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
            <circle cx="12" cy="12" r="5" fill="currentColor"></circle>
            <g stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M12 1v3"></path>
              <path d="M12 20v3"></path>
              <path d="M4.22 4.22l2.12 2.12"></path>
              <path d="M17.66 17.66l2.12 2.12"></path>
              <path d="M1 12h3"></path>
              <path d="M20 12h3"></path>
              <path d="M4.22 19.78l2.12-2.12"></path>
              <path d="M17.66 6.34l2.12-2.12"></path>
            </g>
          </svg>
        )}
      </button>

      <div className="card" role="dialog" aria-labelledby="loginTitle" aria-describedby="loginSubtitle">
        <div className="card-header">
          <div className="logo small" aria-hidden="true">O</div>
          <div>
            <h1 id="loginTitle" className="card-title">Sign in</h1>
            <p id="loginSubtitle" className="card-sub">Ontime Ethiopia Admin</p>
          </div>
        </div>

        {error && (
          <div className="banner error" role="alert">
            <span className="banner-text">{error}</span>
            <button className="banner-close" onClick={() => setError('')} aria-label="Dismiss alert">×</button>
          </div>
        )}

        {isLocked && (
          <div className="banner warning" role="status">
            <span className="banner-text">Login temporarily locked due to multiple failed attempts. Try again in {remainingLockSeconds} seconds.</span>
          </div>
        )}

        <form className="form" onSubmit={handleSubmit} noValidate>
          <div className="field">
            <label htmlFor="username">Username</label>
            <div className="input-wrap">
              <span className="leading-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24"><path d="M4 4h16v16H4z" fill="none" stroke="currentColor"/><path d="M22 6l-10 7L2 6" fill="none" stroke="currentColor"/></svg>
              </span>
              <input
                id="username"
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                autoComplete="username"
                placeholder="adminweb"
                required
                disabled={loading || isLocked}
              />
            </div>
          </div>

          <div className="field">
            <label htmlFor="password">Password</label>
            <div className="input-wrap">
              <span className="leading-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24"><rect x="3" y="11" width="18" height="10" rx="2" fill="none" stroke="currentColor"/><path d="M7 11V8a5 5 0 0 1 10 0v3" fill="none" stroke="currentColor"/></svg>
              </span>
              <input
                id="password"
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                placeholder="••••••••"
                required
                disabled={loading || isLocked}
              />
              <button
                type="button"
                className="password-toggle"
                onClick={() => setShowPassword((v) => !v)}
                aria-label={showPassword ? 'Hide password' : 'Show password'}
              >
                {showPassword ? (
                  <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
                    <path d="M3 3l18 18" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                    <path d="M4.5 4.5C3 5.7 2 7.2 1.5 8c1.7 3 5 6 10.5 6 1.6 0 3-.3 4.3-.8" fill="none" stroke="currentColor" strokeWidth="1.5" />
                  </svg>
                ) : (
                  <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
                    <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" fill="none" stroke="currentColor" strokeWidth="1.5" />
                    <circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" strokeWidth="1.5" />
                  </svg>
                )}
              </button>
            </div>
          </div>

          <div className="row between">
            <label className="checkbox">
              <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
              <span>Remember me</span>
            </label>
          </div>

          <button className="btn primary w-full" disabled={loading || isLocked} aria-busy={loading}>
            <span>{loading ? 'Signing in…' : 'Sign in'}</span>
          </button>
        </form>
      </div>
    </div>
  );
};

export default Login;

