import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Typography, Snackbar, Alert, CircularProgress } from '@mui/material';
import api from '../services/api';

interface ShortsMetricsPayload {
  metrics: any;
  latest_job_id: string | null;
  latest_hls: string | null;
  tenant: string;
}

const ShortsMetrics: React.FC = () => {
  const [data, setData] = useState<ShortsMetricsPayload | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      setError(null);
      try {
        const res = await api.get('/channels/shorts/admin/metrics/', { params: { tenant: 'ontime' } });
        setData(res.data as ShortsMetricsPayload);
      } catch (e: any) {
        setError(e?.response?.data?.detail || e?.message || 'Failed to load shorts metrics');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, []);

  const metricsPretty = data ? JSON.stringify(data.metrics ?? {}, null, 2) : '';

  return (
    <Box>
      <Typography variant="h5" sx={{ mb: 2 }}>Shorts Metrics</Typography>
      <Card>
        <CardContent>
          {loading && (
            <Box sx={{ display: 'flex', justifyContent: 'center', my: 4 }}>
              <CircularProgress />
            </Box>
          )}
          {!loading && data && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <Box>
                <Typography variant="subtitle1">Tenant</Typography>
                <Typography variant="body2" color="text.secondary">{data.tenant}</Typography>
              </Box>
              <Box>
                <Typography variant="subtitle1">Latest READY Job</Typography>
                <Typography variant="body2" color="text.secondary">
                  Job ID: {data.latest_job_id || 'None'}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  HLS master URL: {data.latest_hls || 'None'}
                </Typography>
              </Box>
              <Box>
                <Typography variant="subtitle1" sx={{ mb: 1 }}>Raw Metrics JSON</Typography>
                <Box component="pre" sx={{ p: 2, bgcolor: 'background.paper', borderRadius: 1, maxHeight: 400, overflow: 'auto', fontSize: 12 }}>
                  {metricsPretty}
                </Box>
              </Box>
            </Box>
          )}
          {!loading && !data && !error && (
            <Typography variant="body2" color="text.secondary">No metrics available.</Typography>
          )}
        </CardContent>
      </Card>
      <Snackbar open={!!error} autoHideDuration={4000} onClose={() => setError(null)}>
        <Alert severity="error" variant="filled" onClose={() => setError(null)} sx={{ width: '100%' }}>
          {error}
        </Alert>
      </Snackbar>
    </Box>
  );
};

export default ShortsMetrics;
