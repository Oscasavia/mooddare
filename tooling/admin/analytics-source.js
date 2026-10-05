/**
 * Integration boundary for future staff-only, aggregated app analytics.
 * No events are collected and no analytics endpoint is requested today.
 * Replace this function with an authenticated API call when the collection
 * pipeline is ready. See docs/ADMIN_ANALYTICS.md for the versioned contract.
 */
export async function loadAnalytics({rangeDays, api}) {
  // Keep the API client injected: credentials must never be embedded here.
  void rangeDays;
  void api;
  return {status: 'not-connected'};
}
