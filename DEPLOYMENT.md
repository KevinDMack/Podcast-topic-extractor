# Deployment Guide

This guide walks you through deploying the Podcast Topic Extractor to Azure.

## Prerequisites

1. Azure subscription
2. Azure CLI installed and logged in (`az login`)
3. Terraform installed (version >= 1.0)
4. Python 3.11 or higher
5. Spotify Developer account

## Step-by-Step Deployment

### Step 1: Clone the Repository

```bash
git clone <repository-url>
cd Podcast-topic-extractor
```

### Step 2: Set Up Spotify Credentials

1. Visit [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account
3. Click "Create an App"
4. Fill in the app details:
   - App name: "Podcast Topic Extractor"
   - App description: "Extract topics from podcast episodes"
5. Accept the terms and create
6. Copy your **Client ID** and **Client Secret**

### Step 3: Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and add your Spotify credentials:

```hcl
spotify_client_id     = "your-actual-client-id"
spotify_client_secret = "your-actual-client-secret"

# Optional: customize these
resource_group_name = "podcast-topic-extractor-rg"
location            = "eastus"
environment         = "dev"
```

### Step 4: Deploy Infrastructure with Terraform

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply changes (create resources)
terraform apply
```

Type `yes` when prompted. This will take 5-10 minutes.

**Save the outputs!** Terraform will display important information:
- Function App name
- Function App URL
- Storage account name
- Resource group name

### Step 5: Deploy Function Code

#### Option A: Using Azure CLI

```bash
# Navigate to project root
cd ..

# Create deployment package (excluding unnecessary files)
zip -r function.zip . \
  -x "*.git*" \
  -x "terraform/*" \
  -x "*.pyc" \
  -x "*__pycache__*" \
  -x "*.tfstate*" \
  -x ".terraform/*"

# Get function app name from Terraform output
FUNCTION_APP_NAME=$(cd terraform && terraform output -raw function_app_name)
RESOURCE_GROUP=$(cd terraform && terraform output -raw resource_group_name)

# Deploy
az functionapp deployment source config-zip \
  -g $RESOURCE_GROUP \
  -n $FUNCTION_APP_NAME \
  --src function.zip

# Clean up zip file
rm function.zip
```

#### Option B: Using VS Code

1. Install the Azure Functions extension
2. Open the project in VS Code
3. Click on the Azure icon in the sidebar
4. Sign in to Azure
5. Right-click on the Function App and select "Deploy to Function App"
6. Select your Function App from the list

### Step 6: Get Function Keys

```bash
# Get the default (host) key
az functionapp keys list \
  -g $RESOURCE_GROUP \
  -n $FUNCTION_APP_NAME \
  --query "functionKeys.default" -o tsv
```

Save this key - you'll need it for API requests.

### Step 7: Test the Functions

Get your function URLs:

```bash
cd terraform
terraform output get_podcast_episodes_url
terraform output extract_keywords_url
```

#### Test GetPodcastEpisodes:

```bash
FUNCTION_URL="<get_podcast_episodes_url>"
FUNCTION_KEY="<your-function-key>"

curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "show_id": "4rOoJ6Egrf8K2IrywzwOMk",
    "start_date": "2024-01-01",
    "end_date": "2024-01-31"
  }'
```

#### Test ExtractKeywords:

```bash
EXTRACT_URL="<extract_keywords_url>"

# Get the blob name from the previous response
curl -X POST "${EXTRACT_URL}?code=${FUNCTION_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "blob_name": "episodes_4rOoJ6Egrf8K2IrywzwOMk_<timestamp>.json"
  }'
```

### Step 8: Verify Results in Blob Storage

```bash
# Get storage account name
STORAGE_ACCOUNT=$(cd terraform && terraform output -raw storage_account_name)

# List blobs
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name podcast-episodes \
  --output table
```

## Verification Checklist

- [ ] All Terraform resources created successfully
- [ ] Function App is running
- [ ] Key Vault contains secrets
- [ ] GetPodcastEpisodes function responds to requests
- [ ] ExtractKeywords function responds to requests
- [ ] Results are saved to Blob Storage
- [ ] Application Insights shows telemetry

## Troubleshooting

### Issue: "The subscription is not registered to use namespace 'Microsoft.CognitiveServices'"

**Solution:**
```bash
az provider register --namespace Microsoft.CognitiveServices
az provider show --namespace Microsoft.CognitiveServices --query "registrationState"
```
Wait for registration to complete (5-10 minutes), then re-run `terraform apply`.

### Issue: Function App deployment fails

**Solution:**
1. Check if the Function App exists:
   ```bash
   az functionapp show -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME
   ```
2. Try restarting the Function App:
   ```bash
   az functionapp restart -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME
   ```
3. Check logs:
   ```bash
   az functionapp log tail -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME
   ```

### Issue: "Unable to access Key Vault"

**Solution:**
The managed identity needs time to propagate. Wait 2-3 minutes after Terraform completes, then restart the Function App:
```bash
az functionapp restart -g $RESOURCE_GROUP -n $FUNCTION_APP_NAME
```

### Issue: Spotify API returns 401 Unauthorized

**Solution:**
1. Verify credentials in Key Vault:
   ```bash
   KEY_VAULT_NAME=$(cd terraform && terraform output -raw key_vault_name)
   az keyvault secret show --vault-name $KEY_VAULT_NAME --name spotify-client-id
   ```
2. Check Spotify Developer Dashboard to ensure app is active

## Cost Estimation

**Monthly costs (approximate, for dev environment):**
- Function App (Consumption): ~$0.20 (for moderate usage)
- Storage Account: ~$0.02/GB
- Text Analytics: ~$2.00 per 1000 text records
- Key Vault: ~$0.03
- Application Insights: ~$2.33 for first 5GB

**Total: ~$5-10/month** for development/testing

## Cleanup

To delete all resources and stop incurring costs:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. This will remove all Azure resources.

## Next Steps

1. Set up CI/CD pipeline for automated deployments
2. Add authentication to the API endpoints
3. Create a front-end application
4. Set up alerts in Application Insights
5. Implement rate limiting
6. Add more sophisticated text analysis (sentiment, entities, etc.)

## Support

For issues or questions:
1. Check the main README.md
2. Review Azure Portal logs
3. Check Application Insights for errors
4. Open an issue in the repository
