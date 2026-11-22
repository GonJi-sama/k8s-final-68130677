import os
import time
from datetime import datetime, timezone, timedelta
import psycopg2
from psycopg2.extras import RealDictCursor

TH_TZ = timezone(timedelta(hours=7))

DEFAULT_STUDENT_NAME = os.environ.get("DEFAULT_STUDENT_NAME", "นายธรรมฤทธิ์ ธนอนันต์")
DEFAULT_STUDENT_ID = os.environ.get("DEFAULT_STUDENT_ID", "68130677")
DEFAULT_RESEARCH_TITLE = (
    "ตัวอย่างหัวข้องานวิจัยวิชาสัมมนา (แก้ไขได้ผ่าน admin.iam-68130677.com)"
)
DEFAULT_RESEARCH_CONTENT = (
    "[ข้อความตัวอย่าง — กรุณาเข้าไปแก้ไขเป็นสรุปงานวิจัยจริงประมาณ 300–500 คำ ที่หน้า http://admin.iam-68130677.com]\n\n"
    "งานวิจัยนี้ศึกษาการออกแบบและพัฒนาสถาปัตยกรรมไมโครเซอร์วิส (Microservices Architecture) "
    "บนคลัสเตอร์ Kubernetes แบบหลายโหนดจำนวน 3 โหนด (1 Control-Plane และ 2 Worker Nodes) "
    "เพื่อยกระดับความพร้อมใช้งานสูง (High Availability) ความสามารถในการขยายระบบในแนวนอน "
    "และความมั่นคงปลอดภัยของระบบให้บริการเว็บแอปพลิเคชันในองค์กรยุคใหม่ "
    "โดยสถาปัตยกรรมแบบดั้งเดิม (Monolithic Architecture) มักมีข้อจำกัดในการปรับขนาดเฉพาะบริการ "
    "รวมถึงความเสี่ยงที่ความล้มเหลวขององค์ประกอบหนึ่งจะกระทบต่อระบบทั้งหมด\n\n"
    "ในการดำเนินงานได้แยกบริการออกเป็น 4 ไมโครเซอร์วิสหลัก ได้แก่ บริการหน้าโปรไฟล์นักศึกษา (portal-68130677) "
    "บริการแสดงสรุปงานวิจัย (app-research) บริการแสดงข้อความผ่านส่วนติดต่อโปรแกรมประยุกต์ (api-68130677) "
    "และบริการจัดการเนื้อหาสำหรับผู้ดูแลระบบ (admin-68130677) โดยกำหนดให้แต่ละบริการทำงานจำนวน 2 Replicas "
    "พร้อมเงื่อนไข topologySpreadConstraints เพื่อกระจายพอดข้าม Worker Node ทั้งสองโหนดอย่างสมดุล "
    "และใช้ NGINX Ingress Controller บนโหนดควบคุมในการกำหนดเส้นทางแบบ Host-based และ Path-based Routing\n\n"
    "สำหรับการแชร์ข้อมูลระหว่างบริการข้ามหลายโหนด ได้เลือกใช้ฐานข้อมูลกลาง PostgreSQL 16 "
    "ร่วมกับ PersistentVolumeClaim (PVC) แทนการผูกไฟล์ท้องถิ่นไว้กับโหนดใดโหนดหนึ่ง "
    "ทำให้หน้าผู้ดูแลระบบสามารถปรับปรุงข้อมูลโปรไฟล์ อัปโหลดรูปภาพใหม่ และแก้ไขสรุปงานวิจัยได้ทันที "
    "โดยทุก Replica ของ portal-68130677 และ app-research จะแสดงข้อมูลที่สอดคล้องกันแบบเรียลไทม์ "
    "พร้อมทั้งกำหนด Resource Requests/Limits, Non-root Security Context, Liveness และ Readiness Probes "
    "ผลการทดลองยืนยันว่าระบบสามารถรับมือกับการรีสตาร์ตพอดโดยข้อมูลไม่สูญหาย "
    "และรองรับการปรับใช้แบบอัตโนมัติในคำสั่งเดียวได้อย่างมีประสิทธิภาพ"
)

_SCHEMA_READY = False


def now_str():
    return datetime.now(TH_TZ).strftime("%Y-%m-%d %H:%M:%S (UTC+7)")


def load_default_photo():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    static_dir = os.path.join(base_dir, "static")
    for fname in ("profile.jpg", "profile.jpeg", "profile.png", "default_profile.png"):
        fpath = os.path.join(static_dir, fname)
        if os.path.exists(fpath):
            mime = "image/jpeg" if fname.endswith((".jpg", ".jpeg")) else "image/png"
            with open(fpath, "rb") as f:
                return f.read(), mime
    # Minimal 1x1 transparent PNG fallback
    tiny_png = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01"
        b"\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    return tiny_png, "image/png"


