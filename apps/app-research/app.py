import os
from flask import Flask, render_template_string
import db

app = Flask(__name__)

RESEARCH_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Research Summary - {{ profile.student_id }}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, sans-serif;
      background: #f8fafc;
      color: #0f172a;
      line-height: 1.8;
      padding: 36px 20px;
    }
    .container {
      max-width: 840px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 14px;
      padding: 36px 40px;
      box-shadow: 0 8px 24px rgba(15, 23, 42, 0.06);
      border: 1px solid #e2e8f0;
    }
    .tag {
      display: inline-block;
      background: #e0f2fe;
      color: #0369a1;
      font-size: 0.85rem;
      font-weight: 700;
      padding: 5px 12px;
      border-radius: 999px;
      margin-bottom: 14px;
    }
    h1 { font-size: 1.6rem; color: #0f172a; margin-bottom: 12px; line-height: 1.4; }
    .subtitle {
      font-size: 0.9rem;
      color: #64748b;
      margin-bottom: 24px;
      padding-bottom: 16px;
      border-bottom: 1px solid #e2e8f0;
    }
    .content {
      font-size: 1.05rem;
      color: #1e293b;
      white-space: pre-wrap;
      text-align: justify;
    }
    .footer {
      margin-top: 28px;
      padding-top: 16px;
      border-top: 1px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 12px;
      font-size: 0.85rem;
      color: #64748b;
    }
    .footer a { color: #1d4ed8; text-decoration: none; font-weight: 600; }
    .footer a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <article class="container">
    <span class="tag">DEPLOYMENT: app-research (SEMINAR RESEARCH SUMMARY)</span>
    <h1>{{ data.title }}</h1>
    <div class="subtitle">
      นักศึกษา: {{ profile.student_name }} ({{ profile.student_id }}) | อัปเดตล่าสุด: {{ data.updated_at }}
    </div>
    <div class="content">{{ data.content }}</div>
    <footer class="footer">
      <span>ความยาว: {{ char_count }} ตัวอักษร | Pod: {{ pod_name }} | Node: {{ node_name }}</span>
      <span>
        <a href="/">กลับหน้า Portal</a> |
        <a href="http://admin.iam-68130677.com/edit/research">แก้ไขผ่าน Admin</a>
      </span>
    </footer>
  </article>
</body>
</html>
"""


@app.route("/research", strict_slashes=False)
def research():
    data = db.get_research_summary()
    profile = db.get_portal_profile(include_photo=False)
    return render_template_string(
        RESEARCH_TEMPLATE,
        data=data,
        profile=profile,
        char_count=len(data["content"]),
        pod_name=os.environ.get("POD_NAME", os.environ.get("HOSTNAME", "local")),
        node_name=os.environ.get("NODE_NAME", "local-node"),
    )


@app.route("/healthz")
def healthz():
    try:
        db.check_db_health()
        return {"status": "ok", "service": "app-research"}, 200
    except Exception as exc:
        return {"status": "error", "detail": str(exc)}, 503
