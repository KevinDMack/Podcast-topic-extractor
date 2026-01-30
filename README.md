# Podcast Topic Extractor

A serverless solution that leverages Azure Functions and Cognitive Services to extract topics and keywords from podcast episodes using Spotify's API and Azure Text Analytics.

## Features

- **Fetch Podcast Episodes**: Retrieve all episodes of a podcast from Spotify within a specified date range
- **Keyword Extraction**: Analyze episode descriptions using Azure Text Analytics to extract key phrases and topics
- **Blob Storage**: Automatically store results in Azure Blob Storage
- **Managed Identity**: Secure access to Azure resources using system-assigned managed identities
- **Infrastructure as Code**: Complete Terraform configuration for deploying all Azure resources

## Architecture

The solution consists of:

1. **Azure Functions (Python 3.11)**:
   - `GetPodcastEpisodes`: Fetches podcast episodes from Spotify API
   - `ExtractKeywords`: Extracts keywords using Azure Text Analytics

2. **Azure Resources**:
   - Function App with System-Assigned Managed Identity
   - Blob Storage for storing episodes and keyword results
   - Text Analytics (Cognitive Services) for keyword extraction
   - Key Vault for secure credential storage
   - Application Insights for monitoring

## Prerequisites

- Python 3.11+
- Azure CLI
- Terraform 1.0+
- Spotify Developer Account (for API credentials)

## Setup

### 1. Get Spotify API Credentials

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Create a new app
3. Note down your Client ID and Client Secret

### 2. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
resource_group_name = "podcast-topic-extractor-rg"
location            = "eastus"
environment         = "dev"
spotify_client_id     = "your-spotify-client-id"
spotify_client_secret = "your-spotify-client-secret"
```

### 3. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Terraform will create:
- Resource Group
- Storage Account with Blob Container
- Function App with System-Assigned Managed Identity
- Text Analytics Cognitive Service
- Key Vault with secrets
- Role assignments for managed identity

### 4. Deploy Function Code

After infrastructure is deployed, package and deploy the function code:

```bash
# Install dependencies
pip install -r requirements.txt

# Package the function app
cd /path/to/Podcast-topic-extractor
zip -r function.zip . -x "*.git*" -x "terraform/*" -x "*.pyc" -x "__pycache__/*"

# Deploy using Azure CLI
az functionapp deployment source config-zip \
  -g <resource-group-name> \
  -n <function-app-name> \
  --src function.zip
```

Or use VS Code Azure Functions extension for easier deployment.

## Usage

### Get Podcast Episodes

Fetch episodes from a specific podcast within a date range:

```bash
curl -X POST "https://<function-app-url>/api/GetPodcastEpisodes?code=<function-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "show_id": "4rOoJ6Egrf8K2IrywzwOMk",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31"
  }'
```

Parameters:
- `show_id`: Spotify show/podcast ID (found in Spotify URL)
- `start_date`: Start date in ISO format (YYYY-MM-DD)
- `end_date`: End date in ISO format (YYYY-MM-DD)
- `limit`: (optional) Max episodes per request (default: 50)

Response includes episode details and they are automatically saved to Blob Storage.

### Extract Keywords

Extract keywords from episode descriptions:

```bash
# Option 1: From a blob containing episodes
curl -X POST "https://<function-app-url>/api/ExtractKeywords?code=<function-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "blob_name": "episodes_<show_id>_<timestamp>.json"
  }'

# Option 2: From direct text
curl -X POST "https://<function-app-url>/api/ExtractKeywords?code=<function-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Your podcast episode description here",
    "language": "en"
  }'
```

Results are automatically saved to Blob Storage with a timestamp.

## Project Structure

```
.
├── GetPodcastEpisodes/      # Function to fetch episodes from Spotify
│   ├── __init__.py
│   └── function.json
├── ExtractKeywords/         # Function to extract keywords
│   ├── __init__.py
│   └── function.json
├── terraform/               # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── resources.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── host.json
├── requirements.txt
├── local.settings.json.example
└── README.md
```

## Local Development

1. Copy `local.settings.json.example` to `local.settings.json`
2. Fill in your credentials
3. Install Azure Functions Core Tools
4. Run locally:

```bash
func start
```

## Security Features

- **System-Assigned Managed Identity**: Function App uses managed identity to access Azure resources
- **Key Vault Integration**: Secrets stored securely in Key Vault
- **Role-Based Access Control (RBAC)**: Minimal permissions assigned via role assignments:
  - Storage Blob Data Contributor for blob access
  - Cognitive Services User for Text Analytics
- **Private Blob Storage**: Container access is set to private

## Monitoring

- Application Insights is configured for monitoring and logging
- Function execution logs are available in Azure Portal
- Custom metrics can be added to track usage

## Cost Optimization

The solution uses:
- **Consumption Plan** for Function App (pay-per-execution)
- **Standard Storage** with LRS replication
- **S0 Tier** for Text Analytics (adjust based on usage)

## Cleanup

To remove all resources:

```bash
cd terraform
terraform destroy
```

## Troubleshooting

### Function App won't start
- Check Application Insights logs
- Verify Key Vault access policy is configured
- Ensure all required app settings are present

### Spotify API errors
- Verify credentials in Key Vault
- Check Spotify Developer Dashboard for API limits
- Ensure show_id is valid

### Text Analytics errors
- Verify endpoint and credentials
- Check text length (max 5120 characters per document)
- Ensure language is supported

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License
