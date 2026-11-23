# MySQL MCP components

MCP inside MySQL: server-side components for [mysql-mcp-server](https://github.com/askdba/mysql-mcp-server), designed in its [RFC 0001](https://github.com/askdba/mysql-mcp-server/blob/main/docs/rfc/0001-mysql-component-architecture.md).

| Part | What it does | Servers |
|---|---|---|
| `mysql_mcp` SQL tool pack ([`sql/mcp/`](sql/mcp)) | Stored procedures for the catalog tools, called by mysql-mcp-server and by `component_mcp` | MySQL 8.0 to 26.10, MariaDB 11.4, 12.3 |
| `component_mcp_guard` ([`src/mcp/guard/`](src/mcp/guard)) | Enforces MCP policy inside `mysqld` (kill switch, read-only, schema rules, time limit) and records MCP activity in `performance_schema`, status variables and the audit log | MySQL 8.4, 9.7, 26.10 |
| `component_mcp` ([`src/mcp/endpoint/`](src/mcp/endpoint)) | An MCP Streamable HTTP endpoint served by `mysqld` itself, running each tool call as the caller's MySQL account | MySQL 26.10 |

mysql-mcp-server stays the primary product: it is the only option for MySQL 8.0, MariaDB and managed cloud services, which cannot load third-party components.

## Use

- **Docker:** `ghcr.io/askdba/mysql-mcp:<8.4|9.7|26.10>` is the official MySQL image of that release with `component_mcp_guard` and the tool pack installed on first start.
- **Build:** `scripts/build-components-docker.sh mysql-<version> dist/<dir>` builds the guard for that exact MySQL release (a component works only on the release it was built against). Add `BUILD_ENDPOINT=ON` for `component_mcp` on 26.10. Requires Docker.
- **Tool pack only:** `mysql-mcp-server install-schema`, or run [`sql/mcp/mysql_mcp.sql`](sql/mcp/mysql_mcp.sql).

Install, settings, security model and tests: **[docs/MCP_COMPONENTS.md](docs/MCP_COMPONENTS.md)**.

## Tests

CI (`.github/workflows/ci.yml`) runs:
- the guard on MySQL 8.4, 9.7 and 26.10;
- `component_mcp` end to end and MCP conformance (MCP Inspector CLI, Python SDK client) on 26.10;
- the tool pack on MySQL and MariaDB.

`.github/workflows/mcp-fuzz-soak.yml` runs the fuzzing and ASAN soak of RFC 0001 §10.

## History and license

These components were developed in [askdba/myvector](https://github.com/askdba/myvector) and moved here with their history; references such as `askdba/myvector#318` in the log point there.

GPL-2.0 ([LICENSE](LICENSE)); the SQL tool pack under `sql/mcp/` is Apache-2.0 ([sql/mcp/LICENSE](sql/mcp/LICENSE)). See [NOTICE](NOTICE).