def get_conn():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "svc-postgres"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "k8s_68130677"),
        user=os.environ.get("DB_USER", "appuser"),
        password=os.environ.get("DB_PASSWORD", "SecurePass68130677!"),
        connect_timeout=5,
    )


def ensure_schema(retries=5, delay=1.0):
    global _SCHEMA_READY
    if _SCHEMA_READY:
        return
    last_err = None
    for attempt in range(retries):
        try:
            with get_conn() as conn:
                with conn.cursor() as cur:
                    # Transaction-level advisory lock prevents race conditions across multi-node replicas
                    cur.execute("SELECT pg_advisory_xact_lock(68130677);")
                    cur.execute(
                        """
                        CREATE TABLE IF NOT EXISTS portal_profile (
                            id INTEGER PRIMARY KEY CHECK (id = 1),
                            student_name TEXT NOT NULL,
                            student_id TEXT NOT NULL,
                            photo_mime TEXT NOT NULL,
                            photo_data BYTEA NOT NULL,
                            updated_at TEXT NOT NULL
                        );
                        """
                    )
                    cur.execute(
                        """
                        CREATE TABLE IF NOT EXISTS research_summary (
                            id INTEGER PRIMARY KEY CHECK (id = 1),
                            title TEXT NOT NULL,
                            content TEXT NOT NULL,
                            updated_at TEXT NOT NULL
                        );
                        """
                    )
                    cur.execute("SELECT 1 FROM portal_profile WHERE id = 1;")
                    if cur.fetchone() is None:
                        photo_bytes, photo_mime = load_default_photo()
                        cur.execute(
                            """
                            INSERT INTO portal_profile (id, student_name, student_id, photo_mime, photo_data, updated_at)
                            VALUES (1, %s, %s, %s, %s, %s)
                            ON CONFLICT (id) DO NOTHING;
                            """,
                            (
                                DEFAULT_STUDENT_NAME,
                                DEFAULT_STUDENT_ID,
                                photo_mime,
                                psycopg2.Binary(photo_bytes),
                                now_str(),
                            ),
                        )
                    cur.execute("SELECT 1 FROM research_summary WHERE id = 1;")
                    if cur.fetchone() is None:
                        cur.execute(
                            """
                            INSERT INTO research_summary (id, title, content, updated_at)
                            VALUES (1, %s, %s, %s)
                            ON CONFLICT (id) DO NOTHING;
                            """,
                            (DEFAULT_RESEARCH_TITLE, DEFAULT_RESEARCH_CONTENT, now_str()),
                        )
            _SCHEMA_READY = True
            return
        except Exception as exc:
            last_err = exc
            if attempt < retries - 1:
                time.sleep(delay)
    raise last_err


def get_portal_profile(include_photo=False):
    ensure_schema()
    cols = (
        "student_name, student_id, photo_mime, photo_data, updated_at"
        if include_photo
        else "student_name, student_id, photo_mime, updated_at"
    )
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(f"SELECT {cols} FROM portal_profile WHERE id = 1;")
            row = cur.fetchone()
            return dict(row) if row else None


def update_portal_profile(student_name, student_id, photo_bytes=None, photo_mime=None):
    ensure_schema()
    ts = now_str()
    with get_conn() as conn:
        with conn.cursor() as cur:
            if photo_bytes is not None and photo_mime is not None:
                cur.execute(
                    """
                    UPDATE portal_profile
                    SET student_name = %s,
                        student_id = %s,
                        photo_mime = %s,
                        photo_data = %s,
                        updated_at = %s
                    WHERE id = 1;
                    """,
                    (
                        student_name.strip(),
                        student_id.strip(),
                        photo_mime,
                        psycopg2.Binary(photo_bytes),
                        ts,
                    ),
                )
            else:
                cur.execute(
                    """
                    UPDATE portal_profile
                    SET student_name = %s,
                        student_id = %s,
                        updated_at = %s
                    WHERE id = 1;
                    """,
                    (student_name.strip(), student_id.strip(), ts),
                )


def get_research_summary():
    ensure_schema()
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT title, content, updated_at FROM research_summary WHERE id = 1;")
            row = cur.fetchone()
            return dict(row) if row else None


def update_research_summary(title, content):
    ensure_schema()
    ts = now_str()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE research_summary
                SET title = %s,
                    content = %s,
                    updated_at = %s
                WHERE id = 1;
                """,
                (title.strip(), content.strip(), ts),
            )


def check_db_health():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()
    return True
