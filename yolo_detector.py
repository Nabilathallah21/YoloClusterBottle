import os
import cv2
import base64
import numpy as np
import math
from datetime import datetime, time, timezone
from typing import List, Dict, Any

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
from pymongo import MongoClient

# ==========================================
# 1. KONFIGURASI FASTAPI & CORS
# ==========================================
app = FastAPI(
    title="YOLO Live Tracking & Inventory API",
    description="Backend API untuk deteksi live tracking objek YOLO (best.pt) dan MongoDB Atlas",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# 2. MODEL YOLO & KONFIGURASI MONGODB ATLAS
# ==========================================
MODEL_PATH = "best.pt"
CONFIDENCE_THRESHOLD = 0.70

MONGO_URI = "mongodb+srv://nathallahf22_db_user:aWRw5RPgW0JBGwna@cluster0.gal8y77.mongodb.net/"
DB_NAME = "yolo_counter_db"

try:
    print("Memuat model YOLO (best.pt)...")
    model = YOLO(MODEL_PATH)
    print("Model YOLO berhasil dimuat!")
except Exception as e:
    print(f"Gagal memuat model YOLO: {e}")
    model = None

try:
    mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=2000)
    db = mongo_client[DB_NAME]
    logs_col = db["detection_logs"]
    shift_col = db["shift_summaries"]
    mongo_client.admin.command('ping')
    print("Koneksi MongoDB Atlas berhasil!")
except Exception as e:
    print(f"Peringatan: MongoDB tidak terhubung ({e}). Mode fallback aktif.")
    db = None

# ==========================================
# 3. CLASS CENTROID TRACKER (PELACAK BARANG)
# ==========================================
class CentroidTracker:
    def __init__(self, max_disappeared=5, distance_threshold=80):
        self.next_object_id = 0
        self.objects = {}       # {object_id: (cx, cy, class_name)}
        self.disappeared = {}   # {object_id: count_missing_frames}
        self.max_disappeared = max_disappeared
        self.distance_threshold = distance_threshold

    def update(self, rects) -> List[Dict[str, Any]]:
        """
        rects: list of (x1, y1, x2, y2, class_name, confidence)
        Return: list barang BARU yang pertama kali muncul di layar
        """
        if len(rects) == 0:
            for obj_id in list(self.disappeared.keys()):
                self.disappeared[obj_id] += 1
                if self.disappeared[obj_id] > self.max_disappeared:
                    self.deregister(obj_id)
            return []

        input_centroids = []
        for (x1, y1, x2, y2, cls_name, conf) in rects:
            cx = int((x1 + x2) / 2.0)
            cy = int((y1 + y2) / 2.0)
            input_centroids.append((cx, cy, cls_name, conf))

        if len(self.objects) == 0:
            new_registered = []
            for (cx, cy, cls_name, conf) in input_centroids:
                self.register(cx, cy, cls_name)
                new_registered.append({"class_name": cls_name, "confidence": conf})
            return new_registered

        object_ids = list(self.objects.keys())
        object_centroids = [self.objects[i] for i in object_ids]

        new_registered = []
        used_inputs = set()
        used_objects = set()

        # Jarak euclidean antar centroid
        for i, (ox, oy, ocls) in enumerate(object_centroids):
            best_dist = float("inf")
            best_j = -1
            for j, (cx, cy, ccls, conf) in enumerate(input_centroids):
                if j in used_inputs:
                    continue
                if ocls != ccls:  # Kelas harus sama
                    continue
                dist = math.hypot(ox - cx, oy - cy)
                if dist < best_dist:
                    best_dist = dist
                    best_j = j

            if best_j != -1 and best_dist < self.distance_threshold:
                # Update posisi objek lama
                obj_id = object_ids[i]
                cx, cy, ccls, _ = input_centroids[best_j]
                self.objects[obj_id] = (cx, cy, ccls)
                self.disappeared[obj_id] = 0
                used_inputs.add(best_j)
                used_objects.add(i)

        # Daftarkan objek baru yang tidak terhubungkan dengan objek lama
        for j, (cx, cy, ccls, conf) in enumerate(input_centroids):
            if j not in used_inputs:
                self.register(cx, cy, ccls)
                new_registered.append({"class_name": ccls, "confidence": conf})

        # Objek yang hilang dari frame
        for i in range(len(object_ids)):
            if i not in used_objects:
                obj_id = object_ids[i]
                self.disappeared[obj_id] += 1
                if self.disappeared[obj_id] > self.max_disappeared:
                    self.deregister(obj_id)

        return new_registered

    def register(self, cx, cy, cls_name):
        self.objects[self.next_object_id] = (cx, cy, cls_name)
        self.disappeared[self.next_object_id] = 0
        self.next_object_id += 1

    def deregister(self, obj_id):
        del self.objects[obj_id]
        del self.disappeared[obj_id]

