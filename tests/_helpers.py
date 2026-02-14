"""Shared helper to import sort-Xcode-project-file.py despite hyphens in name."""

import importlib.util
import os

def _import_sorter():
    script_path = os.path.join(os.path.dirname(__file__), "..", "sort-Xcode-project-file.py")
    script_path = os.path.normpath(script_path)
    spec = importlib.util.spec_from_file_location("sort_xcode_project_file", script_path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

sorter = _import_sorter()
