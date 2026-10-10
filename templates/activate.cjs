// A deliberate single request. A timeout is an uncertain result, never a retry.
const https = require('node:https');
const token = process.env.DISPATCH_OPERATOR_TOKEN?.trim();
const ca = process.env.DISPATCH_BACKEND_CA;
const origin = process.env.DISPATCH_BACKEND_ORIGIN;
delete process.env.DISPATCH_OPERATOR_TOKEN;
delete process.env.DISPATCH_BACKEND_CA;
if (!token || !ca || !origin) {
  console.error('Activation configuration missing');
  process.exit(1);
}
try {
const request = https.request(new URL('/internal/undrain', origin), {
  method: 'POST', ca, rejectUnauthorized: true,
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }
}, response => {
  response.resume();
  response.on('end', () => {
    if (response.statusCode !== 200) {
      console.error('Activation refused');
      process.exitCode = 1;
    } else console.log('Activation acknowledged');
  });
  response.on('error', () => { console.error('Activation result uncertain'); process.exitCode = 1; });
});
const deadline = setTimeout(() => request.destroy(new Error('deadline')), 360000);
request.on('close', () => clearTimeout(deadline));
request.on('error', () => { console.error('Activation result uncertain'); process.exitCode = 1; });
request.end('{}');
} catch {
  console.error('Activation configuration refused');
  process.exitCode = 1;
}
