function handler(event) {
  var request = event.request;
  if (request.uri === '/internal' || request.uri.indexOf('/internal/') === 0) {
    return { statusCode: 404, statusDescription: 'Not Found' };
  }
  if (request.uri === '/' || request.uri.endsWith('/') || !request.uri.split('/').pop().includes('.')) {
    request.uri = '/index.html';
  }
  return request;
}
