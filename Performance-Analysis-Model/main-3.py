#!/usr/bin/env python3
# main.py - Release 2
import os
import cv2
import numpy as np
import argparse
import traceback
from utils import read_video, save_video
from trackers import Tracker
from action_recognizer import infer_action_counts

DEFAULT_CLASS_NAMES = ["dribble", "pass", "shoot", "header", "tackle"]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Football Analysis - Target Player Tracking + Action Counting"
    )
    parser.add_argument("--video-path", type=str, required=True,
                        help="Path to input video")
    parser.add_argument("--target-xy", type=float, nargs=2,
                        help="Target player NORMALIZED coords (x y), range 0.0-1.0")
    parser.add_argument("--crop-dir", type=str, default="target_crops",
                        help="Directory to save cropped target images")
    parser.add_argument("--zoom", type=float, default=1.3,
                        help="Zoom factor for target crop")
    parser.add_argument("--crop-size", type=int, default=224,
                        help="Output crop size in pixels (square)")
    parser.add_argument("--iou-thr", type=float, default=0.5,
                        help="IoU threshold for ID fallback continuity")
    parser.add_argument("--original-width", type=float, default=None,
                        help="Original video width before any downscaling")
    parser.add_argument("--original-height", type=float, default=None,
                        help="Original video height before any downscaling")

    # Model paths
    parser.add_argument("--pose-weights", type=str,
                        default="models/pose_best.pt",
                        help="Path to YOLO Pose weights")
    parser.add_argument("--classifier-weights", type=str,
                        default="models/best_ensemble_classifier.pkl",
                        help="Path to Ensemble classifier weights")
    parser.add_argument("--scaler-path", type=str,
                        default="models/feature_scaler_lgbm.joblib",
                        help="Path to feature scaler")
    parser.add_argument("--encoder-path", type=str,
                        default="models/label_encoder_lgbm.joblib",
                        help="Path to label encoder")

    parser.add_argument("--conf-thr", type=float, default=0.35,
                        help="Confidence threshold for action classification")

    return parser.parse_args()


def seed_target_from_first_frame(tracks_players_frame0, target_xy_pixels):
    """Find the target player in frame 0 using provided pixel coordinates."""
    if target_xy_pixels is None:
        return None, None, None

    target_x, target_y = target_xy_pixels

    if not isinstance(tracks_players_frame0, dict):
        print(f"[Seed] Warning: frame 0 player data is not a dict")
        return None, None, None

    print(f"[Seed] Searching Frame 0 near pixel coords ({target_x:.1f}, {target_y:.1f})...")

    min_dist_fallback = float("inf")
    best_fallback_pid = None
    best_fallback_bbox = None

    for pid, tr in tracks_players_frame0.items():
        bbox = tr.get("bbox")
        if not isinstance(bbox, (list, tuple)) or len(bbox) != 4:
            continue
        x1, y1, x2, y2 = bbox
        if not all(isinstance(c, (int, float)) for c in [x1, y1, x2, y2]):
            continue
        if x1 >= x2 or y1 >= y2:
            continue

        # Direct hit: click is inside bounding box
        if x1 <= target_x <= x2 and y1 <= target_y <= y2:
            print(f"[Seed] DIRECT HIT! Player {pid}, bbox={bbox}")
            return 0, pid, bbox

        # Fallback: closest center distance
        cx = (x1 + x2) / 2.0
        cy = (y1 + y2) / 2.0
        dist = np.hypot(cx - target_x, cy - target_y)

        if dist < min_dist_fallback:
            min_dist_fallback = dist
            best_fallback_pid = pid
            best_fallback_bbox = bbox

    if best_fallback_pid is not None:
        print(f"[Seed] No direct hit. Closest player: {best_fallback_pid}, dist={min_dist_fallback:.2f}")
        return 0, best_fallback_pid, best_fallback_bbox

    print(f"[Seed] No player found near coords {target_xy_pixels}")
    return None, None, None


