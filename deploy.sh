#!/bin/bash

# Deployment script for Podcast Topic Extractor
# This script automates the deployment of the Azure Functions app

set -e  # Exit on error

echo "🚀 Podcast Topic Extractor - Deployment Script"
echo "=============================================="
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first."
    echo "   Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install it first."
    echo "   Visit: https://www.terraform.io/downloads"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install it first."
    exit 1
fi

echo "✅ All prerequisites are installed"
echo ""

# Check Azure login
echo "🔐 Checking Azure login status..."
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Running 'az login'..."
    az login
fi

SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "✅ Logged in to Azure"
echo "   Subscription: $SUBSCRIPTION_NAME"
echo ""

# Navigate to terraform directory
cd terraform

# Check if terraform.tfvars exists
if [ ! -f terraform.tfvars ]; then
    echo "⚠️  terraform.tfvars not found!"
    echo "   Creating from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo ""
    echo "📝 Please edit terraform/terraform.tfvars with your Spotify credentials"
    echo "   Get credentials from: https://developer.spotify.com/dashboard"
    echo ""
    read -p "Press Enter after you've updated terraform.tfvars..."
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init
echo ""

# Plan
echo "📊 Planning infrastructure..."
terraform plan -out=tfplan
echo ""

# Confirm deployment
read -p "🤔 Do you want to apply these changes? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

# Apply
echo "🏗️  Creating Azure resources..."
terraform apply tfplan
echo ""

# Get outputs
echo "📝 Saving deployment information..."
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
FUNCTION_URL=$(terraform output -raw function_app_url)

echo "✅ Infrastructure deployed successfully!"
echo ""
echo "   Function App: $FUNCTION_APP_NAME"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   URL: $FUNCTION_URL"
echo ""

# Navigate back to root
cd ..

# Deploy function code
echo "📦 Packaging function code..."
zip -r function.zip . \
  -x "*.git*" \
  -x "terraform/*" \
  -x "*.pyc" \
  -x "*__pycache__*" \
  -x "*.tfstate*" \
  -x ".terraform/*" \
  -x "function.zip" \
  -q

echo "☁️  Deploying function code to Azure..."
az functionapp deployment source config-zip \
  -g "$RESOURCE_GROUP" \
  -n "$FUNCTION_APP_NAME" \
  --src function.zip

# Clean up
rm function.zip

echo ""
echo "⏳ Waiting for deployment to complete..."
sleep 10

# Restart function app to ensure everything loads
echo "🔄 Restarting Function App..."
az functionapp restart -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME"

echo ""
echo "✨ Deployment completed successfully!"
echo ""
echo "📌 Next steps:"
echo "   1. Get your function key:"
echo "      az functionapp keys list -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME"
echo ""
echo "   2. Test GetPodcastEpisodes:"
echo "      curl -X POST \"$FUNCTION_URL/api/GetPodcastEpisodes?code=YOUR_FUNCTION_KEY\" \\"
echo "        -H \"Content-Type: application/json\" \\"
echo "        -d '{\"show_id\":\"4rOoJ6Egrf8K2IrywzwOMk\",\"start_date\":\"2024-01-01\",\"end_date\":\"2024-01-31\"}'"
echo ""
echo "   3. Monitor in Azure Portal:"
echo "      https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
echo ""
echo "🎉 Happy podcasting!"
