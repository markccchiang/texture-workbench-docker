# Texture Workbench (https://github.com/markccchiang/texture-workbench), built from a fresh git clone.
#
# Build:
#   docker build -t texture-workbench .
#   docker build -t texture-workbench --build-arg GIT_REF=v0.1.0 .      # a branch, tag or commit
#   docker build -t texture-workbench --build-arg BUILD_DOCS=false .    # skip the Sphinx documentation
#
# Run the web app, then open http://localhost:8080/:
#   docker run --rm -p 8080:8080 -v texture-data:/data texture-workbench
#
# The server inside the container listens on 0.0.0.0, which Texture Workbench treats as server mode, and that needs an
# access token. Pass one with -e GLCM_API_TOKEN="$(openssl rand -base64 32)". If you pass none, the container makes one
# and prints it in its log (docker logs <container>); the web app asks for it once per browser tab.
#
# The `glcm` command line runs in the same image:
#   docker run --rm texture-workbench glcm measure sample:textures/brick.png --preset haralick
#   docker run --rm -v "$PWD":/work -w /work texture-workbench glcm measure image.png --out results.csv
#   docker exec <container> glcm measure sample:textures/brick.png      # goes to the running server

ARG NODE_MAJOR=24

# ---- Toolchain shared by the OpenCV and application builds ------------------------------------------------------------
FROM node:${NODE_MAJOR}-bookworm-slim AS toolchain

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates cmake g++ make \
        libeigen3-dev nlohmann-json3-dev zlib1g-dev \
        python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ---- Minimal OpenCV ---------------------------------------------------------------------------------------------------
# Texture Workbench needs only core, imgproc and imgcodecs, reading and writing PNG, JPEG, TIFF, BMP and PGM. OpenCV is
# built with just those, as static libraries with its bundled libpng, libjpeg-turbo and libtiff, and linked into the
# Node addon, so the runtime image needs no OpenCV packages (Debian's pull in about 360 MB of codecs and GDAL).
# Its own stage, so a different GIT_REF does not rebuild it.
FROM toolchain AS opencv

ARG OPENCV_VERSION=4.14.0

RUN git clone --depth 1 --branch "${OPENCV_VERSION}" https://github.com/opencv/opencv.git /tmp/opencv \
    && cmake -S /tmp/opencv -B /tmp/opencv/build \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/opt/opencv \
        -D CMAKE_POSITION_INDEPENDENT_CODE=ON \
        -D BUILD_SHARED_LIBS=OFF \
        -D BUILD_LIST=core,imgproc,imgcodecs \
        -D BUILD_PNG=ON -D BUILD_JPEG=ON -D BUILD_TIFF=ON -D BUILD_ZLIB=OFF \
        -D WITH_PNG=ON -D WITH_JPEG=ON -D WITH_TIFF=ON \
        -D WITH_WEBP=OFF -D WITH_OPENJPEG=OFF -D WITH_JASPER=OFF -D WITH_OPENEXR=OFF -D WITH_AVIF=OFF \
        -D WITH_JPEGXL=OFF -D WITH_SPNG=OFF -D WITH_GDAL=OFF -D WITH_GDCM=OFF \
        -D WITH_IMGCODEC_HDR=OFF -D WITH_IMGCODEC_SUNRASTER=OFF -D WITH_IMGCODEC_PFM=OFF -D WITH_IMGCODEC_PXM=ON \
        -D WITH_IPP=OFF -D WITH_ITT=OFF -D WITH_OPENCL=OFF -D WITH_LAPACK=OFF -D WITH_EIGEN=OFF -D WITH_PROTOBUF=OFF \
        -D WITH_ADE=OFF -D WITH_FFMPEG=OFF -D WITH_GSTREAMER=OFF -D WITH_GTK=OFF -D WITH_V4L=OFF -D WITH_1394=OFF \
        -D WITH_VA=OFF -D WITH_OPENMP=OFF -D WITH_TBB=OFF \
        -D BUILD_TESTS=OFF -D BUILD_PERF_TESTS=OFF -D BUILD_EXAMPLES=OFF -D BUILD_DOCS=OFF -D BUILD_opencv_apps=OFF \
        -D BUILD_JAVA=OFF -D BUILD_opencv_python3=OFF -D OPENCV_GENERATE_PKGCONFIG=OFF \
    && cmake --build /tmp/opencv/build --parallel "$(nproc)" \
    && cmake --install /tmp/opencv/build \
    && rm -rf /tmp/opencv

# ---- Build: clone, then the C++ core, Node-API addon, web app and documentation ---------------------------------------
FROM toolchain AS build

ARG REPO_URL=https://github.com/markccchiang/texture-workbench.git
ARG GIT_REF=main
ARG BUILD_DOCS=true

COPY --from=opencv /opt/opencv /opt/opencv
ENV CMAKE_PREFIX_PATH=/opt/opencv

