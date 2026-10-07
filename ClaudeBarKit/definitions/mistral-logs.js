// Mistral has no quota to read: Vibe's session logs are today's usage,
// which TODAY'S USAGE shows beside the provider. This data source only says
// that Vibe is installed — no quota, and no made-up one.
function read(response) {
    const data = response.json;
    if (!data || !Array.isArray(data.entries)) return {error: {parseFailed: 'No Vibe session folder listing'}};
    return {quotas: []};
}
