import { Client, Events, GatewayIntentBits, Message, PartialMessage } from 'discord.js';
import { config } from './config';
import { logger } from './logger';
import { N8nClient } from './n8n-client';

export class DiscordBot {
  private client: Client;
  private n8nClient: N8nClient;
  private isReady: boolean = false;

  constructor() {
    this.client = new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.DirectMessages,
      ],
    });

    this.n8nClient = new N8nClient();
    this.setupEventHandlers();
  }

  private setupEventHandlers(): void {
    // Bot is ready
    this.client.once(Events.ClientReady, (client) => {
      this.isReady = true;
      logger.info(`Bot is ready! Logged in as ${client.user.tag}`, {
        userId: client.user.id,
        guilds: client.guilds.cache.size,
      });
    });

    // Message created
    this.client.on(Events.MessageCreate, async (message: Message) => {
      await this.handleMessageCreate(message);
    });

    // Message updated
    this.client.on(Events.MessageUpdate, async (oldMessage: Message | PartialMessage, newMessage: Message | PartialMessage) => {
      await this.handleMessageUpdate(oldMessage, newMessage);
    });

    // Message deleted
    this.client.on(Events.MessageDelete, async (message: Message | PartialMessage) => {
      await this.handleMessageDelete(message);
    });

    // Error handling
    this.client.on(Events.Error, (error: Error) => {
      logger.error('Discord client error', { error: error.message, stack: error.stack });
    });

    // Warning handling
    this.client.on(Events.Warn, (warning: string) => {
      logger.warn('Discord client warning', { warning });
    });

    // Reconnecting
    this.client.on(Events.ShardReconnecting, () => {
      logger.warn('Discord client reconnecting...');
    });

    // Resumed
    this.client.on(Events.ShardResume, () => {
      logger.info('Discord client resumed connection');
    });
  }

  private async handleMessageCreate(message: Message): Promise<void> {
    try {
      // Ignore bot messages (including self)
      if (message.author.bot) {
        return;
      }

      // Check if we should monitor this channel
      if (!this.shouldMonitorChannel(message.channelId)) {
        return;
      }

      logger.debug('Message created', {
        messageId: message.id,
        author: message.author.tag,
        channelId: message.channelId,
        content: message.content.substring(0, 100),
      });

      const payload = this.n8nClient.createPayload(message, 'messageCreate');
      await this.n8nClient.sendEvent(payload);
    } catch (error) {
      logger.error('Error handling message create', {
        error: (error as Error).message,
        messageId: message.id,
      });
    }
  }

  private async handleMessageUpdate(
    oldMessage: Message | PartialMessage,
    newMessage: Message | PartialMessage
  ): Promise<void> {
    try {
      // Fetch full message if partial
      const message = newMessage.partial ? await newMessage.fetch() : newMessage;

      // Ignore bot messages
      if (message.author.bot) {
        return;
      }

      // Check if we should monitor this channel
      if (!this.shouldMonitorChannel(message.channelId)) {
        return;
      }

      logger.debug('Message updated', {
        messageId: message.id,
        author: message.author.tag,
        channelId: message.channelId,
      });

      const payload = this.n8nClient.createPayload(message, 'messageUpdate');
      await this.n8nClient.sendEvent(payload);
    } catch (error) {
      logger.error('Error handling message update', {
        error: (error as Error).message,
        messageId: newMessage.id,
      });
    }
  }

  private async handleMessageDelete(message: Message | PartialMessage): Promise<void> {
    try {
      // We might not have full message data for deleted messages
      if (message.partial) {
        logger.debug('Partial message deleted (cannot send full data)', {
          messageId: message.id,
        });
        return;
      }

      // Ignore bot messages
      if (message.author?.bot) {
        return;
      }

      // Check if we should monitor this channel
      if (!this.shouldMonitorChannel(message.channelId)) {
        return;
      }

      logger.debug('Message deleted', {
        messageId: message.id,
        author: message.author?.tag,
        channelId: message.channelId,
      });

      const payload = this.n8nClient.createPayload(message as Message, 'messageDelete');
      await this.n8nClient.sendEvent(payload);
    } catch (error) {
      logger.error('Error handling message delete', {
        error: (error as Error).message,
        messageId: message.id,
      });
    }
  }

  private shouldMonitorChannel(channelId: string): boolean {
    // If no specific channels configured, monitor all
    if (config.monitoring.channels.length === 0) {
      return true;
    }

    // Check if channel is in monitored list
    return config.monitoring.channels.includes(channelId);
  }

  async start(): Promise<void> {
    try {
      logger.info('Starting Discord bot...', {
        nodeEnv: config.nodeEnv,
        webhookUrl: config.n8n.webhookUrl,
        monitoredChannels: config.monitoring.channels.length || 'all',
      });

      await this.client.login(config.discord.token);

      logger.info('Discord bot logged in successfully');
    } catch (error) {
      logger.error('Failed to start Discord bot', {
        error: (error as Error).message,
        stack: (error as Error).stack,
      });
      throw error;
    }
  }

  async stop(): Promise<void> {
    logger.info('Stopping Discord bot...');
    this.client.destroy();
    this.isReady = false;
    logger.info('Discord bot stopped');
  }

  getClient(): Client {
    return this.client;
  }

  isClientReady(): boolean {
    return this.isReady;
  }
}
