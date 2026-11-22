import io
import os
from urllib.parse import quote
from flask import Flask, Response, redirect, render_template_string, request
from PIL import Image, ImageOps
import db

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024  # 5 MB upload cap

ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}


def process_uploaded_photo(file_storage):
    raw_bytes = file_storage.read()
    if not raw_bytes:
        return None, None
    try:
        with Image.open(io.BytesIO(raw_bytes)) as img:
            if img.format not in ALLOWED_FORMATS:
                raise ValueError("รองรับเฉพาะไฟล์รูปภาพ JPG, PNG หรือ WEBP เท่านั้น")
            img = ImageOps.exif_transpose(img)
            img.thumbnail((600, 600), Image.Resampling.LANCZOS)
            out = io.BytesIO()
            if img.mode in ("RGBA", "LA", "P"):
                img.convert("RGBA").save(out, format="PNG", optimize=True)
                return out.getvalue(), "image/png"
            else:
                img.convert("RGB").save(out, format="JPEG", quality=88, optimize=True)
                return out.getvalue(), "image/jpeg"
    except ValueError:
        raise
    except Exception:
        raise ValueError("ไฟล์ที่อัปโหลดไม่ใช่รูปภาพที่ถูกต้องหรือไฟล์เสียหาย")


DASHBOARD_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Dashboard - 68130677</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, sans-serif;
      background: #0f172a;
      color: #f8fafc;
      min-height: 100vh;
      padding: 36px 20px;
    }
    .wrap { max-width: 920px; margin: 0 auto; }
    .header {
      text-align: center;
      margin-bottom: 30px;
    }
    .badge {
      display: inline-block;
      background: #fef3c7;
      color: #92400e;
      font-size: 0.85rem;
      font-weight: 700;
      padding: 6px 14px;
      border-radius: 999px;
      margin-bottom: 12px;
    }
    .header h1 { font-size: 1.9rem; margin-bottom: 8px; }
    .header p { color: #94a3b8; font-size: 0.95rem; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 22px;
      margin-bottom: 26px;
    }
    .card {
      background: #ffffff;
      color: #0f172a;
      border-radius: 16px;
      padding: 28px 26px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      box-shadow: 0 12px 30px rgba(0, 0, 0, 0.25);
    }
    .card h2 { font-size: 1.3rem; margin-bottom: 12px; color: #1e3a5f; }
    .preview-row {
      display: flex;
      align-items: center;
      gap: 14px;
      margin-bottom: 18px;
      padding: 12px;
      background: #f8fafc;
      border-radius: 10px;
      border: 1px solid #e2e8f0;
    }
    .thumb {
      width: 64px;
      height: 64px;
      border-radius: 50%;
      object-fit: cover;
      border: 2px solid #1e3a5f;
      flex-shrink: 0;
    }
    .info { font-size: 0.92rem; color: #334155; line-height: 1.5; }
    .snippet {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 10px;
      padding: 12px 14px;
      margin-bottom: 18px;
      font-size: 0.9rem;
      color: #334155;
      line-height: 1.55;
    }
    .btn {
      display: block;
      text-align: center;
      text-decoration: none;
      background: #1e3a5f;
      color: #ffffff;
      font-weight: 700;
      padding: 13px 20px;
      border-radius: 10px;
      font-size: 1rem;
    }
    .btn.research { background: #0f766e; }
    .btn:hover { opacity: 0.92; }
    .quick-links {
      background: #1e293b;
      border-radius: 12px;
      padding: 16px 22px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
      font-size: 0.88rem;
      color: #cbd5e1;
    }
    .quick-links a { color: #38bdf8; text-decoration: none; font-weight: 600; margin-right: 14px; }
    .quick-links a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="wrap">
    <header class="header">
      <span class="badge">DEPLOYMENT: admin-68130677 | admin.iam-68130677.com</span>
      <h1>ศูนย์จัดการข้อมูลระบบ (Admin Console)</h1>
      <p>เลือกส่วนที่ต้องการแก้ไข ข้อมูลจะถูกบันทึกลงฐานข้อมูลกลาง PostgreSQL และอัปเดตทุกโหนดทันที</p>
    </header>

    <section class="grid">
      <div class="card">
        <div>
          <h2>1. ข้อมูลหน้า Portal (portal-68130677)</h2>
          <div class="preview-row">
            <img class="thumb" src="/preview/photo?v={{ photo_ver }}" alt="รูปปัจจุบัน">
            <div class="info">
              <div><strong>ชื่อ:</strong> {{ profile.student_name }}</div>
              <div><strong>รหัส:</strong> {{ profile.student_id }}</div>
              <div style="font-size:0.8rem; color:#64748b;">อัปเดต: {{ profile.updated_at }}</div>
            </div>
          </div>
        </div>
        <a class="btn" href="/edit/portal">แก้ไขข้อมูล Portal (ชื่อ / รหัส / รูปภาพ)</a>
      </div>

      <div class="card">
        <div>
          <h2>2. สรุปงานวิจัยวิชาสัมมนา (app-research)</h2>
          <div class="snippet">
            <div style="font-weight:700; color:#0f172a; margin-bottom:4px;">{{ research.title }}</div>
            <div>ความยาวปัจจุบัน: {{ research_chars }} ตัวอักษร</div>
            <div style="font-size:0.8rem; color:#64748b; margin-top:4px;">อัปเดต: {{ research.updated_at }}</div>
          </div>
        </div>
        <a class="btn research" href="/edit/research">แก้ไขข้อมูลสรุปงานวิจัย (Research)</a>
      </div>
    </section>

    <footer class="quick-links">
      <div>
        <a href="http://www.iam-68130677.com" target="_blank">เปิด Portal (iam)</a>
        <a href="http://www.id-68130677.com" target="_blank">เปิด Portal (id)</a>
        <a href="http://www.iam-68130677.com/research" target="_blank">เปิด Research</a>
        <a href="http://www.iam-68130677.com/api-68130677/Hello" target="_blank">เปิด API</a>
      </div>
      <div>Pod: {{ pod_name }} | Node: {{ node_name }}</div>
    </footer>
  </div>
</body>
</html>
"""

EDIT_PORTAL_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Edit Portal - admin-68130677</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, sans-serif;
      background: #0f172a;
      color: #0f172a;
      min-height: 100vh;
      padding: 36px 20px;
    }
    .panel {
      max-width: 680px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 16px;
      padding: 32px 34px;
      box-shadow: 0 12px 30px rgba(0, 0, 0, 0.25);
    }
    .back { display: inline-block; margin-bottom: 14px; color: #1d4ed8; text-decoration: none; font-weight: 600; font-size: 0.92rem; }
    h1 { font-size: 1.5rem; margin-bottom: 6px; color: #1e3a5f; }
    .hint { font-size: 0.88rem; color: #64748b; margin-bottom: 20px; }
    .alert { padding: 12px 16px; border-radius: 8px; margin-bottom: 18px; font-weight: 600; font-size: 0.95rem; }
    .alert-ok { background: #dcfce7; color: #166534; border: 1px solid #86efac; }
    .alert-err { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }
    .current-photo {
      display: flex;
      align-items: center;
      gap: 18px;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 10px;
      padding: 14px;
      margin-bottom: 18px;
    }
    .current-photo img {
      width: 96px;
      height: 96px;
      border-radius: 50%;
      object-fit: cover;
      border: 3px solid #1e3a5f;
    }
    label { display: block; font-weight: 700; margin-bottom: 6px; color: #1e293b; }
    input[type="text"], input[type="file"] {
      width: 100%;
      padding: 11px 13px;
      border: 1px solid #cbd5e1;
      border-radius: 8px;
      font-family: inherit;
      font-size: 1rem;
      margin-bottom: 18px;
    }
    .actions { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; }
    button {
      background: #1e3a5f;
      color: #ffffff;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
    }
    button:hover { background: #1d4ed8; }
    .link { color: #1d4ed8; text-decoration: none; font-weight: 600; }
  </style>
</head>
<body>
  <main class="panel">
    <a class="back" href="/">← กลับหน้าหลัก Admin Console</a>
    <h1>แก้ไขข้อมูลหน้า Portal (portal-68130677)</h1>
    <p class="hint">อัปเดตล่าสุด: {{ profile.updated_at }} | บันทึกในฐานข้อมูลกลาง PostgreSQL</p>

    {% if saved %}
      <div class="alert alert-ok">บันทึกข้อมูล Portal เรียบร้อยแล้ว — เปิดตรวจสอบได้ที่ www.iam-68130677.com</div>
    {% endif %}
    {% if error %}
      <div class="alert alert-err">{{ error }}</div>
    {% endif %}

    <div class="current-photo">
      <img src="/preview/photo?v={{ photo_ver }}" alt="รูปโปรไฟล์ปัจจุบัน">
      <div style="font-size:0.9rem; color:#475569;">
        <strong>รูปภาพปัจจุบัน</strong><br>
        หากไม่เลือกไฟล์ใหม่ ระบบจะคงรูปเดิมไว้ (รองรับ JPG, PNG, WEBP ไม่เกิน 5 MB)
      </div>
    </div>

    <form method="POST" action="/edit/portal" enctype="multipart/form-data">
      <label for="student_name">ชื่อ-นามสกุล นักศึกษา</label>
      <input type="text" id="student_name" name="student_name" value="{{ profile.student_name }}" required maxlength="200">

      <label for="student_id">รหัสนักศึกษา</label>
      <input type="text" id="student_id" name="student_id" value="{{ profile.student_id }}" required maxlength="50">

      <label for="photo">อัปโหลดรูปภาพใหม่ (ไม่บังคับ)</label>
      <input type="file" id="photo" name="photo" accept="image/jpeg,image/png,image/webp">

      <div class="actions">
        <button type="submit">บันทึกข้อมูล Portal</button>
        <a class="link" href="http://www.iam-68130677.com" target="_blank">เปิดดูหน้า Portal ↗</a>
      </div>
    </form>
  </main>
</body>
</html>
"""

EDIT_RESEARCH_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Edit Research - admin-68130677</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, sans-serif;
      background: #0f172a;
      color: #0f172a;
      min-height: 100vh;
      padding: 36px 20px;
    }
    .panel {
      max-width: 820px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 16px;
      padding: 32px 36px;
      box-shadow: 0 12px 30px rgba(0, 0, 0, 0.25);
    }
    .back { display: inline-block; margin-bottom: 14px; color: #0f766e; text-decoration: none; font-weight: 600; font-size: 0.92rem; }
    h1 { font-size: 1.5rem; margin-bottom: 6px; color: #0f766e; }
    .hint { font-size: 0.88rem; color: #64748b; margin-bottom: 20px; }
    .alert { padding: 12px 16px; border-radius: 8px; margin-bottom: 18px; font-weight: 600; font-size: 0.95rem; }
    .alert-ok { background: #dcfce7; color: #166534; border: 1px solid #86efac; }
    .alert-err { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }
    label { display: block; font-weight: 700; margin-bottom: 6px; color: #1e293b; }
    input[type="text"], textarea {
      width: 100%;
      padding: 12px 14px;
      border: 1px solid #cbd5e1;
      border-radius: 8px;
      font-family: inherit;
      font-size: 1rem;
      margin-bottom: 18px;
      line-height: 1.6;
    }
    textarea { min-height: 300px; resize: vertical; }
    .counter { font-size: 0.85rem; color: #64748b; margin-top: -12px; margin-bottom: 18px; }
    .actions { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; }
    button {
      background: #0f766e;
      color: #ffffff;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
    }
    button:hover { background: #115e59; }
    .link { color: #0f766e; text-decoration: none; font-weight: 600; }
  </style>
</head>
<body>
  <main class="panel">
    <a class="back" href="/">← กลับหน้าหลัก Admin Console</a>
    <h1>แก้ไขสรุปงานวิจัยวิชาสัมมนา (app-research)</h1>
    <p class="hint">อัปเดตล่าสุด: {{ data.updated_at }} | บันทึกในฐานข้อมูลกลาง PostgreSQL</p>

    {% if saved %}
      <div class="alert alert-ok">บันทึกสรุปงานวิจัยเรียบร้อยแล้ว — เปิดตรวจสอบได้ที่ www.iam-68130677.com/research</div>
    {% endif %}
    {% if error %}
      <div class="alert alert-err">{{ error }}</div>
    {% endif %}

    <form method="POST" action="/edit/research">
      <label for="title">หัวข้องานวิจัย</label>
      <input type="text" id="title" name="title" value="{{ data.title }}" required maxlength="300">

      <label for="content">เนื้อหาสรุปงานวิจัย (แนะนำ 300 – 500 คำ)</label>
      <textarea id="content" name="content" required>{{ data.content }}</textarea>
      <div class="counter" id="counter">จำนวนตัวอักษร: {{ char_count }}</div>

      <div class="actions">
        <button type="submit">บันทึกสรุปงานวิจัย</button>
        <a class="link" href="http://www.iam-68130677.com/research" target="_blank">เปิดดูหน้า /research ↗</a>
      </div>
    </form>
  </main>
  <script>
    const ta = document.getElementById('content');
    const counter = document.getElementById('counter');
    function updateCount() {
      const text = ta.value.trim();
      const chars = text.length;
      const estWords = chars ? Math.round(chars / 4.5) : 0;
      counter.textContent = 'จำนวนตัวอักษร: ' + chars + ' | ประมาณการจำนวนคำภาษาไทย: ~' + estWords + ' คำ';
    }
    ta.addEventListener('input', updateCount);
    updateCount();
  </script>
</body>
</html>
"""


@app.route("/")
def dashboard():
    profile = db.get_portal_profile(include_photo=False)
    research = db.get_research_summary()
    return render_template_string(
        DASHBOARD_TEMPLATE,
        profile=profile,
        research=research,
        research_chars=len(research["content"]),
        photo_ver=quote(profile["updated_at"]),
        pod_name=os.environ.get("POD_NAME", os.environ.get("HOSTNAME", "local")),
        node_name=os.environ.get("NODE_NAME", "local-node"),
    )


@app.route("/preview/photo")
def preview_photo():
    profile = db.get_portal_profile(include_photo=True)
    resp = Response(bytes(profile["photo_data"]), mimetype=profile["photo_mime"])
    resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    return resp


@app.route("/edit/portal", methods=["GET", "POST"])
def edit_portal():
    if request.method == "POST":
        student_name = request.form.get("student_name", "").strip()
        student_id = request.form.get("student_id", "").strip()
        if not student_name or not student_id:
            profile = db.get_portal_profile(include_photo=False)
            return (
                render_template_string(
                    EDIT_PORTAL_TEMPLATE,
                    profile=profile,
                    photo_ver=quote(profile["updated_at"]),
                    saved=False,
                    error="กรุณากรอกชื่อ-นามสกุลและรหัสนักศึกษาให้ครบถ้วน",
                ),
                400,
            )
        photo_bytes, photo_mime = None, None
        uploaded = request.files.get("photo")
        if uploaded and uploaded.filename:
            try:
                photo_bytes, photo_mime = process_uploaded_photo(uploaded)
            except ValueError as err:
                profile = db.get_portal_profile(include_photo=False)
                return (
                    render_template_string(
                        EDIT_PORTAL_TEMPLATE,
                        profile=profile,
                        photo_ver=quote(profile["updated_at"]),
                        saved=False,
                        error=str(err),
                    ),
                    400,
                )
        db.update_portal_profile(student_name, student_id, photo_bytes, photo_mime)
        return redirect("/edit/portal?saved=1", code=303)

    profile = db.get_portal_profile(include_photo=False)
    return render_template_string(
        EDIT_PORTAL_TEMPLATE,
        profile=profile,
        photo_ver=quote(profile["updated_at"]),
        saved=request.args.get("saved") == "1",
        error=None,
    )


@app.route("/edit/research", methods=["GET", "POST"])
def edit_research():
    if request.method == "POST":
        title = request.form.get("title", "").strip()
        content = request.form.get("content", "").strip()
        if not title or not content:
            data = db.get_research_summary()
            return (
                render_template_string(
                    EDIT_RESEARCH_TEMPLATE,
                    data=data,
                    char_count=len(data["content"]),
                    saved=False,
                    error="กรุณากรอกทั้งหัวข้อและเนื้อหาสรุปงานวิจัยให้ครบถ้วน",
                ),
                400,
            )
        db.update_research_summary(title, content)
        return redirect("/edit/research?saved=1", code=303)

    data = db.get_research_summary()
    return render_template_string(
        EDIT_RESEARCH_TEMPLATE,
        data=data,
        char_count=len(data["content"]),
        saved=request.args.get("saved") == "1",
        error=None,
    )


@app.route("/healthz")
def healthz():
    try:
        db.check_db_health()
        return {"status": "ok", "service": "admin-68130677"}, 200
    except Exception as exc:
        return {"status": "error", "detail": str(exc)}, 503
