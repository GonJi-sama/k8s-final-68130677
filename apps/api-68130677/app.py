import os
from flask import Flask, render_template_string

app = Flask(__name__)

API_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>API Display - {{ message }}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, sans-serif;
      background: #0f172a;
      color: #f8fafc;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 32px;
    }
    .message {
      font-size: clamp(3rem, 10vw, 7rem);
      font-weight: 800;
      line-height: 1.2;
      word-break: break-word;
      max-width: 92vw;
      color: #38bdf8;
      text-shadow: 0 4px 28px rgba(56, 189, 248, 0.3);
    }
    .meta {
      position: fixed;
      bottom: 18px;
      font-size: 0.85rem;
      color: #94a3b8;
    }
  </style>
</head>
<body>
  <main class="message">{{ message }}</main>
  <div class="meta">Deployment: api-68130677 | Pod: {{ pod_name }} | Node: {{ node_name }}</div>
</body>
</html>
"""


@app.route("/api-68130677", strict_slashes=False)
def api_root():
    return render_template_string(
        API_TEMPLATE,
        message="Hello",
        pod_name=os.environ.get("POD_NAME", os.environ.get("HOSTNAME", "local")),
        node_name=os.environ.get("NODE_NAME", "local-node"),
    )


@app.route("/api-68130677/<path:message>")
def api_display(message):
    return render_template_string(
        API_TEMPLATE,
        message=message,
        pod_name=os.environ.get("POD_NAME", os.environ.get("HOSTNAME", "local")),
        node_name=os.environ.get("NODE_NAME", "local-node"),
    )


@app.route("/healthz")
def healthz():
    return {"status": "ok", "service": "api-68130677"}, 200
