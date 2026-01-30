import logging
import json
import os
from datetime import datetime
from dateutil import parser
import azure.functions as func
import spotipy
from spotipy.oauth2 import SpotifyClientCredentials
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential


def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Azure Function to fetch podcast episodes from Spotify API within a date range.
    
    Query parameters:
    - show_id: Spotify show (podcast) ID
    - start_date: Start date in ISO format (YYYY-MM-DD)
    - end_date: End date in ISO format (YYYY-MM-DD)
    - limit: Maximum number of episodes to fetch (default: 50, max: 50 per request)
    """
    logging.info('GetPodcastEpisodes function triggered.')

    try:
        # Get parameters from request
        show_id = req.params.get('show_id')
        start_date_str = req.params.get('start_date')
        end_date_str = req.params.get('end_date')
        limit = req.params.get('limit', '50')
        
        # Try to get from body if not in params
        if not show_id or not start_date_str or not end_date_str:
            try:
                req_body = req.get_json()
                show_id = show_id or req_body.get('show_id')
                start_date_str = start_date_str or req_body.get('start_date')
                end_date_str = end_date_str or req_body.get('end_date')
                limit = req_body.get('limit', limit)
            except ValueError:
                pass

        # Validate required parameters
        if not show_id:
            return func.HttpResponse(
                "Please provide 'show_id' parameter",
                status_code=400
            )
        
        if not start_date_str or not end_date_str:
            return func.HttpResponse(
                "Please provide 'start_date' and 'end_date' parameters in ISO format (YYYY-MM-DD)",
                status_code=400
            )

        # Parse dates
        try:
            start_date = parser.parse(start_date_str).date()
            end_date = parser.parse(end_date_str).date()
        except Exception as e:
            return func.HttpResponse(
                f"Invalid date format. Please use ISO format (YYYY-MM-DD): {str(e)}",
                status_code=400
            )

        if start_date > end_date:
            return func.HttpResponse(
                "start_date must be before or equal to end_date",
                status_code=400
            )

        # Get Spotify credentials
        client_id = os.environ.get('SPOTIFY_CLIENT_ID')
        client_secret = os.environ.get('SPOTIFY_CLIENT_SECRET')
        
        if not client_id or not client_secret:
            logging.error("Spotify credentials not configured in environment")
            return func.HttpResponse(
                "Service configuration error",
                status_code=500
            )

        # Initialize Spotify client
        auth_manager = SpotifyClientCredentials(
            client_id=client_id,
            client_secret=client_secret
        )
        sp = spotipy.Spotify(auth_manager=auth_manager)

        # Validate limit parameter
        try:
            limit_int = int(limit)
            if limit_int <= 0 or limit_int > 50:
                return func.HttpResponse(
                    "limit must be a positive integer between 1 and 50",
                    status_code=400
                )
        except ValueError:
            return func.HttpResponse(
                "limit must be a valid integer",
                status_code=400
            )
        
        # Fetch episodes
        episodes = []
        offset = 0
        limit_per_request = limit_int
        max_iterations = 100  # Safety limit to prevent infinite loops
        iteration_count = 0
        
        while iteration_count < max_iterations:
            results = sp.show_episodes(
                show_id,
                limit=limit_per_request,
                offset=offset
            )
            
            if not results['items']:
                break
            
            for episode in results['items']:
                # Parse release date
                release_date = parser.parse(episode['release_date']).date()
                
                # Filter by date range
                if start_date <= release_date <= end_date:
                    episode_data = {
                        'id': episode['id'],
                        'name': episode['name'],
                        'description': episode['description'],
                        'release_date': episode['release_date'],
                        'duration_ms': episode['duration_ms'],
                        'language': episode.get('language', 'unknown'),
                        'explicit': episode['explicit'],
                        'uri': episode['uri'],
                        'external_urls': episode['external_urls']
                    }
                    episodes.append(episode_data)
            
            # Check if there are more episodes
            if results['next'] is None:
                break
            
            offset += limit_per_request
            iteration_count += 1
        
        if iteration_count >= max_iterations:
            logging.warning(f"Reached maximum iteration limit ({max_iterations}) when fetching episodes")

        # Store results in Blob Storage
        blob_container = os.environ.get('BLOB_CONTAINER_NAME', 'podcast-episodes')
        
        # Try to use managed identity first, fall back to connection string
        try:
            blob_connection_string = os.environ.get('BLOB_STORAGE_CONNECTION_STRING')
            if blob_connection_string:
                blob_service_client = BlobServiceClient.from_connection_string(blob_connection_string)
            else:
                # Use managed identity
                account_url = os.environ.get('BLOB_STORAGE_ACCOUNT_URL')
                credential = DefaultAzureCredential()
                blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
            
            # Create blob name with timestamp
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            blob_name = f"episodes_{show_id}_{timestamp}.json"
            
            # Upload to blob
            blob_client = blob_service_client.get_blob_client(
                container=blob_container,
                blob=blob_name
            )
            
            blob_data = json.dumps(episodes, indent=2)
            blob_client.upload_blob(blob_data, overwrite=True)
            
            logging.info(f"Uploaded {len(episodes)} episodes to blob: {blob_name}")
            
        except Exception as e:
            logging.warning(f"Failed to upload to blob storage: {str(e)}")

        # Return response
        response_data = {
            'show_id': show_id,
            'start_date': start_date_str,
            'end_date': end_date_str,
            'episodes_count': len(episodes),
            'episodes': episodes
        }

        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            mimetype="application/json",
            status_code=200
        )

    except Exception as e:
        logging.error(f"Error in GetPodcastEpisodes: {str(e)}", exc_info=True)
        return func.HttpResponse(
            "An unexpected error occurred. Please check the logs or contact support.",
            status_code=500
        )
