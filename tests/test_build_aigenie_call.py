import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SKILL_ROOT = Path(__file__).parents[1]
SCRIPT = SKILL_ROOT / "scripts" / "build_aigenie_call.py"
CONSTRUCT = SKILL_ROOT / "assets" / "construct_template.json"


class BuildAigenieCallValidationTests(unittest.TestCase):
    def test_rejects_item_type_not_declared_in_construct(self):
        with tempfile.TemporaryDirectory() as tmp:
            items = Path(tmp) / "items.csv"
            output = Path(tmp) / "run_genie.R"
            with items.open("w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(
                    f, fieldnames=["type", "attribute", "statement", "ID"]
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "type": "未声明维度",
                        "attribute": "属性",
                        "statement": "我能完成这项任务",
                        "ID": "1",
                    }
                )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(CONSTRUCT),
                    str(items),
                    "-o",
                    str(output),
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("type", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_attribute_not_declared_for_dimension(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            construct = json.loads(CONSTRUCT.read_text(encoding="utf-8"))
            item_type = construct["dimensions"][0]["name"]
            with items.open("w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(
                    f, fieldnames=["type", "attribute", "statement", "ID"]
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "type": item_type,
                        "attribute": "未声明属性",
                        "statement": "我能完成这项任务",
                        "ID": "1",
                    }
                )

            result = self._run_builder(items, output, "--provider", "skip")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("attribute", result.stderr.lower())
            self.assertFalse(output.exists())

    def _run_builder(self, items_path, output_path, *extra):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(CONSTRUCT),
                str(items_path),
                "-o",
                str(output_path),
                *extra,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

    def _write_items(self, path):
        construct = json.loads(CONSTRUCT.read_text(encoding="utf-8"))
        item_type = construct["dimensions"][0]["name"]
        attribute = construct["dimensions"][0]["attributes"][0]
        with path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f, fieldnames=["type", "attribute", "statement", "ID"]
            )
            writer.writeheader()
            writer.writerow(
                {
                    "type": item_type,
                    "attribute": attribute,
                    "statement": "I can complete this task.",
                    "ID": "1",
                }
            )

    def test_precomputed_provider_does_not_require_openai_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            matrix = tmp_path / "embedding.rds"
            matrix.write_text("placeholder", encoding="utf-8")
            self._write_items(items)

            result = self._run_builder(
                items,
                output,
                "--provider",
                "precomputed",
                "--embedding-matrix",
                str(matrix),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            script = output.read_text(encoding="utf-8")
            self.assertIn("embedding_matrix <- readRDS", script)
            self.assertIn(str(matrix.resolve()).replace("\\", "\\\\"), script)
            self.assertIn("embedding.matrix = embedding_matrix", script)
            self.assertIn("missing_ids <- setdiff(items$ID", script)
            self.assertIn("embedding.matrix must be numeric", script)
            self.assertNotIn("OPENAI_API_KEY", script)

    def test_local_provider_generates_local_genie_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            self._write_items(items)

            result = self._run_builder(
                items,
                output,
                "--provider",
                "local",
                "--embedding-model",
                "local-test-model",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            script = output.read_text(encoding="utf-8")
            self.assertIn("local_GENIE(", script)
            self.assertIn('embedding.model = "local-test-model"', script)
            self.assertNotIn("OPENAI_API_KEY", script)


    def test_local_provider_requires_explicit_embedding_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            self._write_items(items)

            result = self._run_builder(items, output, "--provider", "local")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("embedding", result.stderr.lower())
            self.assertFalse(output.exists())

    def test_jina_provider_uses_jina_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            self._write_items(items)

            result = self._run_builder(items, output, "--provider", "jina")

            self.assertEqual(result.returncode, 0, result.stderr)
            script = output.read_text(encoding="utf-8")
            self.assertIn('Sys.getenv("JINA_API_KEY")', script)
            self.assertIn("jina.API = jina_api_key", script)
            self.assertNotIn("OPENAI_API_KEY", script)

    def test_huggingface_provider_uses_hf_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            self._write_items(items)

            result = self._run_builder(items, output, "--provider", "huggingface")

            self.assertEqual(result.returncode, 0, result.stderr)
            script = output.read_text(encoding="utf-8")
            self.assertIn('Sys.getenv("HF_TOKEN")', script)
            self.assertIn("hf.token = hf_token", script)
            self.assertNotIn("OPENAI_API_KEY", script)

    def test_config_file_selects_provider(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            config = tmp_path / "input_config.json"
            self._write_items(items)
            config.write_text(
                json.dumps({"provider": "local", "embedding_model": "local-test-model", "run_overall": False}),
                encoding="utf-8",
            )

            result = self._run_builder(
                items,
                output,
                "--validation-config",
                str(config),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("run.overall = FALSE", output.read_text(encoding="utf-8"))

    def test_skip_provider_writes_unvalidated_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            config = tmp_path / "validation_config.json"
            self._write_items(items)

            result = self._run_builder(
                items,
                output,
                "--provider",
                "skip",
                "--config-output",
                str(config),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(config.read_text(encoding="utf-8"))
            self.assertTrue(payload["items_generated"])
            self.assertFalse(payload["scale_validated"])
            self.assertEqual(payload["validation_status"], "skipped")
            script = output.read_text(encoding="utf-8")
            self.assertIn("validation_status <-", script)
            self.assertIn("encoding = \"UTF-8\"", script)
            self.assertIn("check.names = FALSE", script)
            self.assertNotIn("fileEncoding = \"UTF-8\"", script)
            self.assertIn(str(items.resolve()).replace("\\", "\\\\"), script)
            self.assertNotIn("library(AIGENIE)", script)
            self.assertNotIn("library(EGAnet)", script)
            self.assertNotIn("GENIE(", script)

    def test_missing_provider_is_a_decision_gate_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            self._write_items(items)

            result = self._run_builder(items, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("provider", result.stderr.lower())
            self.assertIn("openai", result.stderr.lower())


    def test_generated_script_freezes_manifest_and_calls_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "items.csv"
            output = tmp_path / "run_genie.R"
            config = tmp_path / "validation_config.json"
            manifest = tmp_path / "genie_input_manifest.json"
            self._write_items(items)

            result = self._run_builder(
                items,
                output,
                "--provider",
                "local",
                "--embedding-model",
                "local-test-model",
                "--config-output",
                str(config),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            script = output.read_text(encoding="utf-8")
            self.assertIn('fileEncoding = "UTF-8-BOM"', script)
            self.assertIn('encoding = "UTF-8"', script)
            self.assertIn('genie_results_raw.rds', script)
            self.assertIn('generate_genie_report', script)
            self.assertIn('--require-core-figures', script)
            self.assertIn('genie_final_items.csv', (SKILL_ROOT / 'scripts' / 'genie_report.R').read_text(encoding='ascii'))
            payload = json.loads(config.read_text(encoding="utf-8"))
            self.assertEqual(payload["genie_input_file"], str(items.resolve()))
            self.assertEqual(payload["genie_input_manifest"], str(manifest.resolve()))
            self.assertTrue(manifest.exists())
            manifest_payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(manifest_payload["input_file"], str(items.resolve()))
            self.assertEqual(manifest_payload["input_rows"], 1)
            self.assertEqual(manifest_payload["provider"], "local")
            self.assertTrue(manifest_payload["generated_items_is_complete_pool"])

    def test_config_input_path_matches_actual_r_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            items = tmp_path / "generated_items.csv"
            output = tmp_path / "run_genie.R"
            config = tmp_path / "validation_config.json"
            self._write_items(items)

            result = self._run_builder(
                items,
                output,
                "--provider",
                "jina",
                "--config-output",
                str(config),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            script = output.read_text(encoding="utf-8")
            payload = json.loads(config.read_text(encoding="utf-8"))
            escaped = str(items.resolve()).replace("\\", "\\\\")
            self.assertIn('input_file <- "' + escaped + '"', script)
            self.assertEqual(payload["genie_input_file"], str(items.resolve()))
            self.assertNotIn("generated_items_genie_input.csv", script)
            self.assertNotIn("generated_items_genie_input.csv", json.dumps(payload))


if __name__ == "__main__":
    unittest.main()
