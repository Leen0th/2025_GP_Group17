#!/usr/bin/env python3
"""
Haddaf Backend Server - Football Action Recognition API (Release 2)
"""

import os
import sys
import shutil
import subprocess
import traceback
from datetime import datetime
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from huggingface_hub import hf_hub_download

# ================== App / Paths ==================
app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(BASE_DIR, "models")
DEBUG_DIR = os.path.join(BASE_DIR, "debug_output")

os.makedirs(MODELS_DIR, exist_ok=True)
os.makedirs(DEBUG_DIR, exist_ok=True)

# ================== Download Models from Hugging Face ==================
HF_REPO_ID = "lujain-721/Haddaf_New_Model"

HF_FILES = [
    "detect_best.pt",
    "pose_best.pt",
    "feature_scaler_lgbm.joblib",
    "label_encoder_lgbm.joblib",
]

def download_models():
    print("=" * 60)
    print("Checking / downloading models from Hugging Face...")
    print(f"Repo: {HF_REPO_ID}")
    print("=" * 60)
    for filename in HF_FILES:
        dest = os.path.join(MODELS_DIR, filename)
        if os.path.exists(dest):
            print(f"✅ Already exists: {filename}")
            continue
        print(f"⬇️  Downloading {filename}...")
        hf_hub_download(
            repo_id=HF_REPO_ID,
            filename=filename,
            local_dir=MODELS_DIR,
        )
        print(f"✅ Downloaded: {filename}")
    print("All models ready.")
    print("=" * 60)

# Download models at startup
download_models()

# Try to download classifier from HF first, otherwise train on server
CLASSIFIER_PKL = os.path.join(MODELS_DIR, "best_ensemble_classifier_final.pkl")
if not os.path.exists(CLASSIFIER_PKL):
    try:
        print("Trying to download classifier from Hugging Face...")
        hf_hub_download(
            repo_id="lujain-721/Haddaf_New_Model",
            filename="best_ensemble_classifier_final.pkl",
            local_dir=MODELS_DIR,
        )
        print("Classifier downloaded from Hugging Face!")
    except Exception:
        print("Not found on HF — training on server...")
        from train_on_server import train
        train()

# ================== Model Paths ==================
DETECTION_WEIGHTS  = os.path.join(MODELS_DIR, "detect_best.pt")
POSE_WEIGHTS       = os.path.join(MODELS_DIR, "pose_best.pt")
CLASSIFIER_WEIGHTS = os.path.join(MODELS_DIR, "best_ensemble_classifier_final.pkl")
SCALER_PATH        = os.path.join(MODELS_DIR, "feature_scaler_lgbm.joblib")
ENCODER_PATH       = os.path.join(MODELS_DIR, "label_encoder_lgbm.joblib")


# ================== Routes ==================

def apply_reality_logic(counts):
    has_dribble = counts.get('dribble', 0) > 0
    has_pass    = counts.get('pass', 0) > 0
    has_shoot   = counts.get('shoot', 0) > 0
    has_header  = counts.get('header', 0) > 0
    has_tackle  = counts.get('tackle', 0) > 0

    original = dict(counts)

    if has_header:
        counts = {k: (v if k == 'header' else 0) for k, v in counts.items()}
        print(f"[REALITY LOGIC] Header detected — keeping only header. Before: {original}")
        return counts

    if has_tackle and (has_dribble or has_pass):
        counts['tackle'] = 0
        print(f"[REALITY LOGIC] Tackle removed (dribble/pass present = opponent tackle). Before: {original}")

    has_tackle_now  = counts.get('tackle', 0) > 0
    has_shoot_now   = counts.get('shoot', 0) > 0
    has_dribble_now = counts.get('dribble', 0) > 0
    has_pass_now    = counts.get('pass', 0) > 0

    if has_tackle_now and has_shoot_now and not has_dribble_now and not has_pass_now:
        counts['shoot'] = 0
        print(f"[REALITY LOGIC] Shoot removed (tackle + only shoot = pre-tackle run). Before: {original}")

    if counts != original:
        print(f"[REALITY LOGIC] Final counts: {counts}")
    else:
        print(f"[REALITY LOGIC] No changes applied.")

    return counts


