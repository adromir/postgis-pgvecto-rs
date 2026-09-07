# Stage 1: Pre-download external extension debs (cached independently from base image)
FROM curlimages/curl:latest AS downloader
ARG VECTORCHORD_VERSION=1.1.1
ARG PGVECTO_RS_VERSION=0.4.0

RUN curl -fL "https://github.com/tensorchord/VectorChord/releases/download/${VECTORCHORD_VERSION}/postgresql-17-vchord_${VECTORCHORD_VERSION}-1_amd64.deb" -o /tmp/vectorchord.deb \
	&& curl -fL "https://github.com/tensorchord/pgvecto.rs/releases/download/v${PGVECTO_RS_VERSION}/vectors-pg17_${PGVECTO_RS_VERSION}_amd64.deb" -o /tmp/pgvecto-rs.deb

# Stage 2: Main image
FROM postgres:17-trixie

# Copy pre-downloaded deb packages from downloader stage
COPY --from=downloader /tmp/vectorchord.deb /tmp/pgvecto-rs.deb /tmp/

# Install dependencies, PostGIS, pgvector, cron, and extension debs using cache mounts
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
	&& echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	apt-get update && apt-get install -y --no-install-recommends \
	cron \
	postgresql-17-postgis-3 \
	postgresql-17-postgis-3-scripts \
	postgresql-17-pgvector \
	/tmp/vectorchord.deb \
	/tmp/pgvecto-rs.deb \
	&& rm -f /tmp/vectorchord.deb /tmp/pgvecto-rs.deb

# Configure shared_preload_libraries
RUN echo "shared_preload_libraries = 'vchord, vectors'" >> /usr/share/postgresql/postgresql.conf.sample

# Copy initialization scripts
COPY init-extensions.sql /docker-entrypoint-initdb.d/

# Copy backup/restore scripts
COPY scripts/backup.sh scripts/restore.sh scripts/start-cron.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh /usr/local/bin/start-cron.sh

VOLUME /backups
ENTRYPOINT ["start-cron.sh"]
CMD ["postgres"]

EXPOSE 5432
