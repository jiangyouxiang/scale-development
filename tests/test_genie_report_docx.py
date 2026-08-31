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
                self.assertIn("Russell-Lasalandra", xml)
                self.assertIn("10.3758/s13428-026-03082-1", xml)
                self.assertIn("in-silico", xml)
                self.assertIn("UVA", xml)
                self.assertIn("EGA", xml)
                self.assertIn("bootEGA", xml)
                self.assertNotIn("&lt;U+", xml)

    def test_docx_contains_reverse_item_risk_when_manifest_requests_it(self):
        if not R.exists():
            self.skipTest(f"Rscript not found: {R}")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            manifest = out / "manifest_reverse.json"
            manifest.write_text(
                '{"provider":"local","embedding_model":"BAAI/bge-m3","input_rows":4,"run_overall":true,"uva_cut_off":0.2,"reverse_items":{"include":true,"ratio":"4:1","policy":"explicit_user_requested_high_risk"},"method_reference":{"citation":"Russell-Lasalandra, Christensen, & Golino (2026)","title":"Generative psychometrics via AI-GENIE: Automatic item generation and validation with network-integrated evaluation","journal":"Behavior Research Methods","doi":"10.3758/s13428-026-03082-1"},"skill_version":"0.1.0-rc2"}',
                encoding="utf-8",
            )
            r_script = R_SCRIPT.as_posix()
            fake_results = (FIXTURES / "fake_genie_results_raw.rds").as_posix()
            fake_items = (FIXTURES / "fake_items.csv").as_posix()
            out_dir = out.as_posix()
            manifest_file = manifest.as_posix()
            r_code = (
                "source('" + r_script + "', local=TRUE, encoding='UTF-8'); "
                "generate_genie_report('" + fake_results + "', "
                "'" + fake_items + "', "
                "'" + out_dir + "', "
                "'" + manifest_file + "', character())"
            )
            result = subprocess.run([str(R), "-e", r_code], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stderr)
            md = out / "genie_validation_report.md"
            docx = out / "genie_validation_report.docx"
            result = subprocess.run(
                [sys.executable, str(DOCX_SCRIPT), "--markdown", str(md), "--output", str(docx), "--report-dir", str(out), "--require-core-figures"],
                capture_output=True, text=True, encoding="utf-8"
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            with zipfile.ZipFile(docx) as zf:
                xml = zf.read("word/document.xml").decode("utf-8")
                self.assertIn("反向题高风险提示", xml)
                self.assertIn("题池包含反向题", xml)
                self.assertIn("Russell-Lasalandra", xml)
                self.assertNotIn("&lt;U+", xml)

    def test_docx_uses_neutral_reverse_item_text_by_default(self):
        if not R.exists():
            self.skipTest(f"Rscript not found: {R}")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            env = os.environ.copy(); env["GENIE_REPORT_DIRECT"] = "1"
            result = subprocess.run([str(R), str(R_SCRIPT), str(FIXTURES / "fake_genie_results_raw.rds"), str(FIXTURES / "fake_items.csv"), str(out)], env=env, capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stderr)
            docx = out / "genie_validation_report.docx"
            result = subprocess.run(
                [sys.executable, str(DOCX_SCRIPT), "--markdown", str(out / "genie_validation_report.md"), "--output", str(docx), "--report-dir", str(out), "--require-core-figures"],
                capture_output=True, text=True, encoding="utf-8"
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            with zipfile.ZipFile(docx) as zf:
                xml = zf.read("word/document.xml").decode("utf-8")
                self.assertIn("本次 manifest 未标记包含反向题", xml)
                self.assertNotIn("本次 manifest 标记包含反向题", xml)
                self.assertNotIn("反向题高风险提示", xml)

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