@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "service": "Haddaf Action Recognition API",
        "version": "2.0",
        "status": "running",
        "endpoints": {
            "/health": "Server health status",
            "/analyze": "POST video + normalized (x,y) to analyze a player",
            "/view-crops/current": "View last request's crops in browser"
        }
    })


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "models": {
            "detection_model":  os.path.exists(DETECTION_WEIGHTS),
            "pose_model":       os.path.exists(POSE_WEIGHTS),
            "classifier_model": os.path.exists(CLASSIFIER_WEIGHTS),
            "scaler":           os.path.exists(SCALER_PATH),
            "encoder":          os.path.exists(ENCODER_PATH),
        },
        "python_version": sys.version,
    })


@app.route("/crops/current/<path:filename>")
def serve_crop(filename):
    crops_path = os.path.join(DEBUG_DIR, "current", "crops")
    return send_from_directory(crops_path, filename)


@app.route("/view-crops/current")
def view_crops():
    crops_path = os.path.join(DEBUG_DIR, "current", "crops")
    if not os.path.exists(crops_path):
        return f"<h1>No crops folder found</h1><p>{crops_path}</p>", 404

    images = sorted([f for f in os.listdir(crops_path)
                     if f.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp', '.webp'))])
    if not images:
        return f"<h1>No images found</h1><p>{crops_path}</p>", 404

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Target Player Crops</title>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            * {{ margin: 0; padding: 0; box-sizing: border-box; }}
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                    padding: 20px; background: #0f1222; color: white; min-height: 100vh; }}
            h1 {{ color: #4CAF50; margin-bottom: 20px; }}
            .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 20px; }}
            .item {{ background: #1a1f36; padding: 12px; border-radius: 12px; border: 1px solid #26304a; }}
            img {{ width: 100%; height: 250px; object-fit: cover; border-radius: 8px; }}
            .name {{ margin-top: 8px; color: #9ae6b4; font-family: monospace; font-size: 12px; }}
        </style>
    </head>
    <body>
        <h1>Target Player Crops ({len(images)})</h1>
        <div class="grid">
    """
    for img in images:
        html += f"""
            <div class="item">
                <img src="/crops/current/{img}" alt="{img}" loading="lazy" />
                <div class="name">{img}</div>
            </div>
        """
    html += "</div></body></html>"
    return html


@app.route("/analyze", methods=["POST"])
def analyze_video():
    try:
        if "video" not in request.files:
            return jsonify({"success": False, "error": "No video file provided"}), 400
        video_file = request.files["video"]
        if not video_file.filename:
            return jsonify({"success": False, "error": "Empty filename"}), 400

        try:
            x               = float(request.form.get("x", 0))
            y               = float(request.form.get("y", 0))
            original_width  = float(request.form.get("width", 0))
            original_height = float(request.form.get("height", 0))
        except ValueError:
            return jsonify({"success": False, "error": "Invalid x, y, width, or height"}), 400

        print(f"Received: {video_file.filename}")
        print(f"Target normalized coords: x={x}, y={y}")
        print(f"Original dimensions: {original_width}x{original_height}")

        work_dir = os.path.join(DEBUG_DIR, "current")
        if os.path.exists(work_dir):
            shutil.rmtree(work_dir, ignore_errors=True)
        os.makedirs(work_dir, exist_ok=True)

        video_path = os.path.join(work_dir, "input_video.mp4")
        video_file.save(video_path)
        print(f"Video saved: {video_path}")

        crops_dir = os.path.join(work_dir, "crops")
        os.makedirs(crops_dir, exist_ok=True)

        main_script = os.path.join(BASE_DIR, "main.py")

        env_limited = dict(os.environ,
            OMP_NUM_THREADS="1",
            OPENBLAS_NUM_THREADS="1",
            MKL_NUM_THREADS="1",
            NUMEXPR_NUM_THREADS="1",
            BLIS_NUM_THREADS="1",
            OPENCV_OPENCL_RUNTIME="disabled",
            MALLOC_ARENA_MAX="2",
        )

        def run_pipeline(zoom):
            cmd = [
                sys.executable, main_script,
                "--video-path",          video_path,
                "--target-xy",           str(x), str(y),
                "--crop-dir",            crops_dir,
                "--pose-weights",        POSE_WEIGHTS,
                "--classifier-weights",  CLASSIFIER_WEIGHTS,
                "--scaler-path",         SCALER_PATH,
                "--encoder-path",        ENCODER_PATH,
                "--zoom",                str(zoom),
                "--crop-size",           "224",
                "--conf-thr",            "0.35",
                "--iou-thr",             "0.5",
                "--original-width",      str(original_width),
                "--original-height",     str(original_height),
            ]
            print(f"Running (zoom={zoom}): {' '.join(cmd)}")
            return subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                timeout=2400,
                cwd=BASE_DIR,
                env=env_limited,
            )

        result = run_pipeline(1.3)
        stdout_text = result.stdout or ""
        stderr_text = result.stderr or ""

        tackle_signal = False
        for line in stdout_text.splitlines():
            if "'tackle':" in line:
                try:
                    import re as _re
                    m = _re.search(r"'tackle':\s*([0-9.]+)", line)
                    if m and float(m.group(1)) >= 0.08:
                        tackle_signal = True
                        break
                except Exception:
                    pass

        if tackle_signal:
            print("[TWO-PASS] Tackle signal detected in pass 1 — re-running at zoom=2.0")
            result2 = run_pipeline(2.0)
            stdout_text2 = result2.stdout or ""
            stderr_text2 = result2.stderr or ""
            print("[TWO-PASS] Using zoom=2.0 results")
            print(f"Return code (pass2): {result2.returncode}")
            print("=== SUBPROCESS STDOUT (pass2) ===")
            print(stdout_text2 if stdout_text2 else "(empty)")
            print("=== SUBPROCESS STDERR (pass2) ===")
            print(stderr_text2 if stderr_text2 else "(empty)")
            print("=================================")
            if result2.returncode == 0:
                stdout_text = stdout_text2
                stderr_text = stderr_text2
                result = result2
        else:
            print("[TWO-PASS] No tackle signal — using zoom=1.3 results")
            print(f"Return code: {result.returncode}")
            print("=== SUBPROCESS STDOUT ===")
            print(stdout_text if stdout_text else "(empty)")
            print("=== SUBPROCESS STDERR ===")
            print(stderr_text if stderr_text else "(empty)")
            print("=========================")

        if result.returncode != 0:
            return jsonify({
                "success": False,
                "error": "Processing failed",
                "details": stderr_text[-2000:] if stderr_text else "No error output captured",
                "return_code": result.returncode
            }), 500

        action_counts = {}
        for line in stdout_text.strip().splitlines():
            if "=" in line:
                parts = line.split("=")
                if len(parts) == 2:
                    k = parts[0].strip()
                    try:
                        v = int(parts[1].strip())
                        action_counts[k] = v
                    except ValueError:
                        pass

        if not action_counts:
            action_counts = {"dribble": 0, "pass": 0, "shoot": 0, "header": 0, "tackle": 0}
            print("No action counts parsed, defaulting to zeros.")

        crop_count = len([
            f for f in os.listdir(crops_dir)
            if f.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp', '.webp'))
        ]) if os.path.exists(crops_dir) else 0

        print(f"Total crops: {crop_count}")

        action_counts = apply_reality_logic(action_counts)

        base_url = request.host_url.rstrip("/")
        return jsonify({
            "success": True,
            "action_counts": action_counts,
            "target_coordinates": {"x": x, "y": y},
            "crops_url": f"{base_url}/view-crops/current",
            "total_crops": crop_count,
            "timestamp": datetime.now().isoformat()
        })

    except Exception as e:
        print(f"Exception: {e}")
        print(traceback.format_exc())
        return jsonify({
            "success": False,
            "error": str(e),
            "traceback": traceback.format_exc()
        }), 500


# ================== Error Handlers ==================

@app.errorhandler(404)
def not_found(_):
    return jsonify({"success": False, "error": "Endpoint not found"}), 404


@app.errorhandler(500)
def internal_error(_):
    return jsonify({"success": False, "error": "Internal server error"}), 500


# ================== Entry Point ==================

if __name__ == "__main__":
    print("=" * 60)
    print("Haddaf Backend Server Starting (Release 2)...")
    print("=" * 60)
    print(f"Base directory:      {BASE_DIR}")
    print(f"Models directory:    {MODELS_DIR}")
    print(f"Debug output:        {DEBUG_DIR}")
    print(f"Detection model:     {os.path.exists(DETECTION_WEIGHTS)}")
    print(f"Pose model:          {os.path.exists(POSE_WEIGHTS)}")
    print(f"Classifier:          {os.path.exists(CLASSIFIER_WEIGHTS)}")
    print(f"Scaler:              {os.path.exists(SCALER_PATH)}")
    print(f"Encoder:             {os.path.exists(ENCODER_PATH)}")
    print("=" * 60)

    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
