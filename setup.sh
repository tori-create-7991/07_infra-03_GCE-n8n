#!/bin/bash
set -e

echo "=== n8n on GCP Free Tier Setup ==="

# Check for Terraform
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform is not installed. Please install it first."
    exit 1
fi

# 1. Get Project ID
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
  echo "Error: No GCP Project ID found. Please set it using 'gcloud config set project <PROJECT_ID>'."
  exit 1
fi
echo "Using Project ID: $PROJECT_ID"

# 2. Get GitHub Repo
read -p "Enter GitHub Repository (owner/repo): " GITHUB_REPO
if [ -z "$GITHUB_REPO" ]; then
  echo "Error: Repository is required."
  exit 1
fi

# 3. Enable APIs
echo "Enabling required APIs (this may take a minute)..."
gcloud services enable compute.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com

# 4. Create State Bucket
BUCKET_NAME="n8n-tf-state-${PROJECT_ID}"
echo "Checking/Creating Terraform State Bucket: gs://${BUCKET_NAME}..."
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" &>/dev/null; then
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location=us-central1 --uniform-bucket-level-access
  echo "Bucket created."
else
  echo "Bucket already exists."
fi

# 5. Run Terraform
echo "Running Terraform..."
cd infra
terraform init -backend-config="bucket=${BUCKET_NAME}"
terraform apply -auto-approve -var="project_id=${PROJECT_ID}" -var="github_repo=${GITHUB_REPO}"

# 7. Output Results
echo ""
echo "=== Setup Complete ==="
echo "Please set the following secrets/variables in your GitHub Repository settings:"
echo ""
echo "Secrets:"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: $(terraform output -raw workload_identity_provider)"
echo "  GCP_SERVICE_ACCOUNT: $(terraform output -raw service_account_email)"
echo ""
echo "Variables:"
echo "  GCP_PROJECT_ID: ${PROJECT_ID}"
echo ""
echo "n8n IP Address: $(terraform output -raw n8n_ip)"
echo "Access n8n at: http://$(terraform output -raw n8n_ip):5678"
