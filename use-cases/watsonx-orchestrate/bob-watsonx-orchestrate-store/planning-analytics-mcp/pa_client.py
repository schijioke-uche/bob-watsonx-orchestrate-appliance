#!/usr/bin/env python3
"""
IBM Planning Analytics SaaS (AWS) REST API Client
Implements AWS MCSP IAM API-key exchange and authenticated Planning Analytics REST operations.
"""

import os
import sys
import ssl
import json
import logging
import urllib.request
import urllib.error
import urllib.parse
from typing import Dict, Any, Optional

logger = logging.getLogger("pa_client")
logger.setLevel(logging.INFO)
handler = logging.StreamHandler(sys.stderr)
handler.setFormatter(logging.Formatter("[PA-CLIENT] %(levelname)s: %(message)s"))
logger.addHandler(handler)


def get_ssl_context(verify_tls: bool = True, ca_file: Optional[str] = None) -> ssl.SSLContext:
    if not verify_tls:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx

    ca_bundle = ca_file or os.environ.get("PA_CA_BUNDLE") or os.environ.get("SSL_CERT_FILE")
    if not ca_bundle:
        # Check standard system and certifi paths
        candidates = [
            "/etc/ssl/certs/ca-certificates.crt",
            "/etc/pki/tls/certs/ca-bundle.crt",
            "/etc/ssl/ca-bundle.pem",
            "/etc/ssl/cert.pem"
        ]
        try:
            import certifi
            candidates.insert(0, certifi.where())
        except ImportError:
            pass

        for c in candidates:
            if c and os.path.isfile(c):
                ca_bundle = c
                break

    if ca_bundle and os.path.isfile(ca_bundle):
        return ssl.create_default_context(cafile=ca_bundle)
    return ssl.create_default_context()


