# Production environment settings (no secrets here: this file is versioned).
project      = "bugtracker"
environment  = "prod"
web_replicas = 3
log_level    = "info"
lb_port      = 8080
