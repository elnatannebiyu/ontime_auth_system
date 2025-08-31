// import React, { useState, useEffect } from 'react';
// import { apiService } from '../services/api';
// import './VersionManagement.css';

// interface AppVersion {
//   id: string;
//   platform: string;
//   version: string;
//   minimum_version: string;
//   is_supported: boolean;
//   is_latest: boolean;
//   download_url: string;
//   release_notes: string;
//   released_at: string;
//   features: Record<string, boolean>;
// }

// interface FeatureFlag {
//   name: string;
//   enabled: boolean;
//   description: string;
// }

// const VersionManagement: React.FC = () => {
//   const [versions, setVersions] = useState<AppVersion[]>([]);
//   const [selectedPlatform, setSelectedPlatform] = useState<'ios' | 'android' | 'web'>('ios');
//   const [testVersion, setTestVersion] = useState('1.0.0');
//   const [versionCheckResult, setVersionCheckResult] = useState<any>(null);
//   const [loading, setLoading] = useState(false);
//   const [error, setError] = useState<string | null>(null);

//   useEffect(() => {
//     fetchVersions();
//   }, [selectedPlatform]);

//   const fetchVersions = async () => {
//     try {
//       setLoading(true);
//       const response = await apiService.get(`/channels/version/supported/?platform=${selectedPlatform}`);
//       setVersions(response.data.results || []);
//     } catch (err: any) {
//       setError(err.response?.data?.error || 'Failed to fetch versions');
//     } finally {
//       setLoading(false);
//     }
//   };

//   const checkVersion = async () => {
//     try {
//       setLoading(true);
//       setError(null);
//       const response = await apiService.post('/channels/version/check/', {
//         platform: selectedPlatform,
//         version: testVersion
//       });
//       setVersionCheckResult(response.data);
//     } catch (err: any) {
//       setError(err.response?.data?.error || 'Version check failed');
//       setVersionCheckResult(null);
//     } finally {
//       setLoading(false);
//     }
//   };

//   const getFeatureFlags = async () => {
//     try {
//       setLoading(true);
//       const response = await apiService.get('/channels/features/', {
//         params: {
//           platform: selectedPlatform,
//           version: testVersion
//         }
//       });
//       setVersionCheckResult({ features: response.data });
//     } catch (err: any) {
//       setError(err.response?.data?.error || 'Failed to fetch features');
//     } finally {
//       setLoading(false);
//     }
//   };

//   const formatDate = (dateString: string) => {
//     return new Date(dateString).toLocaleDateString('en-US', {
//       year: 'numeric',
//       month: 'short',
//       day: 'numeric'
//     });
//   };

//   return (
//     <div className="version-management">
//       <h1>Version Management</h1>

//       {/* Platform Selector */}
//       <div className="platform-selector">
//         <button
//           className={`platform-btn ${selectedPlatform === 'ios' ? 'active' : ''}`}
//           onClick={() => setSelectedPlatform('ios')}
//         >
//           🍎 iOS
//         </button>
//         <button
//           className={`platform-btn ${selectedPlatform === 'android' ? 'active' : ''}`}
//           onClick={() => setSelectedPlatform('android')}
//         >
//           🤖 Android
//         </button>
//         <button
//           className={`platform-btn ${selectedPlatform === 'web' ? 'active' : ''}`}
//           onClick={() => setSelectedPlatform('web')}
//         >
//           🌐 Web
//         </button>
//       </div>

//       {/* Version Checker */}
//       <div className="version-checker">
//         <h2>Version Compatibility Checker</h2>
//         <div className="checker-controls">
//           <input
//             type="text"
//             placeholder="Enter version (e.g., 1.0.0)"
//             value={testVersion}
//             onChange={(e) => setTestVersion(e.target.value)}
//             className="version-input"
//           />
//           <button onClick={checkVersion} className="check-btn" disabled={loading}>
//             Check Version
//           </button>
//           <button onClick={getFeatureFlags} className="check-btn secondary" disabled={loading}>
//             Get Features
//           </button>
//         </div>

//         {error && (
//           <div className="error-message">
//             ❌ {error}
//           </div>
//         )}

//         {versionCheckResult && (
//           <div className="check-result">
//             <h3>Check Result</h3>
//             <div className="result-grid">
//               <div className="result-item">
//                 <span className="label">Update Required:</span>
//                 <span className={`value ${versionCheckResult.update_required ? 'danger' : 'success'}`}>
//                   {versionCheckResult.update_required ? '⚠️ Yes' : '✅ No'}
//                 </span>
//               </div>
//               <div className="result-item">
//                 <span className="label">Update Available:</span>
//                 <span className={`value ${versionCheckResult.update_available ? 'warning' : ''}`}>
//                   {versionCheckResult.update_available ? '🔄 Yes' : 'No'}
//                 </span>
//               </div>
//               {versionCheckResult.latest_version && (
//                 <div className="result-item">
//                   <span className="label">Latest Version:</span>
//                   <span className="value">{versionCheckResult.latest_version}</span>
//                 </div>
//               )}
//               {versionCheckResult.minimum_version && (
//                 <div className="result-item">
//                   <span className="label">Minimum Version:</span>
//                   <span className="value">{versionCheckResult.minimum_version}</span>
//                 </div>
//               )}
//             </div>

//             {versionCheckResult.features && (
//               <div className="features-section">
//                 <h4>Feature Flags</h4>
//                 <div className="features-grid">
//                   {Object.entries(versionCheckResult.features).map(([key, value]) => (
//                     <div key={key} className="feature-item">
//                       <span className="feature-name">{key.replace(/_/g, ' ')}</span>
//                       <span className={`feature-status ${value ? 'enabled' : 'disabled'}`}>
//                         {value ? '✅' : '❌'}
//                       </span>
//                     </div>
//                   ))}
//                 </div>
//               </div>
//             )}

//             {versionCheckResult.download_url && (
//               <div className="download-section">
//                 <a href={versionCheckResult.download_url} target="_blank" rel="noopener noreferrer" className="download-link">
//                   📥 Download Latest Version
//                 </a>
//               </div>
//             )}
//           </div>
//         )}
//       </div>

//       {/* Versions List */}
//       <div className="versions-list">
//         <h2>Supported Versions</h2>
//         {loading ? (
//           <div className="loading">Loading versions...</div>
//         ) : versions.length > 0 ? (
//           <div className="versions-grid">
//             {versions.map((version) => (
//               <div key={version.id} className={`version-card ${version.is_latest ? 'latest' : ''} ${!version.is_supported ? 'unsupported' : ''}`}>
//                 <div className="version-header">
//                   <h3>{version.version}</h3>
//                   {version.is_latest && <span className="badge latest">Latest</span>}
//                   {!version.is_supported && <span className="badge unsupported">Unsupported</span>}
//                 </div>
//                 <div className="version-details">
//                   <p className="release-date">Released: {formatDate(version.released_at)}</p>
//                   {version.release_notes && (
//                     <p className="release-notes">{version.release_notes}</p>
//                   )}
//                   {version.minimum_version && (
//                     <p className="min-version">Min Required: {version.minimum_version}</p>
//                   )}
//                 </div>
//                 {version.download_url && (
//                   <a href={version.download_url} target="_blank" rel="noopener noreferrer" className="download-btn">
//                     Download
//                   </a>
//                 )}
//               </div>
//             ))}
//           </div>
//         ) : (
//           <p className="no-versions">No versions found for {selectedPlatform}</p>
//         )}
//       </div>
//     </div>
//   );
// };

// export default VersionManagement;
