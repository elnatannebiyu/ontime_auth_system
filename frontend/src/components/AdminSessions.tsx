import React, { useEffect, useState } from 'react';
import { Box, Button, Card, CardContent, Stack, TextField, InputAdornment, Table, TableHead, TableRow, TableCell, TableSortLabel, TableBody, TablePagination, Typography, Chip } from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import api from '../services/api';
import { useSearchParams, Link as RouterLink } from 'react-router-dom';

interface AdminSessionRow {
  id: string;
  user_email: string;
  device_type: string;
  os_name: string;
  os_version: string;
  ip_address: string;
  is_active: boolean;
  created_at: string;
  last_activity: string;
  expires_at: string;
}

const AdminSessions: React.FC = () => {
  const [rows, setRows] = useState<AdminSessionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(10);
  const [total, setTotal] = useState(0);
  const [ordering, setOrdering] = useState<string>('-last_activity');
  const [urlParams, setUrlParams] = useSearchParams();

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api.get('/sessions/admin/list/', {
        params: { search: debouncedSearch, page: page + 1, page_size: pageSize, ordering },
      });
      const list: AdminSessionRow[] = res.data?.results || [];
      setTotal(res.data?.count ?? list.length);
      setRows(list);
    } catch (e: any) {
      setError(e?.response?.data?.detail || e?.message || 'Failed to load sessions');
    } finally {
      setLoading(false);
    }
  };

  // Debounce search
  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  // URL -> state on mount
  useEffect(() => {
    const s = urlParams.get('search');
    const p = urlParams.get('page');
    const ps = urlParams.get('page_size');
    const ord = urlParams.get('ordering');
    if (s !== null) setSearch(s);
    if (p) { const pn = parseInt(p, 10); if (!isNaN(pn)) setPage(Math.max(0, pn - 1)); }
    if (ps) { const pn = parseInt(ps, 10); if (!isNaN(pn)) setPageSize(Math.min(100, Math.max(1, pn))); }
    if (ord) setOrdering(ord);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // state -> URL
  useEffect(() => {
    const p = new URLSearchParams(urlParams);
    if (search) p.set('search', search); else p.delete('search');
    p.set('page', String(page + 1));
    p.set('page_size', String(pageSize));
    if (ordering) p.set('ordering', ordering); else p.delete('ordering');
    setUrlParams(p, { replace: true });
  }, [search, page, pageSize, ordering]);

  useEffect(() => { load(); }, [debouncedSearch, page, pageSize, ordering]);

  const fmt = (iso?: string) => {
    if (!iso) return '—';
    try { return new Date(iso).toLocaleString(); } catch { return iso; }
  };

  return (
    <Box>
      <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
        <Typography variant="h5">Sessions</Typography>
        <Stack direction="row" spacing={2} alignItems="center">
          <TextField size="small" placeholder="Search sessions" value={search} onChange={e => { setPage(0); setSearch(e.target.value); }} InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon fontSize="small" /></InputAdornment> }} />
          <Button component={RouterLink} to="/users" variant="outlined">View Users</Button>
        </Stack>
      </Stack>
      <Card>
        <CardContent>
          {error && <Box sx={{ mb: 2, color: 'error.main' }}>{error}</Box>}
          {loading ? (
            <Typography>Loading…</Typography>
          ) : (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell sortDirection={ordering.includes('user__email') ? (ordering.startsWith('-user__email') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('user__email')} direction={ordering.startsWith('-user__email') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-user__email') ? 'user__email' : '-user__email')}>User</TableSortLabel>
                  </TableCell>
                  <TableCell>Device type</TableCell>
                  <TableCell>Os name</TableCell>
                  <TableCell>Os version</TableCell>
                  <TableCell>Ip address</TableCell>
                  <TableCell sortDirection={ordering.includes('is_active') ? (ordering.startsWith('-is_active') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('is_active')} direction={ordering.startsWith('-is_active') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-is_active') ? 'is_active' : '-is_active')}>Is active</TableSortLabel>
                  </TableCell>
                  <TableCell sortDirection={ordering.includes('created_at') ? (ordering.startsWith('-created_at') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('created_at')} direction={ordering.startsWith('-created_at') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-created_at') ? 'created_at' : '-created_at')}>Created at</TableSortLabel>
                  </TableCell>
                  <TableCell sortDirection={ordering.includes('last_activity') ? (ordering.startsWith('-last_activity') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('last_activity')} direction={ordering.startsWith('-last_activity') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-last_activity') ? 'last_activity' : '-last_activity')}>Last activity</TableSortLabel>
                  </TableCell>
                  <TableCell sortDirection={ordering.includes('expires_at') ? (ordering.startsWith('-expires_at') ? 'desc' : 'asc') : false as any}>
                    <TableSortLabel active={ordering.includes('expires_at')} direction={ordering.startsWith('-expires_at') ? 'desc' : 'asc'} onClick={() => setOrdering(prev => prev.startsWith('-expires_at') ? 'expires_at' : '-expires_at')}>Expires at</TableSortLabel>
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {rows.map(r => (
                  <TableRow key={r.id} hover>
                    <TableCell>{r.user_email || '—'}</TableCell>
                    <TableCell>{r.device_type || '—'}</TableCell>
                    <TableCell>{r.os_name || '—'}</TableCell>
                    <TableCell>{r.os_version || '—'}</TableCell>
                    <TableCell>{r.ip_address || '—'}</TableCell>
                    <TableCell>{r.is_active ? <Chip label="Active" color="success" size="small" /> : <Chip label="Revoked" size="small" />}</TableCell>
                    <TableCell>{fmt(r.created_at)}</TableCell>
                    <TableCell>{fmt(r.last_activity)}</TableCell>
                    <TableCell>{fmt(r.expires_at)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
          <TablePagination component="div" count={total} page={page} onPageChange={(_, p) => setPage(p)} rowsPerPage={pageSize} onRowsPerPageChange={e => { setPage(0); setPageSize(parseInt(e.target.value, 10)); }} rowsPerPageOptions={[5,10,20,50,100]} />
        </CardContent>
      </Card>
    </Box>
  );
};

export default AdminSessions;
