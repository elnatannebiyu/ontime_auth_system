import React, { useEffect, useMemo, useState } from 'react';
import { Box, Button, Card, CardContent, Dialog, DialogActions, DialogContent, DialogTitle, IconButton, Stack, Switch, Table, TableBody, TableCell, TableHead, TableRow, TextField, Typography, TablePagination, InputAdornment, TableSortLabel, Snackbar, Alert, Tooltip, Chip } from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import api from '../services/api';
import { useSearchParams, Link as RouterLink } from 'react-router-dom';

interface AdminUser {
  id: number;
  username: string;
  email: string;
  first_name?: string;
  last_name?: string;
  is_active: boolean;
  is_superuser: boolean;
  last_login?: string | null;
  date_joined?: string;
  groups?: string[];
  tenant_roles?: string[];
}

const AdminUsers: React.FC = () => {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(10);
  const [total, setTotal] = useState(0);
  const [selfId, setSelfId] = useState<number | null>(null);
  const [ordering, setOrdering] = useState<string>('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [snack, setSnack] = useState<{open: boolean; msg: string; severity: 'success'|'error'|'info'|'warning'}>({ open: false, msg: '', severity: 'success' });
  const [urlParams, setUrlParams] = useSearchParams();

  const [openEdit, setOpenEdit] = useState(false);
  const [editing, setEditing] = useState<AdminUser | null>(null);
  const [form, setForm] = useState({ email: '', first_name: '', last_name: '' });
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const resMe = await api.get('/me/');
      setSelfId(resMe?.data?.id ?? null);
      const res = await api.get('/admin/users/', { params: { search: debouncedSearch, page: page + 1, page_size: pageSize, ordering } });
      const list: AdminUser[] = res.data?.results || [];
      setTotal(res.data?.count ?? list.length);
      setUsers(list);
    } catch (e: any) {
      setError(e?.response?.data?.detail || e?.message || 'Failed to load users');
    } finally {
      setLoading(false);
    }
  };

  // Debounce search input
  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  // Sync URL params -> state on first mount
  useEffect(() => {
    const s = urlParams.get('search');
    const p = urlParams.get('page');
    const ps = urlParams.get('page_size');
    const ord = urlParams.get('ordering');
    if (s !== null) setSearch(s);
    if (p) {
      const pn = parseInt(p, 10); if (!isNaN(pn)) setPage(Math.max(0, pn - 1));
    }
    if (ps) {
      const pn = parseInt(ps, 10); if (!isNaN(pn)) setPageSize(Math.min(100, Math.max(1, pn)));
    }
    if (ord) setOrdering(ord);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // State -> URL params
  useEffect(() => {
    const newParams = new URLSearchParams(urlParams);
    if (search) newParams.set('search', search); else newParams.delete('search');
    newParams.set('page', String(page + 1));
    newParams.set('page_size', String(pageSize));
    if (ordering) newParams.set('ordering', ordering); else newParams.delete('ordering');
    setUrlParams(newParams, { replace: true });
  }, [search, page, pageSize, ordering]);

  useEffect(() => { load(); }, [debouncedSearch, page, pageSize, ordering]);

  const startEdit = (u: AdminUser) => {
    setEditing(u);
    setForm({ email: u.email || '', first_name: u.first_name || '', last_name: u.last_name || '' });
    setOpenEdit(true);
  };

  const save = async () => {
    setSaving(true);
    try {
      if (!editing) {
        throw new Error('Editing context missing');
      }
      const payload: any = { email: form.email, first_name: form.first_name, last_name: form.last_name };
      const res = await api.patch(`/admin/users/${editing.id}/`, payload);
      setUsers(prev => prev.map(u => u.id === editing.id ? res.data : u));
      setSnack({ open: true, msg: 'User updated', severity: 'success' });
      setOpenEdit(false);
    } catch (e: any) {
      const detail = e?.response?.data?.detail || e?.message || 'Save failed';
      setError(detail);
      setSnack({ open: true, msg: detail, severity: 'error' });
    } finally {
      setSaving(false);
    }
  };

  const toggleActive = async (u: AdminUser) => {
    try {
      const res = await api.patch(`/admin/users/${u.id}/`, { is_active: !u.is_active });
      setUsers(prev => prev.map(x => x.id === u.id ? res.data : x));
      setSnack({ open: true, msg: `User ${!u.is_active ? 'activated' : 'deactivated'}`, severity: 'success' });
    } catch (e: any) {
      setError(e?.response?.data?.detail || e?.message || 'Update failed');
      setSnack({ open: true, msg: e?.response?.data?.detail || e?.message || 'Update failed', severity: 'error' });
    }
  };

  const remove = async (u: AdminUser) => {
    if (!confirm(`Delete ${u.email}? This cannot be undone.`)) return;
    try {
      await api.delete(`/admin/users/${u.id}/`);
      setUsers(prev => prev.filter(x => x.id !== u.id));
      setTotal(prev => Math.max(0, prev - 1));
      setSnack({ open: true, msg: 'User deleted', severity: 'success' });
    } catch (e: any) {
      setError(e?.response?.data?.detail || e?.message || 'Delete failed');
      setSnack({ open: true, msg: e?.response?.data?.detail || e?.message || 'Delete failed', severity: 'error' });
    }
  };

  const rows = useMemo(() => users, [users]);

  const addRole = async (u: AdminUser, role: 'Viewer'|'AdminFrontend') => {
    try {
      const res = await api.post(`/admin/users/${u.id}/roles/`, { role });
      setUsers(prev => prev.map(x => x.id === u.id ? res.data : x));
      setSnack({ open: true, msg: `Role ${role} added`, severity: 'success' });
    } catch (e: any) {
      setSnack({ open: true, msg: e?.response?.data?.detail || e?.message || 'Add role failed', severity: 'error' });
    }
  };
  const removeRole = async (u: AdminUser, role: 'Viewer'|'AdminFrontend') => {
    try {
      const res = await api.delete(`/admin/users/${u.id}/roles/${role}/`);
      setUsers(prev => prev.map(x => x.id === u.id ? res.data : x));
      setSnack({ open: true, msg: `Role ${role} removed`, severity: 'success' });
    } catch (e: any) {
      setSnack({ open: true, msg: e?.response?.data?.detail || e?.message || 'Remove role failed', severity: 'error' });
    }
  };

  return (
    <Box>
      <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
        <Typography variant="h5">Users</Typography>
        <Stack direction="row" spacing={2} alignItems="center">
          <TextField size="small" placeholder="Search users" value={search} onChange={e => { setPage(0); setSearch(e.target.value); }} InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon fontSize="small" /></InputAdornment> }} />
          <Button component={RouterLink} to="/users/sessions" variant="outlined">View Sessions</Button>
        </Stack>
      </Stack>
      <Card>
        <CardContent>
          {error && (
            <Box sx={{ mb: 2, color: 'error.main' }}>{error}</Box>
          )}
          {loading ? (
            <Typography>Loading…</Typography>
          ) : (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell sortDirection={ordering.includes('email') ? (ordering.startsWith('-email') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('email')} direction={ordering.startsWith('-email') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-email') ? 'email' : '-email')}>Email</TableSortLabel>
                  </TableCell>
                  <TableCell>Name</TableCell>
                  <TableCell sortDirection={ordering.includes('is_active') ? (ordering.startsWith('-is_active') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('is_active')} direction={ordering.startsWith('-is_active') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-is_active') ? 'is_active' : '-is_active')}>Active</TableSortLabel>
                  </TableCell>
                  <TableCell sortDirection={ordering.includes('last_login') ? (ordering.startsWith('-last_login') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('last_login')} direction={ordering.startsWith('-last_login') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-last_login') ? 'last_login' : '-last_login')}>Last login</TableSortLabel>
                  </TableCell>
                  <TableCell align="right">Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {rows.map(u => (
                  <TableRow key={u.id} hover>
                    <TableCell>{u.email}</TableCell>
                    <TableCell>{[u.first_name, u.last_name].filter(Boolean).join(' ')}</TableCell>
                    <TableCell>
                      <Stack direction="row" spacing={0.5} flexWrap="wrap">
                        {(u.tenant_roles || []).map(r => <Chip key={r} label={r} size="small" />)}
                      </Stack>
                      <Stack direction="row" spacing={1} sx={{ mt: 0.5 }}>
                        <Button size="small" variant="text" disabled={selfId === u.id || (u.tenant_roles||[]).includes('Viewer')} onClick={() => addRole(u, 'Viewer')}>Add Viewer</Button>
                        <Button size="small" variant="text" disabled={selfId === u.id || (u.tenant_roles||[]).includes('AdminFrontend')} onClick={() => addRole(u, 'AdminFrontend')}>Add Admin</Button>
                        <Button size="small" variant="text" color="warning" disabled={selfId === u.id || !(u.tenant_roles||[]).includes('AdminFrontend')} onClick={() => removeRole(u, 'AdminFrontend')}>Remove Admin</Button>
                      </Stack>
                    </TableCell>
                    <TableCell>
                      <Switch checked={!!u.is_active} onChange={() => toggleActive(u)} disabled={selfId === u.id} />
                    </TableCell>
                    <TableCell>{u.last_login ? new Date(u.last_login).toLocaleString() : '—'}</TableCell>
                    <TableCell align="right">
                      <Tooltip title={selfId === u.id ? 'You cannot edit your own account here' : 'Edit user'}>
                        <span><IconButton size="small" onClick={() => startEdit(u)} aria-label="edit" disabled={selfId === u.id}><EditIcon fontSize="small" /></IconButton></span>
                      </Tooltip>
                      <Tooltip title={selfId === u.id ? 'You cannot delete your own account' : 'Delete user'}>
                        <span><IconButton size="small" onClick={() => remove(u)} aria-label="delete" color="error" disabled={selfId === u.id}><DeleteIcon fontSize="small" /></IconButton></span>
                      </Tooltip>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
          <TablePagination component="div" count={total} page={page} onPageChange={(_, p) => setPage(p)} rowsPerPage={pageSize} onRowsPerPageChange={e => { setPage(0); setPageSize(parseInt(e.target.value, 10)); }} rowsPerPageOptions={[5,10,20,50,100]} />
        </CardContent>
      </Card>

      <Snackbar open={snack.open} autoHideDuration={2500} onClose={() => setSnack(s => ({ ...s, open: false }))} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert onClose={() => setSnack(s => ({ ...s, open: false }))} severity={snack.severity} variant="filled" sx={{ width: '100%' }}>
          {snack.msg}
        </Alert>
      </Snackbar>

      <Dialog open={openEdit} onClose={() => setOpenEdit(false)} fullWidth maxWidth="sm">
        <DialogTitle>Edit user</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField label="Email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} fullWidth />
            <Stack direction="row" spacing={2}>
              <TextField label="First name" value={form.first_name} onChange={e => setForm({ ...form, first_name: e.target.value })} fullWidth />
              <TextField label="Last name" value={form.last_name} onChange={e => setForm({ ...form, last_name: e.target.value })} fullWidth />
            </Stack>
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenEdit(false)}>Cancel</Button>
          <Button variant="contained" onClick={save} disabled={saving}>Save</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default AdminUsers;
