import axios, { AxiosInstance, AxiosError } from 'axios';
import { config } from './config';
import { logger } from './logger';
import { Message, User, TextChannel, Guild } from 'discord.js';

export interface DiscordEventPayload {
  eventType: 'messageCreate' | 'messageUpdate' | 'messageDelete';
  timestamp: string;
  message: {
    id: string;
    content: string;
    channelId: string;
    channelName: string;
    guildId: string | null;
    guildName: string | null;
    author: {
      id: string;
      username: string;
      bot: boolean;
      tag: string;
    };
    attachments: Array<{
      id: string;
      url: string;
      proxyUrl: string;
      filename: string;
      contentType: string | null;
      size: number;
    }>;
    embeds: any[];
    mentions: Array<{
      id: string;
      username: string;
      tag: string;
    }>;
    createdAt: string;
    editedAt: string | null;
  };
}

export class N8nClient {
  private client: AxiosInstance;
  private retryCount: number = 3;
  private retryDelay: number = 1000;

  constructor() {
    this.client = axios.create({
      baseURL: config.n8n.webhookUrl,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Discord-N8n-Bot/1.0',
      },
    });
  }

  async sendEvent(payload: DiscordEventPayload): Promise<void> {
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= this.retryCount; attempt++) {
      try {
        logger.debug(`Sending event to n8n (attempt ${attempt}/${this.retryCount})`, {
          eventType: payload.eventType,
          messageId: payload.message.id,
        });

        const response = await this.client.post('', payload);

        logger.info('Event sent successfully to n8n', {
          eventType: payload.eventType,
          messageId: payload.message.id,
          status: response.status,
        });

        return;
      } catch (error) {
        lastError = error as Error;

        if (axios.isAxiosError(error)) {
          const axiosError = error as AxiosError;
          logger.warn(`Failed to send event to n8n (attempt ${attempt}/${this.retryCount})`, {
            status: axiosError.response?.status,
            message: axiosError.message,
            url: config.n8n.webhookUrl,
          });
        } else {
          logger.warn(`Unexpected error sending event (attempt ${attempt}/${this.retryCount})`, {
            error: (error as Error).message,
          });
        }

        if (attempt < this.retryCount) {
          const delay = this.retryDelay * attempt;
          logger.debug(`Retrying in ${delay}ms...`);
          await this.sleep(delay);
        }
      }
    }

    logger.error('Failed to send event to n8n after all retries', {
      error: lastError?.message,
      eventType: payload.eventType,
      messageId: payload.message.id,
    });
  }

  createPayload(message: Message, eventType: DiscordEventPayload['eventType']): DiscordEventPayload {
    const channel = message.channel as TextChannel;
    const guild = message.guild as Guild | null;

    return {
      eventType,
      timestamp: new Date().toISOString(),
      message: {
        id: message.id,
        content: message.content,
        channelId: channel.id,
        channelName: channel.name || 'DM',
        guildId: guild?.id || null,
        guildName: guild?.name || null,
        author: {
          id: message.author.id,
          username: message.author.username,
          bot: message.author.bot,
          tag: message.author.tag,
        },
        attachments: message.attachments.map(attachment => ({
          id: attachment.id,
          url: attachment.url,
          proxyUrl: attachment.proxyURL,
          filename: attachment.name || 'unknown',
          contentType: attachment.contentType,
          size: attachment.size,
        })),
        embeds: message.embeds,
        mentions: message.mentions.users.map(user => ({
          id: user.id,
          username: user.username,
          tag: user.tag,
        })),
        createdAt: message.createdAt.toISOString(),
        editedAt: message.editedAt?.toISOString() || null,
      },
    };
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
