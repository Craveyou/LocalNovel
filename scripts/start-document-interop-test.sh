#!/bin/sh
# Foreground, opt-in local simulator test server. No production credentials or database.
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
pg_bin="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
case "$("$pg_bin/postgres" --version)" in *' 17.'*) ;; *) exit 1 ;; esac
sandbox_dir="$(mktemp -d /tmp/xlib-document-interop.XXXXXX)"
mkdir "$sandbox_dir/socket"
server_pid=''
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    if [ -f "$sandbox_dir/data/postmaster.pid" ]; then "$pg_bin/pg_ctl" -D "$sandbox_dir/data" -m fast -w stop >>"$sandbox_dir/postgres.log" 2>&1; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$pg_bin/initdb" -D "$sandbox_dir/data" -U xlib_test_owner --auth=trust --no-locale -E UTF8 >"$sandbox_dir/init.log" 2>&1
"$pg_bin/pg_ctl" -D "$sandbox_dir/data" -l "$sandbox_dir/postgres.log" -o "-F -k $sandbox_dir/socket -c listen_addresses='' -c max_connections=20" -w start >/dev/null
"$pg_bin/createdb" -h "$sandbox_dir/socket" -U xlib_test_owner xlib_interop_test
for migration in "$root"/services/backend/migrations/*.sql; do
    "$pg_bin/psql" -h "$sandbox_dir/socket" -U xlib_test_owner -d xlib_interop_test -v ON_ERROR_STOP=1 -q -f "$migration"
done
"$pg_bin/psql" -h "$sandbox_dir/socket" -U xlib_test_owner -d xlib_interop_test -v ON_ERROR_STOP=1 -q -c 'CREATE ROLE xlib_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT; GRANT USAGE ON SCHEMA public TO xlib_test_app; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO xlib_test_app; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO xlib_test_app;'
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$sandbox_dir/key.pem" -out "$sandbox_dir/cert.pem" -days 1 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -addext 'extendedKeyUsage=serverAuth' -addext 'keyUsage=digitalSignature,keyEncipherment' -addext 'basicConstraints=critical,CA:FALSE' >"$sandbox_dir/tls.log" 2>&1
openssl x509 -in "$sandbox_dir/cert.pem" -outform der -out "$sandbox_dir/cert.der"
export TEST_DATABASE_APP_URL="postgresql://xlib_test_app@localhost/xlib_interop_test?host=$sandbox_dir/socket"
export XLIB_INTEROP_DIRECTORY="$sandbox_dir"
printf 'Temporary interop directory: %s\n' "$sandbox_dir"
node "$root/services/backend/dist/test/mobile-server.js" &
server_pid=$!
if [ "$#" -gt 0 ]; then
    # Optional automatic client run. Certificate trust is scoped to the test session;
    # no simulator/system trust-store mutation and no credentials printed to logs.
    ruby -rjson - "$sandbox_dir/connection.json" "$@" <<'RUBY'
path = ARGV.shift
100.times do
  break if File.file?(path)
  sleep 0.1
end
abort "Temporary HTTPS test server did not become ready" unless File.file?(path)
connection = JSON.parse(File.read(path))
env = {
  "TEST_RUNNER_XLIB_DOC_INTEROP_URL" => connection.fetch("url"),
  "TEST_RUNNER_XLIB_DOC_INTEROP_RUN" => connection.fetch("run"),
  "TEST_RUNNER_XLIB_DOC_INTEROP_CERT" => connection.fetch("certificate")
}
system(env, *ARGV)
exit($?.exitstatus || 1)
RUBY
    exit 0
fi
wait "$server_pid"
