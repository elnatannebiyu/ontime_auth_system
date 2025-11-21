import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Typography, Stack, TextField, Button, MenuItem } from '@mui/material';
import api from '../services/api';

const AppVersions: React.FC = () => {
  const [platform, setPlatform] = useState('web');
  const [version, setVersion] = useState('1.0.0');
  const [latest, setLatest] = useState<any>(null);
  const [supported, setSupported] = useState<any>(null);
  const [check, setCheck] = useState<any>(null);

  const load = async () => {
    try {
      const [lat, sup] = await Promise.all([
        api.get('/channels/version/latest/', { params: { platform } }).catch(()=>({data:null})),
        api.get('/channels/version/supported/', { params: { platform } }).catch(()=>({data:null})),
      ]);
      setLatest(lat.data);
      setSupported(sup.data);
    } catch {}
  };

  useEffect(()=>{ load(); }, [platform]);

  const doCheck = async () => {
    try {
      const { data } = await api.post('/channels/version/check/', { platform, version });
      setCheck(data);
    } catch (e:any) {
      setCheck({ error: e?.response?.data || 'failed' });
    }
  };

  return (
    <Stack spacing={2}>
      <Card>
        <CardContent>
          <Typography variant="h6">Version Check</Typography>
          <Stack direction="row" spacing={2} sx={{ mt: 2 }}>
            <TextField
              select
              size="small"
              label="Platform"
              value={platform}
              onChange={e => setPlatform(e.target.value)}
              sx={{ minWidth: 140 }}
            >
              <MenuItem value="web">web</MenuItem>
              <MenuItem value="android">android</MenuItem>
              <MenuItem value="ios">ios</MenuItem>
            </TextField>
            <TextField size="small" label="Version" value={version} onChange={e=>setVersion(e.target.value)} />
            <Button variant="contained" onClick={doCheck}>Check</Button>
          </Stack>
          {check && (
            <Box sx={{ mt: 2, p:1.5, bgcolor:'action.hover', borderRadius:1 }}>
              {check.error ? (
                <Typography variant="body2" color="error">
                  {typeof check.error === 'string' ? check.error : 'Version check failed'}
                </Typography>
              ) : (
                <>
                  <Typography variant="subtitle2" gutterBottom>
                    Result for <strong>{platform}</strong> / <strong>{version}</strong>
                  </Typography>
                  <Typography variant="body2">
                    Update required:{' '}
                    <strong>{check.update_required ? 'Yes' : 'No'}</strong>
                  </Typography>
                  <Typography variant="body2">
                    Update available:{' '}
                    <strong>{check.update_available ? 'Yes' : 'No'}</strong>
                  </Typography>
                  {check.latest_version && (
                    <Typography variant="body2">
                      Latest version: <strong>{check.latest_version}</strong>
                    </Typography>
                  )}
                  {check.minimum_version && (
                    <Typography variant="body2">
                      Minimum supported: <strong>{check.minimum_version}</strong>
                    </Typography>
                  )}
                </>
              )}
            </Box>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardContent>
          <Typography variant="h6">Latest</Typography>
          {latest ? (
            <Box sx={{ mt: 2, p:1.5, bgcolor:'action.hover', borderRadius:1 }}>
              <Typography variant="body2">
                Platform: <strong>{latest.platform}</strong>
              </Typography>
              <Typography variant="body2">
                Version: <strong>{latest.version}</strong>{latest.build_number != null ? ` (build ${latest.build_number})` : ''}
              </Typography>
              {latest.released_at && (
                <Typography variant="body2">
                  Released at:{' '}
                  {new Date(latest.released_at).toLocaleString()}
                </Typography>
              )}
              {latest.store_url && (
                <Typography variant="body2" sx={{ mt: 0.5 }}>
                  Store URL:{' '}
                  <a href={latest.store_url} target="_blank" rel="noreferrer">
                    {latest.store_url}
                  </a>
                </Typography>
              )}
            </Box>
          ) : (
            <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>
              No latest version data.
            </Typography>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardContent>
          <Typography variant="h6">Supported</Typography>
          {supported && Array.isArray(supported.versions) && supported.versions.length > 0 ? (
            <Box sx={{ mt: 2, p:1.5, bgcolor:'action.hover', borderRadius:1 }}>
              <Typography variant="body2" gutterBottom>
                {supported.versions.length} supported version{supported.versions.length === 1 ? '' : 's'} for <strong>{platform}</strong>
              </Typography>
              {supported.versions.slice(0, 5).map((v: any, idx: number) => (
                <Box key={`${v.platform}-${v.version}-${idx}`} sx={{ mb: 0.5 }}>
                  <Typography variant="body2">
                    <strong>{v.version}</strong>{' '}
                    {v.status ? `(${v.status})` : ''}
                    {v.deprecated ? ' – deprecated' : ''}
                  </Typography>
                  {v.released_at && (
                    <Typography variant="caption" color="text.secondary">
                      Released: {new Date(v.released_at).toLocaleDateString()}
                    </Typography>
                  )}
                </Box>
              ))}
              {supported.versions.length > 5 && (
                <Typography variant="caption" color="text.secondary">
                  +{supported.versions.length - 5} more…
                </Typography>
              )}
            </Box>
          ) : (
            <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>
              No supported versions data.
            </Typography>
          )}
        </CardContent>
      </Card>
    </Stack>
  );
};

export default AppVersions;
