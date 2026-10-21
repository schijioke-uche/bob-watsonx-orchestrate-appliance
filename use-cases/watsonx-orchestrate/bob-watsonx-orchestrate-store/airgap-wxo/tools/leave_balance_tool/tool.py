"""
leave_balance_tool — retrieve remaining leave balance for an employee.

Calls the internal HR REST API. No external network dependency.
Secrets are injected by the HashiCorp Vault Agent sidecar at pod start.
"""
import os
import requests
from ibm_watsonx_orchestrate.agent_builder.tools import tool, ToolPermission


@tool(
    name="leave_balance_tool",
    description=(
        "Retrieve remaining leave balance for a given employee ID from the "
        "internal HR system. Returns annual_leave, sick_leave, and carry_over "
        "values in days."
    ),
    permission=ToolPermission.READ,
)
def get_leave_balance(employee_id: str) -> dict:
    """
    Args:
        employee_id: The internal employee identifier (e.g. 'EMP-00123').

    Returns:
        dict with keys:
            - annual_leave (float): Remaining annual leave days.
            - sick_leave (float): Remaining sick leave days.
            - carry_over (float): Carried-over leave days.

    Raises:
        ValueError: If employee_id is empty.
        requests.HTTPError: If the HR API returns a non-2xx status.
    """
    if not employee_id or not employee_id.strip():
        raise ValueError("employee_id must not be empty.")

    hr_api_url = os.environ["HR_API_URL"]   # injected by Vault sidecar
    hr_api_key = os.environ["HR_API_KEY"]   # injected by Vault sidecar
    ca_bundle = os.environ.get(
        "INTERNAL_CA_BUNDLE", "/etc/ssl/certs/internal-ca.crt"
    )

    resp = requests.get(
        f"{hr_api_url}/employees/{employee_id.strip()}/leave-balance",
        headers={"X-API-Key": hr_api_key},
        verify=ca_bundle,
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()
