#!/bin/bash

# Simple Configuration Startup Script
# データベース不要の簡易版を起動

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_feature() {
    echo -e "${BLUE}[特徴]${NC} $1"
}

# Check Docker
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        echo "Error: Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_info "Docker is running."
}

# Check/Create .env
check_env_file() {
    if [ ! -f .env ]; then
        print_warning ".env file not found. Creating minimal .env..."
        cat > .env << 'EOF'
# 簡易版環境変数（データベース不要）

# Timezone
TIMEZONE=Asia/Tokyo

# n8n Configuration
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=admin
N8N_HOST=localhost
N8N_PROTOCOL=http
N8N_WEBHOOK_URL=http://localhost:5678/
N8N_ENCRYPTION_KEY=simple_encryption_key_change_in_production

# Dify Configuration
DIFY_SECRET_KEY=simple_secret_key_change_in_production
DIFY_CONSOLE_API_URL=http://localhost:5001
DIFY_SERVICE_API_URL=http://localhost:5001
DIFY_APP_API_URL=http://localhost:5001
DIFY_APP_WEB_URL=http://localhost:3000

# Logging
LOG_LEVEL=INFO
DEBUG=false
EOF
        print_info ".env file created."
    else
        print_info ".env file found."
    fi
}

# Display features
display_features() {
    echo ""
    echo "========================================"
    echo "  簡易版: PostgreSQL/Redis不要"
    echo "========================================"
    echo ""
    print_feature "SQLite使用（PostgreSQL不要）"
    print_feature "キューなし（Redis不要）"
    print_feature "メモリ使用量: 約2GB"
    print_feature "セットアップ時間: 約3分"
    print_feature "コスト: \$0"
    echo ""
    print_warning "制限事項:"
    echo "  • n8n: 並列実行不可（順次実行のみ）"
    echo "  • Dify: バックグラウンド処理なし"
    echo "  • スケールアウト不可"
    echo ""
    print_info "推奨用途: 個人利用、テスト、プロトタイピング"
    echo ""
}

# Start services
start_services() {
    print_info "Starting services with docker-compose (simple mode)..."
    docker-compose -f docker-compose.simple.yml up -d

    print_info "Waiting for services to be ready..."
    sleep 5

    print_info "Checking service health..."
    docker-compose -f docker-compose.simple.yml ps
}

# Display access info
display_info() {
    echo ""
    echo "========================================"
    print_info "Services started successfully!"
    echo "========================================"
    echo ""
    echo "Access your services at:"
    echo "  - n8n: http://localhost:5678"
    echo "    ユーザー: admin"
    echo "    パスワード: admin"
    echo ""
    echo "  - Dify Console: http://localhost:3000"
    echo ""
    echo "  - Dify API: http://localhost:5001"
    echo ""
    echo "データ保存場所:"
    echo "  - n8n: Dockerボリューム (n8n_data)"
    echo "  - Dify: Dockerボリューム (dify_simple_db, dify_simple_storage)"
    echo ""
    echo "ログを確認:"
    echo "  docker-compose -f docker-compose.simple.yml logs -f"
    echo ""
    echo "サービスを停止:"
    echo "  docker-compose -f docker-compose.simple.yml down"
    echo ""
    echo "データも削除して停止:"
    echo "  docker-compose -f docker-compose.simple.yml down -v"
    echo ""
    print_info "より多くの機能が必要な場合は、標準版を使用してください:"
    echo "  ./scripts/start-local.sh"
    echo ""
    print_warning "この簡易版は開発・テスト用です。本番環境では標準版を推奨します。"
    echo ""
}

# Main
main() {
    print_info "Starting simple configuration (no PostgreSQL/Redis)..."

    check_docker
    check_env_file
    display_features

    read -p "この設定で起動しますか? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cancelled."
        exit 0
    fi

    start_services
    display_info
}

main "$@"
