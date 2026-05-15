"""
get_coords.py
--------------
Run this script to click on a player in the first frame of your video
and get the normalized (x, y) coordinates to use in test_server.py.

Usage:
    python get_coords.py

Then update the video_path below to point to your video file.
"""

import cv2

# *** CHANGE THIS to your video path ***
video_path = r"C:\Users\ragha\OneDrive\Desktop\test_vid\test11.mp4"


def click_event(event, x, y, flags, params):
    if event == cv2.EVENT_LBUTTONDOWN:
        h, w = params
        norm_x = x / w
        norm_y = y / h

        print("\n" + "="*40)
        print(f"Clicked pixel:     ({x}, {y})")
        print(f"Video dimensions:  {w} x {h}")
        print("-" * 40)
        print("Copy these values into test_server.py:")
        print(f"   'x': {norm_x:.4f}")
        print(f"   'y': {norm_y:.4f}")
        print(f"   'width': {w}")
        print(f"   'height': {h}")
        print("=" * 40 + "\n")


cap = cv2.VideoCapture(video_path)
ret, frame = cap.read()
cap.release()

if ret:
    h, w, _ = frame.shape
    print(f"Loaded video frame: {w}x{h}")
    print("Click on the player you want to track.")
    print("Press any key to exit.")

    cv2.imshow('Select Target Player - Click to get coordinates', frame)
    cv2.setMouseCallback('Select Target Player - Click to get coordinates', click_event, (h, w))
    cv2.waitKey(0)
    cv2.destroyAllWindows()
else:
    print(f"Could not read video: {video_path}")
    print("Please check the video_path variable.")