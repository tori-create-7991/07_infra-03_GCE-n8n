#!/bin/bash

set -e

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
ZONE="${GCP_ZONE:-asia-northeast1-b}"
INSTANCE_NAME="${INSTANCE_NAME:-discord-bot}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-micro}"
BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-10GB}"

# Discord Bot Configuration
DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN}"
DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL}"
MONITORED_CHANNELS="${MONITORED_CHANNELS:-}"
DEBUG="${DEBUG:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate required variables
if [ -z "$DISCORD_BOT_TOKEN" ]; then
    echo_error "DISCORD_BOT_TOKEN is required"
    exit 1
fi

if [ -z "$DISCORD_CLIENT_ID" ]; then
    echo_error "DISCORD_CLIENT_ID is required"
    exit 1
fi

if [ -z "$N8N_WEBHOOK_URL" ]; then
    echo_error "N8N_WEBHOOK_URL is required"
    exit 1
fi

echo_info "Starting deployment to Compute Engine..."
echo_info "Project: $PROJECT_ID"
echo_info "Zone: $ZONE"
echo_info "Instance: $INSTANCE_NAME"
echo_info "Machine Type: $MACHINE_TYPE"

# Set project
gcloud config set project "$PROJECT_ID"

# Check if instance already exists
if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &> /dev/null; then
    echo_warn "Instance $INSTANCE_NAME already exists"
    read -p "Do you want to delete and recreate it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo_info "Deleting existing instance..."
        gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet
    else
        echo_info "Updating existing instance..."
        UPDATE_MODE=true
    fi
fi

# Create startup script
cat > /tmp/startup-script.sh << 'EOF'
#!/bin/bash

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install git
apt-get install -y git

# Create bot user
useradd -m -s /bin/bash discord-bot || true

# Create application directory
mkdir -p /opt/discord-bot
chown discord-bot:discord-bot /opt/discord-bot

# Install global dependencies
npm install -g pm2

# Set up log directory
mkdir -p /var/log/discord-bot
chown discord-bot:discord-bot /var/log/discord-bot

echo "System setup complete"
EOF

if [ "$UPDATE_MODE" != true ]; then
    echo_info "Creating Compute Engine instance..."

    gcloud compute instances create "$INSTANCE_NAME" \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --tags=discord-bot,http-server \
        --create-disk=auto-delete=yes,boot=yes,device-name="$INSTANCE_NAME",image=projects/debian-cloud/global/images/debian-11-bullseye-v20240213,mode=rw,size="$BOOT_DISK_SIZE",type=projects/"$PROJECT_ID"/zones/"$ZONE"/diskTypes/pd-standard \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=app=discord-bot,environment=production \
        --metadata-from-file=startup-script=/tmp/startup-script.sh \
        --metadata=discord-bot-token="$DISCORD_BOT_TOKEN",discord-client-id="$DISCORD_CLIENT_ID",n8n-webhook-url="$N8N_WEBHOOK_URL",monitored-channels="$MONITORED_CHANNELS",debug="$DEBUG"

    echo_info "Instance created. Waiting for it to be ready..."
    sleep 30
fi

# Get instance external IP
EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo_info "Instance IP: $EXTERNAL_IP"

# Create firewall rule for health check (if needed)
if ! gcloud compute firewall-rules describe allow-discord-bot-health &> /dev/null; then
    echo_info "Creating firewall rule for health check..."
    gcloud compute firewall-rules create allow-discord-bot-health \
        --project="$PROJECT_ID" \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:3000 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=discord-bot
fi

echo_info "Uploading bot code to instance..."

# Create temporary directory with bot code
TEMP_DIR=$(mktemp -d)
cp -r package.json tsconfig.json src "$TEMP_DIR/"
cd "$TEMP_DIR"

# Create tar archive
tar -czf bot-code.tar.gz package.json tsconfig.json src/

# Upload to instance
gcloud compute scp bot-code.tar.gz "$INSTANCE_NAME:/tmp/" --zone="$ZONE"

# Create .env file content
cat > .env << ENVEOF
DISCORD_BOT_TOKEN=$DISCORD_BOT_TOKEN
DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL
MONITORED_CHANNELS=$MONITORED_CHANNELS
DEBUG=$DEBUG
NODE_ENV=production
HEALTH_CHECK_PORT=3000
ENVEOF

# Upload .env file
gcloud compute scp .env "$INSTANCE_NAME:/tmp/" --zone="$ZONE"

# Clean up temp directory
cd -
rm -rf "$TEMP_DIR"

# Install and start the bot
echo_info "Installing and starting the bot on the instance..."

gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
set -e

# Extract bot code
sudo tar -xzf /tmp/bot-code.tar.gz -C /opt/discord-bot/
sudo mv /tmp/.env /opt/discord-bot/.env
sudo chown -R discord-bot:discord-bot /opt/discord-bot

# Install dependencies and build
cd /opt/discord-bot
sudo -u discord-bot npm install
sudo -u discord-bot npm run build

# Create systemd service
sudo tee /etc/systemd/system/discord-bot.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=Discord to n8n Webhook Bot
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=discord-bot
Group=discord-bot
WorkingDirectory=/opt/discord-bot
Environment=\"NODE_ENV=production\"
EnvironmentFile=/opt/discord-bot/.env

ExecStart=/usr/bin/node /opt/discord-bot/dist/index.js

Restart=always
RestartSec=10
StartLimitInterval=0

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/discord-bot
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

StandardOutput=journal
StandardError=journal
SyslogIdentifier=discord-bot

LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable discord-bot
sudo systemctl restart discord-bot

# Check status
sleep 5
sudo systemctl status discord-bot --no-pager
"

echo_info "Deployment complete!"
echo_info ""
echo_info "Instance Information:"
echo_info "  Name: $INSTANCE_NAME"
echo_info "  Zone: $ZONE"
echo_info "  External IP: $EXTERNAL_IP"
echo_info "  Health Check: http://$EXTERNAL_IP:3000/health"
echo_info ""
echo_info "Useful commands:"
echo_info "  View logs: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='sudo journalctl -u discord-bot -f'"
echo_info "  Check status: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='sudo systemctl status discord-bot'"
echo_info "  Restart bot: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='sudo systemctl restart discord-bot'"
echo_info "  SSH to instance: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo_info ""
echo_info "To delete the instance:"
echo_info "  gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE"
