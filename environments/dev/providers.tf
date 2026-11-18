# No host on purpose: the provider then uses DOCKER_HOST or the default local
# socket, so the same code works on Linux, macOS (Docker Desktop) and Windows.
provider "docker" {}
