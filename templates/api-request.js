function handler(event) {
  var request = event.request;
  if (request.method === 'GET' && request.uri === '/api/connections/oauth/callback') {
    request.querystring = {};
  }
  return request;
}
