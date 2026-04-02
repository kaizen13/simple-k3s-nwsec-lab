const express = require('express');
const redis = require('redis');

const app = express();
const client = redis.createClient({
  url: 'redis://redis.sample-app.svc.cluster.local:6379'
});

(async () => {
  await client.connect();
})();

app.get('/', (req, res) => {
  res.send('Hello from the backend!');
});

app.get('/data', async (req, res) => {
  await client.set('key', 'value');
  const value = await client.get('key');
  res.send(`Data from Redis: ${value}`);
});

app.listen(3000, () => {
  console.log('Backend running on port 3000');
});