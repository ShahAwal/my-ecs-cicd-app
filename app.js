// app.js
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello from ECS Fargate deployed via GitHub Actions!');
});

app.get('/health', (req, res) => {
    // Simple health check endpoint
    res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(`App listening at http://localhost:${port}`);
});
