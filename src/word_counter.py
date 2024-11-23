import json
from collections import Counter
import boto3
import os
import re
from datetime import datetime

def lambda_handler(event, context):
    try:
        # Get text from request
        body = json.loads(event['body'])
        text = body.get('text', '')
        
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'No text provided'})
            }
        
        # Process text
        words = re.sub(r'[^\w\s]', '', text.lower()).split()
        word_counts = Counter(words)
        top_10 = dict(word_counts.most_common(10))
        
        # Save to S3
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"word_counts_{timestamp}_{context.aws_request_id}.json"
        
        s3 = boto3.client('s3')
        bucket_name = os.environ['BUCKET_NAME']
        
        s3.put_object(
            Bucket=bucket_name,
            Key=filename,
            Body=json.dumps(top_10, indent=2),
            ContentType='application/json'
        )
        
        # Generate download URL
        url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket_name, 'Key': filename},
            ExpiresIn=3600
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'download_url': url,
                'word_counts': top_10
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
