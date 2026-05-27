import re
from pathlib import Path

import cowsay
import streamlit as st

st.set_page_config(page_title="DAB Demo App", page_icon=":cow:")
st.title("DAB Demo App")

req_path = Path(__file__).parent / "requirements.txt"
volume_path = None
catalog = schema = None
env_label = "unknown"

if req_path.exists():
    for line in req_path.read_text().splitlines():
        if line.startswith("--find-links"):
            volume_path = line.split(maxsplit=1)[1].strip()
            break

if volume_path:
    m = re.match(r"/Volumes/([^/]+)/([^/]+)/", volume_path)
    if m:
        catalog, schema = m.groups()
        if schema.endswith("prod"):
            env_label = "PROD"
        elif schema.endswith("dev"):
            env_label = "DEV"
        else:
            env_label = schema

st.subheader("Environment")
col1, col2 = st.columns(2)
col1.metric("Target", env_label)
col2.metric("Streamlit version", st.__version__)

st.write(f"**UC catalog / schema:** `{catalog}` / `{schema}`")
st.write(f"**Wheel source:** `{volume_path}`")

st.subheader("Library loaded from UC Volume")
st.code(cowsay.get_output_string("cow", f"Hello from {env_label}!"), language="text")

with st.expander("requirements.txt actually installed at deploy time"):
    st.code(req_path.read_text() if req_path.exists() else "(missing)", language="text")
