import requests

try:
    response = requests.post(
        "http://localhost:8000/speak",
        json={
            "text": "Hello world",
            "voice": "af_bella",
            "speed": 1.0,
            "volume": 1.0
        }
    )
    print(f"Status: {response.status_code}")
    print(f"Body: {response.text}")
except Exception as e:
    print(f"Error: {e}")
