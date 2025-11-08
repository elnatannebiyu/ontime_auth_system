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

  useEffect(() => {
    try {
      const saved = localStorage.getItem('auth:lastUser');
      if (saved) setUsername(saved);
    } catch {}
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await login(username, password);
      if (remember) {
        try { localStorage.setItem('auth:lastUser', username); } catch {}
      }
      onLogin();
      navigate('/dashboard');
    } catch (err: any) {
      setError(err?.response?.data?.detail || 'Invalid credentials');
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

        <form className="form" onSubmit={handleSubmit} noValidate>
          <div className="field">
            <label htmlFor="email">Email</label>
            <div className="input-wrap">
              <span className="leading-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24"><path d="M4 4h16v16H4z" fill="none" stroke="currentColor"/><path d="M22 6l-10 7L2 6" fill="none" stroke="currentColor"/></svg>
              </span>
              <input id="email" type="email" value={username} onChange={(e) => setUsername(e.target.value)} inputMode="email" autoComplete="email" placeholder="you@company.com" required disabled={loading} />
            </div>
          </div>

          <div className="field">
            <label htmlFor="password">Password</label>
            <div className="input-wrap">
              <span className="leading-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24"><rect x="3" y="11" width="18" height="10" rx="2" fill="none" stroke="currentColor"/><path d="M7 11V8a5 5 0 0 1 10 0v3" fill="none" stroke="currentColor"/></svg>
              </span>
              <input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" placeholder="••••••••" required disabled={loading} />
            </div>
          </div>

          <div className="row between">
            <label className="checkbox">
              <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
              <span>Remember me</span>
            </label>
            <a href="#" className="link" onClick={(e) => { e.preventDefault(); /* TODO: route to forgot */ }}>Forgot password?</a>
          </div>

          <button className="btn primary w-full" disabled={loading} aria-busy={loading}>
            <span>{loading ? 'Signing in…' : 'Sign in'}</span>
          </button>
        </form>
      </div>
    </div>
  );
};

export default Login;

