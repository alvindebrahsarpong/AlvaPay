import pino from 'pino';

import { app } from './app.js';

const logger = pino({ level: process.env.LOG_LEVEL ?? 'info' });
const port = Number(process.env.PORT ?? 3000);

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('PORT must be an integer between 1 and 65535.');
}

app.listen(port, () => {
  logger.info({ port }, 'AlvaPay API listening');
});
