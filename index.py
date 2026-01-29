import json
import boto3
import os
import uuid

def lambda_handler(event, context):
    # 1. LOG THE EVENT (This is your best friend for debugging)
    print("FULL EVENT RECEIVED:", json.dumps(event))
    
    transcribe = boto3.client('transcribe')
    output_bucket = os.environ.get('OUTPUT_BUCKET')

    # 2. CHECK FOR THE 'Records' KEY
    if 'Records' not in event:
        print("This is not a standard S3 event (e.g., Console Test or S3 Test Notification).")
        return { 'status': 'ignored', 'reason': 'No Records key found' }

    try:
        # 3. EXTRACT FILE INFO
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        # Ignore folder creations (keys ending in /)
        if key.endswith('/'):
            return { 'status': 'ignored', 'reason': 'Folder creation' }

        print(f"Processing file: s3://{bucket}/{key}")

        # 4. START TRANSCRIBE JOB
        job_name = f"Job-{uuid.uuid4().hex}"
        file_uri = f"s3://{bucket}/{key}"
        
        transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': file_uri},
            MediaFormat=key.split('.')[-1], # mp3, wav, etc.
            LanguageCode='en-US',
            OutputBucketName=output_bucket
        )
        
        print(f"Started job: {job_name}")
        return { 'status': 'success', 'job': job_name }

    except Exception as e:
        print(f"Error processing record: {str(e)}")
        raise e