variable "name" {
  description = "Container name. It is also the hostname other containers use to connect."
  type        = string
}

variable "network" {
  description = "Name or ID of the Docker network the cache joins."
  type        = string
}

variable "max_memory" {
  description = "Memory limit for cached data (Redis syntax, e.g. 64mb). The least recently used keys are evicted when it is full."
  type        = string
  default     = "64mb"
}

variable "image" {
  description = "Redis image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "redis:8.10.3-alpine"
}
