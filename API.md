# API Documentation

## Overview

The Podcast Topic Extractor provides two main API endpoints for fetching podcast episodes and extracting keywords from their descriptions.

## Base URL

```
https://<your-function-app-name>.azurewebsites.net/api
```

## Authentication

All endpoints require a function key to be passed as a query parameter:

```
?code=<your-function-key>
```

Get your function key from Azure Portal or using Azure CLI:
```bash
az functionapp keys list -g <resource-group> -n <function-app-name>
```

## Endpoints

### 1. Get Podcast Episodes

Fetches podcast episodes from Spotify within a specified date range.

**Endpoint:** `/GetPodcastEpisodes`

**Method:** `GET` or `POST`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| show_id | string | Yes | Spotify show/podcast ID (from Spotify URL) |
| start_date | string | Yes | Start date in ISO format (YYYY-MM-DD) |
| end_date | string | Yes | End date in ISO format (YYYY-MM-DD) |
| limit | integer | No | Max episodes per request (default: 50) |

**Example Request (JSON body):**

```bash
curl -X POST "https://your-function-app.azurewebsites.net/api/GetPodcastEpisodes?code=YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "show_id": "4rOoJ6Egrf8K2IrywzwOMk",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "limit": 50
  }'
```

**Example Request (Query parameters):**

```bash
curl "https://your-function-app.azurewebsites.net/api/GetPodcastEpisodes?code=YOUR_KEY&show_id=4rOoJ6Egrf8K2IrywzwOMk&start_date=2024-01-01&end_date=2024-12-31"
```

**Response:**

```json
{
  "show_id": "4rOoJ6Egrf8K2IrywzwOMk",
  "start_date": "2024-01-01",
  "end_date": "2024-12-31",
  "episodes_count": 10,
  "episodes": [
    {
      "id": "episode-id-123",
      "name": "Episode Title",
      "description": "Episode description...",
      "release_date": "2024-01-15",
      "duration_ms": 3600000,
      "language": "en",
      "explicit": false,
      "uri": "spotify:episode:episode-id-123",
      "external_urls": {
        "spotify": "https://open.spotify.com/episode/episode-id-123"
      }
    }
  ]
}
```

**Side Effects:**
- Episodes are automatically saved to Blob Storage as `episodes_{show_id}_{timestamp}.json`

**Error Responses:**

- `400 Bad Request`: Missing or invalid parameters
- `500 Internal Server Error`: Spotify API error or configuration issue

---

### 2. Extract Keywords

Extracts keywords and key phrases from podcast episode descriptions using Azure Text Analytics.

**Endpoint:** `/ExtractKeywords`

**Method:** `GET` or `POST`

**Parameters (Option 1 - Analyze from Blob):**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| blob_name | string | Yes* | Name of blob containing episodes JSON |
| language | string | No | Language code (default: "en") |

**Parameters (Option 2 - Analyze Direct Text):**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| text | string | Yes* | Text to analyze (max 5120 characters) |
| language | string | No | Language code (default: "en") |

*Either `blob_name` or `text` must be provided

**Example Request (from blob):**

```bash
curl -X POST "https://your-function-app.azurewebsites.net/api/ExtractKeywords?code=YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "blob_name": "episodes_4rOoJ6Egrf8K2IrywzwOMk_20240130_120000.json",
    "language": "en"
  }'
```

**Example Request (direct text):**

```bash
curl -X POST "https://your-function-app.azurewebsites.net/api/ExtractKeywords?code=YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "In this episode, we discuss machine learning, artificial intelligence, and the future of technology in healthcare.",
    "language": "en"
  }'
```

**Response (from blob):**

```json
{
  "results_count": 10,
  "results": [
    {
      "episode_id": "episode-id-123",
      "episode_name": "Episode Title",
      "release_date": "2024-01-15",
      "key_phrases": [
        "machine learning",
        "artificial intelligence",
        "healthcare technology",
        "data science"
      ]
    }
  ]
}
```