# Fetching a single ref works for branches, tags and full commit hashes alike
RUN git init /app \
    && git -C /app remote add origin "${REPO_URL}" \
    && git -C /app fetch --depth 1 origin "${GIT_REF}" \
    && git -C /app checkout --detach FETCH_HEAD \
    && git -C /app log -1 --format='Building %H (%cd)'

WORKDIR /app

RUN npm ci \
    && npm run build:native \
    && npm run build:web

# The documentation is served at /docs/ and linked from Help ▸ Feature Equations
RUN if [ "${BUILD_DOCS}" = "true" ]; then \
        python3 -m venv /tmp/docs-venv \
        && /tmp/docs-venv/bin/pip install --no-cache-dir -r doc/requirements.txt \
        && /tmp/docs-venv/bin/sphinx-build -q -b html doc doc/_build/html; \
    else \
        mkdir -p doc/_build/html; \
    fi

# Keep only the runtime packages. Not `--omit=optional`: that would drop esbuild's platform binary, which tsx needs.
RUN npm prune --omit=dev

# ---- Runtime ----------------------------------------------------------------------------------------------------------
# OpenCV is linked into the addon, so no system packages are needed beyond the base image (zlib is part of it)
FROM node:${NODE_MAJOR}-bookworm-slim

# The `glcm` command is /usr/local/bin/glcm, a wrapper around the one in node_modules/.bin (see below)
ENV NODE_ENV=production \
    GLCM_HOST=0.0.0.0 \
    GLCM_PORT=8080 \
    GLCM_DATA_DIR=/data \
    GLCM_WEB_DIR=/app/web/dist \
    GLCM_SAMPLES_DIR=/app/samples \
    GLCM_DOCS_DIR=/app/doc/_build/html \
    UV_THREADPOOL_SIZE=16

WORKDIR /app

# node_modules keeps the workspace links (@glcm/api, @glcm/native, ...) to the directories copied next to it
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules node_modules
COPY --from=build /app/packages/api/package.json packages/api/
COPY --from=build /app/packages/api/src packages/api/src
COPY --from=build /app/packages/client/package.json packages/client/
COPY --from=build /app/packages/client/src packages/client/src
COPY --from=build /app/bindings/node/package.json /app/bindings/node/index.js /app/bindings/node/index.d.ts bindings/node/
COPY --from=build /app/bindings/node/build/Release/glcm_native.node bindings/node/build/Release/
COPY --from=build /app/server/package.json server/
COPY --from=build /app/server/src server/src
COPY --from=build /app/web/package.json web/
COPY --from=build /app/web/dist web/dist
COPY --from=build /app/cli/package.json cli/
COPY --from=build /app/cli/bin cli/bin
COPY --from=build /app/cli/src cli/src
COPY --from=build /app/samples samples
COPY --from=build /app/doc/_build/html doc/_build/html

# `server` (the default) starts the web app; anything else, such as `glcm ...` or `bash`, runs as given
COPY --chmod=755 <<'EOF' /usr/local/bin/texture-workbench-entrypoint
#!/bin/sh
set -e
if [ "$#" -eq 0 ] || [ "$1" = "server" ]; then
    case "${GLCM_HOST}" in
        127.0.0.1 | ::1 | localhost) ;;
        *)
            if [ -z "${GLCM_API_TOKEN}" ]; then
                GLCM_API_TOKEN="$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64url'))")"
                export GLCM_API_TOKEN
                echo "================================================================================"
                echo " No GLCM_API_TOKEN was given, so this container made one for this run:"
                echo ""
                echo "   ${GLCM_API_TOKEN}"
                echo ""
                echo " Open http://localhost:<published port>/ and enter it when the web app asks."
                echo " Pass -e GLCM_API_TOKEN=... to choose your own and keep it across restarts."
                echo "================================================================================"
            fi
            ;;
    esac
    # Lets `docker exec <container> glcm ...` reach this server with its token (see the glcm wrapper below)
    (umask 077 && printf '%s' "${GLCM_API_TOKEN}" > /tmp/glcm-server-token)
    exec node --import tsx server/src/main.ts
fi
exec "$@"
EOF

# `glcm` inside a container whose server is running talks to that server; in a one-off container it runs on its own
COPY --chmod=755 <<'EOF' /usr/local/bin/glcm
#!/bin/sh
if [ -f /tmp/glcm-server-token ]; then
    export GLCM_SERVER="${GLCM_SERVER:-http://127.0.0.1:${GLCM_PORT}}"
    GLCM_API_TOKEN="${GLCM_API_TOKEN:-$(cat /tmp/glcm-server-token)}"
    [ -n "${GLCM_API_TOKEN}" ] && export GLCM_API_TOKEN
fi
exec /app/node_modules/.bin/glcm "$@"
EOF

RUN mkdir -p /data && chown node:node /data
USER node
VOLUME /data
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
    CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.GLCM_PORT || 8080) + '/api/v1/health').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]

ENTRYPOINT ["texture-workbench-entrypoint"]
CMD ["server"]
