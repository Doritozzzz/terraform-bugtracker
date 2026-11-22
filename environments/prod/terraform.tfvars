# Production environment settings (no secrets here: this file is versioned).
project              = "bugtracker"
environment          = "prod"
web_replicas         = 3
lb_port              = 8080
storage_console_port = 9002
