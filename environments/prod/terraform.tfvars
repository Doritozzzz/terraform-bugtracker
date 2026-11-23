# Production environment settings (no secrets here: this file is versioned).
project           = "bugtracker"
environment       = "prod"
web_replicas      = 3
lb_port           = 8080
grafana_port      = 8081
alertmanager_port = 9093
mail_port         = 8025
