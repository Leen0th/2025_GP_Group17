# action_recognizer.py (Release 5 - DYNAMIC SEGMENTATION)

import os
import re
import cv2
import numpy as np
import joblib
import warnings
import pandas as pd
from itertools import groupby
from collections import Counter
from ultralytics import YOLO

warnings.filterwarnings("ignore")

DEFAULT_CLASS_NAMES = ["dribble", "pass", "shoot", "header", "tackle"]
INT_TO_CLASS = {0: "dribble", 1: "pass", 2: "shoot", 3: "header", 4: "tackle"}

FEATURE_COLS = (
    [f'kp_{i}_x' for i in range(17)] +
    [f'kp_{i}_y' for i in range(17)] +
    [f'kp_{i}_conf' for i in range(17)] +
    ['bbox_x1', 'bbox_y1', 'bbox_x2', 'bbox_y2', 'bbox_conf',
     'bbox_width', 'bbox_height', 'bbox_aspect_ratio', 'bbox_area',
     'mean_keypoint_conf', 'min_keypoint_conf', 'max_keypoint_conf',
     'std_keypoint_conf', 'num_visible_keypoints', 'keypoint_spread']
)


def _extract_index_from_name(fn):
    m = re.findall(r'\d+', fn)
    return int(m[0]) if m else None


def extract_features_from_result(res, img_w=224, img_h=224):
    if res.boxes is None or len(res.boxes) == 0:
        return None
    if res.keypoints is None or len(res.keypoints.data) == 0:
        return None
    # Pick the person closest to center of the crop
    # The target player is always centered (we cropped around them)
    # This avoids picking upright bystanders over horizontal tacklers
    boxes = res.boxes.xyxy.cpu().numpy()
    crop_cx = img_w / 2
    crop_cy = img_h / 2
    box_cx = (boxes[:, 0] + boxes[:, 2]) / 2
    box_cy = (boxes[:, 1] + boxes[:, 3]) / 2
    dist = (box_cx - crop_cx) ** 2 + (box_cy - crop_cy) ** 2
    best_idx = int(np.argmin(dist))
    kps_data = res.keypoints.data[best_idx]
    if kps_data.shape[0] != 17:
        return None
    kps = kps_data[:, :2].cpu().numpy()
    kp_conf = kps_data[:, 2].cpu().numpy() if kps_data.shape[1] >= 3 else np.ones(17)
    bbox = res.boxes.xyxy[best_idx].cpu().numpy()
    bbox_conf = float(res.boxes.conf[best_idx].cpu().numpy())
    bx1, by1, bx2, by2 = float(bbox[0]), float(bbox[1]), float(bbox[2]), float(bbox[3])
    bw, bh = bx2 - bx1, by2 - by1
    feat = np.array([
        *[float(kps[i][0]) for i in range(17)],
        *[float(kps[i][1]) for i in range(17)],
        *[float(kp_conf[i]) for i in range(17)],
        bx1, by1, bx2, by2, bbox_conf,
        bw, bh, bw / (bh + 1e-6), bw * bh,
        float(np.mean(kp_conf)), float(np.min(kp_conf)),
        float(np.max(kp_conf)), float(np.std(kp_conf)),
        float(np.sum(kp_conf > 0.5)), float(np.std(kps)),
    ], dtype=np.float64)
    return np.nan_to_num(feat, nan=0.0, posinf=0.0, neginf=0.0)


def extract_kps_xy(res):
    if res.keypoints is None:
        return None
    kps = res.keypoints.xy.cpu().numpy()
    return kps[0] if len(kps) else None


def get_scale(kps_xy):
    if np.any(kps_xy[5] == 0) or np.any(kps_xy[6] == 0):
        return None
    width = np.linalg.norm(kps_xy[5] - kps_xy[6])
    return width if width > 5.0 else None


