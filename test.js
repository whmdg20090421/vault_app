const https = require('https');
const options = {
  hostname: 'webdav.123pan.com',
  port: 443,
  path: '/webdav/',
  method: 'PROPFIND',
  headers: {
    'Authorization': 'Basic ' + Buffer.from('18302339198:d1fa16lh').toString('base64'),
    'Depth': '1'
  }
};
const req = https.request(options, (res) => {
  console.log('Status:', res.statusCode);
  res.on('data', (d) => process.stdout.write(d));
});
req.on('error', (e) => {
  console.error('Error occurred:', e);
});
req.end();
