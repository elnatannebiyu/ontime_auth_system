import { useEffect, useMemo, useState } from 'react';
import { Box, Card, CardContent, Typography, TextField, Button, Stack, Divider, Alert } from '@mui/material';
import { changePassword, getCurrentUser, User } from '../services/auth';

export default function MyProfile() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const me = await getCurrentUser();
        if (active) setUser(me);
      } catch (e: any) {
        if (active) setError(e?.response?.data?.detail || 'Failed to load profile');
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => { active = false; };
  }, []);

  const canSubmit = useMemo(() => !!current && !!next && next.length >= 8, [current, next]);

  const onChangePassword = async () => {
    setSaving(true);
    setError(null);
    try {
      await changePassword(current, next);
      // changePassword will log out and redirect via LogoutWatcher
    } catch (e: any) {
      setError(e?.response?.data?.detail || 'Unable to change password');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box sx={{ display: 'grid', gap: 3 }}>
      <Typography variant="h5">My Profile</Typography>
      {error && <Alert severity="error">{error}</Alert>}
      <Card>
        <CardContent>
          <Typography variant="h6" gutterBottom>Account</Typography>
          {loading ? (
            <Typography>Loading…</Typography>
          ) : (
            <Stack spacing={1}>
              <Typography><b>Username:</b> {user?.username}</Typography>
              <Typography><b>Email:</b> {user?.email}</Typography>
              <Typography><b>Name:</b> {user?.first_name} {user?.last_name}</Typography>
              <Typography><b>Roles:</b> {user?.roles?.join(', ') || '—'}</Typography>
            </Stack>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent>
          <Typography variant="h6" gutterBottom>Change Password</Typography>
          <Stack spacing={2} sx={{ maxWidth: 420 }}>
            <TextField
              label="Current Password"
              type="password"
              value={current}
              onChange={(e) => setCurrent(e.target.value)}
              fullWidth
            />
            <TextField
              label="New Password"
              type="password"
              value={next}
              onChange={(e) => setNext(e.target.value)}
              helperText="Minimum 8 characters and must meet strength rules"
              fullWidth
            />
            <Divider />
            <Button variant="contained" onClick={onChangePassword} disabled={!canSubmit || saving}>
              {saving ? 'Saving…' : 'Change Password'}
            </Button>
            <Typography variant="body2" color="text.secondary">
              You will be signed out from all devices after changing your password.
            </Typography>
          </Stack>
        </CardContent>
      </Card>
    </Box>
  );
}
