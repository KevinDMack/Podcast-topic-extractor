# Architecture and Design Decisions

## Overview

This document explains the architectural decisions made in building the Podcast Topic Extractor solution.

## System Architecture

```
┌─────────────────┐
│   User/Client   │
└────────┬────────┘
         │ HTTPS
         ▼
┌─────────────────────────────────────────┐
│      Azure Function App                 │
│  ┌─────────────────────────────────┐   │
│  │  GetPodcastEpisodes Function    │   │
│  │  - Fetches from Spotify API     │   │
│  │  - Stores in Blob Storage       │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  ExtractKeywords Function       │   │
│  │  - Reads from Blob Storage      │   │
│  │  - Calls Text Analytics         │   │
│  │  - Stores results in Blob       │   │
│  └─────────────────────────────────┘   │
└─────────┬────────────────┬──────────────┘
          │                │
          │                │
  ┌───────▼─────┐   ┌──────▼────────────┐
  │   Spotify   │   │  Azure Text       │
  │   API       │   │  Analytics        │
  └─────────────┘   └───────────────────┘
          │                │
          │                │
          └────────┬───────┘
                   ▼
         ┌──────────────────┐
         │  Blob Storage    │
         │  - Episodes      │
         │  - Keywords      │
         └──────────────────┘
```

## Design Decisions

### 1. Serverless Architecture (Azure Functions)

**Decision:** Use Azure Functions Consumption Plan

**Rationale:**
- **Cost-effective**: Pay only for actual execution time
- **Auto-scaling**: Handles variable load automatically
- **Low maintenance**: No server management required
- **Quick deployment**: Fast to develop and deploy

**Alternatives Considered:**
- Azure App Service: More expensive for intermittent workloads
- Container-based solutions: More complex, overkill for simple functions

### 2. Separate Functions for Each Operation

**Decision:** Create two independent functions instead of one monolithic function

**Rationale:**
- **Single Responsibility Principle**: Each function does one thing well
- **Independent scaling**: Functions scale based on their own demand
- **Easier testing and maintenance**: Smaller, focused codebases
- **Flexibility**: Can be invoked independently or chained

**Workflow:**
```
User → GetPodcastEpisodes → Blob Storage → ExtractKeywords → Blob Storage
```

### 3. System-Assigned Managed Identity

**Decision:** Use managed identity instead of connection strings/keys

**Rationale:**
- **Security**: No credentials in code or configuration
- **Automatic rotation**: Azure handles credential rotation
- **Least privilege**: Fine-grained RBAC permissions
- **Audit trail**: Better tracking of resource access

**Permissions Granted:**
- Storage Blob Data Contributor (for blob access)
- Cognitive Services User (for Text Analytics)
- Key Vault Secrets Get/List (for retrieving Spotify credentials)

### 4. Azure Key Vault for Secrets

**Decision:** Store Spotify credentials in Key Vault

**Rationale:**
- **Centralized secret management**: Single source of truth
- **Access control**: Control who can read secrets
- **Audit logging**: Track secret access
- **Integration**: Native integration with Function Apps

**Secrets Stored:**
- Spotify Client ID
- Spotify Client Secret
- Text Analytics Key (as backup)

### 5. Blob Storage for Data Persistence

**Decision:** Use Azure Blob Storage for storing episodes and results

**Rationale:**
- **Cost-effective**: Cheapest storage option for unstructured data
- **Scalable**: Handles any amount of data
- **Durable**: Built-in redundancy (LRS/GRS)
- **Integration**: Native support in Azure Functions
- **Versioning**: Enabled to track changes

**Alternative Considered:**
- Azure Cosmos DB: Too expensive for simple JSON storage
- Azure SQL: Overkill for unstructured podcast data

### 6. Infrastructure as Code (Terraform)

**Decision:** Use Terraform for infrastructure deployment

**Rationale:**
- **Reproducibility**: Consistent deployments across environments
- **Version control**: Infrastructure changes tracked in Git
- **Documentation**: Code serves as documentation
- **Multi-cloud**: Terraform works with multiple cloud providers

**What Terraform Manages:**
- Resource Group
- Storage Account and Container
- Function App with App Service Plan
- Text Analytics Cognitive Service
- Key Vault and Secrets
- Managed Identity and Role Assignments
- Application Insights

### 7. Python as Implementation Language

**Decision:** Use Python 3.11 for Azure Functions

**Rationale:**
- **Rich ecosystem**: Excellent libraries for API interaction (spotipy, requests)
- **Azure SDK**: First-class Python support
- **Readability**: Clean, maintainable code
- **Data processing**: Strong for JSON manipulation

### 8. HTTP Triggers for Functions

**Decision:** Use HTTP triggers instead of other trigger types

**Rationale:**
- **Flexibility**: Can be called from anywhere (API, UI, CLI)
- **Direct invocation**: Synchronous responses
- **Testing**: Easy to test with curl or Postman

**Alternative Considered:**
- Timer trigger: Would require more complex orchestration
- Queue trigger: Adds unnecessary complexity for direct API calls

### 9. Date Range Filtering

