import sys
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import server as host_server  # noqa: E402


class SafeNameTests(unittest.TestCase):
    def test_accepts_simple_name(self):
        self.assertEqual(host_server.safe_name("notes.txt"), "notes.txt")

    def test_strips_directory_components(self):
        self.assertEqual(host_server.safe_name("a/b/c.txt"), "c.txt")

    def test_rejects_empty_and_dotdot(self):
        with self.assertRaises(ValueError):
            host_server.safe_name("")
        with self.assertRaises(ValueError):
            host_server.safe_name("..")
        # Path traversal prefixes are stripped to basename (same as a/b/c.txt → c.txt)
        self.assertEqual(host_server.safe_name("../x"), "x")


class ServerIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.storage = Path(self.tmp.name) / "storage"
        self.clients = Path(self.tmp.name) / "clients"
        self.storage.mkdir()
        self.clients.mkdir()
        (self.clients / "bash.sh").write_text("echo bash-client\n")
        (self.clients / "ruby.rb").write_text("# ruby-client\n")
        self.httpd = host_server.make_server(
            "127.0.0.1",
            0,
            storage_dir=self.storage,
            clients_dir=self.clients,
        )
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def _conn(self):
        return HTTPConnection("127.0.0.1", self.port, timeout=5)

    def test_serves_clients(self):
        conn = self._conn()
        conn.request("GET", "/clients/bash.sh")
        resp = conn.getresponse()
        body = resp.read().decode()
        self.assertEqual(resp.status, 200)
        self.assertIn("bash-client", body)

    def test_send_and_receive_overwrite(self):
        conn = self._conn()
        conn.request(
            "POST",
            "/send?name=hello.txt",
            body=b"first",
            headers={"Content-Type": "application/octet-stream"},
        )
        self.assertEqual(conn.getresponse().status, 200)
        conn.close()

        conn = self._conn()
        conn.request(
            "POST",
            "/send?name=hello.txt",
            body=b"second",
            headers={"Content-Type": "application/octet-stream"},
        )
        self.assertEqual(conn.getresponse().status, 200)
        conn.close()

        self.assertEqual((self.storage / "hello.txt").read_bytes(), b"second")

        conn = self._conn()
        conn.request("GET", "/files/hello.txt")
        resp = conn.getresponse()
        self.assertEqual(resp.status, 200)
        self.assertEqual(resp.read(), b"second")
        conn.close()

    def test_receive_missing_is_404(self):
        conn = self._conn()
        conn.request("GET", "/files/missing.txt")
        self.assertEqual(conn.getresponse().status, 404)
        conn.close()

    def test_send_rejects_bad_name(self):
        conn = self._conn()
        conn.request("POST", "/send?name=..", body=b"x")
        self.assertEqual(conn.getresponse().status, 400)
        conn.close()


class EncryptServerTests(unittest.TestCase):
    KEY = "test-session-key"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.storage = Path(self.tmp.name) / "storage"
        self.clients = Path(self.tmp.name) / "clients"
        self.storage.mkdir()
        self.clients.mkdir()
        self.httpd = host_server.make_server(
            "127.0.0.1",
            0,
            storage_dir=self.storage,
            clients_dir=self.clients,
            sft_key=self.KEY,
        )
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def _conn(self):
        return HTTPConnection("127.0.0.1", self.port, timeout=5)

    def test_rejects_plaintext_upload(self):
        conn = self._conn()
        conn.request(
            "POST",
            "/send?name=plain.txt",
            body=b"not-encrypted",
            headers={"Content-Type": "application/octet-stream"},
        )
        self.assertEqual(conn.getresponse().status, 400)
        conn.close()
        self.assertFalse((self.storage / "plain.txt").exists())

    def test_encrypted_roundtrip_stores_plaintext(self):
        plain = b"secret payload"
        cipher = host_server.openssl_crypt(plain, key=self.KEY, decrypt=False)

        conn = self._conn()
        conn.request(
            "POST",
            "/send?name=secret.txt",
            body=cipher,
            headers={"Content-Type": "application/octet-stream"},
        )
        self.assertEqual(conn.getresponse().status, 200)
        conn.close()

        self.assertEqual((self.storage / "secret.txt").read_bytes(), plain)

        conn = self._conn()
        conn.request("GET", "/files/secret.txt")
        resp = conn.getresponse()
        self.assertEqual(resp.status, 200)
        wire = resp.read()
        conn.close()

        self.assertNotEqual(wire, plain)
        self.assertEqual(
            host_server.openssl_crypt(wire, key=self.KEY, decrypt=True), plain
        )


if __name__ == "__main__":
    unittest.main()
