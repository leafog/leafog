# leafog

## start

#### build keycloak

```bash
docker build -f leafog/pre-build/keycloak/Dockerfile  -t keycloak .
```

#### build leafog

```bash
./gradlew build -Dquarkus.package.type=native -Dquarkus.native.container-build=true
docker build -f src/main/docker/Dockerfile.native -t quarkus/leafog .
```

#### run

```bash
cd leafog && docker compose up -d 
```