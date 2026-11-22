# Development environment settings (no secrets here: this file is versioned).
project              = "bugtracker"
environment          = "dev"
web_replicas         = 2
log_level            = "debug"
lb_port              = 3000
storage_console_port = 9001
prometheus_port      = 9090
grafana_port         = 3001
