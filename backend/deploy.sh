#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")/.."
if [[ ! -f backend/.env ]]; then
    printf 'Create backend/.env from backend/.env.example and set DATABASE_URL.\n' >&2
    exit 1
fi
target=dudosyka@192.168.1.148
release="apps/delivery-analytics/$(date -u +%Y%m%dT%H%M%SZ)-$$"
ssh_tmp=$(mktemp -d)
ssh_options=(-F /dev/null -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new
    -o ControlMaster=auto -o ControlPersist=600 -o "ControlPath=$ssh_tmp/control")
cleanup() {
    ssh "${ssh_options[@]}" -O exit "$target" >/dev/null 2>&1 || true
    rm -rf -- "$ssh_tmp"
}
trap cleanup EXIT

ssh "${ssh_options[@]}" -t "$target" 'set -eu
    command -v docker
    command -v curl
    command -v systemctl
    sudo docker compose version
    sudo docker info >/dev/null
    sudo nginx -t
    test -d /etc/nginx/conf.d'

tar --exclude='*/node_modules' --exclude='*/dist' --exclude='*/test-artifacts' \
    --exclude='*/__pycache__' --exclude='*/.venv' --exclude='*.pyc' \
    --exclude='*.tsbuildinfo' --exclude='pipeline/.local' \
    -czf - backend frontend pipeline README.md .dockerignore .gitignore \
    | ssh "${ssh_options[@]}" "$target" \
        "set -eu; umask 077; mkdir -p \"\$HOME/$release\"; tar --no-same-owner -xzpf - -C \"\$HOME/$release\""

ssh "${ssh_options[@]}" -t "$target" "set -eu
    cd \"\$HOME/$release\"
    compose() { sudo docker compose --env-file backend/.env -f backend/compose.yaml \"\$@\"; }
    compose config --quiet
    compose --progress plain build backend frontend
    compose --ansi never run --rm --no-deps backend python migrate.py
    compose --ansi never up -d --force-recreate --wait --wait-timeout 180 backend frontend

    config=/etc/nginx/conf.d/analytics.dudosyka.ru.conf
    if ! sudo test -e \"\$config\"; then
        sudo install -m 644 frontend/nginx.analytics.dudosyka.ru.conf \"\$config\"
        if ! sudo nginx -t; then
            sudo rm -- \"\$config\"
            exit 1
        fi
    fi
    if sudo grep -q 'proxy_read_timeout 30s;' \"\$config\"; then
        sudo cp -p \"\$config\" \"\$config.before-corrections.bak\"
        sudo sed -i 's/proxy_read_timeout 30s;/proxy_read_timeout 120s;/' \"\$config\"
    fi
    sudo nginx -t
    sudo systemctl enable --now nginx
    sudo systemctl reload nginx
    for path in / /er.jpg /api/schema.svg /api/health /api/bootstrap; do
        curl --fail --silent --show-error --location --max-time 30 \\
            --retry 3 --retry-all-errors --retry-delay 1 \\
            --noproxy analytics.dudosyka.ru \\
            --resolve analytics.dudosyka.ru:80:127.0.0.1 \\
            --resolve analytics.dudosyka.ru:443:127.0.0.1 \\
            \"http://analytics.dudosyka.ru\$path\" >/dev/null
    done
    compose ps
"
printf '\nDeployment directory: ~/%s\nURL: http://analytics.dudosyka.ru\n' "$release"
