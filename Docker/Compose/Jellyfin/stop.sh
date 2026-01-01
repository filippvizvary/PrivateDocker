docker compose \
  --env-file /companyname/Docker/Config/GLOBAL/GENERAL.env \
  --env-file /companyname/Docker/Config/GLOBAL/VERSIONS.env \
  --env-file jellyfin.env \
  down