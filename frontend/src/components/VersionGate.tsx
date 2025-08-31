// import React, { useEffect, useState } from 'react';
// import { apiService } from '../services/api';

// interface VersionInfo {
//   update_required: boolean;
//   update_available: boolean;
//   latest_version: string;
//   minimum_version: string;
//   download_url: string;
//   release_notes?: string;
//   features: Record<string, boolean>;
// }

// interface VersionGateProps {
//   platform: 'ios' | 'android' | 'web';
//   currentVersion: string;
//   children: React.ReactNode;
// }

// const VersionGate: React.FC<VersionGateProps> = ({ platform, currentVersion, children }) => {
//   const [versionInfo, setVersionInfo] = useState<VersionInfo | null>(null);
//   const [loading, setLoading] = useState(true);
//   const [error, setError] = useState<string | null>(null);
//   const [dismissed, setDismissed] = useState(false);

//   useEffect(() => {
//     checkVersion();
//   }, [platform, currentVersion]);

//   const checkVersion = async () => {
//     try {
//       setLoading(true);
//       const response = await apiService.post('/channels/version/check/', {
//         platform,
//         version: currentVersion
//       });
//       setVersionInfo(response.data);
//     } catch (err: any) {
//       setError(err.response?.data?.error || 'Failed to check version');
//     } finally {
//       setLoading(false);
//     }
//   };

//   const handleUpdate = () => {
//     if (versionInfo?.download_url) {
//       window.open(versionInfo.download_url, '_blank');
//     }
//   };

//   const handleDismiss = () => {
//     setDismissed(true);
//     // Store dismissal in localStorage with expiry
//     const dismissalData = {
//       version: currentVersion,
//       timestamp: Date.now(),
//       expiresAt: Date.now() + (24 * 60 * 60 * 1000) // 24 hours
//     };
//     localStorage.setItem('version_update_dismissed', JSON.stringify(dismissalData));
//   };

//   // Check if update was previously dismissed
//   useEffect(() => {
//     const dismissalData = localStorage.getItem('version_update_dismissed');
//     if (dismissalData) {
//       const parsed = JSON.parse(dismissalData);
//       if (parsed.version === currentVersion && parsed.expiresAt > Date.now()) {
//         setDismissed(true);
//       } else {
//         localStorage.removeItem('version_update_dismissed');
//       }
//     }
//   }, [currentVersion]);

//   if (loading) {
//     return (
//       <div className="version-gate-loading">
//         <div className="spinner"></div>
//         <p>Checking version compatibility...</p>
//       </div>
//     );
//   }

//   if (error) {
//     console.error('Version check error:', error);
//     // Don't block the app on version check failure
//     return <>{children}</>;
//   }

//   // Force update required - block access
//   if (versionInfo?.update_required) {
//     return (
//       <div className="version-gate-blocked">
//         <div className="update-modal">
//           <div className="update-icon">⚠️</div>
//           <h2>Update Required</h2>
//           <p>
//             A new version ({versionInfo.latest_version}) is required to continue using this application.
//             Your current version ({currentVersion}) is no longer supported.
//           </p>
//           {versionInfo.release_notes && (
//             <div className="release-notes">
//               <h3>What's New:</h3>
//               <p>{versionInfo.release_notes}</p>
//             </div>
//           )}
//           <button className="update-button primary" onClick={handleUpdate}>
//             Update Now
//           </button>
//         </div>
//       </div>
//     );
//   }

//   // Optional update available - show dismissible banner
//   if (versionInfo?.update_available && !dismissed) {
//     return (
//       <>
//         <div className="version-update-banner">
//           <div className="update-content">
//             <span className="update-icon">🎉</span>
//             <span className="update-text">
//               New version {versionInfo.latest_version} is available!
//             </span>
//             <div className="update-actions">
//               <button className="update-button secondary" onClick={handleDismiss}>
//                 Later
//               </button>
//               <button className="update-button primary" onClick={handleUpdate}>
//                 Update
//               </button>
//             </div>
//           </div>
//         </div>
//         {children}
//       </>
//     );
//   }

//   // No update needed or dismissed
//   return <>{children}</>;
// };

// // Feature flag component
// interface FeatureGateProps {
//   feature: string;
//   platform?: 'ios' | 'android' | 'web';
//   version?: string;
//   children: React.ReactNode;
//   fallback?: React.ReactNode;
// }

// export const FeatureGate: React.FC<FeatureGateProps> = ({ 
//   feature, 
//   platform = 'web', 
//   version = '1.0.0',
//   children, 
//   fallback = null 
// }) => {
//   const [enabled, setEnabled] = useState(false);
//   const [loading, setLoading] = useState(true);

//   useEffect(() => {
//     checkFeature();
//   }, [feature, platform, version]);

//   const checkFeature = async () => {
//     try {
//       const response = await apiService.get('/channels/features/', {
//         params: { platform, version }
//       });
//       setEnabled(response.data[feature] || false);
//     } catch (err) {
//       console.error('Feature check failed:', err);
//       setEnabled(false);
//     } finally {
//       setLoading(false);
//     }
//   };

//   if (loading) {
//     return null;
//   }

//   return enabled ? <>{children}</> : <>{fallback}</>;
// };

// export default VersionGate;