# Inisialisasi Tracker Global
tracker = CentroidTracker(max_disappeared=5, distance_threshold=80)

# ==========================================
# 4. HELPER FUNCTIONS
# ==========================================
def get_current_shift_info() -> Dict[str, str]:
    now = datetime.now()
    current_time = now.time()
    today_str = now.strftime("%Y-%m-%d")

    s1_start, s1_end = time(7, 0), time(15, 0)
    s2_start, s2_end = time(15, 0), time(23, 0)

    if s1_start <= current_time < s1_end:
        shift_name = "Shift 1"
    elif s2_start <= current_time < s2_end:
        shift_name = "Shift 2"
    else:
        shift_name = "Shift 3"

    return {"shift_name": shift_name, "shift_date": today_str}

def update_mongodb_inventory(new_items: List[Dict[str, Any]], shift_info: Dict[str, str]):
    if db is None or not new_items:
        return

    now_utc = datetime.now(timezone.utc)
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    shift_name = shift_info["shift_name"]
    shift_date = shift_info["shift_date"]

    for det in new_items:
        item_name = det["class_name"]
        conf_val = det["confidence"]
        
        logs_col.insert_one({
            "timestamp": now_utc,
            "object_class": item_name,
            "confidence": conf_val,
            "count": 1,
            "shift_name": shift_name,
            "shift_date": shift_date
        })

        shift_col.update_one(
            {"shift_name": shift_name, "shift_date": shift_date},
            {
                "$inc": {
                    "total_count": 1,
                    f"class_counts.{item_name}": 1
                },
                "$set": {"updated_at": now_str}
            },
            upsert=True
        )

# ==========================================
# 5. ENDPOINT FASTAPI
# ==========================================
@app.get("/")
def read_root():
    return {
        "status": "online",
        "message": "YOLO Live Tracker Running",
        "active_tracked_objects": len(tracker.objects)
    }

@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    if model is None:
        raise HTTPException(status_code=500, detail="Model YOLO belum dimuat.")

    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img is None:
            raise HTTPException(status_code=400, detail="Gambar tidak valid.")

        results = model(img, conf=CONFIDENCE_THRESHOLD)

        rects = []
        all_detections = []

        for result in results:
            for box in result.boxes:
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                class_id = int(box.cls[0])
                class_name = model.names[class_id]
                confidence = float(box.conf[0])

                rects.append((x1, y1, x2, y2, class_name, confidence))
                all_detections.append({
                    "nama_barang": class_name,
                    "class_name": class_name,
                    "confidence": round(confidence, 4),
                    "persen_kepercayaan": f"{confidence * 100:.1f}%"
                })

        # Update Tracker & Dapatkan Hanya Barang Baru
        new_items = tracker.update(rects)

        shift_info = get_current_shift_info()

        # Simpan ke DB hanya jika ada barang BARU yang masuk ke layar
        if new_items:
            update_mongodb_inventory(new_items, shift_info)

        res_plotted = results[0].plot()
        _, buffer = cv2.imencode('.jpg', res_plotted)
        img_base64 = base64.b64encode(buffer).decode('utf-8')

        return {
            "status": "success",
            "shift_name": shift_info["shift_name"],
            "shift_date": shift_info["shift_date"],
            "total_in_screen": len(all_detections),
            "new_counted_items": len(new_items),
            "detections": all_detections,
            "image_base64": img_base64
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")

@app.get("/inventory")
def get_inventory():
    shift_info = get_current_shift_info()
    if db is None:
        return []

    pipeline = [
        {"$match": {"shift_name": shift_info["shift_name"], "shift_date": shift_info["shift_date"]}},
        {"$group": {"_id": "$object_class", "quantity": {"$sum": "$count"}}},
        {"$project": {"_id": 0, "item_name": "$_id", "quantity": 1}}
    ]

    items = list(logs_col.aggregate(pipeline))
    return items

@app.get("/api/v1/shift-summary/today")
def get_today_shift_summary():
    today_str = datetime.now().strftime("%Y-%m-%d")
    if db is None:
        return {"summaries": []}

    summaries = list(shift_col.find({"shift_date": today_str}, {"_id": 0}))
    return {"summaries": summaries}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("yolo_detector:app", host="0.0.0.0", port=8000, reload=False)