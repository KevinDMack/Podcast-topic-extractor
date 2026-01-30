import logging
import json
import os
from datetime import datetime
import azure.functions as func
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient


def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Azure Function to extract keywords from podcast episode descriptions using Azure Text Analytics.
    
    Query parameters or JSON body:
    - text: Text to analyze (single episode description)
    - blob_name: Name of blob containing episodes JSON (from GetPodcastEpisodes)
    - language: Language code (default: "en")
    """
    logging.info('ExtractKeywords function triggered.')

    try:
        # Get parameters from request
        text = req.params.get('text')
        blob_name = req.params.get('blob_name')
        language = req.params.get('language', 'en')
        
        # Try to get from body if not in params
        if not text and not blob_name:
            try:
                req_body = req.get_json()
                text = text or req_body.get('text')
                blob_name = blob_name or req_body.get('blob_name')
                language = req_body.get('language', language)
            except ValueError:
                pass

        # Validate parameters
        if not text and not blob_name:
            return func.HttpResponse(
                "Please provide either 'text' or 'blob_name' parameter",
                status_code=400
            )

        # Initialize Text Analytics client
        endpoint = os.environ.get('TEXT_ANALYTICS_ENDPOINT')
        key = os.environ.get('TEXT_ANALYTICS_KEY')
        
        if not endpoint:
            logging.error("TEXT_ANALYTICS_ENDPOINT not configured in environment")
            return func.HttpResponse(
                "Service configuration error",
                status_code=500
            )

        # Use key or managed identity
        if key:
            credential = AzureKeyCredential(key)
        else:
            credential = DefaultAzureCredential()
        
        text_analytics_client = TextAnalyticsClient(
            endpoint=endpoint,
            credential=credential
        )

        # Process text or blob
        results = []
        
        if blob_name:
            # Fetch episodes from blob storage
            try:
                blob_container = os.environ.get('BLOB_CONTAINER_NAME', 'podcast-episodes')
                blob_connection_string = os.environ.get('BLOB_STORAGE_CONNECTION_STRING')
                
                if blob_connection_string:
                    blob_service_client = BlobServiceClient.from_connection_string(blob_connection_string)
                else:
                    account_url = os.environ.get('BLOB_STORAGE_ACCOUNT_URL')
                    blob_service_client = BlobServiceClient(
                        account_url=account_url,
                        credential=DefaultAzureCredential()
                    )
                
                blob_client = blob_service_client.get_blob_client(
                    container=blob_container,
                    blob=blob_name
                )
                
                blob_data = blob_client.download_blob().readall()
                episodes = json.loads(blob_data)
                
                logging.info(f"Loaded {len(episodes)} episodes from blob: {blob_name}")
                
                # Extract keywords for each episode
                errors = []
                for episode in episodes:
                    episode_text = f"{episode['name']}. {episode['description']}"
                    
                    # Limit text to 5120 characters (Text Analytics limit)
                    truncated = False
                    if len(episode_text) > 5120:
                        episode_text = episode_text[:5120]
                        truncated = True
                    
                    # Extract key phrases
                    response = text_analytics_client.extract_key_phrases(
                        documents=[{"id": episode['id'], "language": language, "text": episode_text}]
                    )
                    
                    for doc in response:
                        if not doc.is_error:
                            result = {
                                'episode_id': episode['id'],
                                'episode_name': episode['name'],
                                'release_date': episode['release_date'],
                                'key_phrases': doc.key_phrases
                            }
                            if truncated:
                                result['warning'] = 'Text was truncated to 5120 characters'
                            results.append(result)
                        else:
                            error_msg = f"Error analyzing episode {episode['id']}: {doc.error}"
                            logging.error(error_msg)
                            errors.append({
                                'episode_id': episode['id'],
                                'episode_name': episode['name'],
                                'error': 'Failed to extract keywords'
                            })
                
            except Exception as e:
                return func.HttpResponse(
                    f"Error reading from blob storage: {str(e)}",
                    status_code=500
                )
        else:
            # Process single text
            # Limit text to 5120 characters
            if len(text) > 5120:
                text = text[:5120]
            
            response = text_analytics_client.extract_key_phrases(
                documents=[{"id": "1", "language": language, "text": text}]
            )
            
            for doc in response:
                if not doc.is_error:
                    results.append({
                        'key_phrases': doc.key_phrases
                    })
                else:
                    return func.HttpResponse(
                        f"Error analyzing text: {doc.error}",
                        status_code=500
                    )

        # Store results in Blob Storage
        if results:
            try:
                blob_container = os.environ.get('BLOB_CONTAINER_NAME', 'podcast-episodes')
                blob_connection_string = os.environ.get('BLOB_STORAGE_CONNECTION_STRING')
                
                if blob_connection_string:
                    blob_service_client = BlobServiceClient.from_connection_string(blob_connection_string)
                else:
                    account_url = os.environ.get('BLOB_STORAGE_ACCOUNT_URL')
                    blob_service_client = BlobServiceClient(
                        account_url=account_url,
                        credential=DefaultAzureCredential()
                    )
                
                # Create blob name with timestamp
                timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
                output_blob_name = f"keywords_{timestamp}.json"
                
                # Upload to blob
                blob_client = blob_service_client.get_blob_client(
                    container=blob_container,
                    blob=output_blob_name
                )
                
                blob_data = json.dumps(results, indent=2)
                blob_client.upload_blob(blob_data, overwrite=True)
                
                logging.info(f"Uploaded keywords to blob: {output_blob_name}")
                
            except Exception as e:
                logging.warning(f"Failed to upload to blob storage: {str(e)}")

        # Return response
        response_data = {
            'results_count': len(results),
            'results': results
        }
        
        # Add errors if processing from blob
        if blob_name and 'errors' in locals() and errors:
            response_data['errors'] = errors
            response_data['errors_count'] = len(errors)

        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            mimetype="application/json",
            status_code=200
        )

    except Exception as e:
        logging.error(f"Error in ExtractKeywords: {str(e)}", exc_info=True)
        return func.HttpResponse(
            "An unexpected error occurred. Please check the logs or contact support.",
            status_code=500
        )
