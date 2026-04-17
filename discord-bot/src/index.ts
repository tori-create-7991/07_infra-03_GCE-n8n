import { DiscordBot } from './bot';
import { logger } from './logger';
import { config } from './config';

// Graceful shutdown handling
let bot: DiscordBot | null = null;

async function shutdown(signal: string): Promise<void> {
  logger.info(`Received ${signal}, shutting down gracefully...`);

  if (bot) {
    await bot.stop();
  }

  process.exit(0);
}

async function main(): Promise<void> {
  try {
    logger.info('Initializing Discord bot...', {
      version: '1.0.0',
      nodeVersion: process.version,
      platform: process.platform,
    });

    // Validate configuration
    logger.info('Configuration loaded', {
      webhookUrl: config.n8n.webhookUrl,
      monitoredChannels: config.monitoring.channels.length || 'all channels',
      debug: config.debug,
    });

    // Create and start bot
    bot = new DiscordBot();
    await bot.start();

    logger.info('Discord bot is running. Press CTRL+C to stop.');

    // Health check endpoint (optional - for monitoring)
    if (config.nodeEnv === 'production') {
      const http = require('http');
      const server = http.createServer((req: any, res: any) => {
        if (req.url === '/health') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'ok',
            ready: bot?.isClientReady() || false,
            timestamp: new Date().toISOString(),
          }));
        } else {
          res.writeHead(404);
          res.end();
        }
      });

      const port = process.env.HEALTH_CHECK_PORT || 3000;
      server.listen(port, () => {
        logger.info(`Health check server listening on port ${port}`);
      });
    }
  } catch (error) {
    logger.error('Fatal error during startup', {
      error: (error as Error).message,
      stack: (error as Error).stack,
    });
    process.exit(1);
  }
}

// Handle shutdown signals
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Handle uncaught errors
process.on('uncaughtException', (error: Error) => {
  logger.error('Uncaught exception', {
    error: error.message,
    stack: error.stack,
  });
  process.exit(1);
});

process.on('unhandledRejection', (reason: any) => {
  logger.error('Unhandled rejection', {
    reason: reason?.message || reason,
    stack: reason?.stack,
  });
  process.exit(1);
});

// Start the application
main();
