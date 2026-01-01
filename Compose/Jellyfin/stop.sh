docker compose \
  --env-file /companyname/Docker/Config/global.env \
  --env-file /companyname/Docker/Config/versions.env \
  --env-file jellyfin.env \
  down