**Response (direct text):**

```json
{
  "results_count": 1,
  "results": [
    {
      "key_phrases": [
        "machine learning",
        "artificial intelligence",
        "future of technology",
        "healthcare"
      ]
    }
  ]
}
```

**Side Effects:**
- Results are automatically saved to Blob Storage as `keywords_{timestamp}.json`

**Error Responses:**

- `400 Bad Request`: Missing parameters or invalid input
- `500 Internal Server Error`: Text Analytics error or configuration issue

---

## Typical Workflow

### Step 1: Fetch Podcast Episodes

```bash
curl -X POST "https://your-app.azurewebsites.net/api/GetPodcastEpisodes?code=KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "show_id": "4rOoJ6Egrf8K2IrywzwOMk",
    "start_date": "2024-01-01",
    "end_date": "2024-01-31"
  }'
```

Note the blob file saved (check logs or Blob Storage).

### Step 2: Extract Keywords from Episodes

```bash
curl -X POST "https://your-app.azurewebsites.net/api/ExtractKeywords?code=KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "blob_name": "episodes_4rOoJ6Egrf8K2IrywzwOMk_20240130_120000.json"
  }'
```

### Step 3: Download Results

Use Azure Storage Explorer or Azure CLI to download the results:

```bash
az storage blob download \
  --account-name <storage-account> \
  --container-name podcast-episodes \
  --name keywords_20240130_120500.json \
  --file keywords.json
```

---

## Finding Spotify Show IDs

To get the `show_id` for a podcast:

1. Open Spotify and find your podcast
2. Right-click on the podcast → Share → Copy Show Link
3. The URL will look like: `https://open.spotify.com/show/4rOoJ6Egrf8K2IrywzwOMk`
4. The show_id is the last part: `4rOoJ6Egrf8K2IrywzwOMk`

---

## Supported Languages

Azure Text Analytics supports many languages. Common codes:

- `en` - English
- `es` - Spanish
- `fr` - French
- `de` - German
- `it` - Italian
- `pt` - Portuguese
- `ja` - Japanese
- `ko` - Korean
- `zh` - Chinese

Full list: https://docs.microsoft.com/en-us/azure/cognitive-services/language-service/key-phrase-extraction/language-support

---

## Rate Limits

- **Spotify API**: 
  - Rate limits vary based on your Spotify app
  - Typically allows thousands of requests per day
  
- **Azure Text Analytics**:
  - S0 tier: 1000 text records per minute
  - Adjust based on your pricing tier

- **Azure Functions**:
  - Consumption plan has no specific limits
  - Subject to Azure subscription limits

---

## Error Codes

### HTTP Status Codes

- `200 OK`: Request successful
- `400 Bad Request`: Invalid parameters or request format
- `401 Unauthorized`: Invalid or missing function key
- `500 Internal Server Error`: Server-side error (check logs)
- `503 Service Unavailable`: Function app is starting or unavailable

### Common Errors

**"Spotify credentials not configured"**
- Check Key Vault has spotify-client-id and spotify-client-secret
- Verify Function App has access to Key Vault

**"TEXT_ANALYTICS_ENDPOINT not configured"**
- Check Function App environment variables
- Verify Text Analytics service is deployed

**"Error reading from blob storage"**
- Verify blob name is correct
- Check Function App has Storage Blob Data Contributor role

---

## Best Practices

1. **Pagination**: For podcasts with many episodes, use the limit parameter to control response size

2. **Error Handling**: Always check response status codes and handle errors appropriately

3. **Caching**: Consider caching episode data to reduce Spotify API calls

4. **Monitoring**: Use Application Insights to monitor function performance and errors

5. **Security**: Keep your function keys secure and rotate them regularly

---

## Support

For issues or questions:
- Check Application Insights logs in Azure Portal
- Review DEPLOYMENT.md for troubleshooting
- Check README.md for general information
