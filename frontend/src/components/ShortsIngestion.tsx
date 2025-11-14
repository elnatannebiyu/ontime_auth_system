import React, { useEffect, useState } from 'react';
import { Button, Card, CardContent, Stack, TextField, Typography, IconButton, Tooltip, List, ListItem, ListItemText } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import api from '../services/api';

interface ShortJob {
  id: string;
  status: string;
  error_message?: string;
  hls_master_url?: string;
  updated_at?: string;
  created_at?: string;
}

const ShortsIngestion: React.FC = () => {
  const [submitting, setSubmitting] = useState(false);
  const [ready, setReady] = useState<ShortJob[]>([]);
  const [batchLimit, setBatchLimit] = useState<number | ''>(50);

  const loadReady = async () => {
    try {
      const { data } = await api.get('/channels/shorts/ready/', { params: { limit: 50 } });
      console.log('Shorts READY response', data);
      setReady(Array.isArray(data) ? data : []);
    } catch { setReady([]); }
  };

  useEffect(()=>{ loadReady(); }, []);

  const runBatchImport = async () => {
    const lim = batchLimit === '' ? 10 : Math.floor(Number(batchLimit) || 10);
    const safeLimit = Math.min(Math.max(lim, 1), 50);
    setSubmitting(true);
    try {
      const { data } = await api.post('/channels/shorts/import/batch/recent/', undefined, { params: { limit: safeLimit } });
      console.log('Shorts batch import response', data);
      await loadReady();
    } catch {
      // ignore errors here; admin can inspect logs if needed
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} alignItems="center">
        <Typography variant="h5">Short Ingestion Jobs</Typography>
        <Tooltip title="Reload READY list"><span><IconButton onClick={loadReady}><RefreshIcon/></IconButton></span></Tooltip>
      </Stack>
      <Card>
        <CardContent>
          <Typography variant="subtitle1">Batch import recent from Shorts playlists</Typography>
          <Typography variant="body2" color="text.secondary">
            Uses active playlists marked as Shorts (is_shorts=true & is_active=true) and queues up to 50 latest videos as short jobs.
          </Typography>
          <Stack direction="row" spacing={2} sx={{ mt: 2 }}>
            <TextField
              size="small"
              label="Max jobs"
              type="number"
              value={batchLimit}
              onChange={e=>{
                const raw = e.target.value;
                if (raw === '') { setBatchLimit(''); return; }
                let n = Math.floor(Number(raw) || 0);
                if (n < 1) n = 1;
                if (n > 50) n = 50;
                setBatchLimit(n);
              }}
              inputProps={{ min: 1, max: 50, step: 1 }}
              sx={{ width: 120 }}
            />
            <Button variant="outlined" onClick={runBatchImport} disabled={submitting}>Run batch (max 50)</Button>
          </Stack>
        </CardContent>
      </Card>
      <Card>
        <CardContent>
          <Typography variant="subtitle1">READY items (latest)</Typography>
          <List>
            {ready.map((j, idx) => (
              <ListItem key={j.id || j.hls_master_url || `${j.status}-${idx}`} divider>
                <ListItemText
                  primary={<Typography variant="body1">{j.hls_master_url || j.id}</Typography>}
                  secondary={<Typography variant="caption" color="text.secondary">{j.status} · {j.updated_at || j.created_at || ''}</Typography>}
                />
              </ListItem>
            ))}
          </List>
        </CardContent>
      </Card>
    </Stack>
  );
};

export default ShortsIngestion;
