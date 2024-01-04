FROM postgres:16-bullseye
# add pg_graphql
ADD pg_graphql-v1.4.2-pg16-arm64-linux-gnu.deb /tmp/pg_graphql.deb
RUN apt-get install -f /tmp/pg_graphql.deb