#!/usr/bin/env python3
"""Run approved Arm C branch 4 using the reviewed shared implementation."""
import runpy
from pathlib import Path

source = Path(__file__).with_name("run_context_searchlight_branch3_final_20260909.py")
text = source.read_text()
text = text.replace('"n_test_predictions": 80,', '"n_test_predictions": len(folds) * 2,')
text = text.replace('"accuracy_quantization_percentage_points": 1.25,', '"accuracy_quantization_percentage_points": 100.0 / (len(folds) * 2),')
if '"n_test_predictions": len(folds) * 2,' not in text:
    raise RuntimeError("Failed to specialize n_test_predictions")
if '"accuracy_quantization_percentage_points": 100.0 / (len(folds) * 2),' not in text:
    raise RuntimeError("Failed to specialize quantization metadata")
code = compile(text, str(source), "exec")
exec(code, {"__name__": "__main__", "__file__": str(source)})
