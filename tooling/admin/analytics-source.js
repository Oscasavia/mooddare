export async function loadAnalytics({rangeDays, environment='production', api}) {
  return api(`analytics?days=${rangeDays}&environment=${environment}`);
}