**Decision:** Filter episodes by date range in application code

**Rationale:**
- **Spotify API limitation**: API doesn't support date filtering
- **Efficiency**: Only process relevant episodes
- **Flexibility**: User controls the date range

**Implementation:**
- Fetch all episodes
- Filter by date in Python
- Return only matching episodes

### 10. Text Analytics Key Phrase Extraction

**Decision:** Use Key Phrase Extraction over other NLP techniques

**Rationale:**
- **Simplicity**: One API call per document
- **Quality**: Azure's pre-trained models are high quality
- **Language support**: Supports 10+ languages
- **Cost**: Reasonable pricing for moderate usage

**Alternatives Considered:**
- Custom ML model: Too complex, expensive to train/maintain
- Entity recognition: Key phrases are more flexible
- Sentiment analysis: Not required for this use case

### 11. Versioning and Naming Conventions

**Decision:** Include timestamps in blob names

**Rationale:**
- **Uniqueness**: Prevents overwriting
- **Traceability**: Easy to find when data was created
- **Debugging**: Helps correlate data with logs

**Format:**
```
episodes_{show_id}_{timestamp}.json
keywords_{timestamp}.json
```

### 12. Error Handling Strategy

**Decision:** Return detailed error messages in development, log internally

**Rationale:**
- **Developer experience**: Clear errors aid debugging
- **Security**: Don't expose internal details in production
- **Observability**: Application Insights captures all errors

**Error Handling:**
- Input validation → 400 Bad Request
- External API errors → 500 Internal Server Error
- All errors logged to Application Insights

## Security Considerations

### 1. Authentication & Authorization

- Function keys required for API calls
- Managed identity for Azure resource access
- Key Vault for secret storage

### 2. Data Protection

- HTTPS enforced for all communications
- Private blob container (no public access)
- Encryption at rest (Azure default)

### 3. Principle of Least Privilege

- Function App has minimal required permissions
- No over-privileged service principals
- Role-based access control (RBAC)

## Performance Considerations

### 1. Consumption Plan Limits

- **Execution time**: 5-minute timeout (configurable to 10)
- **Memory**: 1.5 GB per instance
- **Concurrency**: Up to 200 concurrent executions

### 2. API Rate Limits

- **Spotify**: Respects API rate limits (pagination)
- **Text Analytics**: S0 tier = 1000 requests/minute

### 3. Optimization Strategies

- Pagination for large episode lists
- Batch processing for keyword extraction
- Async storage uploads (non-blocking)

## Scalability

The solution scales automatically:

1. **Horizontal scaling**: Function instances spin up on demand
2. **Storage scaling**: Blob storage scales to petabytes
3. **Text Analytics**: Automatically scales within tier limits

## Cost Breakdown

**Estimated monthly costs (dev environment, light usage):**

- Function App (Consumption): $0.20
- Storage Account: $0.02/GB
- Text Analytics (S0): $2.00/1000 records
- Key Vault: $0.03
- Application Insights: $2.33 (first 5GB free)

**Total**: ~$5-10/month for development

**Production scaling:**
- Costs scale linearly with usage
- Consider reserved capacity for high volume
- Monitor and set budget alerts

## Future Enhancements

Potential improvements:

1. **Authentication**: Add Azure AD authentication
2. **Webhooks**: Support Spotify webhooks for new episodes
3. **Batch processing**: Process multiple shows at once
4. **Caching**: Redis cache for frequently accessed data
5. **Analytics**: Add custom metrics and dashboards
6. **Advanced NLP**: Entity recognition, sentiment analysis
7. **API Gateway**: Azure API Management for rate limiting
8. **Queue-based**: Use Storage Queues for async processing

## Monitoring and Observability

### Application Insights Integration

- Request/response logging
- Performance metrics
- Dependency tracking (Spotify, Text Analytics)
- Custom events and metrics

### Key Metrics to Monitor

- Function execution count
- Average execution duration
- Error rate
- Spotify API latency
- Text Analytics API latency
- Blob storage operations

## Disaster Recovery

### Backup Strategy

- Blob Storage: Versioning enabled (can restore previous versions)
- Key Vault: Soft delete enabled (90-day recovery window)
- Infrastructure: Terraform state in source control

### Recovery Time Objective (RTO)

- Infrastructure: ~10 minutes (Terraform redeploy)
- Data: Immediate (blob versioning)
- Secrets: ~5 minutes (Key Vault recovery)

## Testing Strategy

### Manual Testing

- Use provided sample-requests.json
- Test via Azure Portal (Function App test UI)
- curl commands from command line

### Automated Testing (Future)

- Unit tests for core logic
- Integration tests with test resources
- End-to-end tests in CI/CD pipeline

## Compliance and Privacy

- **Data residency**: Deployed to specific Azure region
- **GDPR**: Podcast metadata is public domain
- **Spotify ToS**: Complies with Spotify Developer Terms
- **Azure compliance**: Inherits Azure certifications

## Conclusion

This architecture balances simplicity, cost, security, and scalability. It leverages Azure's managed services to minimize operational overhead while maintaining flexibility for future enhancements.
