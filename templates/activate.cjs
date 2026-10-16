// Poll only read-only owner status, then send exactly one authenticated mutation.
// POST timeout/failure is uncertain; never retry it or print response/token data.
const https = require('node:https');
const token = process.env.DISPATCH_OPERATOR_TOKEN?.trim();
const ca = process.env.DISPATCH_BACKEND_CA;
const origin = process.env.DISPATCH_BACKEND_ORIGIN;
const action = process.env.DISPATCH_OPERATOR_ACTION ?? 'activate';
delete process.env.DISPATCH_OPERATOR_TOKEN;
delete process.env.DISPATCH_BACKEND_CA;
if (!token || !ca || !origin || action !== 'activate') {
  console.error('Operator configuration missing');
  process.exit(1);
}
const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const options = { ca, rejectUnauthorized: true, headers };
function submitOnce() {
  const request = https.request(new URL('/internal/undrain', origin), {
    ...options, method: 'POST'
  }, response => {
    response.resume();
    response.on('end', () => {
      const valid = response.statusCode === 200;
      console.log(valid ? 'Operator request acknowledged' : 'Operator request refused or unresolved');
      if (!valid) process.exitCode = 1;
    });
    response.on('error', () => { console.error('Operator result uncertain'); process.exitCode = 1; });
  });
  const deadline = setTimeout(() => request.destroy(new Error('deadline')), 360000);
  request.on('close', () => clearTimeout(deadline));
  request.on('error', () => { console.error('Operator result uncertain'); process.exitCode = 1; });
  request.end('{}');
}
// RUNNING and /internal/health do not prove the backend owner is initialized.
// Read-only authenticated status does. Owner startup may take minutes.
function waitForOwner(deadline) {
  let settled = false;
  const finish = ready => {
    if (settled) return;
    settled = true;
    if (ready) submitOnce();
    else if (Date.now() >= deadline) {
      console.error('Owner readiness not observed; no POST sent');
      process.exitCode = 1;
    } else setTimeout(() => waitForOwner(deadline), 5000);
  };
  const request = https.request(new URL('/internal/status', origin), { ...options, method: 'GET' }, response => {
    response.resume();
    response.on('end', () => finish(response.statusCode === 200));
    response.on('error', () => finish(false));
  });
  const timeout = setTimeout(() => request.destroy(new Error('read deadline')), 5000);
  request.on('close', () => clearTimeout(timeout));
  request.on('error', () => finish(false));
  request.end();
}
try {
  waitForOwner(Date.now() + 360000);
} catch {
  console.error('Operator configuration refused');
  process.exitCode = 1;
}
