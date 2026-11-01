"""API contract tests use a stub pipeline; they do not validate ML inference."""
import os
import tempfile
import unittest
from unittest.mock import patch
os.environ['COVER_DATA'] = tempfile.mkdtemp(prefix='cover-api-test-')
os.environ['COVER_TOKEN'] = 'test-only-token'
from fastapi.testclient import TestClient
import server
from pipeline import make_guide

class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(server.app)
        self.headers = {'Authorization': 'Bearer test-only-token'}
        server.active = False
    def test_auth_required(self):
        self.assertEqual(self.client.get('/health').status_code, 401)
    def test_range_rejected_before_upload(self):
        for start,end in [(0,61),(5,2),(-1,3),('nan',3)]:
            r=self.client.post(f'/jobs?start={start}&end={end}',content=b'audio',headers=self.headers)
            self.assertEqual(r.status_code,422)
    def test_empty_upload_releases_slot(self):
        r=self.client.post('/jobs?start=0&end=5',content=b'',headers=self.headers)
        self.assertEqual(r.status_code,400)
        self.assertFalse(server.active)
    def test_busy_rejected(self):
        server.active=True
        r=self.client.post('/jobs?start=0&end=5',content=b'x',headers=self.headers)
        self.assertEqual(r.status_code,409)
    def test_roundtrip_and_disk_recovery(self):
        def fake(folder,start,end,progress):
            progress('test')
            (folder/'vocals.wav').write_bytes(b'test-wav')
            (folder/'backing.wav').write_bytes(b'test-wav')
            return make_guide([(0,1,60,.9)],end-start,start)
        with patch.object(server,'run',fake), patch.object(server.executor,'submit',lambda f,*a:f(*a)):
            r=self.client.post('/jobs?start=60&end=65',content=b'test-input',headers=self.headers)
        self.assertEqual(r.status_code,202)
        job=r.json()['id']
        status=self.client.get('/jobs/'+job,headers=self.headers).json()
        self.assertEqual(status['status'],'complete')
        self.assertEqual(status['result']['sourceOffset'],60)
        self.assertEqual(self.client.get('/jobs/'+job+'/backing',headers=self.headers).content,b'test-wav')
        server.jobs.clear()
        self.assertEqual(self.client.get('/jobs/'+job,headers=self.headers).json()['status'],'complete')
        self.assertEqual(self.client.get('/jobs/'+job+'/source',headers=self.headers).status_code,404)
    def test_unknown_job(self):
        self.assertEqual(self.client.get('/jobs/not-a-uuid',headers=self.headers).status_code,404)

if __name__=='__main__': unittest.main()
