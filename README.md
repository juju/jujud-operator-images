# jujud-operator-images

## Introduction
This repository is used for (re)bulding the juju operator images used by
[Juju](github.com/juju/juju/).

## Preerequisites
- Docker 19.02 (requires buildx support with quemu for building multiple
  platforms). See [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/) for more
  information.
- GNU Make
- Bash
- [yq](https://github.com/mikefarah/yq)

## Image Locations
Images built by this repository can be found at:
- [Docker Hub](https://hub.docker.com/r/jujusolutions/jujud-operator)

## Usage

### Building the images in this repository
Images can be built by either running:

```sh
make
```

or

```sh
make build
```

### Pushing the images in this repository
Images can be built and pushed to a registry by runing:

```sh
make push
```
