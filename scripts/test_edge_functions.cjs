// Offline checks of released CloudFront function source; no browser/app/AWS run.
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const assert = require('node:assert/strict');
function invoke(file, request) {
  return runInNewContext(`${readFileSync(`templates/${file}`, 'utf8')}\nhandler(event)`, { event: { request } });
}
for (const path of ['/', '/chat/abc', '/settings/']) {
  assert.equal(invoke('spa-rewrite.js', { uri: path }).uri, '/index.html');
}
for (const path of ['/assets/does-not-exist.js', '/favicon.ico']) {
  assert.equal(invoke('spa-rewrite.js', { uri: path }).uri, path);
}
for (const path of ['/internal', '/internal/undrain']) {
  assert.equal(invoke('spa-rewrite.js', { uri: path }).statusCode, 404);
}
const headers = { authorization: { value: 'synthetic' }, cookie: { value: 'synthetic' } };
const callback = { uri: '/api/connections/oauth/callback', method: 'GET', headers, querystring: { code: { value: 'synthetic' } } };
assert.equal(invoke('api-request.js', callback), callback);
assert.equal(Object.keys(callback.querystring).length, 0);
assert.equal(callback.headers, headers);
const api = { uri: '/api/history', method: 'GET', headers, querystring: { before: { value: 'synthetic' } } };
assert.equal(invoke('api-request.js', api), api);
assert.equal(api.querystring.before.value, 'synthetic');
assert.equal(api.uri, '/api/history');
console.log('Edge rewrite/query/header offline checks passed.');
