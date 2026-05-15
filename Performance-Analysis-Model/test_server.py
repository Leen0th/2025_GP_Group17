import requests
import os

print("=" * 60)
print("Testing Haddaf Backend Server")
print("=" * 60)

# 1. Test /health
print("\n1. Testing /health endpoint...")
try:
    response = requests.get("http://localhost:5000/health", timeout=5)
    print(f"   Status Code: {response.status_code}")
    print(f"   Response: {response.json()}")
except Exception as e:
    print(f"   Error: {e}")

# 2. Test /analyze
print("\n2. Testing /analyze endpoint...")

# *** CHANGE THIS PATH TO YOUR LOCAL VIDEO FILE ***
video_path = r"C:\Users\ragha\OneDrive\Desktop\test_vid\test2.mp4"

if os.path.exists(video_path):
    print(f"   Found video: {video_path}")
    print("   Uploading and analyzing... (may take 1-2 minutes)")

    try:
        with open(video_path, 'rb') as f:
            files = {'video': f}
            # Use normalized coordinates (0.0 to 1.0)
            # Run get_coords.py first to find the correct x, y values
            data = {
                'x': 0.0820,     # <-- Replace with your normalized x from get_coords.py
                'y': 0.5236,     # <-- Replace with your normalized y from get_coords.py
                'width': 1920,   # <-- Replace with your video's width
                'height': 1080,  # <-- Replace with your video's height
            }

            response = requests.post(
                "http://localhost:5000/analyze",
                files=files,
                data=data,
                timeout=3600
            )

        print(f"   Status Code: {response.status_code}")

        if response.status_code == 200:
            result = response.json()
            print(f"\n   Action Counts:")
            for action, count in result.get('action_counts', {}).items():
                print(f"      {action}: {count}")
            print(f"\n   View crops at: {result.get('crops_url', 'N/A')}")
            print(f"   Total crops:   {result.get('total_crops', 0)}")
        else:
            print(f"   Error: {response.text}")

    except Exception as e:
        print(f"   Error: {e}")
else:
    print(f"   Video not found: {video_path}")
    print(f"   Please update the video_path variable in this file.")
    print(f"   Current working directory: {os.getcwd()}")

print("\n" + "=" * 60)
print("Testing complete!")
print("=" * 60)