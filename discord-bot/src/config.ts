import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

export interface Config {
  discord: {
    token: string;
    clientId: string;
  };
  n8n: {
    webhookUrl: string;
  };
  monitoring: {
    channels: string[];
  };
  debug: boolean;
  nodeEnv: string;
}

function validateEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

export const config: Config = {
  discord: {
    token: validateEnv('DISCORD_BOT_TOKEN'),
    clientId: validateEnv('DISCORD_CLIENT_ID'),
  },
  n8n: {
    webhookUrl: validateEnv('N8N_WEBHOOK_URL'),
  },
  monitoring: {
    channels: process.env.MONITORED_CHANNELS
      ? process.env.MONITORED_CHANNELS.split(',').map(id => id.trim())
      : [],
  },
  debug: process.env.DEBUG === 'true',
  nodeEnv: process.env.NODE_ENV || 'development',
};
