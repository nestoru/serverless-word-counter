import unittest
import requests
import os
import json

class TestWordCounter(unittest.TestCase):
    def setUp(self):
        self.api_endpoint = os.environ.get('API_ENDPOINT')
        if not self.api_endpoint:
            self.fail("API_ENDPOINT environment variable not set")
    
    def test_word_counting(self):
        # Test data
        payload = {
            "text": "This is a test. This test will test testing tests."
        }
        
        # Make request
        response = requests.post(self.api_endpoint, json=payload)
        self.assertEqual(response.status_code, 200)
        
        # Check response
        data = response.json()
        self.assertIn('download_url', data)
        self.assertIn('word_counts', data)
        
        # Verify word counts
        word_counts = data['word_counts']
        self.assertIn('test', word_counts)
        self.assertTrue(word_counts['test'] >= 2)
        
        # Verify download URL works
        result = requests.get(data['download_url'])
        self.assertEqual(result.status_code, 200)
    
    def test_empty_text(self):
        response = requests.post(self.api_endpoint, json={"text": ""})
        self.assertEqual(response.status_code, 400)
        self.assertIn('error', response.json())

if __name__ == '__main__':
    unittest.main()
