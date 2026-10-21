#!/usr/bin/env python3
"""
IBM Planning Analytics SaaS MCP Server
Implements JSON-RPC 2.0 Model Context Protocol for Planning Analytics on AWS.
"""

import os
import sys
import json
import logging
from typing import Dict, Any, List, Optional

# Ensure all logging goes to stderr so stdout remains clean for JSON-RPC
logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="[PA-MCP-SERVER] %(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("pa_mcp_server")


def load_env_file():
    """Locate and load .env from project root if not already populated."""
    env_file = os.environ.get("ENV_FILE")
    if not env_file or not os.path.exists(env_file):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        candidates = [
            os.path.join(script_dir, "..", "..", ".env"),
            os.path.join(script_dir, "..", ".env"),
            os.path.join(script_dir, ".env"),
        ]
        for candidate in candidates:
            cand_path = os.path.abspath(candidate)
            if os.path.isfile(cand_path):
                env_file = cand_path
                break

    if env_file and os.path.isfile(env_file):
        logger.info(f"Loading environment from: {env_file}")
        try:
            with open(env_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if line.startswith("export "):
                        line = line[7:].strip()
                    if "=" in line:
                        k, v = line.split("=", 1)
                        k = k.strip()
                        v = v.strip().strip("'\"")
                        if k and k not in os.environ:
                            os.environ[k] = v
        except Exception as e:
            logger.warning(f"Could not load .env file: {e}")


# Pre-load environment before importing client
load_env_file()

# Import the Planning Analytics client
try:
    from pa_client import PlanningAnalyticsClient
except ImportError:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, script_dir)
    from pa_client import PlanningAnalyticsClient


SERVER_INFO = {
    "name": "ibm-planning-analytics-mcp-server",
    "version": "1.0.0"
}

PROTOCOL_VERSION = "2024-11-05"

TOOLS: List[Dict[str, Any]] = [
    {
        "name": "pa_verify_connectivity",
        "description": "Verifies connectivity to IBM Planning Analytics SaaS on AWS and retrieves the authenticated user profile and roles.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "pa_get_user_info",
        "description": "Retrieves the current user identity, tenant info, and role assignments from Planning Analytics role management.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "pa_list_cubes",
        "description": "Lists all cubes available in the Planning Analytics / TM1 instance.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "db_name": {
                    "type": "string",
                    "description": "Optional TM1 database name if querying a specific database"
                }
            },
            "required": []
        }
    },
    {
        "name": "pa_list_dimensions",
        "description": "Lists all dimensions defined in the Planning Analytics instance.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "db_name": {
                    "type": "string",
                    "description": "Optional TM1 database name if querying a specific database"
                }
            },
            "required": []
        }
    },
    {
        "name": "pa_execute_mdx",
        "description": "Executes a multidimensional expression (MDX) query against Planning Analytics and returns cell data.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "mdx": {
                    "type": "string",
                    "description": "The MDX query string to execute"
                },
                "db_name": {
                    "type": "string",
                    "description": "Optional TM1 database name"
                }
            },
            "required": ["mdx"]
        }
    },
    {
        "name": "pa_run_process",
        "description": "Executes a TurboIntegrator (TI) process in Planning Analytics with optional parameters.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "process_name": {
                    "type": "string",
                    "description": "Name of the TurboIntegrator process"
                },
                "parameters": {
                    "type": "object",
                    "description": "Key-value map of process parameters",
                    "default": {}
                },
                "db_name": {
                    "type": "string",
                    "description": "Optional TM1 database name"
                }
            },
            "required": ["process_name"]
        }
    }
]


class PAMCPServer:
    def __init__(self):
        self.pa_client = PlanningAnalyticsClient()
        self.mcp_api_key = os.environ.get("WXO_MCP_CONN_API_KEY") or os.environ.get("PA_MCP_SERVER_API_KEY", "")

    def handle_request(self, request: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        req_id = request.get("id")
        method = request.get("method")
        params = request.get("params", {})

        logger.info(f"Handling JSON-RPC method: {method}")

        if method == "initialize":
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {
                        "tools": {"listChanged": False}
                    },
                    "serverInfo": SERVER_INFO
                }
            }

        elif method == "notifications/initialized":
            logger.info("Client initialized notification received.")
            return None

        elif method == "ping":
            return {"jsonrpc": "2.0", "id": req_id, "result": {}}

        elif method == "tools/list":
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "tools": TOOLS
                }
            }

        elif method == "tools/call":
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            return self.call_tool(req_id, tool_name, arguments)

        else:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }

    def call_tool(self, req_id: Any, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        logger.info(f"Executing tool: {tool_name}")
        
        try:
            if tool_name in ("pa_verify_connectivity", "pa_get_user_info"):
                res = self.pa_client.verify_connectivity()
            elif tool_name == "pa_list_cubes":
                db = arguments.get("db_name")
                res = self.pa_client.list_cubes(db_name=db)
            elif tool_name == "pa_list_dimensions":
                db = arguments.get("db_name")
                res = self.pa_client.list_dimensions(db_name=db)
            elif tool_name == "pa_execute_mdx":
                mdx = arguments.get("mdx", "")
                db = arguments.get("db_name")
                res = self.pa_client.execute_mdx(mdx, db_name=db)
            elif tool_name == "pa_run_process":
                proc = arguments.get("process_name", "")
                params = arguments.get("parameters", {})
                db = arguments.get("db_name")
                res = self.pa_client.run_process(proc, params, db_name=db)
            else:
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {
                        "code": -32602,
                        "message": f"Unknown tool: {tool_name}"
                    }
                }

            text_content = json.dumps(res, indent=2)
            is_error = not res.get("success", False)

            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": text_content
                        }
                    ],
                    "isError": is_error
                }
            }
        except Exception as e:
            logger.error(f"Error executing {tool_name}: {e}")
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({"error": str(e), "success": False})
                        }
                    ],
                    "isError": True
                }
            }

    def run_stdio(self):
        logger.info("Starting IBM Planning Analytics MCP Server over stdio...")
        while True:
            try:
                line = sys.stdin.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                
                try:
                    request = json.loads(line)
                except json.JSONDecodeError as e:
                    logger.error(f"Malformed JSON received: {e}")
                    continue

                response = self.handle_request(request)
                if response is not None:
                    sys.stdout.write(json.dumps(response) + "\n")
                    sys.stdout.flush()
            except KeyboardInterrupt:
                logger.info("Shutdown requested.")
                break
            except Exception as e:
                logger.error(f"Unexpected stdio processing error: {e}")


if __name__ == "__main__":
    server = PAMCPServer()
    server.run_stdio()
