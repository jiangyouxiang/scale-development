from __future__ import annotations
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
R_SCRIPT = ROOT / "scripts" / "genie_report.R"
DOCX_SCRIPT = ROOT / "scripts" / "genie_report_docx.py"
FIXTURES = ROOT / "tests" / "fixtures"
R = Path(os.environ["RSCRIPT"]) if os.environ.get("RSCRIPT") else Path(shutil.which("Rscript") or "Rscript")

class GenieReportDocxTests(unittest.TestCase):
    def test_docx_contains_report_text_and_images(self):
        if not R.exists():
            self.skipTest(f"Rscript not found: {R}")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            env = os.environ.copy(); env["GENIE_REPORT_DIRECT"] = "1"
            result = subprocess.run([str(R), str(R_SCRIPT), str(FIXTURES / "fake_genie_results_raw.rds"), str(FIXTURES / "fake_items.csv"), str(out)], env=env, capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stderr)
            md = out / "genie_validation_report.md"
            docx = out / "genie_validation_report.docx"
            result = subprocess.run([sys.executable, str(DOCX_SCRIPT), "--markdown", str(md), "--output", str(docx), "--report-dir", str(out)], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(docx.exists())
            with zipfile.ZipFile(docx) as zf:
                self.assertIsNone(zf.testzip())
                media = [n for n in zf.namelist() if n.startswith("word/media/")]
                self.assertGreaterEqual(len(media), 4)
                xml = zf.read("word/document.xml").decode("utf-8")
                self.assertIn("GENIE", xml)
                self.assertNotIn("&lt;U+", xml)

    def test_markdown_forward_slash_images_are_embedded(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            fig_dir = out / "figures"
            fig_dir.mkdir()
            # A tiny valid PNG keeps this test independent of R and plotting packages.
            png = bytes.fromhex(
                "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
                "1f15c4890000000d49444154789c6360f8cf00000004000101"
                "00b5cddf0000000049454e44ae426082"
            )
            (fig_dir / "portable.png").write_bytes(png)
            md = out / "report.md"
            md.write_text("# Portable\n\n![Figure](figures/portable.png)\n", encoding="utf-8")
            docx = out / "report.docx"
            result = subprocess.run(
                [sys.executable, str(DOCX_SCRIPT), "--markdown", str(md), "--output", str(docx), "--report-dir", str(out)],
                capture_output=True, text=True, encoding="utf-8"
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            with zipfile.ZipFile(docx) as zf:
                self.assertTrue(any(name.startswith("word/media/") for name in zf.namelist()))

    def test_strict_mode_rejects_missing_core_figures(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            md = out / "report.md"
            md.write_text("# Report\n", encoding="utf-8")
            docx = out / "report.docx"
            result = subprocess.run(
                [sys.executable, str(DOCX_SCRIPT), "--markdown", str(md), "--output", str(docx), "--report-dir", str(out), "--require-core-figures"],
                capture_output=True, text=True, encoding="utf-8"
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing core report figures", result.stderr)

if __name__ == "__main__":
    unittest.main()
