import tempfile
import threading
import unittest
import time
import json
import ssl
import urllib.request
import urllib.error
from pathlib import Path
from bridge import Bridge, certificate, make_server, sanitize

class BridgeTests(unittest.TestCase):
    def test_whitelist_and_staleness(self):
        data={"status":"ok","updatedAt":int(time.time()),"secret":"DO NOT SEND","fiveHour":{"remaining":75,"resetsAt":int(time.time())+600},"weekly":{"remaining":5,"resetsAt":int(time.time())+600}}
        self.assertEqual(sanitize(data)["status"],"ok")
        self.assertNotIn("secret",sanitize(data))
        data["weekly"]["remaining"]=float("nan")
        self.assertEqual(sanitize(data)["status"],"stale")

    def test_tls_pairing_one_use_and_authorization(self):
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp); b=Bridge(state); cert,key,pin=certificate(state,"127.0.0.1")
            server=make_server(b,"127.0.0.1",0,cert,key)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            context=ssl.create_default_context(cafile=str(cert))
            base=f"https://127.0.0.1:{server.server_port}"
            def request(path,token,method="GET"):
                r=urllib.request.Request(base+path,headers={"Authorization":"Bearer "+token},method=method)
                opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context))
                return json.loads(opener.open(r,timeout=5).read())
            try:
                with self.assertRaises(urllib.error.HTTPError):request("/usage","bad")
                invite=b.invite
                token=request("/pair",invite,"POST")["token"]
                with self.assertRaises(urllib.error.HTTPError):request("/pair",invite,"POST")
                self.assertEqual(request("/usage",token)["status"],"stale")
                self.assertNotIn(token,(state/"devices.json").read_text())
                self.assertEqual(len(pin),64)
            finally:server.shutdown();server.server_close();thread.join()

if __name__=="__main__":unittest.main()