def smooth_predictions(timeline, window_size=11):
    if not timeline:
        return []
    smoothed = []
    actions = [t[1] for t in timeline]
    indices = [t[0] for t in timeline]
    for i in range(len(actions)):
        start = max(0, i - window_size // 2)
        end = min(len(actions), i + window_size // 2 + 1)
        window = actions[start:end]
        most_common = Counter(window).most_common(1)[0][0] if window else actions[i]
        smoothed.append((indices[i], most_common))
    return smoothed


def infer_action_counts(
    crops_dir,
    pose_weights,
    classifier_weights,
    scaler_path,
    encoder_path,
    class_names=None,
    conf_threshold=0.35,
    smooth_window=11,
    min_seg_frames=10,
    **kwargs
):
    print("\n" + "="*80)
    print("ACTION RECOGNITION PIPELINE (YOLO Pose + Ensemble Classifier)")
    print("="*80)

    classes = class_names if class_names else DEFAULT_CLASS_NAMES

    if not os.path.exists(crops_dir):
        print(f"Crops directory not found: {crops_dir}")
        return {c: 0 for c in classes}

    print("Loading models...")
    print(f"   - Pose model:   {os.path.basename(pose_weights)}")
    print(f"   - Classifier:   {os.path.basename(classifier_weights)}")
    print(f"   - Class mapping: {INT_TO_CLASS}")

    yolo = YOLO(pose_weights)
    clf  = joblib.load(classifier_weights)
    clf_classes = [INT_TO_CLASS[i] for i in range(5)]

    image_paths = sorted(
        [os.path.join(crops_dir, f) for f in os.listdir(crops_dir)
         if f.lower().endswith(('.jpg', '.jpeg', '.png'))],
        key=lambda x: _extract_index_from_name(os.path.basename(x)) or 0
    )

    if not image_paths:
        print("No images found in crops directory")
        return {c: 0 for c in classes}

    total_frames = len(image_paths)
    print(f"Processing {total_frames} frames...")

    # --- PASS 1: INFERENCE ---
    all_results = []
    all_scales  = []

    for idx, img_path in enumerate(image_paths):
        if idx % 50 == 0:
            print(f"   Frame {idx}/{total_frames}...")
        img = cv2.imread(img_path)
        if img is None:
            all_results.append(None)
            continue
        h, w = img.shape[:2]
        res    = yolo(img, conf=0.25, verbose=False)[0]
        feat   = extract_features_from_result(res, img_w=w, img_h=h)
        kps_xy = extract_kps_xy(res)
        all_results.append((feat, kps_xy))
        if kps_xy is not None:
            s = get_scale(kps_xy)
            if s:
                all_scales.append(s)

    global_scale = float(np.median(all_scales)) if all_scales else 1.0
    print(f"Global Player Scale (Shoulder Width): {global_scale:.2f} px")

    # --- PASS 2: CLASSIFY ---
    timeline = []

    for idx, entry in enumerate(all_results):
        if entry is None:
            continue
        feat, kps_xy = entry
        frame_idx = _extract_index_from_name(os.path.basename(image_paths[idx])) or idx
        if feat is None:
            continue
        feat_df = pd.DataFrame([feat], columns=FEATURE_COLS)
        proba   = clf.predict_proba(feat_df)[0]
        probs   = dict(zip(clf_classes, proba))
        # Tackle boost: only if tackle >= 0.03 AND tackle > header (prevents header confusion)
        # Header boost: header is short action, lower threshold to catch it
        tackle_prob = probs.get('tackle', 0)
        header_prob = probs.get('header', 0)
        if tackle_prob >= 0.03 and tackle_prob > header_prob:
            best_act  = 'tackle'
            best_prob = tackle_prob
            print(f"   F{frame_idx:03d}: {best_act} ({best_prob:.2f}) | {dict(sorted({k: round(float(v),2) for k,v in probs.items()}.items()))}")
            timeline.append((frame_idx, best_act))  # bypass conf_threshold for tackle
        elif header_prob >= 0.40 and header_prob == max(probs.values()):
            best_act  = 'header'
            best_prob = header_prob
            print(f"   F{frame_idx:03d}: {best_act} ({best_prob:.2f}) | {dict(sorted({k: round(float(v),2) for k,v in probs.items()}.items()))}")
            timeline.append((frame_idx, best_act))  # bypass conf_threshold for header
        else:
            best_act  = max(probs, key=probs.get)
            best_prob = probs[best_act]
            print(f"   F{frame_idx:03d}: {best_act} ({best_prob:.2f}) | {dict(sorted({k: round(float(v),2) for k,v in probs.items()}.items()))}")
            if best_prob > conf_threshold:
                timeline.append((frame_idx, best_act))

    print(f"Raw detections: {len(timeline)}")
    if timeline:
        print(f"Raw distribution: {dict(Counter([t[1] for t in timeline]))}")

    # --- PASS 3: SMOOTHING ---
    # Preserve tackle and header frames before smoothing (both are short burst actions)
    tackle_frames = {frame_idx for frame_idx, act in timeline if act == 'tackle'}
    header_frames = {frame_idx for frame_idx, act in timeline if act == 'header'}
    timeline = smooth_predictions(timeline, window_size=smooth_window)
    # Restore tackle and header labels that were overwritten by smoothing
    timeline = [(idx,
                 'tackle' if idx in tackle_frames else
                 'header' if idx in header_frames else act)
                for idx, act in timeline]
    # Fill small gaps between tackle frames (up to 4 frames apart)
    if tackle_frames:
        sorted_tackles = sorted(tackle_frames)
        filled = set(tackle_frames)
        for i in range(len(sorted_tackles) - 1):
            gap = sorted_tackles[i+1] - sorted_tackles[i]
            if gap <= 4:
                for f in range(sorted_tackles[i], sorted_tackles[i+1]+1):
                    filled.add(f)
        timeline = [(idx, 'tackle' if idx in filled else act) for idx, act in timeline]

    # --- PASS 4: DYNAMIC SEGMENTATION ---
    total_detected = len(timeline)
    if total_detected < 60:
        dynamic_min = 4
    elif total_detected > 200:
        dynamic_min = 20
    else:
        dynamic_min = int(4 + (total_detected - 60) / 140 * 16)
    dynamic_max_gap = max(2, dynamic_min // 4)
    print(f"Dynamic thresholds: min_seg={dynamic_min}, max_gap={dynamic_max_gap} (from {total_detected} detected frames)")

    raw_segments = []
    if timeline:
        timeline.sort(key=lambda x: x[0])
        actions_raw = [t[1] for t in timeline]
        for key, group in groupby(actions_raw):
            length = len(list(group))
            print(f"   Segment: {key} x {length} frames")
            # Tackle and header use lower min_seg — both are short burst actions
            # Dribble uses higher min_seg — it's often noise from walking/running frames
            if key == 'tackle':
                effective_min = 3
            elif key == 'header':
                effective_min = 3
            elif key == 'dribble':
                effective_min = max(dynamic_min, int(dynamic_min * 2.0))
            else:
                effective_min = dynamic_min
            if length >= effective_min:
                raw_segments.append((key, length))
                print(f"   --> ACCEPTED: {key} ({length} frames)")

    # --- PASS 5: MERGE ---
    def merge_segments(segs, max_gap):
        # Step 1: merge pass/shoot
        merged = []
        i = 0
        while i < len(segs):
            act, length = segs[i]
            group_acts = [act]
            group_lengths = [length]
            j = i + 1
            while j < len(segs):
                next_act, next_len = segs[j]
                if act in ("pass", "shoot") and next_act in ("pass", "shoot"):
                    group_acts.append(next_act)
                    group_lengths.append(next_len)
                    j += 1
                else:
                    break
            if len(group_acts) > 1:
                act_totals = {}
                for a, l in zip(group_acts, group_lengths):
                    act_totals[a] = act_totals.get(a, 0) + l
                winner = max(act_totals, key=act_totals.get)
                print(f"   MERGED pass/shoot -> {winner} {act_totals}")
                merged.append((winner, sum(group_lengths)))
                i = j
            else:
                merged.append((act, length))
                i += 1
        # Step 2: merge same-action over short gap
        changed = True
        while changed:
            changed = False
            result = []
            i = 0
            while i < len(merged):
                act, length = merged[i]
                if (i + 2 < len(merged) and
                    merged[i+2][0] == act and
                    merged[i+1][1] <= max_gap):
                    gap_act, gap_len = merged[i+1]
                    new_len = length + gap_len + merged[i+2][1]
                    print(f"   MERGED {act}+{gap_act}({gap_len})+{act} -> {act} ({new_len} frames)")
                    result.append((act, new_len))
                    i += 3
                    changed = True
                else:
                    result.append((act, length))
                    i += 1
            merged = result
        return merged

    raw_segments = merge_segments(raw_segments, max_gap=dynamic_max_gap)
    merged = [act for act, _ in raw_segments]

    # --- PASS 6: DEDUP ---
    deduped = []
    if merged:
        deduped = [merged[0]]
        for e in merged[1:]:
            if e != deduped[-1]:
                deduped.append(e)

    counts = Counter(deduped)
    result = {c: counts.get(c, 0) for c in classes}

    print("\nFINAL RESULTS:")
    for action, count in result.items():
        print(f"   {action}: {count}")

    return result
