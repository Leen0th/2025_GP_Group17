#!/usr/bin/env python3
"""
Download models from Hugging Face Hub into the local models/ directory.
This runs automatically before the server starts.
"""
import os
from huggingface_hub import hf_hub_download

REPO_ID = "lujain-721/Haddaf_New_Model"

MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
os.makedirs(MODELS_DIR, exist_ok=True)

FILES = [
    "detect_best.pt",
    "pose_best.pt",
    "feature_scaler_lgbm.joblib",
    "label_encoder_lgbm.joblib",
]

def download_models():
    for filename in FILES:
        dest = os.path.join(MODELS_DIR, filename)
        if os.path.exists(dest):
            print(f"✅ Already exists: {filename}")
            continue
        print(f"⬇️  Downloading {filename} from {REPO_ID}...")
        hf_hub_download(
            repo_id=REPO_ID,
            filename=filename,
            local_dir=MODELS_DIR,
        )
        print(f"✅ Downloaded: {filename}")

if __name__ == "__main__":
    download_models()
    print("All models ready.")
