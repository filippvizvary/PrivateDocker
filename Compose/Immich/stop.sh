docker compose \
  --env-file /companyname/Docker/Config/global.env \
  --env-file /companyname/Docker/Config/versions.env \
  --env-file immich.env \
  down