def calculate_iou(a, b):
    """Calculate Intersection over Union between two bounding boxes."""
    if not isinstance(a, (list, tuple)) or len(a) != 4:
        return 0.0
    if not isinstance(b, (list, tuple)) or len(b) != 4:
        return 0.0

    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b

    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)

    iw = max(0, ix2 - ix1)
    ih = max(0, iy2 - iy1)
    inter = iw * ih

    if inter <= 0:
        return 0.0

    area_a = (ax2 - ax1) * (ay2 - ay1)
    area_b = (bx2 - bx1) * (by2 - by1)
    denom = area_a + area_b - inter

    return inter / denom if denom > 0 else 0.0


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def enlarge_bbox(bbox, zoom=1.3, W=None, H=None, pad_px=10):
    """Expand a bounding box by zoom factor for cropping."""
    if W is None or H is None:
        raise ValueError("W and H must be provided")
    if not isinstance(bbox, (list, tuple)) or len(bbox) != 4:
        raise ValueError(f"Invalid bbox format: {bbox}")

    x1, y1, x2, y2 = bbox
    w = x2 - x1
    h = y2 - y1

    if w <= 0 or h <= 0:
        return [0, 0, 1, 1]

    cx = (x1 + x2) / 2.0
    cy = (y1 + y2) / 2.0
    nw = w * zoom + 2 * pad_px
    nh = h * zoom + 2 * pad_px

    nx1 = int(clamp(cx - nw / 2, 0, W - 1))
    ny1 = int(clamp(cy - nh / 2, 0, H - 1))
    nx2 = int(clamp(cx + nw / 2, 0, W - 1))
    ny2 = int(clamp(cy + nh / 2, 0, H - 1))

    if nx2 <= nx1:
        nx2 = min(W - 1, nx1 + 1)
    if ny2 <= ny1:
        ny2 = min(H - 1, ny1 + 1)

    return [nx1, ny1, nx2, ny2]


