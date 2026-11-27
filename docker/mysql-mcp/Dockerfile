# mysql-mcp: the official MySQL image with the MCP components of RFC 0001
# (askdba/mysql-mcp-server): component_mcp_guard and the mysql_mcp SQL tool pack, and on
# MySQL 26.10 component_mcp, the MCP endpoint inside mysqld (opt-in: MYSQL_MCP_HTTP_TOKEN).
# Published as ghcr.io/askdba/mysql-mcp:<8.4|9.7|26.10> by docker-publish.yml.
# Build context: the repository root, with component_mcp_guard-<arch>.so staged there, and
# for 26.10 component_mcp-<arch>.so.
# MYSQL_VERSION (required, no default) must be the exact release the component was built
# against, for example 8.4.13: a component built for another patch release can crash the
# server.
ARG MYSQL_VERSION

FROM mysql:${MYSQL_VERSION}
ARG TARGETARCH

LABEL org.opencontainers.image.title="mysql-mcp" \
      org.opencontainers.image.description="MySQL with the MCP components for mysql-mcp-server: component_mcp_guard, the mysql_mcp tool pack, and on 26.10 the component_mcp endpoint" \
      org.opencontainers.image.source="https://github.com/askdba/mysql-mcp-components" \
      org.opencontainers.image.documentation="https://github.com/askdba/mysql-mcp-components/blob/main/docs/MCP_COMPONENTS.md" \
      org.opencontainers.image.licenses="GPL-2.0-only AND Apache-2.0"

# Statically linked against libstdc++/libgcc and built in oraclelinux:9, this image's base.
# The pattern matches component_mcp_guard-<arch>.so, and component_mcp-<arch>.so where it was
# staged (26.10); each is renamed to its component name.
COPY component_mcp*-${TARGETARCH}.so /usr/lib64/mysql/plugin/
RUN cd /usr/lib64/mysql/plugin && \
    mv "component_mcp_guard-${TARGETARCH}.so" component_mcp_guard.so && \
    if [ -f "component_mcp-${TARGETARCH}.so" ]; then mv "component_mcp-${TARGETARCH}.so" component_mcp.so; fi
COPY sql/mcp/mysql_mcp.sql sql/mcp/uninstall.sql sql/mcp/LICENSE src/mcp/endpoint/mcp_tokens.sql /usr/share/mysql-mcp/
COPY docker/mysql-mcp/mysql-mcp-init.sh /docker-entrypoint-initdb.d/50-mysql-mcp.sh
COPY docker/mysql-mcp/mysql-mcp-healthcheck.sh /usr/local/bin/mysql-mcp-healthcheck
COPY docker/mysql-mcp/mysql-mcp-entrypoint.sh /usr/local/bin/mysql-mcp-entrypoint

# checkov:skip=CKV_DOCKER_3:MySQL entrypoint needs root for initialization
# Healthy only after first-start setup, on the server's port, without touching root's
# login (see the script).
# component_mcp (26.10, when enabled).
EXPOSE 33480

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD ["/usr/local/bin/mysql-mcp-healthcheck"]

# Checks the MYSQL_MCP_* settings before the official entrypoint initializes anything.
ENTRYPOINT ["mysql-mcp-entrypoint"]
CMD ["mysqld"]
