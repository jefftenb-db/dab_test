import os
import re
from pathlib import Path

import cowsay
import streamlit as st

st.set_page_config(page_title="DAB Demo App", page_icon=":cow:")
st.title("DAB Demo App")

find_links = os.environ.get("PIP_FIND_LINKS", "")
no_index = os.environ.get("PIP_NO_INDEX", "")

catalog = schema = None
env_label = "unknown"
m = re.match(r"/Volumes/([^/]+)/([^/]+)/", find_links)
if m:
    catalog, schema = m.groups()
    if schema.endswith("prod"):
        env_label = "PROD"
    elif schema.endswith("dev"):
        env_label = "DEV"
    else:
        env_label = schema

st.subheader("Environment")
c1, c2 = st.columns(2)
c1.metric("Target", env_label)
c2.metric("Streamlit version", st.__version__)

st.write(f"**UC catalog / schema:** `{catalog}` / `{schema}`")
st.write(f"**`PIP_FIND_LINKS` (volume path):** `{find_links or '(unset)'}`")
st.write(f"**`PIP_NO_INDEX`:** `{no_index or '(unset)'}`")

st.subheader("Library loaded from UC Volume")
st.code(cowsay.get_output_string("cow", f"Hello from {env_label}!"), language="text")

req_file = Path(__file__).parent / "requirements.txt"
with st.expander("requirements.txt (static in git — pip uses PIP_NO_INDEX + PIP_FIND_LINKS at install time)"):
    st.code(req_file.read_text() if req_file.exists() else "(missing)", language="text")
