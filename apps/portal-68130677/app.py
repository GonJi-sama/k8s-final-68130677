import os
from urllib.parse import quote
from flask import Flask, Response, render_template_string
import db

app = Flask(__name__)

PORTAL_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Student Portal - {{ profile.student_id }}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, sans-serif;
      background: linear-gradient(135deg, #f1f5f9 0%, #e2e8f0 100%);
      color: #0f172a;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: #ffffff;
      border-radius: 18px;
      box-shadow: 0 12px 30px rgba(15, 23, 42, 0.1);
      max-width: 500px;
      width: 100%;
      padding: 36px 30px;
      text-align: center;
      border: 1px solid #e2e8f0;
    }
    .avatar {
      width: 190px;
      height: 190px;
      border-radius: 50%;
      object-fit: cover;
      border: 4px solid #1e3a5f;
      margin-bottom: 18px;
      background: #e2e8f0;
    }
    .badge {
      display: inline-block;
      background: #dbeafe;
      color: #1e40af;
      font-weight: 700;
      font-size: 0.85rem;
      padding: 5px 14px;
      border-radius: 999px;
      margin-bottom: 14px;
    }
    h1 { font-size: 1.7rem; margin-bottom: 8px; color: #0f172a; }
    .id-text { font-size: 1.15rem; color: #334155; font-weight: 600; margin-bottom: 22px; }
    .nav {
      display: flex;
      gap: 10px;
      justify-content: center;
      flex-wrap: wrap;
      margin-bottom: 18px;
    }
    .nav a {
      text-decoration: none;
      background: #1e3a5f;
      color: #ffffff;
      padding: 9px 16px;
      border-radius: 8px;
      font-size: 0.9rem;
      font-weight: 600;
    }
    .nav a.admin { background: #b45309; }
    .nav a:hover { opacity: 0.9; }
    .meta {
      margin-top: 16px;
      padding-top: 14px;
      border-top: 1px solid #e2e8f0;
      font-size: 0.8rem;
      color: #64748b;
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <main class="card">
    <img class="avatar" src="/photo?v={{ photo_ver }}" alt="รูปนักศึกษา {{ profile.student_id }}">
    <div><span class="badge">DEPLOYMENT: portal-68130677</span></div>
    <h1>{{ profile.student_name }}</h1>
    <p class="id-text">รหัสนักศึกษา: {{ profile.student_id }}</p>
    <nav class="nav">
      <a href="/research">สรุปงานวิจัย (/research)</a>
      <a href="/api-68130677/Hello">ทดสอบ API (/api-68130677/Hello)</a>
      <a class="admin" href="http://admin.iam-68130677.com">Admin Console</a>
    </nav>
    <div class="meta">
      <div>อัปเดตล่าสุด: {{ profile.updated_at }}</div>
      <div>Pod: {{ pod_name }} | Node: {{ node_name }}</div>
    </div>
  </main>
</body>
</html>
"""


@app.route("/")
def portal_home():
    profile = db.get_portal_profile(include_photo=False)
    return render_template_string(
        PORTAL_TEMPLATE,
        profile=profile,
        photo_ver=quote(profile["updated_at"]),
        pod_name=os.environ.get("POD_NAME", os.environ.get("HOSTNAME", "local")),
        node_name=os.environ.get("NODE_NAME", "local-node"),
    )


@app.route("/photo")
def portal_photo():
    profile = db.get_portal_profile(include_photo=True)
    raw = bytes(profile["photo_data"])
    resp = Response(raw, mimetype=profile["photo_mime"])
    resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    return resp


@app.route("/healthz")
def healthz():
    try:
        db.check_db_health()
        return {"status": "ok", "service": "portal-68130677"}, 200
    except Exception as exc:
        return {"status": "error", "detail": str(exc)}, 503
