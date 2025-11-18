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

  const fmtGb = (bytes: number | undefined | null) => {
    if (typeof bytes !== 'number' || !Number.isFinite(bytes)) return null;
    const gb = bytes / (1024 * 1024 * 1024);
    return `${gb.toFixed(1)} GB`;
  };

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
                <Typography variant="subtitle1" sx={{ mb: 1 }}>Storage & Job Metrics</Typography>
                {data.metrics ? (
                  <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                    {data.metrics.ts && (
                      <Typography variant="body2" color="text.secondary">
                        Last updated: {String(data.metrics.ts)}
                      </Typography>
                    )}
                    {data.metrics.counts && (
                      <Typography variant="body2" color="text.secondary">
                        READY shorts: {String(data.metrics.counts.ready ?? 0)} | FAILED: {String(data.metrics.counts.failed ?? 0)}
                      </Typography>
                    )}
                    {fmtGb(data.metrics.used_bytes) && (
                      <Typography variant="body2" color="text.secondary">
                        Used storage: {fmtGb(data.metrics.used_bytes)}
                      </Typography>
                    )}
                    {fmtGb(data.metrics.cap_soft) && (
                      <Typography variant="body2" color="text.secondary">
                        Soft capacity: {fmtGb(data.metrics.cap_soft)}
                      </Typography>
                    )}
                    {fmtGb(data.metrics.cap_hard) && (
                      <Typography variant="body2" color="text.secondary">
                        Hard capacity: {fmtGb(data.metrics.cap_hard)}
                      </Typography>
                    )}
                    {typeof data.metrics.pct_soft === 'number' && (
                      <Typography variant="body2" color="text.secondary">
                        Usage vs soft cap: {String(data.metrics.pct_soft)}%
                      </Typography>
                    )}
                    {typeof data.metrics.pct_hard === 'number' && (
                      <Typography variant="body2" color="text.secondary">
                        Usage vs hard cap: {String(data.metrics.pct_hard)}%
                      </Typography>
                    )}
                    {!data.metrics.ts && !data.metrics.counts &&
                      typeof data.metrics.used_bytes === 'undefined' &&
                      typeof data.metrics.cap_soft === 'undefined' &&
                      typeof data.metrics.cap_hard === 'undefined' && (
                        <Typography variant="body2" color="text.secondary">
                          Metrics loaded.
                        </Typography>
                      )}
                  </Box>
                ) : (
                  <Typography variant="body2" color="text.secondary">No metrics payload.</Typography>
                )}
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
