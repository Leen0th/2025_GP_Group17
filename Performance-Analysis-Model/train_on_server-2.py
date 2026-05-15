#!/usr/bin/env python3
"""
Train the ensemble classifier directly on the server.
Runs once if best_ensemble_classifier_final.pkl doesn't exist.
"""
import os
import numpy as np
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier, VotingClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight
from lightgbm import LGBMClassifier
from huggingface_hub import hf_hub_download, HfApi
import warnings
warnings.filterwarnings('ignore')

BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(BASE_DIR, "models")
HF_REPO_ID = "lujain-721/Haddaf_New_Model"
CSV_FILE   = "pose_features_v10.csv"
OUT_MODEL  = os.path.join(MODELS_DIR, "best_ensemble_classifier_final.pkl")

def train():
    print("=" * 60)
    print("Training ensemble classifier on server...")
    print("=" * 60)

    # Download CSV from Hugging Face
    csv_path = os.path.join(MODELS_DIR, CSV_FILE)
    if not os.path.exists(csv_path):
        print(f"Downloading {CSV_FILE} from Hugging Face...")
        hf_hub_download(repo_id=HF_REPO_ID, filename=CSV_FILE, local_dir=MODELS_DIR)
        print("Downloaded!")

    # Load data
    df = pd.read_csv(csv_path)
    print(f"Loaded: {len(df)} samples")

    X = df.drop(['tag', 'action_class'], axis=1)
    y = df['action_class']

    cw = dict(enumerate(compute_class_weight('balanced', classes=np.unique(y), y=y)))
    X_train, _, y_train, _ = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    # Build ensemble
    rf = Pipeline([
        ('s', StandardScaler()),
        ('c', RandomForestClassifier(n_estimators=500, class_weight=cw, random_state=42, n_jobs=-1, min_samples_leaf=2))
    ])
    lgbm = Pipeline([
        ('s', StandardScaler()),
        ('c', LGBMClassifier(n_estimators=500, class_weight=cw, random_state=42, n_jobs=-1, verbose=-1, num_leaves=63, min_child_samples=5))
    ])
    gb = Pipeline([
        ('s', StandardScaler()),
        ('c', GradientBoostingClassifier(n_estimators=300, random_state=42, min_samples_leaf=2, max_depth=5))
    ])

    ensemble = VotingClassifier(
        estimators=[('rf', rf), ('lgbm', lgbm), ('gb', gb)],
        voting='soft', n_jobs=-1
    )

    print("Training... (this will take several minutes)")
    ensemble.fit(X_train, y_train)
    print("Training complete!")

    joblib.dump(ensemble, OUT_MODEL)
    print(f"Saved: {OUT_MODEL}")

    # Upload to Hugging Face automatically
    hf_token = os.environ.get("HF_TOKEN")
    if hf_token:
        try:
            api = HfApi()
            api.upload_file(
                path_or_fileobj=OUT_MODEL,
                path_in_repo="best_ensemble_classifier_final.pkl",
                repo_id=HF_REPO_ID,
                token=hf_token,
            )
            print("✅ Uploaded to Hugging Face successfully!")
        except Exception as e:
            print(f"⚠️ Upload to HF failed: {e}")
    else:
        print("⚠️ HF_TOKEN not set — skipping upload")

    print("=" * 60)

if __name__ == "__main__":
    train()
