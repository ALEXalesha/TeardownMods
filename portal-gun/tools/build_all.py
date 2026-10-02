"""Rebuild assets and run all offline checks.

    ..\\_shared\\.venv\\Scripts\\python tools\\build_all.py
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.exit(subprocess.call([sys.executable, os.path.join(HERE, "..", "..", "_shared", "tdlib", "build_mod.py"), os.path.join(HERE, "..")]))
