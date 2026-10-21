"""
db2_query_tool — execute read-only parameterised queries against the
internal Db2 operational database.

Only queries in the approved catalog are permitted (deny-by-default).
Secrets injected by Vault Agent sidecar.
"""
import os
from ibm_watsonx_orchestrate.agent_builder.tools import tool, ToolPermission


# Approved, parameterised queries — extend via change management only.
_APPROVED_QUERIES: dict[str, str] = {
    "order_status":  "SELECT ORDER_ID, STATUS, LAST_UPDATED FROM ORDERS WHERE ORDER_ID = ?",
    "inventory_qty": "SELECT SKU, DESCRIPTION, QTY_ON_HAND FROM INVENTORY WHERE SKU = ?",
    "supplier_info": "SELECT SUPPLIER_ID, NAME, CONTACT FROM SUPPLIERS WHERE SUPPLIER_ID = ?",
}


@tool(
    name="db2_query_tool",
    description=(
        "Execute a read-only named query against the internal Db2 operational "
        "database. Only queries listed in the approved catalog are permitted. "
        "Available queries: order_status, inventory_qty, supplier_info."
    ),
    permission=ToolPermission.READ,
)
def query_db2(query_name: str, params: dict) -> list[dict]:
    """
    Args:
        query_name: Key of the named query (one of: order_status,
                    inventory_qty, supplier_info).
        params: Dict of bind parameters, passed in order as values.
                Example: {"order_id": "ORD-9981"}

    Returns:
        list of row dicts.

    Raises:
        ValueError: If query_name is not in the approved catalog.
        Exception: Propagates Db2 errors.
    """
    if query_name not in _APPROVED_QUERIES:
        raise ValueError(
            f"Query '{query_name}' is not in the approved catalog. "
            f"Allowed: {sorted(_APPROVED_QUERIES.keys())}"
        )

    try:
        import ibm_db  # type: ignore[import]
    except ImportError as exc:
        raise RuntimeError(
            "ibm_db is not installed. Install it in the wxo-adk-env from the "
            "offline pip mirror."
        ) from exc

    conn_string = os.environ["DB2_CONN_STRING"]  # injected by Vault sidecar

    conn = ibm_db.connect(conn_string, "", "")
    try:
        stmt = ibm_db.prepare(conn, _APPROVED_QUERIES[query_name])
        for i, value in enumerate(params.values(), start=1):
            ibm_db.bind_param(stmt, i, value)
        ibm_db.execute(stmt)

        rows: list[dict] = []
        row = ibm_db.fetch_assoc(stmt)
        while row:
            rows.append(dict(row))
            row = ibm_db.fetch_assoc(stmt)
    finally:
        ibm_db.close(conn)

    return rows
