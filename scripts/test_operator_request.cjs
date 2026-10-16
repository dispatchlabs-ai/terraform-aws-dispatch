// Offline template transport tests. No sockets or application runtime.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const source = fs.readFileSync(path.join(__dirname, '../templates/activate.cjs'), 'utf8');
function run(action, responses) {
  const calls = [], timers = new Map();
  let clock = 0, sequence = 0;
  const process = { env: { DISPATCH_OPERATOR_TOKEN: 'fixture-not-a-secret', DISPATCH_BACKEND_CA: 'fixture-ca', DISPATCH_BACKEND_ORIGIN: 'https://backend.example:3001', DISPATCH_OPERATOR_ACTION: action }, exitCode: 0, exit: code => { throw new Error(`exit-${code}`); } };
  const https = { request: (url, options, callback) => {
    const request = new EventEmitter();
    calls.push({ url: url.pathname, method: options.method });
    assert.equal(options.rejectUnauthorized, true);
    request.destroy = error => { request.emit('error', error); request.emit('close'); };
    request.end = () => {
      const next = responses.shift();
      assert.ok(next, 'Unexpected transport replay');
      if (next.error) request.emit('error', new Error('synthetic'));
      else {
        const response = new EventEmitter();
        response.statusCode = next.status;
        response.resume = () => {};
        callback(response);
        if (next.body) response.emit('data', Buffer.from(next.body));
        response.emit('end');
      }
      request.emit('close');
    };
    return request;
  }};
  vm.runInNewContext(source, { require: name => { assert.equal(name, 'node:https'); return https; }, process, URL, console: { log() {}, error() {} }, Date: { now: () => clock }, setTimeout: (fn, ms) => { const id = ++sequence; timers.set(id, { fn, ms }); return id; }, clearTimeout: id => timers.delete(id) });
  for (let count = 0; timers.size && count < 100; count++) {
    const [id, timer] = timers.entries().next().value;
    timers.delete(id); clock += timer.ms; timer.fn();
  }
  assert.equal(timers.size, 0);
  assert.equal(process.env.DISPATCH_OPERATOR_TOKEN, undefined);
  return { calls, code: process.exitCode };
}
let result = run('activate', [{ status: 503 }, { status: 200 }, { status: 200 }]);
assert.deepEqual(result.calls.map(c => c.method), ['GET', 'GET', 'POST']);
assert.equal(result.calls[0].url, '/internal/status');
assert.equal(result.calls[2].url, '/internal/undrain');
assert.equal(result.code, 0);
result = run('activate', [{ error: true }, { status: 200 }, { error: true }]);
assert.equal(result.calls.filter(c => c.method === 'POST').length, 1);
assert.equal(result.code, 1);
assert.throws(() => run('sleep', []), /exit-1/);
console.log('3 offline operator-request cases passed.');