def main():
    args = parse_args()

    # --- READ VIDEO ---
    video_frames = read_video(args.video_path)
    if len(video_frames) == 0:
        print("No frames read from video. Check --video-path.")
        return

    original_h_video, original_w_video = video_frames[0].shape[:2]

    # --- DOWNSCALE IF NEEDED ---
    max_w = 960
    H, W = original_h_video, original_w_video

    if original_w_video > max_w:
        scale = max_w / float(original_w_video)
        new_w = int(original_w_video * scale)
        new_h = int(original_h_video * scale)
        print(f"Downscaling from {original_w_video}x{original_h_video} to {new_w}x{new_h}")
        video_frames = [cv2.resize(fr, (new_w, new_h), interpolation=cv2.INTER_AREA) for fr in video_frames]
        H, W = new_h, new_w
    else:
        print(f"No downscaling needed. Dimensions: {W}x{H}")

    print(f"Processed video: {W}x{H}, {len(video_frames)} frames")

    # --- CONVERT NORMALIZED COORDS TO PIXELS ---
    target_xy_pixels = None
    if args.target_xy:
        norm_x, norm_y = args.target_xy
        target_xy_pixels = (norm_x * W, norm_y * H)
        print(f"Target normalized [{norm_x:.3f}, {norm_y:.3f}] -> pixel ({target_xy_pixels[0]:.1f}, {target_xy_pixels[1]:.1f})")
    else:
        print("No --target-xy provided.")

    # --- GET FPS ---
    cap = cv2.VideoCapture(args.video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    try:
        fps = float(fps)
        if fps <= 0 or np.isnan(fps):
            fps = 30.0
    except:
        fps = 30.0
    cap.release()
    print(f"Video FPS: {fps:.2f}")

    # --- TRACKING ---
    print("Running object tracking...")
    tracker = Tracker("models/detect_best.pt")
    tracks = tracker.get_object_tracks(
        video_frames, read_from_stub=False, stub_path="stubs/track_stubs.pkl",
    )

    if not tracks or not tracks.get("players"):
        print("Tracking failed or returned no player data.")
        print("\n--- TRACKING FAILED ---")
        for cls in DEFAULT_CLASS_NAMES:
            print(f"{cls} = 0")
        return

    tracker.add_position_to_tracks(tracks)
    print(f"Tracking complete. Players in frame 0: {len(tracks['players'][0])}")

    # --- SEED TARGET PLAYER ---
    target_id = None
    last_bbox_of_original = None

    if target_xy_pixels and tracks.get("players"):
        tracks_frame0 = tracks["players"][0] if len(tracks["players"]) > 0 else {}
        f0, pid0, bbox0 = seed_target_from_first_frame(tracks_frame0, target_xy_pixels)
        if pid0 is not None:
            target_id = pid0
            last_bbox_of_original = bbox0
            print(f"Target player ID: {target_id} (bbox={bbox0})")
        else:
            print("No player found near the provided coordinates in frame 0.")
    elif not target_xy_pixels:
        print("No target coordinates provided.")

    # --- CROPPING LOOP ---
    frames_cropped = 0

    if target_id is not None:
        os.makedirs(args.crop_dir, exist_ok=True)
        print(f"Cropping target player ID {target_id} to: {os.path.abspath(args.crop_dir)}")
        IOU_THR = float(args.iou_thr)
        original_target_id = target_id

        for f_idx, frame in enumerate(video_frames):
            target_bbox = None
            current_frame_players = (
                tracks.get("players", [])[f_idx]
                if f_idx < len(tracks.get("players", []))
                else {}
            )
            found_by_direct_id = False

            # Step 1: Look for original ID
            if original_target_id in current_frame_players:
                bbox_candidate = current_frame_players[original_target_id].get("bbox")
                if bbox_candidate and isinstance(bbox_candidate, (list, tuple)) and len(bbox_candidate) == 4:
                    target_bbox = bbox_candidate
                    last_bbox_of_original = target_bbox
                    found_by_direct_id = True

            # Step 2: Fallback via IoU if original ID lost
            if not found_by_direct_id and last_bbox_of_original is not None:
                best_iou = 0.0
                best_bbox_candidate = None

                for current_pid, pdata in current_frame_players.items():
                    if current_pid == original_target_id:
                        continue
                    b = pdata.get("bbox")
                    if not b:
                        continue
                    try:
                        iou = calculate_iou(last_bbox_of_original, b)
                    except Exception:
                        continue
                    if iou > best_iou:
                        best_iou = iou
                        best_bbox_candidate = b

                if best_iou > IOU_THR:
                    target_bbox = best_bbox_candidate
                    # NOTE: do NOT update last_bbox_of_original with fallback bbox

            # Step 3: Crop
            if target_bbox:
                try:
                    ex1, ey1, ex2, ey2 = map(int, enlarge_bbox(target_bbox, args.zoom, W, H))

                    if ex1 < ex2 and ey1 < ey2:
                        crop = frame[ey1:ey2, ex1:ex2]
                        if crop.size > 0:
                            crop_resized = cv2.resize(crop, (args.crop_size, args.crop_size),
                                                      interpolation=cv2.INTER_LINEAR)
                            crop_path = os.path.join(args.crop_dir, f"frame_{f_idx:05d}.jpg")
                            if cv2.imwrite(crop_path, crop_resized):
                                frames_cropped += 1
                except Exception as e_crop:
                    print(f"F[{f_idx:04d}] Crop error: {e_crop}")

        print(f"Cropped target player in {frames_cropped} frames.")
    else:
        print("No target player ID set, skipping cropping.")

    # --- ACTION COUNTING ---
    counts_printed = False

    if target_id is not None and os.path.exists(args.crop_dir) and frames_cropped > 0:
        print("Performing action recognition on crops...")
        try:
            counts = infer_action_counts(
                crops_dir=args.crop_dir,
                pose_weights=args.pose_weights,
                classifier_weights=args.classifier_weights,
                scaler_path=args.scaler_path,
                encoder_path=args.encoder_path,
                class_names=DEFAULT_CLASS_NAMES,
                conf_threshold=args.conf_thr
            )
            print("Action recognition complete!")
            print("\n--- FINAL ACTION COUNTS ---")
            for cls in DEFAULT_CLASS_NAMES:
                print(f"{cls} = {counts.get(cls, 0)}")
            counts_printed = True
        except Exception as e_action:
            traceback.print_exc()
            print(f"Action counting failed: {e_action}")

    # --- DEFAULT COUNTS IF NOTHING PRINTED ---
    if not counts_printed:
        if target_id is None:
            print("No target ID set, skipping action recognition.")
        elif frames_cropped == 0:
            print("No frames were cropped, skipping action recognition.")
        else:
            print("Action counting encountered an error.")

        print("\n--- FINAL ACTION COUNTS (Default) ---")
        for cls in DEFAULT_CLASS_NAMES:
            print(f"{cls} = 0")


if __name__ == "__main__":
    try:
        main()
        print("\nScript finished successfully.")
    except Exception as e_main:
        print(f"CRITICAL ERROR in main: {e_main}")
        traceback.print_exc()
        print("\n--- MAIN FUNCTION ERROR ---")
        for cls in DEFAULT_CLASS_NAMES:
            print(f"{cls} = 0")