class PlanningAnalyticsClient:
    def __init__(
        self,
        api_key: Optional[str] = None,
        region: Optional[str] = None,
        api_root: Optional[str] = None,
        tenant_id: Optional[str] = None,
        timeout: int = 30,
        verify_tls: bool = True
    ):
        self.region = (
            region
            or os.environ.get("PA_SAAS_REGION")
            or os.environ.get("PLANNING_ANALYTICS_REGION")
            or "us-east-1"
        )
        self.tenant_id = (
            tenant_id
            or os.environ.get("PLANNING_ANALYTICS_TENANT_ID")
            or "I6LGK60NC25B"
        )
        self.api_root = (
            api_root
            or os.environ.get("PA_TM1_API_ROOT")
            or os.environ.get("PLANNING_ANALYTICS_BASE_URL")
            or f"https://{self.region}.planninganalytics.saas.ibm.com/api/{self.tenant_id}/v0"
        ).rstrip("/")
        
        self.api_key = (
            api_key
            or os.environ.get("PA_API_KEY")
            or os.environ.get("PLANNING_ANALYTICS_API_KEY")
            or ""
        )
        self.timeout = timeout
        self.verify_tls = verify_tls
        self._bearer_token: Optional[str] = None
        self._ssl_ctx = get_ssl_context(verify_tls=self.verify_tls)

    def get_iam_token_url() -> str:
        return f"https://{self.region}.aws.data.ibm.com/api/rest/mcsp/apikeys/token"

    def authenticate_mcsp(self, force_refresh: bool = False) -> str:
        """
        Exchanges the PA SaaS API key for an AWS MCSP IAM Bearer Token.
        """
        if self._bearer_token and not force_refresh:
            return self._bearer_token

        if not self.api_key:
            raise ValueError("PA_API_KEY is missing. Set PA_API_KEY in .env.")

        token_url = f"https://{self.region}.aws.data.ibm.com/api/rest/mcsp/apikeys/token"
        logger.info(f"Authenticating with AWS MCSP IAM at {token_url}...")

        req_payload = json.dumps({"apikey": self.api_key}).encode("utf-8")
        req = urllib.request.Request(
            token_url,
            data=req_payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "IBM-Bob-WXA-PA-MCP/2.0"
            },
            method="POST"
        )

        try:
            with urllib.request.urlopen(req, context=self._ssl_ctx, timeout=self.timeout) as resp:
                raw_body = resp.read().decode("utf-8")
                body = json.loads(raw_body)
                token = body.get("token") or body.get("access_token")
                if not token:
                    raise ValueError(f"MCSP IAM response did not contain a valid token: {raw_body[:200]}")
                self._bearer_token = token
                logger.info("AWS MCSP IAM Bearer token obtained successfully.")
                return token
        except urllib.error.HTTPError as e:
            raw_err = e.read().decode("utf-8", errors="replace")
            logger.error(f"MCSP IAM token exchange failed HTTP {e.code}: {raw_err}")
            raise RuntimeError(f"MCSP IAM HTTP {e.code}: {raw_err}")
        except Exception as e:
            logger.error(f"Network error during MCSP IAM token exchange: {e}")
            raise

    def _request(
        self,
        path: str,
        method: str = "GET",
        payload: Optional[Dict[str, Any]] = None,
        retry_on_401: bool = True
    ) -> Dict[str, Any]:
        """
        Executes an authenticated HTTP request against Planning Analytics REST endpoints.
        """
        token = self.authenticate_mcsp()
        
        if path.startswith("http"):
            url = path
        else:
            url = f"{self.api_root}/{path.lstrip('/')}"

        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "IBM-Bob-WXA-PA-MCP/2.0"
        }

        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(url, data=data, headers=headers, method=method)

        try:
            with urllib.request.urlopen(req, context=self._ssl_ctx, timeout=self.timeout) as response:
                status_code = response.getcode()
                raw_body = response.read().decode("utf-8")
                try:
                    body = json.loads(raw_body) if raw_body else {}
                except json.JSONDecodeError:
                    body = {"raw_response": raw_body}
                return {
                    "success": True,
                    "status_code": status_code,
                    "data": body
                }
        except urllib.error.HTTPError as e:
            if e.code == 401 and retry_on_401:
                logger.warning("HTTP 401 encountered. Refreshing IAM Bearer token and retrying once...")
                self._bearer_token = None
                return self._request(path, method, payload, retry_on_401=False)

            raw_err = e.read().decode("utf-8", errors="replace")
            logger.error(f"HTTP {e.code} error from {url}: {raw_err}")
            try:
                err_data = json.loads(raw_err)
            except Exception:
                err_data = {"error": raw_err}
            return {
                "success": False,
                "status_code": e.code,
                "error": err_data
            }
        except Exception as e:
            logger.error(f"Connection failure to {url}: {e}")
            return {
                "success": False,
                "status_code": 0,
                "error": str(e)
            }

    def verify_connectivity(self) -> Dict[str, Any]:
        """Validates connection and returns user info from /rolemgmt/v1/users/me"""
        logger.info(f"Verifying Planning Analytics identity at: {self.api_root}/rolemgmt/v1/users/me")
        return self._request("rolemgmt/v1/users/me", method="GET")

    def list_cubes(self, db_name: Optional[str] = None) -> Dict[str, Any]:
        """Lists cubes from TM1 REST service"""
        path = f"tm1/api/{db_name}/api/v1/Cubes" if db_name else "api/v1/Cubes"
        return self._request(path, method="GET")

    def list_dimensions(self, db_name: Optional[str] = None) -> Dict[str, Any]:
        """Lists dimensions from TM1 REST service"""
        path = f"tm1/api/{db_name}/api/v1/Dimensions" if db_name else "api/v1/Dimensions"
        return self._request(path, method="GET")

    def execute_mdx(self, mdx_query: str, db_name: Optional[str] = None) -> Dict[str, Any]:
        """Executes an MDX query against the instance"""
        path = f"tm1/api/{db_name}/api/v1/ExecuteMDX" if db_name else "api/v1/ExecuteMDX"
        return self._request(path, method="POST", payload={"MDX": mdx_query})

    def run_process(self, process_name: str, parameters: Optional[Dict[str, Any]] = None, db_name: Optional[str] = None) -> Dict[str, Any]:
        """Triggers a TurboIntegrator process"""
        enc_proc = urllib.parse.quote(process_name)
        path = f"tm1/api/{db_name}/api/v1/Processes('{enc_proc}')/Execute" if db_name else f"api/v1/Processes('{enc_proc}')/Execute"
        return self._request(path, method="POST", payload=parameters or {})
