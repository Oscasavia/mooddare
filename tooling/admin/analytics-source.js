export async function loadAnalytics({rangeDays, api}) {
  return api(`analytics?days=${rangeDays}`);
}
