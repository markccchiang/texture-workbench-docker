# Texture Workbench in Docker

A Docker image of [Texture Workbench](https://github.com/markccchiang/texture-workbench), a web application that measures
the texture of regions in images (GLCM/Haralick, run length, size zone, NGTDM, LBP, first-order and shape features). The
image contains the web app, its server, the `glcm` command line, the sample images and the documentation. It is built
straight from the texture-workbench GitHub repository.

- Docker Hub: [`markccchiang/texture-workbench`](https://hub.docker.com/r/markccchiang/texture-workbench)
- Platforms: `linux/amd64` and `linux/arm64` (Intel/AMD PCs and servers, Apple Silicon Macs, ARM servers)
- Size: about 440 MB

## Quick start

```bash
docker run -d --name texture-workbench -p 127.0.0.1:8080:8080 -v texture-data:/data markccchiang/texture-workbench
docker logs texture-workbench          # shows the access token
```

Open http://localhost:8080/, enter the access token from the log when the web app asks for it, and click
**Open sample image**.

To stop and start it again:

```bash
docker stop texture-workbench
docker start texture-workbench         # a new token is made on every start; see docker logs again
docker rm -f texture-workbench         # remove the container; your data stays in the texture-data volume
```

## The access token

Inside a container the server has to accept connections from outside the container, which Texture Workbench treats as
**server mode**. Server mode requires an access token.

- **No token given:** the container makes one when it starts and prints it in its log (`docker logs texture-workbench`).
  It changes every time the container starts.
- **Your own token:** pass one with `-e GLCM_API_TOKEN=...`, at least 43 characters, and it stays the same across
  restarts:

  ```bash
  export GLCM_API_TOKEN="$(openssl rand -base64 32)"
  echo "$GLCM_API_TOKEN"                 # keep it somewhere safe
  docker run -d --name texture-workbench -p 127.0.0.1:8080:8080 -v texture-data:/data \
      -e GLCM_API_TOKEN markccchiang/texture-workbench
  ```

The web app asks for the token once per browser tab.

## Using the web app

1. **Open an image:** *File ▸ Open Image*, drag a file onto the window, or open a sample image. PNG, JPEG, BMP, TIFF,
   DICOM and NIfTI are supported.
2. **Draw a region:** pick the rectangle tool (`R`), drag over the image, and press `T` to add it to the ROI Manager.
3. **Choose features:** pick a preset or the features you want in *Analysis Settings*.
4. **Measure:** press `M`. The results appear in the table below the image.
5. **Keep the results:** *File ▸ Export Results as CSV*, or *File ▸ Save Project*.

The full user guide and the equation of every feature are at http://localhost:8080/docs/ (also under *Help*).

## Keeping your data

Uploaded images, results and caches are stored in `/data` inside the container. The commands above keep it in a Docker
volume named `texture-data`, which survives removing and recreating the container.

In server mode, images and results **older than 7 days are deleted automatically**. For a personal installation, turn
that off with `-e GLCM_RETENTION_HOURS=0`. Projects and exports you save to your computer from the web app are not
affected.

## The command line (`glcm`)

The same image runs the `glcm` command, which measures images without the browser: for scripts and batch runs.
*Analyze ▸ Copy as Command…* in the web app writes the command for the measurement you set up.

```bash
# The commands and their options
docker run --rm markccchiang/texture-workbench glcm --help
docker run --rm markccchiang/texture-workbench glcm features --presets

# Measure a sample image
docker run --rm markccchiang/texture-workbench glcm measure sample:textures/brick.png --preset haralick

# Measure your own images: mount the current folder as /work and write the results there
docker run --rm -v "$PWD":/work -w /work markccchiang/texture-workbench \
    glcm measure image.png --rois regions.roi.json --preset all --out results.csv
```

When a container is already running the web app, `docker exec` sends the command to that server, with its token:

```bash
docker exec texture-workbench glcm measure sample:textures/brick.png --preset haralick
```

On Linux, the container runs as user `node` (UID 1000), so the mounted folder must be writable by that user to receive
`--out` files. To write them as yourself instead, run as your own user and give `glcm` a working folder that user can
write (`/data` belongs to `node`):

```bash
docker run --rm --user "$(id -u):$(id -g)" -e GLCM_DATA_DIR=/tmp/glcm -v "$PWD":/work -w /work \
    markccchiang/texture-workbench glcm measure image.png --out results.csv
```

### AI assistants (MCP)

`glcm mcp` is an [MCP](https://modelcontextprotocol.io) server on standard input and output, which lets an AI assistant
open images, select regions and measure them. To use it from Claude Code, for example:

```bash
claude mcp add texture-workbench -- docker run --rm -i markccchiang/texture-workbench glcm mcp
```

## Docker Compose

```yaml
services:
  texture-workbench:
    image: markccchiang/texture-workbench
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      GLCM_API_TOKEN: ${GLCM_API_TOKEN:?Set GLCM_API_TOKEN, e.g. export GLCM_API_TOKEN="$(openssl rand -base64 32)"}
      GLCM_RETENTION_HOURS: "0"
    volumes:
      - texture-data:/data
    restart: unless-stopped

volumes:
  texture-data:
```

```bash
export GLCM_API_TOKEN="$(openssl rand -base64 32)"
docker compose up -d
```

## Configuration

The server is configured with environment variables (`-e NAME=value`). The most useful ones:

| Variable | Default in the container | Meaning |
| --- | --- | --- |
| `GLCM_API_TOKEN` | made at start-up | Access token, at least 43 characters |
| `GLCM_PORT` | `8080` | Port inside the container; publish it with `-p`, e.g. `-p 127.0.0.1:9000:8080` |
| `GLCM_RETENTION_HOURS` | `168` | Delete uploaded images and results older than this; `0` keeps everything |
| `GLCM_RATE_LIMIT_PER_MINUTE` | `600` | API requests per minute per token; `0` for no limit |
| `GLCM_MAX_UPLOAD_BYTES` | 100 MiB | Largest upload (for a DICOM series, of each file) |
| `GLCM_MAX_IMAGE_PIXELS` | 100,000,000 | Largest image |
| `GLCM_ANALYSIS_CONCURRENCY` | number of CPU cores | Analysis jobs running at the same time |
| `GLCM_TRUST_PROXY` | `false` | Set to `true` behind a reverse proxy, so client addresses come from `X-Forwarded-For` |
| `GLCM_LOG_LEVEL` | `info` | Server log level |

The full list is in the
[texture-workbench developer guide](https://github.com/markccchiang/texture-workbench/blob/main/DEVELOPMENT.md#configuration).

## Security

The server speaks plain HTTP. The commands above publish it on `127.0.0.1` only, so it can be reached from your own
computer but not from the network. To share it with other people, keep that binding and put a reverse proxy with HTTPS
in front of it, with `GLCM_TRUST_PROXY=true`. See the
[deployment guide](https://github.com/markccchiang/texture-workbench/blob/main/doc/deployment.md), which also has a
security checklist.

## Building the image yourself

```bash
git clone https://github.com/markccchiang/texture-workbench-docker.git
cd texture-workbench-docker
docker build -t texture-workbench .
docker run -d --name texture-workbench -p 127.0.0.1:8080:8080 -v texture-data:/data texture-workbench
```

The build clones texture-workbench from GitHub; nothing else is needed next to the `Dockerfile`. A first build takes
about 5–10 minutes, most of it downloading packages and compiling OpenCV. Later builds reuse the cached stages.

Build arguments (`--build-arg NAME=value`):

| Argument | Default | Meaning |
| --- | --- | --- |
| `GIT_REF` | `main` | Branch, tag or commit of texture-workbench to build |
| `REPO_URL` | `https://github.com/markccchiang/texture-workbench.git` | Repository to clone, e.g. a fork |
| `BUILD_DOCS` | `true` | Build the documentation served at `/docs/`; `false` saves about 15 MB and the Python step |
| `OPENCV_VERSION` | `4.14.0` | OpenCV release to compile |
| `NODE_MAJOR` | `24` | Node.js major version of the base images |

Docker caches the clone step, so to pick up new commits on the same branch, build with `--no-cache` or pass a commit
hash as `GIT_REF`:

```bash
docker build -t texture-workbench --build-arg GIT_REF="$(git ls-remote https://github.com/markccchiang/texture-workbench.git main | cut -f1)" .
```

### How the image is built

The `Dockerfile` has four stages:

1. **toolchain:** Debian 12 with Node.js, CMake, a C++ compiler, Eigen, nlohmann/json, zlib and Python.
2. **opencv:** OpenCV compiled with only the parts Texture Workbench uses (core, imgproc and imgcodecs, reading and
   writing PNG, JPEG, TIFF, BMP and PGM), as static libraries. Debian's OpenCV packages would add about 360 MB of codecs
   and GIS libraries to the image; this build adds about 9 MB.
3. **build:** clones texture-workbench and builds the C++ core, its Node.js addon, the web app and the documentation.
4. **runtime:** a slim Node.js image with only what the application needs, running as the unprivileged `node` user,
   with a health check on `/api/v1/health`.

## Publishing to Docker Hub

Build both platforms and push them under one tag with `docker buildx`. On an Apple Silicon Mac the `linux/amd64` half
is built under emulation, which takes longer (roughly 20–40 minutes the first time).

```bash
docker login -u markccchiang                  # with a Docker Hub Personal Access Token as the password

docker buildx create --name multiarch --use   # once; the default builder cannot push multi-platform images
docker buildx build --platform linux/amd64,linux/arm64 \
    -t markccchiang/texture-workbench:latest \
    -t markccchiang/texture-workbench:0.1.0 \
    --push .
```

Tag each release with the texture-workbench version it contains (and build that version with `--build-arg GIT_REF`),
so that users can pin a version instead of `latest`. Check what was pushed with:

```bash
docker buildx imagetools inspect markccchiang/texture-workbench:latest
```

## Troubleshooting

- **The web app keeps asking for the token:** the container made a new token when it started. Get the current one with
  `docker logs texture-workbench`, or pass your own with `-e GLCM_API_TOKEN`.
- **"GLCM_API_TOKEN must be at least 43 characters":** use `openssl rand -base64 32`, which gives 44.
- **Port 8080 is already in use:** publish another host port, e.g. `-p 127.0.0.1:9000:8080`, and open
  http://localhost:9000/.
- **`glcm` says a server is already using `/data`:** a one-off `docker run` was given the same volume as a running
  container. Use `docker exec texture-workbench glcm ...` instead, or leave out the volume.
- **Pulls fail with "your account must log in with a Personal Access Token":** Docker Hub rejects the saved login.
  Run `docker logout`, then `docker login` with a Personal Access Token from
  https://app.docker.com/settings/personal-access-tokens.

## License

Texture Workbench is released under the
[MIT License](https://github.com/markccchiang/texture-workbench/blob/main/LICENSE). Its sample images and dependencies
keep their own licenses; see the texture-workbench repository.
