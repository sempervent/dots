-- DOTS host inventory (read-only). Never collect credentials or user documents.
-- Invoked via: osqueryi --json < this file (or --file)

SELECT
  'os_version' AS section,
  name,
  version,
  platform,
  platform_like
FROM os_version;

SELECT
  'system_info' AS section,
  hostname,
  cpu_brand,
  cpu_physical_cores,
  physical_memory
FROM system_info;

SELECT
  'kernel' AS section,
  version,
  name
FROM kernel_info;

SELECT
  'interfaces' AS section,
  interface,
  address,
  mask
FROM interface_addresses
WHERE address NOT LIKE 'fe80%'
LIMIT 32;

SELECT
  'listening' AS section,
  pid,
  port,
  protocol,
  address,
  path
FROM listening_ports
  JOIN processes USING (pid)
WHERE port > 0
LIMIT 64;
